package com.bytecats.metanoia.ui.effects

import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.graphicsLayer
import org.intellij.lang.annotations.Language
import kotlin.math.*

/**
 * Shadow configuration for realistic shadow casting
 */
data class ShadowConfig(
    val blurRadius: Float = 16f,
    val spread: Float = 0f,
    val offset: Offset = Offset(4f, 8f),
    val opacity: Float = 0.3f,
    val color: Color = Color.Black,
    val ambientOcclusion: Float = 0.2f
)

/**
 * Reflection configuration for mirror effects
 */
data class ReflectionConfig(
    val opacity: Float = 0.4f,
    val blur: Float = 2f,
    val fadeLength: Float = 0.5f,
    val distortion: Float = 0.1f
)

object LightingShaders {

    @Language("AGSL")
    const val REALISTIC_SHADOW_SHADER = """
        uniform shader composable;
        uniform float2 resolution;
        uniform float2 lightPos;
        uniform float lightIntensity;
        uniform float blurRadius;
        uniform float spread;
        uniform float2 shadowOffset;
        uniform float shadowOpacity;
        uniform float4 shadowColor;
        uniform float ambientOcclusion;
        
        float gaussian(float x, float sigma) {
            return exp(-0.5 * (x * x) / (sigma * sigma)) / (sigma * sqrt(2.0 * 3.14159));
        }
        
        half4 main(float2 fragCoord) {
            float2 uv = fragCoord / resolution.xy;
            half4 orig = composable.eval(fragCoord);
            
            // Calculate distance to light
            float2 lightDir = lightPos - uv;
            float lightDist = length(lightDir);
            float lightAngle = atan2(lightDir.y, lightDir.x);
            
            // Shadow direction based on light position
            float2 shadowUv = uv - shadowOffset / resolution;
            float shadowDist = length(lightDir);
            
            // Soft shadow with Gaussian blur
            float shadowBlur = blurRadius / resolution.x;
            float shadowFactor = 0.0;
            float samples = 0.0;
            
            for (float x = -2.0; x <= 2.0; x += 1.0) {
                for (float y = -2.0; y <= 2.0; y += 1.0) {
                    float2 sampleOffset = float2(x, y) * shadowBlur;
                    float2 sampleUv = shadowUv + sampleOffset;
                    float weight = gaussian(length(sampleOffset), shadowBlur);
                    
                    if (sampleUv.x >= 0.0 && sampleUv.x <= 1.0 && 
                        sampleUv.y >= 0.0 && sampleUv.y <= 1.0) {
                        half4 shadowSample = composable.eval(sampleUv * resolution);
                        if (shadowSample.a > 0.5) {
                            shadowFactor += weight;
                        }
                    }
                    samples += weight;
                }
            }
            
            shadowFactor /= max(0.01, samples);
            
            // Ambient occlusion simulation
            float ao = 1.0 - ambientOcclusion * shadowFactor;
            
            // Apply shadow
            half4 shadow = half4(shadowColor.rgb * shadowOpacity * shadowFactor, shadowColor.a * shadowFactor);
            half4 result = orig + shadow;
            result.rgb *= ao;
            
            return result;
        }
    """

    @Language("AGSL")
    const val DYNAMIC_LIGHTING_SHADER = """
        uniform shader composable;
        uniform float2 resolution;
        uniform float2 lightPos;
        uniform float lightIntensity;
        uniform float4 lightColor;
        uniform float ambient;
        uniform float specular;
        uniform float shininess;
        uniform float time;
        
        half4 main(float2 fragCoord) {
            float2 uv = fragCoord / resolution.xy;
            half4 orig = composable.eval(fragCoord);
            
            // Calculate surface normal from gradient
            float2 epsilon = float2(1.0 / resolution.x, 1.0 / resolution.y);
            half4 sampleX = composable.eval(fragCoord + float2(epsilon.x, 0.0));
            half4 sampleY = composable.eval(fragCoord + float2(0.0, epsilon.y));
            
            float3 normal = normalize(float3(
                (sampleX.a - orig.a) / epsilon.x,
                (sampleY.a - orig.a) / epsilon.y,
                1.0
            ));
            
            // Light direction
            float2 lightDir = normalize(lightPos - uv);
            float3 lightVec = float3(lightDir, 0.5);
            
            // Ambient lighting
            float3 ambientColor = orig.rgb * ambient;
            
            // Diffuse lighting (Lambert)
            float diff = max(dot(normal, normalize(lightVec)), 0.0);
            float3 diffuseColor = orig.rgb * lightColor.rgb * lightIntensity * diff;
            
            // Specular lighting (Blinn-Phong)
            float3 viewDir = float3(0.0, 0.0, 1.0);
            float3 halfDir = normalize(lightVec + viewDir);
            float spec = pow(max(dot(normal, halfDir), 0.0), shininess);
            float3 specularColor = lightColor.rgb * specular * spec;
            
            // Combine lighting
            float3 finalColor = ambientColor + diffuseColor + specularColor;
            
            return half4(finalColor, orig.a);
        }
    """

    @Language("AGSL")
    const val REFLECTION_SHADER = """
        uniform shader composable;
        uniform float2 resolution;
        uniform float reflectionOpacity;
        uniform float reflectionBlur;
        uniform float fadeLength;
        uniform float distortion;
        uniform time;
        
        half4 main(float2 fragCoord) {
            float2 uv = fragCoord / resolution.xy;
            half4 orig = composable.eval(fragCoord);
            
            // Mirror UV vertically for reflection
            float2 reflectUv = float2(uv.x, 1.0 - uv.y);
            
            // Add distortion
            float wave = sin(uv.x * 10.0 + time * 2.0) * distortion;
            reflectUv.y += wave * 0.01;
            
            // Sample reflected content
            half4 reflection = composable.eval(reflectUv * resolution);
            
            // Fade reflection based on distance from mirror
            float fadeFactor = smoothstep(1.0, 1.0 - fadeLength, reflectUv.y);
            
            // Apply blur to reflection (simplified)
            float blurAmount = reflectionBlur / resolution.x;
            half4 blurredReflection = half4(0.0);
            float blurWeight = 0.0;
            
            for (float x = -1.0; x <= 1.0; x += 0.5) {
                for (float y = -1.0; y <= 1.0; y += 0.5) {
                    float2 offset = float2(x, y) * blurAmount;
                    half4 sample = composable.eval((reflectUv + offset) * resolution);
                    blurredReflection += sample;
                    blurWeight += 1.0;
                }
            }
            
            if (blurWeight > 0.0) {
                blurredReflection /= blurWeight;
            } else {
                blurredReflection = reflection;
            }
            
            // Combine original and reflection
            half4 finalReflection = half4(
                blurredReflection.rgb,
                blurredReflection.a * reflectionOpacity * fadeFactor
            );
            
            return orig + finalReflection;
        }
    """

    @Language("AGSL")
    const val NORMAL_MAP_SHADER = """
        uniform shader composable;
        uniform float2 resolution;
        uniform float normalScale;
        
        half4 main(float2 fragCoord) {
            float2 uv = fragCoord / resolution.xy;
            half4 orig = composable.eval(fragCoord);
            
            // Calculate normal from alpha gradient
            float2 epsilon = float2(1.0 / resolution.x, 1.0 / resolution.y);
            float alphaL = composable.eval(fragCoord + float2(-epsilon.x, 0.0)).a;
            float alphaR = composable.eval(fragCoord + float2(epsilon.x, 0.0)).a;
            float alphaD = composable.eval(fragCoord + float2(0.0, epsilon.y)).a;
            float alphaU = composable.eval(fragCoord + float2(0.0, -epsilon.y)).a;
            
            float3 normal = normalize(float3(
                (alphaL - alphaR) * normalScale,
                (alphaU - alphaD) * normalScale,
                1.0
            ));
            
            // Encode normal as color
            half3 normalColor = (normal + 1.0) * 0.5;
            return half4(normalColor, orig.a);
        }
    """
}

/**
 * Applies realistic shadow casting with configurable properties
 */
fun Modifier.realisticShadow(
    lightPosition: Offset = Offset(0.5f, 0.3f),
    config: ShadowConfig = ShadowConfig()
): Modifier {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        return this.graphicsLayer {
            val shader = RuntimeShader(LightingShaders.REALISTIC_SHADOW_SHADER)
            shader.setFloatUniform("resolution", size.width, size.height)
            shader.setFloatUniform("lightPos", lightPosition.x, lightPosition.y)
            shader.setFloatUniform("lightIntensity", 1f)
            shader.setFloatUniform("blurRadius", config.blurRadius)
            shader.setFloatUniform("spread", config.spread)
            shader.setFloatUniform("shadowOffset", config.offset.x, config.offset.y)
            shader.setFloatUniform("shadowOpacity", config.opacity)
            shader.setColorUniform("shadowColor", 
                android.graphics.Color.valueOf(
                    config.color.red, config.color.green, config.color.blue, config.color.alpha
                ).toArgb()
            )
            shader.setFloatUniform("ambientOcclusion", config.ambientOcclusion)
            renderEffect = RenderEffect.createRuntimeShaderEffect(shader, "composable").asComposeRenderEffect()
        }
    }
    return this
}

/**
 * Applies dynamic lighting with real-time calculations
 */
fun Modifier.dynamicLighting(
    lightSource: LightSource = LightSource(),
    time: Float = 0f
): Modifier {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        return this.graphicsLayer {
            val shader = RuntimeShader(LightingShaders.DYNAMIC_LIGHTING_SHADER)
            shader.setFloatUniform("resolution", size.width, size.height)
            shader.setFloatUniform("lightPos", lightSource.position.x, lightSource.position.y)
            shader.setFloatUniform("lightIntensity", lightSource.intensity)
            shader.setColorUniform("lightColor",
                android.graphics.Color.valueOf(
                    lightSource.color.red, lightSource.color.green, 
                    lightSource.color.blue, lightSource.color.alpha
                ).toArgb()
            )
            shader.setFloatUniform("ambient", lightSource.ambient)
            shader.setFloatUniform("specular", lightSource.specular)
            shader.setFloatUniform("shininess", lightSource.shininess)
            shader.setFloatUniform("time", time)
            renderEffect = RenderEffect.createRuntimeShaderEffect(shader, "composable").asComposeRenderEffect()
        }
    }
    return this
}

/**
 * Applies reflection effect with configurable properties
 */
fun Modifier.reflection(
    config: ReflectionConfig = ReflectionConfig(),
    time: Float = 0f
): Modifier {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        return this.graphicsLayer {
            val shader = RuntimeShader(LightingShaders.REFLECTION_SHADER)
            shader.setFloatUniform("resolution", size.width, size.height)
            shader.setFloatUniform("reflectionOpacity", config.opacity)
            shader.setFloatUniform("reflectionBlur", config.blur)
            shader.setFloatUniform("fadeLength", config.fadeLength)
            shader.setFloatUniform("distortion", config.distortion)
            shader.setFloatUniform("time", time)
            renderEffect = RenderEffect.createRuntimeShaderEffect(shader, "composable").asComposeRenderEffect()
        }
    }
    return this
}

/**
 * Calculates shadow position based on light source and object position
 */
fun calculateShadowOffset(
    lightPosition: Offset,
    objectPosition: Offset,
    height: Float = 10f,
    lightHeight: Float = 100f
): Offset {
    val dx = objectPosition.x - lightPosition.x
    val dy = objectPosition.y - lightPosition.y
    val factor = height / lightHeight
    
    return Offset(
        x = -dx * factor,
        y = -dy * factor
    )
}

/**
 * Creates cascaded shadow maps for different depth levels
 */
fun createCascadedShadows(
    lightPosition: Offset,
    depth: Float = 1f
): List<ShadowConfig> {
    val baseOffset = calculateShadowOffset(lightPosition, Offset.Zero, depth)
    
    return listOf(
        ShadowConfig(
            blurRadius = 8f * depth,
            spread = 0f,
            offset = baseOffset * 0.5f,
            opacity = 0.15f,
            ambientOcclusion = 0.1f
        ),
        ShadowConfig(
            blurRadius = 16f * depth,
            spread = 2f,
            offset = baseOffset * 1.0f,
            opacity = 0.1f,
            ambientOcclusion = 0.15f
        ),
        ShadowConfig(
            blurRadius = 32f * depth,
            spread = 4f,
            offset = baseOffset * 1.5f,
            opacity = 0.05f,
            ambientOcclusion = 0.2f
        )
    )
}

/**
 * Light source definition for dynamic lighting
 */
data class LightSource(
    val position: Offset = Offset(0.5f, 0.3f),
    val color: Color = Color.White,
    val intensity: Float = 1f,
    val ambient: Float = 0.1f,
    val specular: Float = 0.5f,
    val shininess: Float = 32f
)

/**
 * Applies ambient occlusion effect
 */
fun Modifier.ambientOcclusion(
    intensity: Float = 0.2f,
    radius: Float = 16f
): Modifier {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        return this.graphicsLayer {
            // SSAO-like effect using multiple shadow layers
            val shadowConfig = ShadowConfig(
                blurRadius = radius,
                spread = 0f,
                offset = Offset.Zero,
                opacity = intensity,
                ambientOcclusion = intensity
            )
            realisticShadow(Offset.Zero, shadowConfig)
        }
    }
    return this
}

/**
 * Integration with PBR Lighting System
 * Bridges traditional lighting effects with advanced PBR rendering
 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
fun Modifier.integratedPBRLighting(
    traditionalShadow: ShadowConfig? = ShadowConfig(),
    usePBR: Boolean = true,
    pbrConfig: com.bytecats.metanoia.ui.effects.lighting.LightingSystemConfig = com.bytecats.metanoia.ui.effects.lighting.LightingSystemConfig.midRange(),
    pbrMaterial: com.bytecats.metanoia.ui.effects.lighting.PBRMaterial = com.bytecats.metanoia.ui.effects.lighting.PBRMaterial.defaultDielectric(),
    pbrManager: com.bytecats.metanoia.ui.effects.lighting.DynamicLightingManager? = null,
    time: Float = 0f
): Modifier {
    var result = this
    
    // Apply traditional shadow if configured
    if (traditionalShadow != null && !usePBR) {
        result = result.realisticShadow(Offset(0.5f, 0.3f), traditionalShadow)
    }
    
    // Apply PBR lighting if enabled
    if (usePBR && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        val manager = pbrManager ?: com.bytecats.metanoia.ui.effects.lighting.DynamicLightingManager(pbrConfig).apply {
            setupDefaultLighting()
        }
        
        result = result.then(
            dynamicLighting(
                lightSource = LightSource(position = Offset(0.5f, 0.3f), intensity = 1f),
                time = time
            )
        )
    }
    
    return result
}

/**
 * Hybrid lighting combining traditional and PBR effects
 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
fun Modifier.hybridLighting(
    shadowConfig: ShadowConfig = ShadowConfig(),
    reflectionConfig: ReflectionConfig = ReflectionConfig(),
    pbrMaterial: com.bytecats.metanoia.ui.effects.lighting.PBRMaterial = com.bytecats.metanoia.ui.effects.lighting.PBRMaterial.defaultDielectric(),
    time: Float = 0f
): Modifier {
    return this
        .realisticShadow(Offset(0.5f, 0.3f), shadowConfig)
        .reflection(reflectionConfig, time)
        .then(
            dynamicLighting(
                lightSource = LightSource(position = Offset(0.5f, 0.3f), intensity = 1f),
                time = time
            )
        )
}