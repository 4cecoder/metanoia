package com.bytecats.metanoia.ui.effects.lighting

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color

/**
 * Quality presets for different performance targets
 */
enum class QualityPreset(val performanceLevel: Float) {
    LOW(0.3f),
    MEDIUM(0.6f),
    HIGH(0.9f),
    ULTRA(1.0f)
}

/**
 * Light type enumeration
 */
enum class LightType(val shaderValue: Int) {
    POINT(0),
    DIRECTIONAL(1),
    SPOT(2)
}

/**
 * Mobile optimization level
 */
enum class MobileOptimizationLevel {
    NONE,           // Full quality, desktop-like
    LOW,            // Minor optimizations
    MEDIUM,         // Balanced optimizations
    HIGH,           // Significant optimizations
    EXTREME         // Maximum performance, minimal quality
}

/**
 * PBR Lighting System Configuration
 * Comprehensive configuration for physically-based rendering on mobile devices
 */
data class LightingSystemConfig(
    // Quality settings
    val qualityPreset: QualityPreset = QualityPreset.HIGH,
    val enableMobileOptimizations: Boolean = true,
    val mobileOptimizationLevel: MobileOptimizationLevel = MobileOptimizationLevel.MEDIUM,
    val adaptiveQuality: Boolean = true,
    val adaptiveQualityFactor: Float = 0.8f, // Threshold for quality adjustment
    
    // Light settings
    val maxLights: Int = 8,
    val maxDynamicLights: Int = 4,
    val lightCullingEnabled: Boolean = true,
    val lightCullingDistance: Float = 100f,
    val enableShadowMapping: Boolean = true,
    val shadowQuality: ShadowQuality = ShadowQuality.MEDIUM,
    
    // Environment settings
    val enableIBL: Boolean = true,
    val iblQuality: IBLQuality = IBLQuality.MEDIUM,
    val enableSSR: Boolean = false, // Screen-space reflections (expensive)
    val ssrQuality: SSRQuality = SSRQuality.LOW,
    val enableSSAO: Boolean = true,
    val ssaoQuality: SSAOQuality = SSAOQuality.MEDIUM,
    
    // Material settings
    val maxMaterialLayers: Int = 4,
    val enableNormalMaps: Boolean = true,
    val normalMapQuality: NormalMapQuality = NormalMapQuality.HIGH,
    val enableEmissive: Boolean = true,
    val enableMaterialBlending: Boolean = true,
    
    // Performance settings
    val useHalfPrecision: Boolean = true,
    val textureCompression: Boolean = true,
    val maxTextureSize: Int = 2048,
    val enableLODBias: Boolean = true,
    val lodBias: Float = 0.5f,
    val enableMipmaps: Boolean = true,
    
    // Frame rate target
    val targetFrameRate: Int = 60,
    val allowFrameSkipping: Boolean = true,
    val maxFrameTimeMs: Float = 16.67f, // For 60 FPS
    
    // Memory settings
    val maxMemoryUsageMB: Int = 256,
    val enableMemoryManagement: Boolean = true,
    val textureAtlasEnabled: Boolean = true,
    
    // Shadow settings
    val shadowCascadeCount: Int = 3,
    val shadowMapResolution: Int = 1024,
    val softShadows: Boolean = true,
    val shadowPCFSamples: Int = 4,
    
    // Anti-aliasing
    val enableFXAA: Boolean = true,
    val enableTAA: Boolean = false, // Temporal anti-aliasing (expensive)
    
    // Debug settings
    val debugMode: Boolean = false,
    val showLightBounds: Boolean = false,
    val showWireframe: Boolean = false,
    val showNormals: Boolean = false,
    val showDepth: Boolean = false
) {
    enum class ShadowQuality {
        OFF, LOW, MEDIUM, HIGH, ULTRA
    }
    
    enum class IBLQuality {
        OFF, LOW, MEDIUM, HIGH
    }
    
    enum class SSRQuality {
        OFF, LOW, MEDIUM
    }
    
    enum class SSAOQuality {
        OFF, LOW, MEDIUM, HIGH
    }
    
    enum class NormalMapQuality {
        LOW, MEDIUM, HIGH
    }
    
    companion object {
        /**
         * Creates configuration optimized for low-end devices
         */
        fun lowEnd() = LightingSystemConfig(
            qualityPreset = QualityPreset.LOW,
            enableMobileOptimizations = true,
            mobileOptimizationLevel = MobileOptimizationLevel.EXTREME,
            adaptiveQuality = true,
            maxLights = 4,
            maxDynamicLights = 2,
            lightCullingEnabled = true,
            enableShadowMapping = true,
            shadowQuality = ShadowQuality.LOW,
            enableIBL = true,
            iblQuality = IBLQuality.LOW,
            enableSSR = false,
            enableSSAO = false,
            maxMaterialLayers = 2,
            enableNormalMaps = false,
            useHalfPrecision = true,
            textureCompression = true,
            maxTextureSize = 1024,
            enableLODBias = true,
            lodBias = 1.5f,
            targetFrameRate = 30,
            shadowCascadeCount = 1,
            shadowMapResolution = 512,
            softShadows = false,
            enableFXAA = false
        )
        
        /**
         * Creates configuration for mid-range devices
         */
        fun midRange() = LightingSystemConfig(
            qualityPreset = QualityPreset.MEDIUM,
            enableMobileOptimizations = true,
            mobileOptimizationLevel = MobileOptimizationLevel.MEDIUM,
            adaptiveQuality = true,
            maxLights = 6,
            maxDynamicLights = 3,
            lightCullingEnabled = true,
            enableShadowMapping = true,
            shadowQuality = ShadowQuality.MEDIUM,
            enableIBL = true,
            iblQuality = IBLQuality.MEDIUM,
            enableSSR = false,
            enableSSAO = true,
            ssaoQuality = SSAOQuality.LOW,
            maxMaterialLayers = 3,
            enableNormalMaps = true,
            normalMapQuality = NormalMapQuality.MEDIUM,
            useHalfPrecision = true,
            textureCompression = true,
            maxTextureSize = 1536,
            enableLODBias = true,
            lodBias = 0.8f,
            targetFrameRate = 60,
            shadowCascadeCount = 2,
            shadowMapResolution = 1024,
            softShadows = true,
            shadowPCFSamples = 2,
            enableFXAA = true
        )
        
        /**
         * Creates configuration for high-end devices
         */
        fun highEnd() = LightingSystemConfig(
            qualityPreset = QualityPreset.HIGH,
            enableMobileOptimizations = true,
            mobileOptimizationLevel = MobileOptimizationLevel.LOW,
            adaptiveQuality = true,
            maxLights = 8,
            maxDynamicLights = 4,
            lightCullingEnabled = true,
            enableShadowMapping = true,
            shadowQuality = ShadowQuality.HIGH,
            enableIBL = true,
            iblQuality = IBLQuality.HIGH,
            enableSSR = true,
            ssrQuality = SSRQuality.LOW,
            enableSSAO = true,
            ssaoQuality = SSAOQuality.MEDIUM,
            maxMaterialLayers = 4,
            enableNormalMaps = true,
            normalMapQuality = NormalMapQuality.HIGH,
            useHalfPrecision = false,
            textureCompression = false,
            maxTextureSize = 2048,
            enableLODBias = true,
            lodBias = 0.3f,
            targetFrameRate = 60,
            shadowCascadeCount = 3,
            shadowMapResolution = 2048,
            softShadows = true,
            shadowPCFSamples = 8,
            enableFXAA = true,
            enableTAA = true
        )
        
        /**
         * Creates configuration for ultra quality
         */
        fun ultra() = LightingSystemConfig(
            qualityPreset = QualityPreset.ULTRA,
            enableMobileOptimizations = false,
            mobileOptimizationLevel = MobileOptimizationLevel.NONE,
            adaptiveQuality = false,
            maxLights = 8,
            maxDynamicLights = 8,
            lightCullingEnabled = true,
            enableShadowMapping = true,
            shadowQuality = ShadowQuality.ULTRA,
            enableIBL = true,
            iblQuality = IBLQuality.HIGH,
            enableSSR = true,
            ssrQuality = SSRQuality.MEDIUM,
            enableSSAO = true,
            ssaoQuality = SSAOQuality.HIGH,
            maxMaterialLayers = 4,
            enableNormalMaps = true,
            normalMapQuality = NormalMapQuality.HIGH,
            useHalfPrecision = false,
            textureCompression = false,
            maxTextureSize = 4096,
            enableLODBias = false,
            targetFrameRate = 60,
            shadowCascadeCount = 4,
            shadowMapResolution = 4096,
            softShadows = true,
            shadowPCFSamples = 16,
            enableFXAA = true,
            enableTAA = true
        )
    }
    
    /**
     * Gets the quality level as a float for shader uniforms
     */
    fun getQualityLevel(): Float {
        return if (enableMobileOptimizations) {
            when (mobileOptimizationLevel) {
                MobileOptimizationLevel.NONE -> 1.0f
                MobileOptimizationLevel.LOW -> 0.9f
                MobileOptimizationLevel.MEDIUM -> 0.6f
                MobileOptimizationLevel.HIGH -> 0.3f
                MobileOptimizationLevel.EXTREME -> 0.1f
            }
        } else {
            1.0f
        }
    }
    
    /**
     * Calculates effective max lights based on quality
     */
    fun getEffectiveMaxLights(): Int {
        val qualityFactor = qualityPreset.performanceLevel
        return (maxLights * qualityFactor).toInt().coerceAtLeast(2)
    }
    
    /**
     * Gets shadow resolution adjusted for quality
     */
    fun getEffectiveShadowResolution(): Int {
        return when (shadowQuality) {
            ShadowQuality.OFF -> 0
            ShadowQuality.LOW -> shadowMapResolution / 2
            ShadowQuality.MEDIUM -> shadowMapResolution
            ShadowQuality.HIGH -> (shadowMapResolution * 1.5).toInt()
            ShadowQuality.ULTRA -> shadowMapResolution * 2
        }
    }
    
    /**
     * Determines if full PBR should be used
     */
    fun useFullPBR(): Boolean {
        return qualityPreset != QualityPreset.LOW && 
               mobileOptimizationLevel != MobileOptimizationLevel.EXTREME
    }
    
    /**
     * Validates configuration settings
     */
    fun validate(): LightingSystemConfig {
        return copy(
            maxLights = maxLights.coerceIn(1, 8),
            maxDynamicLights = maxDynamicLights.coerceIn(1, maxLights),
            shadowCascadeCount = shadowCascadeCount.coerceIn(1, 4),
            shadowMapResolution = shadowMapResolution.coerceIn(256, 4096),
            targetFrameRate = targetFrameRate.coerceIn(30, 120),
            shadowPCFSamples = shadowPCFSamples.coerceIn(1, 32),
            maxMaterialLayers = maxMaterialLayers.coerceIn(1, 8),
            maxTextureSize = maxTextureSize.coerceIn(512, 8192),
            lodBias = lodBias.coerceIn(0f, 4f),
            adaptiveQualityFactor = adaptiveQualityFactor.coerceIn(0f, 1f)
        )
    }
}

/**
 * Light source data structure
 */
data class LightSource(
    val id: Int = 0,
    val type: LightType = LightType.POINT,
    val position: Offset = Offset(0.5f, 0.3f), // Normalized [0,1] or world coordinates
    val color: Color = Color.White,
    val intensity: Float = 1f,
    val radius: Float = 100f, // For point lights
    val direction: Offset = Offset(0f, -1f), // For directional/spot lights
    val spotAngle: Float = 45f, // For spot lights (in degrees)
    val enabled: Boolean = true,
    val castsShadow: Boolean = false,
    val importance: Float = 1.0f // For light sorting/culling
) {
    companion object {
        fun defaultPointLight() = LightSource(
            type = LightType.POINT,
            position = Offset(0.5f, 0.3f),
            color = Color.White,
            intensity = 1f,
            radius = 100f
        )
        
        fun defaultDirectionalLight() = LightSource(
            type = LightType.DIRECTIONAL,
            direction = Offset(0.3f, -1f),
            color = Color.White,
            intensity = 0.8f
        )
        
        fun defaultSpotLight() = LightSource(
            type = LightType.SPOT,
            position = Offset(0.5f, 0.2f),
            direction = Offset(0f, -1f),
            color = Color.White,
            intensity = 1.2f,
            spotAngle = 30f
        )
        
        fun warmLight() = LightSource(
            type = LightType.POINT,
            position = Offset(0.3f, 0.2f),
            color = Color(1f, 0.9f, 0.7f), // Warm white
            intensity = 0.8f
        )
        
        fun coolLight() = LightSource(
            type = LightType.POINT,
            position = Offset(0.7f, 0.4f),
            color = Color(0.7f, 0.85f, 1f), // Cool white
            intensity = 0.6f
        )
        
        fun rimLight() = LightSource(
            type = LightType.SPOT,
            position = Offset(0.9f, 0.5f),
            direction = Offset(-1f, 0f),
            color = Color(1f, 1f, 1f),
            intensity = 1.5f,
            spotAngle = 60f
        )
    }
    
    /**
     * Converts color to RGB float array
     */
    fun toRGBArray(): FloatArray = floatArrayOf(
        color.red,
        color.green,
        color.blue
    )
    
    /**
     * Converts position to 3D coordinates
     */
    fun toPosition3D(): FloatArray = floatArrayOf(
        position.x * 100f, // Scale to reasonable world coordinates
        position.y * 100f,
        50f // Assume light at height 50
    )
    
    /**
     * Converts direction to normalized 3D vector
     */
    fun toDirection3D(): FloatArray {
        val length = kotlin.math.sqrt(direction.x * direction.x + direction.y * direction.y)
        return floatArrayOf(
            direction.x / length,
            direction.y / length,
            -0.5f // Slight downward tilt
        )
    }
}

/**
 * Environment configuration for IBL
 */
data class EnvironmentConfig(
    val useHDR: Boolean = true,
    val exposure: Float = 1f,
    val rotation: Float = 0f,
    val backgroundIntensity: Float = 1f,
    val irradianceIntensity: Float = 1f,
    val radianceIntensity: Float = 1f
)