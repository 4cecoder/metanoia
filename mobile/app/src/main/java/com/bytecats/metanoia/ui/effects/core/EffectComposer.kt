package com.bytecats.metanoia.ui.effects.core

import android.util.Log
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.layer.GraphicsLayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.math.max
import kotlin.math.min

/**
 * Effect composition system for combining multiple effects with sophisticated blending.
 * Manages effect chaining, blending modes, and pass management.
 * 
 * @property pipeline Reference to the effects pipeline for resource access
 */
class EffectComposer(
    private val pipeline: EffectsPipeline
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val compositionLock = Mutex()
    
    private val _compositions = MutableStateFlow<Map<String, EffectComposition>>(emptyMap())
    val compositions: StateFlow<Map<String, EffectComposition>> = _compositions.asStateFlow()
    
    private val _activePasses = MutableStateFlow<List<RenderPass>>(emptyList())
    val activePasses: StateFlow<List<RenderPass>> = _activePasses.asStateFlow()
    
    private val blendModeManager = BlendModeManager()
    private val passManager = PassManager()

    companion object {
        private const val TAG = "EffectComposer"
        private const val MAX_COMPOSITION_CHAIN_LENGTH = 8
        private const val MAX_LAYERS_PER_COMPOSITION = 16
    }

    /**
     * Create a new effect composition
     */
    suspend fun createComposition(
        compositionId: String,
        config: CompositionConfig = CompositionConfig()
    ): Result<String> = compositionLock.withLock {
        return try {
            if (compositionId.isBlank()) {
                throw IllegalArgumentException("Composition ID cannot be blank")
            }
            
            if (_compositions.value.containsKey(compositionId)) {
                throw IllegalStateException("Composition $compositionId already exists")
            }
            
            val composition = EffectComposition(
                id = compositionId,
                config = config,
                layers = mutableListOf(),
                blendMode = config.blendMode,
                timestamp = System.currentTimeMillis()
            )
            
            _compositions.value = _compositions.value + (compositionId to composition)
            
            Log.i(TAG, "Composition created: $compositionId")
            Result.success(compositionId)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create composition: $compositionId", e)
            Result.failure(e)
        }
    }

    /**
     * Add an effect layer to a composition
     */
    suspend fun addLayer(
        compositionId: String,
        effect: Effect,
        config: EffectConfig,
        blendMode: BlendMode = BlendMode.NORMAL
    ): Result<Int> = compositionLock.withLock {
        return try {
            val composition = _compositions.value[compositionId]
                ?: throw IllegalStateException("Composition $compositionId not found")
            
            if (composition.layers.size >= MAX_LAYERS_PER_COMPOSITION) {
                throw IllegalStateException("Maximum layers reached for composition $compositionId")
            }
            
            val layer = EffectLayer(
                id = "${compositionId}_layer_${composition.layers.size}",
                effect = effect,
                config = config,
                blendMode = blendMode,
                opacity = 1f,
                enabled = true,
                zIndex = composition.layers.size
            )
            
            composition.layers.add(layer)
            _compositions.value = _compositions.value + (compositionId to composition)
            
            Log.i(TAG, "Layer added to composition $compositionId: ${layer.id}")
            Result.success(composition.layers.size - 1)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add layer to composition: $compositionId", e)
            Result.failure(e)
        }
    }

    /**
     * Remove an effect layer from a composition
     */
    suspend fun removeLayer(compositionId: String, layerIndex: Int): Result<Unit> = compositionLock.withLock {
        return try {
            val composition = _compositions.value[compositionId]
                ?: throw IllegalStateException("Composition $compositionId not found")
            
            if (layerIndex < 0 || layerIndex >= composition.layers.size) {
                throw IndexOutOfBoundsException("Invalid layer index: $layerIndex")
            }
            
            composition.layers.removeAt(layerIndex)
            
            // Reorder remaining layers
            composition.layers.forEachIndexed { index, layer ->
                composition.layers[index] = layer.copy(zIndex = index)
            }
            
            _compositions.value = _compositions.value + (compositionId to composition)
            
            Log.i(TAG, "Layer removed from composition $compositionId: index $layerIndex")
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to remove layer from composition: $compositionId", e)
            Result.failure(e)
        }
    }

    /**
     * Apply a composition to a modifier
     */
    fun applyComposition(
        baseModifier: Modifier,
        compositionId: String,
        time: Float = 0f
    ): Modifier {
        val composition = _compositions.value[compositionId] ?: return baseModifier
        
        if (!composition.config.enabled || composition.layers.isEmpty()) {
            return baseModifier
        }
        
        var modifier = baseModifier
        
        try {
            // Sort layers by Z-index
            val sortedLayers = composition.layers.sortedBy { it.zIndex }
            
            // Apply each layer with its blend mode
            for (layer in sortedLayers) {
                if (!layer.enabled || layer.opacity <= 0f) continue
                
                modifier = applyLayer(modifier, layer, composition, time)
            }
            
            return modifier
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply composition: $compositionId", e)
            return baseModifier
        }
    }

    /**
     * Apply a single layer with blend mode
     */
    private fun applyLayer(
        baseModifier: Modifier,
        layer: EffectLayer,
        composition: EffectComposition,
        time: Float
    ): Modifier {
        var modifier = baseModifier
        
        // Apply the effect
        modifier = layer.effect.apply(modifier, layer.config, time)
        
        // Apply blend mode
        modifier = blendModeManager.applyBlendMode(
            modifier = modifier,
            blendMode = layer.blendMode,
            opacity = layer.opacity * composition.config.globalOpacity
        )
        
        return modifier
    }

    /**
     * Chain multiple compositions together
     */
    fun chainCompositions(
        baseModifier: Modifier,
        compositionIds: List<String>,
        time: Float = 0f
    ): Modifier {
        if (compositionIds.size > MAX_COMPOSITION_CHAIN_LENGTH) {
            Log.w(TAG, "Composition chain exceeds maximum length")
        }
        
        var modifier = baseModifier
        
        for (compositionId in compositionIds.take(MAX_COMPOSITION_CHAIN_LENGTH)) {
            modifier = applyComposition(modifier, compositionId, time)
        }
        
        return modifier
    }

    /**
     * Create and execute a render pass
     */
    suspend fun createPass(
        passId: String,
        compositionIds: List<String>,
        config: PassConfig = PassConfig()
    ): Result<String> = compositionLock.withLock {
        return try {
            val pass = RenderPass(
                id = passId,
                compositionIds = compositionIds,
                config = config,
                timestamp = System.currentTimeMillis()
            )
            
            _activePasses.value = _activePasses.value + pass
            
            Log.i(TAG, "Render pass created: $passId")
            Result.success(passId)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create render pass: $passId", e)
            Result.failure(e)
        }
    }

    /**
     * Execute a render pass
     */
    fun executePass(
        passId: String,
        input: RenderInput
    ): RenderOutput {
        val pass = _activePasses.value.find { it.id == passId }
            ?: throw IllegalStateException("Render pass not found: $passId")
        
        var modifier = input.baseModifier
        
        try {
            // Execute pre-pass operations
            if (pass.config.enablePrePass) {
                modifier = executePrePass(modifier, pass)
            }
            
            // Apply compositions
            modifier = chainCompositions(modifier, pass.compositionIds, input.frameTime)
            
            // Execute post-pass operations
            if (pass.config.enablePostPass) {
                modifier = executePostPass(modifier, pass)
            }
            
            return RenderOutput(
                modifier = modifier,
                metadata = mapOf(
                    "passId" to passId,
                    "compositions" to pass.compositionIds.size,
                    "executionTime" to System.currentTimeMillis()
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to execute render pass: $passId", e)
            throw EffectCompositionException("Render pass execution failed", e)
        }
    }

    /**
     * Execute pre-pass operations
     */
    private fun executePrePass(modifier: Modifier, pass: RenderPass): Modifier {
        return passManager.executePrePass(modifier, pass.config)
    }

    /**
     * Execute post-pass operations
     */
    private fun executePostPass(modifier: Modifier, pass: RenderPass): Modifier {
        return passManager.executePostPass(modifier, pass.config)
    }

    /**
     * Update composition configuration
     */
    suspend fun updateCompositionConfig(
        compositionId: String,
        config: CompositionConfig
    ): Result<Unit> = compositionLock.withLock {
        return try {
            val composition = _compositions.value[compositionId]
                ?: throw IllegalStateException("Composition $compositionId not found")
            
            _compositions.value = _compositions.value + (
                compositionId to composition.copy(config = config)
            )
            
            Log.i(TAG, "Composition config updated: $compositionId")
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update composition config: $compositionId", e)
            Result.failure(e)
        }
    }

    /**
     * Update layer configuration
     */
    suspend fun updateLayerConfig(
        compositionId: String,
        layerIndex: Int,
        opacity: Float? = null,
        blendMode: BlendMode? = null,
        enabled: Boolean? = null
    ): Result<Unit> = compositionLock.withLock {
        return try {
            val composition = _compositions.value[compositionId]
                ?: throw IllegalStateException("Composition $compositionId not found")
            
            if (layerIndex < 0 || layerIndex >= composition.layers.size) {
                throw IndexOutOfBoundsException("Invalid layer index: $layerIndex")
            }
            
            val layer = composition.layers[layerIndex]
            composition.layers[layerIndex] = layer.copy(
                opacity = opacity ?: layer.opacity,
                blendMode = blendMode ?: layer.blendMode,
                enabled = enabled ?: layer.enabled
            )
            
            _compositions.value = _compositions.value + (compositionId to composition)
            
            Log.i(TAG, "Layer config updated in composition $compositionId: index $layerIndex")
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update layer config in composition: $compositionId", e)
            Result.failure(e)
        }
    }

    /**
     * Delete a composition
     */
    suspend fun deleteComposition(compositionId: String): Result<Unit> = compositionLock.withLock {
        return try {
            if (!_compositions.value.containsKey(compositionId)) {
                throw IllegalStateException("Composition $compositionId not found")
            }
            
            _compositions.value = _compositions.value - compositionId
            
            Log.i(TAG, "Composition deleted: $compositionId")
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete composition: $compositionId", e)
            Result.failure(e)
        }
    }

    /**
     * Clear all compositions
     */
    suspend fun clearCompositions() = compositionLock.withLock {
        _compositions.value = emptyMap()
        _activePasses.value = emptyList()
        
        Log.i(TAG, "All compositions cleared")
    }

    /**
     * Get composition information
     */
    fun getCompositionInfo(compositionId: String): CompositionInfo? {
        val composition = _compositions.value[compositionId] ?: return null
        
        return CompositionInfo(
            id = composition.id,
            layerCount = composition.layers.size,
            blendMode = composition.blendMode,
            enabled = composition.config.enabled,
            timestamp = composition.timestamp
        )
    }

    /**
     * Get all composition IDs
     */
    fun getCompositionIds(): Set<String> {
        return _compositions.value.keys
    }
}

/**
 * Effect composition
 */
data class EffectComposition(
    val id: String,
    val config: CompositionConfig,
    val layers: MutableList<EffectLayer>,
    val blendMode: BlendMode,
    val timestamp: Long
)

/**
 * Effect layer in a composition
 */
data class EffectLayer(
    val id: String,
    val effect: Effect,
    val config: EffectConfig,
    val blendMode: BlendMode,
    val opacity: Float,
    val enabled: Boolean,
    val zIndex: Int
)

/**
 * Composition configuration
 */
data class CompositionConfig(
    val enabled: Boolean = true,
    val globalOpacity: Float = 1f,
    val blendMode: BlendMode = BlendMode.NORMAL,
    val enableCache: Boolean = true,
    val enableOptimization: Boolean = true
)

/**
 * Render pass
 */
data class RenderPass(
    val id: String,
    val compositionIds: List<String>,
    val config: PassConfig,
    val timestamp: Long
)

/**
 * Pass configuration
 */
data class PassConfig(
    val enablePrePass: Boolean = false,
    val enablePostPass: Boolean = false,
    val enableCache: Boolean = true,
    val clearAfterExecution: Boolean = false
)

/**
 * Blend mode
 */
enum class BlendMode {
    NORMAL,
    MULTIPLY,
    SCREEN,
    OVERLAY,
    DARKEN,
    LIGHTEN,
    COLOR_DODGE,
    COLOR_BURN,
    HARD_LIGHT,
    SOFT_LIGHT,
    DIFFERENCE,
    EXCLUSION,
    HUE,
    SATURATION,
    COLOR,
    LUMINOSITY,
    ADD,
    SUBTRACT
}

/**
 * Composition information
 */
data class CompositionInfo(
    val id: String,
    val layerCount: Int,
    val blendMode: BlendMode,
    val enabled: Boolean,
    val timestamp: Long
)

/**
 * Blend mode manager
 */
private class BlendModeManager {
    fun applyBlendMode(
        modifier: Modifier,
        blendMode: BlendMode,
        opacity: Float
    ): Modifier {
        return modifier.graphicsLayer {
            this.alpha = opacity
            // Note: Full blend mode support requires GraphicsLayer API
            // This is a simplified implementation
        }
    }
}

/**
 * Pass manager
 */
private class PassManager {
    fun executePrePass(modifier: Modifier, config: PassConfig): Modifier {
        // Pre-pass operations like clearing, setup
        return modifier
    }
    
    fun executePostPass(modifier: Modifier, config: PassConfig): Modifier {
        // Post-pass operations like cleanup, final effects
        return modifier
    }
}

/**
 * Custom exception for effect composition errors
 */
class EffectCompositionException(message: String, cause: Throwable? = null) : 
    Exception(message, cause)