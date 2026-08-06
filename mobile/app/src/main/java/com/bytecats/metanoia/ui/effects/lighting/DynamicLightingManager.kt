package com.bytecats.metanoia.ui.effects.lighting

import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.graphicsLayer
import org.intellij.lang.annotations.Language
import kotlin.math.abs
import kotlin.math.sqrt
import kotlin.collections.ArrayList

/**
 * Dynamic Lighting Manager
 * Handles multiple light sources, light culling, and real-time updates for PBR rendering
 */
class DynamicLightingManager(
    private val config: LightingSystemConfig = LightingSystemConfig()
) {
    private val lights = ArrayList<LightSource>()
    private var nextLightId = 0
    
    // Performance tracking
    private var lastFrameTime = 0L
    private var frameCount = 0
    private var averageFrameTime = 0f
    
    /**
     * Adds a light source to the scene
     */
    fun addLight(light: LightSource): Int {
        val lightWithId = light.copy(id = nextLightId++)
        lights.add(lightWithId)
        return lightWithId.id
    }
    
    /**
     * Removes a light source by ID
     */
    fun removeLight(lightId: Int): Boolean {
        return lights.removeIf { it.id == lightId }
    }
    
    /**
     * Updates an existing light source
     */
    fun updateLight(lightId: Int, update: (LightSource) -> LightSource): Boolean {
        val index = lights.indexOfFirst { it.id == lightId }
        if (index >= 0) {
            lights[index] = update(lights[index])
            return true
        }
        return false
    }
    
    /**
     * Gets a light source by ID
     */
    fun getLight(lightId: Int): LightSource? {
        return lights.find { it.id == lightId }
    }
    
    /**
     * Gets all active lights
     */
    fun getActiveLights(): List<LightSource> {
        return lights.filter { it.enabled }
    }
    
    /**
     * Performs light culling based on distance and view frustum
     */
    fun cullLights(viewPosition: Offset, viewDirection: Offset): List<LightSource> {
        if (!config.lightCullingEnabled) {
            return getActiveLights().take(config.maxLights)
        }
        
        val activeLights = getActiveLights()
        val culledLights = ArrayList<LightSource>()
        
        for (light in activeLights) {
            // Distance culling
            val dx = light.position.x - viewPosition.x
            val dy = light.position.y - viewPosition.y
            val distance = sqrt(dx * dx + dy * dy)
            
            if (distance > config.lightCullingDistance) {
                continue
            }
            
            // Frustum culling (simplified)
            val lightDirX = light.position.x - viewPosition.x
            val lightDirY = light.position.y - viewPosition.y
            val lightDirLen = sqrt(lightDirX * lightDirX + lightDirY * lightDirY)
            val lightDirXNorm = lightDirX / lightDirLen
            val lightDirYNorm = lightDirY / lightDirLen
            
            val dotProduct = (lightDirXNorm * viewDirection.x + lightDirYNorm * viewDirection.y)
            if (dotProduct < 0.2f) { // Light is behind camera
                continue
            }
            
            // Calculate light importance
            val importance = calculateLightImportance(light, distance)
            culledLights.add(light.copy(importance = importance))
        }
        
        // Sort by importance and limit count
        return culledLights
            .sortedByDescending { it.importance }
            .take(config.maxLights)
    }
    
    /**
     * Calculates light importance for culling decisions
     */
    private fun calculateLightImportance(light: LightSource, distance: Float): Float {
        val intensity = light.intensity
        val distanceFactor = 1f / (1f + distance * 0.01f)
        return intensity * distanceFactor * light.importance
    }
    
    /**
     * Updates light positions for animation
     */
    fun updateAnimatedLights(time: Float) {
        for (i in lights.indices) {
            val light = lights[i]
            if (light.id != 0) { // Skip main light
                // Simple circular motion
                val angle = time * 0.5f + light.id * 1.5f
                val radius = 0.3f
                val newX = 0.5f + cos(angle) * radius
                val newY = 0.5f + sin(angle) * radius
                lights[i] = light.copy(position = Offset(newX, newY))
            }
        }
    }
    
    /**
     * Prepares light data for shader uniforms
     */
    fun prepareShaderLights(): ShaderLightData {
        val effectiveLights = getActiveLights().take(config.maxLights)
        
        val positions = Array(8) { FloatArray(3) }
        val colors = Array(8) { FloatArray(3) }
        val intensities = FloatArray(8)
        val types = IntArray(8)
        val directions = Array(8) { FloatArray(3) }
        val spotAngles = FloatArray(8)
        
        for (i in effectiveLights.indices) {
            val light = effectiveLights[i]
            positions[i] = light.toPosition3D()
            colors[i] = light.toRGBArray()
            intensities[i] = light.intensity
            types[i] = light.type.shaderValue
            directions[i] = light.toDirection3D()
            spotAngles[i] = light.spotAngle
        }
        
        // Fill remaining slots with default data
        for (i in effectiveLights.size until 8) {
            positions[i] = floatArrayOf(0f, 0f, 0f)
            colors[i] = floatArrayOf(0f, 0f, 0f)
            intensities[i] = 0f
            types[i] = 0
            directions[i] = floatArrayOf(0f, 0f, 0f)
            spotAngles[i] = 0f
        }
        
        return ShaderLightData(
            lightCount = effectiveLights.size,
            positions = positions,
            colors = colors,
            intensities = intensities,
            types = types,
            directions = directions,
            spotAngles = spotAngles
        )
    }
    
    /**
     * Updates performance metrics
     */
    fun updatePerformanceMetrics(frameTimeMs: Float) {
        frameCount++
        lastFrameTime = frameTimeMs.toLong()
        
        // Exponential moving average
        averageFrameTime = averageFrameTime * 0.95f + frameTimeMs * 0.05f
        
        // Adaptive quality adjustment
        if (config.adaptiveQuality && frameCount % 30 == 0) {
            adjustAdaptiveQuality()
        }
    }
    
    /**
     * Adjusts quality based on performance
     */
    private fun adjustAdaptiveQuality() {
        val targetFrameTime = 1000f / config.targetFrameRate
        val performanceRatio = targetFrameTime / averageFrameTime
        
        if (performanceRatio < config.adaptiveQualityFactor) {
            // Performance is below threshold, reduce quality
            // This would normally adjust config parameters
            // For now, we just track the state
        }
    }
    
    /**
     * Gets current performance statistics
     */
    fun getPerformanceStats(): PerformanceStats {
        val fps = if (averageFrameTime > 0) 1000f / averageFrameTime else 60f
        return PerformanceStats(
            fps = fps,
            frameTimeMs = averageFrameTime,
            activeLightCount = lights.count { it.enabled },
            culledLightCount = lights.count { it.enabled } - config.maxLights.coerceAtMost(lights.size)
        )
    }
    
    /**
     * Clears all lights
     */
    fun clearLights() {
        lights.clear()
        nextLightId = 0
    }
    
    /**
     * Sets up default lighting configuration
     */
    fun setupDefaultLighting() {
        clearLights()
        
        // Main directional light
        addLight(LightSource.defaultDirectionalLight().copy(
            id = 0,
            intensity = 0.8f,
            color = Color(1f, 0.98f, 0.95f)
        ))
        
        // Warm fill light
        addLight(LightSource.warmLight().copy(
            position = Offset(0.3f, 0.4f),
            intensity = 0.4f
        ))
        
        // Cool rim light
        addLight(LightSource.rimLight().copy(
            position = Offset(0.8f, 0.3f),
            color = Color(0.7f, 0.85f, 1f),
            intensity = 0.5f
        ))
    }
    
    /**
     * Sets up dramatic lighting configuration
     */
    fun setupDramaticLighting() {
        clearLights()
        
        // Strong key light
        addLight(LightSource(
            type = LightType.SPOT,
            position = Offset(0.2f, 0.2f),
            direction = Offset(0.3f, -0.7f),
            color = Color(1f, 0.95f, 0.9f),
            intensity = 1.5f,
            spotAngle = 45f,
            castsShadow = true
        ))
        
        // Weak fill light
        addLight(LightSource(
            type = LightType.POINT,
            position = Offset(0.7f, 0.5f),
            color = Color(0.9f, 0.9f, 1f),
            intensity = 0.2f
        ))
        
        // Strong rim light
        addLight(LightSource(
            type = LightType.SPOT,
            position = Offset(0.9f, 0.6f),
            direction = Offset(-1f, 0.2f),
            color = Color(1f, 1f, 1f),
            intensity = 1.2f,
            spotAngle = 60f
        ))
    }
    
    /**
     * Sets up studio lighting configuration
     */
    fun setupStudioLighting() {
        clearLights()
        
        // Key light
        addLight(LightSource(
            type = LightType.SPOT,
            position = Offset(0.3f, 0.2f),
            direction = Offset(0.1f, -0.9f),
            color = Color.White,
            intensity = 1.0f,
            spotAngle = 50f
        ))
        
        // Fill light
        addLight(LightSource(
            type = LightType.POINT,
            position = Offset(0.7f, 0.4f),
            color = Color(0.95f, 0.95f, 1f),
            intensity = 0.6f
        ))
        
        // Back light
        addLight(LightSource(
            type = LightType.SPOT,
            position = Offset(0.5f, 0.1f),
            direction = Offset(0f, 1f),
            color = Color.White,
            intensity = 0.8f,
            spotAngle = 30f
        ))
    }
    
    /**
     * Determines if full PBR should be used based on current configuration
     */
    fun getUseFullPBR(): Boolean {
        return config.useFullPBR()
    }
}

/**
 * Shader light data structure for uniform updates
 */
data class ShaderLightData(
    val lightCount: Int,
    val positions: Array<FloatArray>,
    val colors: Array<FloatArray>,
    val intensities: FloatArray,
    val types: IntArray,
    val directions: Array<FloatArray>,
    val spotAngles: FloatArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        
        other as ShaderLightData
        
        if (lightCount != other.lightCount) return false
        if (!positions.contentDeepEquals(other.positions)) return false
        if (!colors.contentDeepEquals(other.colors)) return false
        if (!intensities.contentEquals(other.intensities)) return false
        if (!types.contentEquals(other.types)) return false
        if (!directions.contentDeepEquals(other.directions)) return false
        if (!spotAngles.contentEquals(other.spotAngles)) return false
        
        return true
    }
    
    override fun hashCode(): Int {
        var result = lightCount
        result = 31 * result + positions.contentDeepHashCode()
        result = 31 * result + colors.contentDeepHashCode()
        result = 31 * result + intensities.contentHashCode()
        result = 31 * result + types.contentHashCode()
        result = 31 * result + directions.contentDeepHashCode()
        result = 31 * result + spotAngles.contentHashCode()
        return result
    }
}

/**
 * Performance statistics
 */
data class PerformanceStats(
    val fps: Float,
    val frameTimeMs: Float,
    val activeLightCount: Int,
    val culledLightCount: Int
)

/**
 * Helper functions for dynamic lighting modifiers
 */
object DynamicLightingModifiers {
    
    /**
     * Applies PBR lighting with the specified lighting manager
     */
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    fun Modifier.applyPBRLighting(
        manager: DynamicLightingManager,
        material: PBRMaterial,
        time: Float = 0f,
        cameraPosition: Offset = Offset(50f, 50f)
    ): Modifier {
        return this.graphicsLayer {
            val shader = RuntimeShader(if (manager.getUseFullPBR()) {
                CookTorranceBRDF.PBR_SHADER
            } else {
                CookTorranceBRDF.MOBILE_OPTIMIZED_SHADER
            })
            
            val validatedMaterial = material.validate()
            val lightData = manager.prepareShaderLights()
            
            // Resolution
            shader.setFloatUniform("resolution", size.width, size.height)
            shader.setFloatUniform("time", time)
            
            // Material properties
            shader.setFloatUniform("albedo", 
                validatedMaterial.albedo.red,
                validatedMaterial.albedo.green,
                validatedMaterial.albedo.blue
            )
            shader.setFloatUniform("metallic", validatedMaterial.metallic)
            shader.setFloatUniform("roughness", validatedMaterial.roughness)
            shader.setFloatUniform("emissive",
                validatedMaterial.emissive.red,
                validatedMaterial.emissive.green,
                validatedMaterial.emissive.blue
            )
            shader.setFloatUniform("normalStrength", validatedMaterial.normalStrength)
            shader.setFloatUniform("occlusion", validatedMaterial.occlusion)
            shader.setFloatUniform("opacity", validatedMaterial.opacity)
            
            // Light properties
            shader.setIntUniform("lightCount", lightData.lightCount)
            
            for (i in 0 until 8) {
                shader.setFloatUniform("lightPositions[$i]", 
                    lightData.positions[i][0],
                    lightData.positions[i][1],
                    lightData.positions[i][2]
                )
                shader.setFloatUniform("lightColors[$i]",
                    lightData.colors[i][0],
                    lightData.colors[i][1],
                    lightData.colors[i][2]
                )
                shader.setFloatUniform("lightIntensities[$i]", lightData.intensities[i])
                shader.setIntUniform("lightTypes[$i]", lightData.types[i])
                shader.setFloatUniform("lightDirections[$i]",
                    lightData.directions[i][0],
                    lightData.directions[i][1],
                    lightData.directions[i][2]
                )
                shader.setFloatUniform("lightSpotAngles[$i]", lightData.spotAngles[i])
            }
            
            // Camera
            shader.setFloatUniform("cameraPos",
                cameraPosition.x,
                cameraPosition.y,
                50f
            )
            
            // Environment settings
            // shader.setBooleanUniform("useIBL", manager.config.enableIBL)
            // shader.setFloatUniform("qualityLevel", manager.config.getQualityLevel())
            // shader.setIntUniform("maxReflections", manager.config.iblQuality.ordinal)
            
            renderEffect = RenderEffect.createRuntimeShaderEffect(shader, "composable")
                .asComposeRenderEffect()
        }
    }
    
    /**
     * Applies multiple point lights for dramatic effect
     */
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    fun Modifier.multiPointLighting(
        lights: List<LightSource>,
        material: PBRMaterial = PBRMaterial.defaultDielectric(),
        time: Float = 0f
    ): Modifier {
        val manager = DynamicLightingManager().apply {
            lights.forEach { addLight(it) }
        }
        
        return applyPBRLighting(manager, material, time)
    }
    
    /**
     * Applies rim lighting effect
     */
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    fun Modifier.rimLighting(
        rimColor: Color = Color.White,
        rimIntensity: Float = 1.2f,
        baseMaterial: PBRMaterial = PBRMaterial.defaultDielectric(),
        time: Float = 0f
    ): Modifier {
        val manager = DynamicLightingManager().apply {
            addLight(LightSource(
                type = LightType.SPOT,
                position = Offset(0.9f, 0.5f),
                direction = Offset(-1f, 0f),
                color = rimColor,
                intensity = rimIntensity,
                spotAngle = 60f
            ))
            addLight(LightSource.defaultDirectionalLight().copy(
                intensity = 0.3f
            ))
        }
        
        return applyPBRLighting(manager, baseMaterial, time)
    }
    
    /**
     * Applies cinematic lighting setup
     */
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    fun Modifier.cinematicLighting(
        material: PBRMaterial = PBRMaterial.defaultDielectric(),
        time: Float = 0f
    ): Modifier {
        val manager = DynamicLightingManager(
            config = LightingSystemConfig.highEnd()
        ).apply {
            setupDramaticLighting()
        }
        
        return applyPBRLighting(manager, material, time)
    }
}

// Helper math functions
private fun cos(angle: Float): Float = kotlin.math.cos(angle)
private fun sin(angle: Float): Float = kotlin.math.sin(angle)