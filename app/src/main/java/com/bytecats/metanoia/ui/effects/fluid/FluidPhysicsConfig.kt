package com.bytecats.metanoia.ui.effects.fluid

import android.graphics.ColorSpace
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmapConfig
import androidx.compose.ui.graphics.colorspace.ColorSpaces
import kotlinx.serialization.Serializable

/**
 * Configuration for fluid physics simulation parameters.
 * Mobile-optimized defaults based on research in docs/research/fluid_simulation_agsl.md
 */
@Serializable
data class FluidPhysicsConfig(
    // Basic fluid properties
    val viscosity: Float = 0.0001f,
    val density: Float = 1.0f,
    val diffusion: Float = 0.00001f,

    // Velocity field parameters
    val velocityDamping: Float = 0.99f,
    val velocityDissipation: Float = 0.001f,
    val maxVelocity: Float = 10.0f,
    val velocityScale: Float = 1.0f,

    // Simulation resolution (multi-scale approach)
    val physicsResolution: Int = 128,
    val visualResolution: Int = 512,

    // Pressure projection settings
    val pressureIterations: Int = 20,
    val pressureTolerance: Float = 0.001f,
    val pressureUnderRelaxation: Float = 1.0f,

    // Advection settings
    val advectionTimestep: Float = 0.016f, // ~60 FPS
    val advectionMethod: AdvectionMethod = AdvectionMethod.SEMI_LAGRANGIAN,
    val advectionDissipation: Float = 0.0001f,

    // Vorticity settings
    val enableVorticityConfinement: Boolean = false,
    val vorticityEpsilon: Float = 0.3f,
    val vorticityScale: Float = 1.0f,

    // Boundary conditions
    val boundaryMode: BoundaryMode = BoundaryMode.NO_SLIP,
    val wallDamping: Float = 0.8f,
    val reflectionCoefficients: Float2D = Float2D(-0.5f, -0.5f),

    // Density/Dye parameters
    val densityDecay: Float = 0.002f,
    val densitySpread: Float = 1.0f,
    val maxDensity: Float = 1.0f,

    // Performance optimizations
    val enableAdaptiveQuality: Boolean = true,
    val targetFPS: Float = 60f,
    val minFPS: Float = 30f,
    val enableProfiling: Boolean = false,

    // Force application
    val forceRadius: Float = 0.1f,
    val forceStrength: Float = 10.0f,
    val forceDecay: Float = 0.5f,

    // Texture format (mobile-optimized)
    val useHalfFloat: Boolean = true,
    val textureWrapMode: TextureWrapMode = TextureWrapMode.CLAMP_TO_EDGE,
    val textureFilterMode: FilterMode = FilterMode.LINEAR
) {
    companion object {
        /**
         * Quality presets optimized for different device tiers.
         * Based on research recommendations for mobile performance.
         */
        val PRESETS = mapOf(
            QualityPreset.BUDGET to FluidPhysicsConfig(
                viscosity = 0.0002f,
                density = 1.0f,
                diffusion = 0.00002f,
                velocityDamping = 0.98f,
                velocityDissipation = 0.002f,
                maxVelocity = 8.0f,
                velocityScale = 0.8f,
                physicsResolution = 64,
                visualResolution = 256,
                pressureIterations = 10,
                pressureTolerance = 0.002f,
                advectionTimestep = 0.033f, // ~30 FPS
                advectionMethod = AdvectionMethod.SEMI_LAGRANGIAN,
                enableVorticityConfinement = false,
                targetFPS = 30f,
                minFPS = 20f,
                useHalfFloat = true
            ),
            QualityPreset.MEDIUM to FluidPhysicsConfig(
                viscosity = 0.0001f,
                density = 1.0f,
                diffusion = 0.00001f,
                velocityDamping = 0.99f,
                velocityDissipation = 0.001f,
                maxVelocity = 10.0f,
                velocityScale = 1.0f,
                physicsResolution = 128,
                visualResolution = 512,
                pressureIterations = 20,
                pressureTolerance = 0.001f,
                advectionTimestep = 0.016f,
                advectionMethod = AdvectionMethod.SEMI_LAGRANGIAN,
                enableVorticityConfinement = false,
                targetFPS = 60f,
                minFPS = 45f,
                useHalfFloat = true
            ),
            QualityPreset.HIGH to FluidPhysicsConfig(
                viscosity = 0.0001f,
                density = 1.0f,
                diffusion = 0.000005f,
                velocityDamping = 0.995f,
                velocityDissipation = 0.0005f,
                maxVelocity = 12.0f,
                velocityScale = 1.2f,
                physicsResolution = 256,
                visualResolution = 1024,
                pressureIterations = 30,
                pressureTolerance = 0.0005f,
                advectionTimestep = 0.016f,
                advectionMethod = AdvectionMethod.MACCORMACK,
                enableVorticityConfinement = true,
                vorticityScale = 1.5f,
                targetFPS = 60f,
                minFPS = 50f,
                useHalfFloat = true
            ),
            QualityPreset.ULTRA to FluidPhysicsConfig(
                viscosity = 0.00005f,
                density = 1.0f,
                diffusion = 0.000002f,
                velocityDamping = 0.998f,
                velocityDissipation = 0.0002f,
                maxVelocity = 15.0f,
                velocityScale = 1.5f,
                physicsResolution = 512,
                visualResolution = 2048,
                pressureIterations = 40,
                pressureTolerance = 0.0001f,
                advectionTimestep = 0.016f,
                advectionMethod = AdvectionMethod.BFECC,
                enableVorticityConfinement = true,
                vorticityScale = 2.0f,
                targetFPS = 60f,
                minFPS = 55f,
                useHalfFloat = true
            )
        )

        /**
         * Create config based on detected device capabilities
         */
        fun forDevice(deviceTier: DeviceTier): FluidPhysicsConfig {
            return when (deviceTier) {
                DeviceTier.BUDGET -> PRESETS[QualityPreset.BUDGET]!!
                DeviceTier.MID_RANGE -> PRESETS[QualityPreset.MEDIUM]!!
                DeviceTier.FLAGSHIP -> PRESETS[QualityPreset.HIGH]!!
                DeviceTier.ULTRA -> PRESETS[QualityPreset.ULTRA]!!
            }
        }
    }

    /**
     * Calculate texel size for a given resolution
     */
    fun getTexelSize(resolution: Int): Float2D {
        return Float2D(1.0f / resolution, 1.0f / resolution)
    }

    /**
     * Get texture configuration based on settings
     */
    fun getTextureConfig(): TextureConfig {
        return TextureConfig(
            colorSpace = if (useHalfFloat) {
                ColorSpaces.Srgb // Use sRGB with linear workflow
            } else {
                ColorSpaces.Srgb
            },
            hasAlpha = true,
            premultiplied = true,
            wrapMode = textureWrapMode,
            filterMode = textureFilterMode
        )
    }

    /**
     * Validate configuration parameters
     */
    fun validate(): ValidationResult {
        val errors = mutableListOf<String>()

        if (viscosity < 0) errors.add("Viscosity must be non-negative")
        if (density <= 0) errors.add("Density must be positive")
        if (diffusion < 0) errors.add("Diffusion must be non-negative")
        if (velocityDamping < 0 || velocityDamping > 1) {
            errors.add("Velocity damping must be in [0, 1]")
        }
        if (pressureIterations < 1) errors.add("Pressure iterations must be at least 1")
        if (physicsResolution !in 32..1024) {
            errors.add("Physics resolution must be in [32, 1024]")
        }
        if (visualResolution !in 64..4096) {
            errors.add("Visual resolution must be in [64, 4096]")
        }

        return ValidationResult(
            isValid = errors.isEmpty(),
            errors = errors
        )
    }
}

/**
 * Advection method types with different performance/quality trade-offs
 */
enum class AdvectionMethod {
    /**
     * Basic semi-Lagrangian advection.
     * Unconditionally stable, fast, good default.
     */
    SEMI_LAGRANGIAN,

    /**
     * MacCormack scheme with error correction.
     * 2x texture lookups, better accuracy.
     */
    MACCORMACK,

    /**
     * Back and Forth Error Compensation and Correction.
     * Highest accuracy, very expensive. Desktop-quality fluid.
     */
    BFECC
}

/**
 * Boundary condition modes for simulation edges
 */
enum class BoundaryMode {
    /**
     * No-slip: velocity is reflected at boundaries (u_wall = -u_neighbor)
     */
    NO_SLIP,

    /**
     * Free-slip: tangential velocity is preserved
     */
    FREE_SLIP,

    /**
     * Periodic: wrap around edges (toroidal topology)
     */
    PERIODIC,

    /**
     * Open: fluid can flow freely out of domain
     */
    OPEN
}

/**
 * Quality preset levels for different device capabilities
 */
enum class QualityPreset {
    BUDGET,      // Low-end devices, 30 FPS target
    MEDIUM,      // Mid-range devices, 60 FPS target
    HIGH,        // Flagship devices, 60 FPS with effects
    ULTRA        // High-end flagships, maximum quality
}

/**
 * Device tier classification
 */
enum class DeviceTier {
    BUDGET,      // < 3GB RAM, OpenGL ES 2.0
    MID_RANGE,   // 3-6GB RAM, OpenGL ES 3.0
    FLAGSHIP,    // 6-12GB RAM, OpenGL ES 3.1+
    ULTRA        // > 12GB RAM, OpenGL ES 3.2+
}

/**
 * Texture wrap mode
 */
enum class TextureWrapMode {
    REPEAT,
    CLAMP_TO_EDGE,
    MIRRORED_REPEAT
}

/**
 * Texture filter mode
 */
enum class FilterMode {
    NEAREST,
    LINEAR
}

/**
 * 2D float vector helper
 */
@Serializable
data class Float2D(val x: Float, val y: Float)

/**
 * Texture configuration
 */
data class TextureConfig(
    val colorSpace: ColorSpace,
    val hasAlpha: Boolean,
    val premultiplied: Boolean,
    val wrapMode: TextureWrapMode,
    val filterMode: FilterMode
)

/**
 * Configuration validation result
 */
data class ValidationResult(
    val isValid: Boolean,
    val errors: List<String>
)