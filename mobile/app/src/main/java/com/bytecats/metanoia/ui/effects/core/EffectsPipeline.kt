package com.bytecats.metanoia.ui.effects.core

import android.content.Context
import android.graphics.RenderEffect
import android.graphics.RenderNode
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.IntSize
import com.bytecats.metanoia.ui.effects.ParallaxConfig
import com.bytecats.metanoia.ui.effects.LightSource
import com.bytecats.metanoia.ui.effects.ShadowConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.math.max

/**
 * Core pipeline orchestrator for graphics effects system.
 * Manages effect composition, execution order, and resource lifecycle.
 * 
 * @property context Android context for resource access
 * @property qualityManager Graphics quality manager for performance optimization
 * @property scope Coroutine scope for async operations
 */
class EffectsPipeline(
    private val context: Context,
    qualityManager: GraphicsQualityManager? = null
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val qualityManager: GraphicsQualityManager = qualityManager ?: GraphicsQualityManager(context)
    
    private val _activeEffects = MutableStateFlow<List<ActiveEffect>>(emptyList())
    val activeEffects: StateFlow<List<ActiveEffect>> = _activeEffects.asStateFlow()
    
    private val _pipelineState = MutableStateFlow(PipelineState.IDLE)
    val pipelineState: StateFlow<PipelineState> = _pipelineState.asStateFlow()
    
    private val _renderStatistics = MutableStateFlow(RenderStatistics())
    val renderStatistics: StateFlow<RenderStatistics> = _renderStatistics.asStateFlow()
    
    private val resourceManager = EffectsResourceManager()
    private val passExecutor = PassExecutor()
    
    private var isInitialized = false
    private val initializationLock = Any()

    /**
     * Initialize the effects pipeline
     */
    suspend fun initialize() {
        synchronized(initializationLock) {
            if (isInitialized) return
            isInitialized = true
        }
        
        try {
            _pipelineState.value = PipelineState.INITIALIZING
            resourceManager.initialize()
            
            _pipelineState.value = PipelineState.READY
        } catch (e: Exception) {
            _pipelineState.value = PipelineState.ERROR
            throw EffectsPipelineException("Failed to initialize effects pipeline", e)
        }
    }

    /**
     * Add an effect to the pipeline with specified priority
     */
    fun addEffect(
        effect: Effect,
        priority: EffectPriority = EffectPriority.NORMAL,
        config: EffectConfig? = null
    ): EffectHandle {
        val handle = EffectHandle.generate()
        val activeEffect = ActiveEffect(
            handle = handle,
            effect = effect,
            priority = priority,
            config = config ?: effect.defaultConfig(),
            timestamp = System.currentTimeMillis()
        )
        
        _activeEffects.value = _activeEffects.value + activeEffect
        reorderEffects()
        
        return handle
    }

    /**
     * Remove an effect from the pipeline
     */
    fun removeEffect(handle: EffectHandle): Boolean {
        val current = _activeEffects.value
        val updated = current.filterNot { it.handle == handle }
        
        return if (updated.size != current.size) {
            _activeEffects.value = updated
            true
        } else {
            false
        }
    }

    /**
     * Apply all active effects to a modifier
     */
    fun applyEffects(baseModifier: Modifier, frameTime: Float = 0f): Modifier {
        if (_pipelineState.value != PipelineState.READY) {
            return baseModifier
        }
        
        val sortedEffects = getSortedEffects()
        var modifier = baseModifier
        
        try {
            _pipelineState.value = PipelineState.RENDERING
            val startTime = System.nanoTime()
            
            for (activeEffect in sortedEffects) {
                if (qualityManager.shouldApplyEffect(activeEffect.effect)) {
                    modifier = activeEffect.effect.apply(
                        modifier = modifier,
                        config = activeEffect.config,
                        time = frameTime
                    )
                }
            }
            
            val renderTime = (System.nanoTime() - startTime) / 1_000_000f
            updateRenderStatistics(renderTimeMs = renderTime)
            
            return modifier
        } catch (e: Exception) {
            _pipelineState.value = PipelineState.ERROR
            throw EffectsPipelineException("Failed to apply effects", e)
        } finally {
            if (_pipelineState.value == PipelineState.RENDERING) {
                _pipelineState.value = PipelineState.READY
            }
        }
    }

    /**
     * Execute a specific render pass
     */
    suspend fun executePass(pass: RenderPass, input: RenderInput): RenderOutput {
        if (_pipelineState.value != PipelineState.READY) {
            throw EffectsPipelineException("Pipeline not ready")
        }
        
        return passExecutor.executePass(pass, input, _activeEffects.value, qualityManager)
    }

    /**
     * Get sorted effects by priority and timestamp
     */
    private fun getSortedEffects(): List<ActiveEffect> {
        return _activeEffects.value.sortedWith(compareBy(
            { it.priority.ordinal },
            { it.timestamp }
        ))
    }

    /**
     * Reorder effects based on dependencies
     */
    private fun reorderEffects() {
        val effects = _activeEffects.value.toMutableList()
        val reordered = mutableListOf<ActiveEffect>()
        val visited = mutableSetOf<EffectHandle>()
        
        fun visit(effect: ActiveEffect) {
            if (effect.handle in visited) return
            visited.add(effect.handle)
            
            // Visit dependencies first
            effect.effect.dependencies.forEach { dep ->
                effects.find { it.effect::class == dep }?.let { visit(it) }
            }
            
            reordered.add(effect)
        }
        
        effects.forEach { visit(it) }
        _activeEffects.value = reordered
    }

    /**
     * Update render statistics
     */
    private fun updateRenderStatistics(
        renderTimeMs: Float? = null,
        metrics: PerformanceMetrics? = null
    ) {
        val current = _renderStatistics.value
        _renderStatistics.value = current.copy(
            frameTimeMs = renderTimeMs ?: current.frameTimeMs,
            fps = metrics?.fps ?: current.fps,
            memoryUsedMb = metrics?.memoryUsedMb ?: current.memoryUsedMb,
            gpuUsage = metrics?.gpuUsage ?: current.gpuUsage,
            lastUpdate = System.currentTimeMillis()
        )
    }

    /**
     * Clear all effects from the pipeline
     */
    suspend fun clearEffects() {
        _activeEffects.value = emptyList()
        resourceManager.clearResources()
    }

    /**
     * Release pipeline resources
     */
    suspend fun release() {
        _pipelineState.value = PipelineState.SHUTTING_DOWN
        clearEffects()
        resourceManager.release()
        _pipelineState.value = PipelineState.IDLE
        isInitialized = false
    }

    /**
     * Get pipeline information for debugging
     */
    fun getPipelineInfo(): PipelineInfo {
        return PipelineInfo(
            state = _pipelineState.value,
            activeEffectCount = _activeEffects.value.size,
            statistics = _renderStatistics.value,
            qualityLevel = qualityManager.currentQuality.value,
            isInitialized = isInitialized
        )
    }
}

/**
 * Active effect in the pipeline
 */
data class ActiveEffect(
    val handle: EffectHandle,
    val effect: Effect,
    val priority: EffectPriority,
    val config: EffectConfig,
    val timestamp: Long
)

/**
 * Unique handle for an effect instance
 */
data class EffectHandle(private val id: String) {
    companion object {
        fun generate(): EffectHandle = EffectHandle("effect_${System.currentTimeMillis()}_${randomId()}")
        private fun randomId(): String = (0..7).joinToString("") { 
            ('a'..'z').random().toString() 
        }
    }
}

/**
 * Effect priority levels
 */
enum class EffectPriority {
    BACKGROUND,  // Applied first
    LOW,
    NORMAL,
    HIGH,
    POST_PROCESS  // Applied last
}

/**
 * Pipeline states
 */
enum class PipelineState {
    IDLE,
    INITIALIZING,
    READY,
    RENDERING,
    ERROR,
    SHUTTING_DOWN
}

/**
 * Render statistics
 */
data class RenderStatistics(
    val frameTimeMs: Float = 0f,
    val fps: Float = 60f,
    val memoryUsedMb: Float = 0f,
    val gpuUsage: Float = 0f,
    val lastUpdate: Long = System.currentTimeMillis()
)

/**
 * Pipeline information
 */
data class PipelineInfo(
    val state: PipelineState,
    val activeEffectCount: Int,
    val statistics: RenderStatistics,
    val qualityLevel: GraphicsQuality,
    val isInitialized: Boolean
)

/**
 * Render input for pass execution
 */
data class RenderInput(
    val baseModifier: Modifier,
    val frameTime: Float,
    val screenSize: IntSize,
    val deltaTime: Float
)

/**
 * Render output from pass execution
 */
data class RenderOutput(
    val modifier: Modifier,
    val metadata: Map<String, Any> = emptyMap()
)

/**
 * Custom exception for effects pipeline errors
 */
class EffectsPipelineException(message: String, cause: Throwable? = null) : 
    Exception(message, cause)