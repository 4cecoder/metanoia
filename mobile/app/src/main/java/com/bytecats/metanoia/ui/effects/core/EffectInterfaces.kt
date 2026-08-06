package com.bytecats.metanoia.ui.effects.core

import android.content.Context
import android.graphics.RenderEffect
import android.graphics.RenderNode
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.ConcurrentHashMap

/**
 * Resource manager for effects pipeline.
 * Handles creation, caching, and lifecycle of graphics resources.
 */
internal class EffectsResourceManager {
    private val resourceLock = Mutex()
    private val renderNodes = ConcurrentHashMap<String, RenderNode>()
    private val renderEffects = ConcurrentHashMap<String, RenderEffect>()
    private var isInitialized = false

    /**
     * Initialize the resource manager
     */
    suspend fun initialize() {
        resourceLock.withLock {
            if (isInitialized) return
            isInitialized = true
        }
    }

    /**
     * Create or get a cached render node
     */
    suspend fun getRenderNode(key: String, width: Int, height: Int): RenderNode {
        val cacheKey = "${key}_${width}x${height}"
        
        return renderNodes[cacheKey] ?: resourceLock.withLock {
            renderNodes.getOrPut(cacheKey) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    RenderNode("effect_$key").apply {
                        setPosition(0, 0, width, height)
                    }
                } else {
                    throw UnsupportedOperationException("RenderNode requires API 29+")
                }
            }
        }
    }

    /**
     * Cache a render effect
     */
    suspend fun cacheRenderEffect(key: String, effect: RenderEffect) {
        resourceLock.withLock {
            renderEffects[key] = effect
        }
    }

    /**
     * Get cached render effect
     */
    fun getCachedRenderEffect(key: String): RenderEffect? {
        return renderEffects[key]
    }

    /**
     * Clear all resources
     */
    suspend fun clearResources() {
        resourceLock.withLock {
            renderNodes.clear()
            renderEffects.clear()
        }
    }

    /**
     * Release resources
     */
    suspend fun release() {
        clearResources()
        isInitialized = false
    }
}

/**
 * Pass executor for running render passes.
 */
internal class PassExecutor {
    private val passLock = Mutex()

    /**
     * Execute a render pass with given effects
     */
    suspend fun executePass(
        pass: RenderPass,
        input: RenderInput,
        effects: List<ActiveEffect>,
        qualityManager: GraphicsQualityManager
    ): RenderOutput = passLock.withLock {
        try {
            var modifier = input.baseModifier
            
            // Apply effects based on pass configuration
            for (activeEffect in effects) {
                if (qualityManager.shouldApplyEffect(activeEffect.effect)) {
                    modifier = activeEffect.effect.apply(
                        modifier = modifier,
                        config = activeEffect.config,
                        time = input.frameTime
                    )
                }
            }
            
            RenderOutput(
                modifier = modifier,
                metadata = mapOf(
                    "passId" to pass.id,
                    "effectsApplied" to effects.size,
                    "executionTime" to System.currentTimeMillis()
                )
            )
        } catch (e: Exception) {
            throw EffectsPipelineException("Pass execution failed", e)
        }
    }
}

/**
 * Base effect interface that all effects must implement.
 */
interface Effect {
    /**
     * Unique name identifier for the effect
     */
    val name: String
    
    /**
     * Version of the effect implementation
     */
    val version: String
    
    /**
     * Dependencies required by this effect
     */
    val dependencies: Set<kotlin.reflect.KClass<out Effect>>
    
    /**
     * Apply this effect to a modifier
     * 
     * @param modifier The base modifier to apply the effect to
     * @param config Configuration for this effect instance
     * @param time Time parameter for animated effects
     * @return Modified modifier with effect applied
     */
    fun apply(
        modifier: Modifier,
        config: EffectConfig,
        time: Float
    ): Modifier
    
    /**
     * Get default configuration for this effect
     */
    fun defaultConfig(): EffectConfig
    
    /**
     * Estimate resource cost of this effect in MB
     */
    fun estimateResourceCost(): Float {
        return when {
            name.contains("lighting", ignoreCase = true) -> 16f
            name.contains("shadow", ignoreCase = true) -> 12f
            name.contains("reflection", ignoreCase = true) -> 24f
            name.contains("post", ignoreCase = true) -> 8f
            else -> 4f
        }
    }
    
    /**
     * Check if this effect is compatible with the current API level
     */
    fun isCompatible(): Boolean {
        return when {
            name.contains("lighting", ignoreCase = true) -> 
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
            name.contains("shader", ignoreCase = true) -> 
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
            else -> true
        }
    }
}

/**
 * Base configuration interface for effects
 */
interface EffectConfig {
    /**
     * Whether the effect is enabled
     */
    val enabled: Boolean
        get() = true
    
    /**
     * Intensity of the effect (0.0 to 1.0)
     */
    val intensity: Float
        get() = 1f
    
    /**
     * Priority for rendering order
     */
    val priority: EffectPriority
        get() = EffectPriority.NORMAL
}

/**
 * Extension functions for integration with existing effects
 */

/**
 * Convert ParallaxEffects.kt configurations to EffectConfig
 */
fun com.bytecats.metanoia.ui.effects.ParallaxConfig.toEffectConfig(): EffectConfig = object : EffectConfig {
    override val enabled: Boolean = true
    override val intensity: Float = this@toEffectConfig.intensity
    override val priority: EffectPriority = EffectPriority.NORMAL
}

/**
 * Convert LightingEffects.kt configurations to EffectConfig
 */
fun com.bytecats.metanoia.ui.effects.ShadowConfig.toEffectConfig(): EffectConfig = object : EffectConfig {
    override val enabled: Boolean = this@toEffectConfig.opacity > 0f
    override val intensity: Float = this@toEffectConfig.opacity
    override val priority: EffectPriority = EffectPriority.HIGH
}

/**
 * Convert LightSource to EffectConfig
 */
fun com.bytecats.metanoia.ui.effects.LightSource.toEffectConfig(): EffectConfig = object : EffectConfig {
    override val enabled: Boolean = this@toEffectConfig.intensity > 0f
    override val intensity: Float = this@toEffectConfig.intensity
    override val priority: EffectPriority = EffectPriority.HIGH
}

/**
 * Effect wrapper for ParallaxEffects
 */
class ParallaxEffectWrapper(
    private val config: com.bytecats.metanoia.ui.effects.ParallaxConfig = com.bytecats.metanoia.ui.effects.ParallaxConfig()
) : Effect {
    override val name: String = "parallax"
    override val version: String = "1.0.0"
    override val dependencies: Set<kotlin.reflect.KClass<out Effect>> = emptySet()
    
    override fun apply(
        modifier: Modifier,
        config: EffectConfig,
        time: Float
    ): Modifier {
        return modifier // Parallax is applied via specific modifiers
    }
    
    override fun defaultConfig(): EffectConfig = config.toEffectConfig()
}

/**
 * Effect wrapper for LightingEffects
 */
class LightingEffectWrapper(
    private val lightSource: com.bytecats.metanoia.ui.effects.LightSource = com.bytecats.metanoia.ui.effects.LightSource(),
    private val time: Float = 0f
) : Effect {
    override val name: String = "lighting"
    override val version: String = "1.0.0"
    override val dependencies: Set<kotlin.reflect.KClass<out Effect>> = emptySet()
    
    override fun apply(
        modifier: Modifier,
        config: EffectConfig,
        time: Float
    ): Modifier {
        return modifier // Lighting is applied via specific modifiers
    }
    
    override fun defaultConfig(): EffectConfig = lightSource.toEffectConfig()
}

/**
 * Effect wrapper for ShadowEffects
 */
class ShadowEffectWrapper(
    private val config: com.bytecats.metanoia.ui.effects.ShadowConfig = com.bytecats.metanoia.ui.effects.ShadowConfig()
) : Effect {
    override val name: String = "shadow"
    override val version: String = "1.0.0"
    override val dependencies: Set<kotlin.reflect.KClass<out Effect>> = emptySet()
    
    override fun apply(
        modifier: Modifier,
        config: EffectConfig,
        time: Float
    ): Modifier {
        return modifier // Shadow is applied via specific modifiers
    }
    
    override fun defaultConfig(): EffectConfig = config.toEffectConfig()
}