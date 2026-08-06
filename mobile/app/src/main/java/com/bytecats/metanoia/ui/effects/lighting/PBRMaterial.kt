package com.bytecats.metanoia.ui.effects.lighting

import androidx.compose.ui.graphics.Color

/**
 * PBR Material Properties
 * Contains all physical properties needed for physically-based rendering
 */
data class PBRMaterial(
    /** Base color of the material (albedo) */
    val albedo: Color = Color.White,
    
    /** Metallic property (0.0 = dielectric, 1.0 = metallic) */
    val metallic: Float = 0.0f,
    
    /** Roughness property (0.0 = smooth, 1.0 = rough) */
    val roughness: Float = 0.5f,
    
    /** Emissive color for self-illumination */
    val emissive: Color = Color.Black,
    
    /** Normal map strength (0.0 = flat, 1.0 = full normal effect) */
    val normalStrength: Float = 1.0f,
    
    /** Ambient occlusion factor (0.0 = fully occluded, 1.0 = no occlusion) */
    val occlusion: Float = 1.0f,
    
    /** Opacity (0.0 = transparent, 1.0 = opaque) */
    val opacity: Float = 1.0f
) {
    companion object {
        /** Default dielectric material (plastic-like) */
        fun defaultDielectric() = PBRMaterial(
            albedo = Color(0.8f, 0.8f, 0.8f),
            metallic = 0.0f,
            roughness = 0.5f
        )
        
        /** Default metallic material (metal-like) */
        fun defaultMetallic() = PBRMaterial(
            albedo = Color(0.7f, 0.7f, 0.7f),
            metallic = 1.0f,
            roughness = 0.4f
        )
        
        /** Glass material */
        fun glass() = PBRMaterial(
            albedo = Color(0.9f, 0.9f, 0.9f),
            metallic = 0.0f,
            roughness = 0.05f,
            opacity = 0.3f
        )
        
        /** Mirror material */
        fun mirror() = PBRMaterial(
            albedo = Color(0.95f, 0.95f, 0.95f),
            metallic = 1.0f,
            roughness = 0.0f
        )
        
        /** Matte material */
        fun matte(color: Color = Color.White) = PBRMaterial(
            albedo = color,
            metallic = 0.0f,
            roughness = 0.9f
        )
        
        /** Glossy plastic */
        fun glossyPlastic(color: Color = Color.White) = PBRMaterial(
            albedo = color,
            metallic = 0.0f,
            roughness = 0.2f
        )
        
        /** Rough metal */
        fun roughMetal(color: Color = Color(0.6f, 0.6f, 0.6f)) = PBRMaterial(
            albedo = color,
            metallic = 1.0f,
            roughness = 0.7f
        )
        
        /** Emissive material (glowing) */
        fun emissive(
            color: Color = Color.White,
            baseAlbedo: Color = Color.White
        ) = PBRMaterial(
            albedo = baseAlbedo,
            metallic = 0.0f,
            roughness = 0.5f,
            emissive = color
        )
    }
    
    /**
     * Validates material properties and clamps to valid ranges
     */
    fun validate(): PBRMaterial {
        return copy(
            metallic = metallic.coerceIn(0f, 1f),
            roughness = roughness.coerceIn(0.04f, 1f), // Prevent division by zero
            normalStrength = normalStrength.coerceIn(0f, 2f),
            occlusion = occlusion.coerceIn(0f, 1f),
            opacity = opacity.coerceIn(0f, 1f)
        )
    }
    
    /**
     * Blends this material with another based on weight
     */
    fun blendWith(other: PBRMaterial, weight: Float): PBRMaterial {
        val clampedWeight = weight.coerceIn(0f, 1f)
        return PBRMaterial(
            albedo = Color(
                red = albedo.red * (1f - clampedWeight) + other.albedo.red * clampedWeight,
                green = albedo.green * (1f - clampedWeight) + other.albedo.green * clampedWeight,
                blue = albedo.blue * (1f - clampedWeight) + other.albedo.blue * clampedWeight,
                alpha = albedo.alpha * (1f - clampedWeight) + other.albedo.alpha * clampedWeight
            ),
            metallic = metallic * (1f - clampedWeight) + other.metallic * clampedWeight,
            roughness = roughness * (1f - clampedWeight) + other.roughness * clampedWeight,
            emissive = Color(
                red = emissive.red * (1f - clampedWeight) + other.emissive.red * clampedWeight,
                green = emissive.green * (1f - clampedWeight) + other.emissive.green * clampedWeight,
                blue = emissive.blue * (1f - clampedWeight) + other.emissive.blue * clampedWeight,
                alpha = emissive.alpha * (1f - clampedWeight) + other.emissive.alpha * clampedWeight
            ),
            normalStrength = normalStrength * (1f - clampedWeight) + other.normalStrength * clampedWeight,
            occlusion = occlusion * (1f - clampedWeight) + other.occlusion * clampedWeight,
            opacity = opacity * (1f - clampedWeight) + other.opacity * clampedWeight
        )
    }
    
    /**
     * Creates a modified copy with adjusted properties
     */
    fun adjust(
        albedoMultiplier: Float = 1f,
        roughnessDelta: Float = 0f,
        metallicDelta: Float = 0f
    ): PBRMaterial {
        return copy(
            albedo = Color(
                red = (albedo.red * albedoMultiplier).coerceIn(0f, 1f),
                green = (albedo.green * albedoMultiplier).coerceIn(0f, 1f),
                blue = (albedo.blue * albedoMultiplier).coerceIn(0f, 1f),
                alpha = albedo.alpha
            ),
            roughness = (roughness + roughnessDelta).coerceIn(0.04f, 1f),
            metallic = (metallic + metallicDelta).coerceIn(0f, 1f)
        )
    }
}

/**
 * Material layer for layered materials
 */
data class MaterialLayer(
    val material: PBRMaterial = PBRMaterial(),
    val weight: Float = 1f,
    val blendMode: BlendMode = BlendMode.MIX
) {
    enum class BlendMode {
        MIX,           // Linear interpolation
        ADD,           // Additive
        MULTIPLY,      // Multiplicative
        SCREEN         // Screen blend
    }
}

/**
 * Normal map data structure
 */
data class NormalMap(
    val enabled: Boolean = false,
    val strength: Float = 1.0f,
    val scale: Float = 1.0f
) {
    companion object {
        fun disabled() = NormalMap(enabled = false)
        fun default() = NormalMap(enabled = true, strength = 1.0f, scale = 1.0f)
        fun strong() = NormalMap(enabled = true, strength = 1.5f, scale = 1.0f)
        fun subtle() = NormalMap(enabled = true, strength = 0.5f, scale = 1.0f)
    }
}