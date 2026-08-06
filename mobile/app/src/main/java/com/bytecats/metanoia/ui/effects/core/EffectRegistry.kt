package com.bytecats.metanoia.ui.effects.core

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.reflect.KClass

/**
 * Central registry for managing effects, their discovery, loading, and lifecycle.
 * Provides dynamic effect registration and dependency management.
 * 
 * @property context Android context for resource loading
 */
class EffectRegistry(
    private val context: Context
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val registrationLock = Mutex()
    
    private val _registeredEffects = MutableStateFlow<Map<String, RegisteredEffect>>(emptyMap())
    val registeredEffects: StateFlow<Map<String, RegisteredEffect>> = _registeredEffects.asStateFlow()
    
    private val _registryState = MutableStateFlow(RegistryState.IDLE)
    val registryState: StateFlow<RegistryState> = _registryState.asStateFlow()
    
    private val effectFactories = mutableMapOf<String, EffectFactory>()
    private val effectMetadata = mutableMapOf<String, EffectMetadata>()
    private val lifecycleListeners = mutableListOf<EffectLifecycleListener>()
    
    private var isInitialized = false

    companion object {
        private const val TAG = "EffectRegistry"
        
        // Built-in effect types
        private val BUILTIN_EFFECTS = setOf(
            "parallax",
            "lighting",
            "shadow",
            "reflection",
            "glassmorphism",
            "cyberpunk"
        )
    }

    /**
     * Initialize the registry and discover built-in effects
     */
    suspend fun initialize() {
        if (isInitialized) return
        
        try {
            _registryState.value = RegistryState.INITIALIZING
            
            // Register built-in effects
            registerBuiltinEffects()
            
            // Auto-discover effects if available
            discoverEffects()
            
            isInitialized = true
            _registryState.value = RegistryState.READY
            
            Log.i(TAG, "EffectRegistry initialized with ${_registeredEffects.value.size} effects")
        } catch (e: Exception) {
            _registryState.value = RegistryState.ERROR
            Log.e(TAG, "Failed to initialize EffectRegistry", e)
            throw EffectRegistryException("Registry initialization failed", e)
        }
    }

    /**
     * Register a new effect factory
     */
    suspend fun registerEffect(
        effectId: String,
        factory: EffectFactory,
        metadata: EffectMetadata
    ): Result<Unit> = registrationLock.withLock {
        return try {
            // Validate effect ID
            if (effectId.isBlank()) {
                throw IllegalArgumentException("Effect ID cannot be blank")
            }
            
            if (_registeredEffects.value.containsKey(effectId)) {
                throw IllegalStateException("Effect $effectId is already registered")
            }
            
            // Validate dependencies
            validateDependencies(effectId, metadata.dependencies)
            
            // Store factory and metadata
            effectFactories[effectId] = factory
            effectMetadata[effectId] = metadata
            
            // Create registered effect entry
            val registeredEffect = RegisteredEffect(
                id = effectId,
                metadata = metadata,
                factory = factory,
                state = EffectState.REGISTERED,
                timestamp = System.currentTimeMillis()
            )
            
            _registeredEffects.value = _registeredEffects.value + (effectId to registeredEffect)
            
            // Notify lifecycle listeners
            notifyLifecycleListeners(EffectLifecycleEvent.REGISTERED, effectId, metadata)
            
            Log.i(TAG, "Effect registered: $effectId")
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register effect: $effectId", e)
            Result.failure(e)
        }
    }

    /**
     * Unregister an effect
     */
    suspend fun unregisterEffect(effectId: String): Result<Unit> = registrationLock.withLock {
        return try {
            val effect = _registeredEffects.value[effectId]
                ?: throw IllegalStateException("Effect $effectId not found")
            
            if (effect.state == EffectState.ACTIVE) {
                throw IllegalStateException("Cannot unregister active effect: $effectId")
            }
            
            // Remove from registry
            _registeredEffects.value = _registeredEffects.value - effectId
            effectFactories.remove(effectId)
            effectMetadata.remove(effectId)
            
            // Notify lifecycle listeners
            notifyLifecycleListeners(EffectLifecycleEvent.UNREGISTERED, effectId, effect.metadata)
            
            Log.i(TAG, "Effect unregistered: $effectId")
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to unregister effect: $effectId", e)
            Result.failure(e)
        }
    }

    /**
     * Create an effect instance
     */
    suspend fun createEffect(effectId: String, config: EffectConfig? = null): Result<Effect> {
        return try {
            if (!isInitialized) {
                throw IllegalStateException("Registry not initialized")
            }
            
            val factory = effectFactories[effectId]
                ?: throw NoSuchElementException("Effect factory not found: $effectId")
            
            val effect = factory.create(config)
            
            // Update effect state
            updateEffectState(effectId, EffectState.INSTANTIATED)
            
            Log.i(TAG, "Effect created: $effectId")
            Result.success(effect)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create effect: $effectId", e)
            Result.failure(e)
        }
    }

    /**
     * Get effect metadata
     */
    fun getEffectMetadata(effectId: String): EffectMetadata? {
        return effectMetadata[effectId]
    }

    /**
     * Get all registered effect IDs
     */
    fun getRegisteredEffectIds(): Set<String> {
        return _registeredEffects.value.keys
    }

    /**
     * Check if an effect is registered
     */
    fun isEffectRegistered(effectId: String): Boolean {
        return _registeredEffects.value.containsKey(effectId)
    }

    /**
     * Check if an effect is a built-in effect
     */
    fun isBuiltinEffect(effectId: String): Boolean {
        return effectId in BUILTIN_EFFECTS
    }

    /**
     * Get effects that depend on a given effect
     */
    fun getDependents(effectId: String): Set<String> {
        return _registeredEffects.value
            .filter { (_, effect) -> effectId in effect.metadata.dependencies }
            .keys
    }

    /**
     * Get effects that are dependencies of a given effect
     */
    fun getDependencies(effectId: String): Set<String> {
        return _registeredEffects.value[effectId]?.metadata?.dependencies ?: emptySet()
    }

    /**
     * Validate effect dependencies
     */
    private suspend fun validateDependencies(effectId: String, dependencies: Set<String>) {
        for (dep in dependencies) {
            if (dep == effectId) {
                throw IllegalStateException("Effect $effectId cannot depend on itself")
            }
            
            if (dep !in _registeredEffects.value && dep !in BUILTIN_EFFECTS) {
                throw IllegalStateException("Dependency $dep not found for effect $effectId")
            }
        }
        
        // Check for circular dependencies
        checkCircularDependencies(effectId, dependencies, mutableSetOf())
    }

    /**
     * Check for circular dependencies using depth-first search
     */
    private fun checkCircularDependencies(
        effectId: String,
        dependencies: Set<String>,
        visiting: MutableSet<String>
    ) {
        if (effectId in visiting) {
            throw IllegalStateException("Circular dependency detected involving $effectId")
        }
        
        visiting.add(effectId)
        
        for (dep in dependencies) {
            val depDeps = effectMetadata[dep]?.dependencies ?: emptySet()
            checkCircularDependencies(dep, depDeps, visiting.toMutableSet())
        }
        
        visiting.remove(effectId)
    }

    /**
     * Register built-in effects
     */
    private suspend fun registerBuiltinEffects() {
        BUILTIN_EFFECTS.forEach { effectId ->
            val metadata = EffectMetadata(
                id = effectId,
                name = effectId.capitalize(),
                version = "1.0.0",
                description = "Built-in $effectId effect",
                category = EffectCategory.BUILTIN,
                dependencies = emptySet(),
                minApiLevel = when (effectId) {
                    "lighting", "shadow", "reflection" -> 33  // TIRAMISU for shaders
                    else -> 21
                },
                resourceRequirements = ResourceRequirements(
                    memoryMb = when (effectId) {
                        "lighting" -> 16f
                        "reflection" -> 32f
                        else -> 8f
                    },
                    gpuRequired = effectId in setOf("lighting", "reflection", "cyberpunk")
                )
            )
            
            // Register with placeholder factory
            registerEffect(effectId, PlaceholderEffectFactory(effectId), metadata)
        }
    }

    /**
     * Auto-discover effects from packages
     */
    private suspend fun discoverEffects() {
        // This would scan for effects in designated packages
        // For now, built-in effects are registered manually
        Log.d(TAG, "Effect discovery complete")
    }

    /**
     * Update effect state
     */
    private suspend fun updateEffectState(effectId: String, state: EffectState) {
        val current = _registeredEffects.value[effectId] ?: return
        _registeredEffects.value = _registeredEffects.value + (
            effectId to current.copy(state = state)
        )
    }

    /**
     * Add lifecycle listener
     */
    fun addLifecycleListener(listener: EffectLifecycleListener) {
        lifecycleListeners.add(listener)
    }

    /**
     * Remove lifecycle listener
     */
    fun removeLifecycleListener(listener: EffectLifecycleListener) {
        lifecycleListeners.remove(listener)
    }

    /**
     * Notify lifecycle listeners of events
     */
    private fun notifyLifecycleListeners(
        event: EffectLifecycleEvent,
        effectId: String,
        metadata: EffectMetadata
    ) {
        lifecycleListeners.forEach { listener ->
            try {
                listener.onEffectLifecycleEvent(event, effectId, metadata)
            } catch (e: Exception) {
                Log.e(TAG, "Lifecycle listener error", e)
            }
        }
    }

    /**
     * Clear all registered effects
     */
    suspend fun clear() {
        registrationLock.withLock {
            val effectIds = _registeredEffects.value.keys.toList()
            
            effectIds.forEach { effectId ->
                try {
                    unregisterEffect(effectId)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to clear effect: $effectId", e)
                }
            }
            
            _registeredEffects.value = emptyMap()
            lifecycleListeners.clear()
            isInitialized = false
            
            Log.i(TAG, "EffectRegistry cleared")
        }
    }

    /**
     * Get registry statistics
     */
    fun getRegistryStatistics(): RegistryStatistics {
        val effects = _registeredEffects.value
        return RegistryStatistics(
            totalEffects = effects.size,
            builtinEffects = effects.values.count { it.metadata.category == EffectCategory.BUILTIN },
            customEffects = effects.values.count { it.metadata.category == EffectCategory.CUSTOM },
            activeEffects = effects.values.count { it.state == EffectState.ACTIVE },
            registeredEffects = effects.values.count { it.state == EffectState.REGISTERED }
        )
    }
}

/**
 * Registered effect information
 */
data class RegisteredEffect(
    val id: String,
    val metadata: EffectMetadata,
    val factory: EffectFactory,
    val state: EffectState,
    val timestamp: Long
)

/**
 * Effect metadata
 */
data class EffectMetadata(
    val id: String,
    val name: String,
    val version: String,
    val description: String,
    val category: EffectCategory,
    val dependencies: Set<String>,
    val minApiLevel: Int,
    val resourceRequirements: ResourceRequirements,
    val tags: Set<String> = emptySet(),
    val author: String = "",
    val license: String = ""
)

/**
 * Effect category
 */
enum class EffectCategory {
    BUILTIN,
    CUSTOM,
    EXPERIMENTAL,
    DEPRECATED
}

/**
 * Effect state
 */
enum class EffectState {
    REGISTERED,
    INSTANTIATED,
    ACTIVE,
    SUSPENDED,
    DISPOSED
}

/**
 * Registry state
 */
enum class RegistryState {
    IDLE,
    INITIALIZING,
    READY,
    ERROR
}

/**
 * Effect lifecycle events
 */
enum class EffectLifecycleEvent {
    REGISTERED,
    UNREGISTERED,
    INSTANTIATED,
    ACTIVATED,
    DEACTIVATED,
    DISPOSED
}

/**
 * Resource requirements for effects
 */
data class ResourceRequirements(
    val memoryMb: Float,
    val gpuRequired: Boolean = false,
    val minGpuMemoryMb: Float = 0f,
    val shaderSupportRequired: Boolean = false
)

/**
 * Registry statistics
 */
data class RegistryStatistics(
    val totalEffects: Int,
    val builtinEffects: Int,
    val customEffects: Int,
    val activeEffects: Int,
    val registeredEffects: Int
)

/**
 * Effect factory interface
 */
interface EffectFactory {
    fun create(config: EffectConfig? = null): Effect
}

/**
 * Placeholder factory for built-in effects
 */
private class PlaceholderEffectFactory(private val effectId: String) : EffectFactory {
    override fun create(config: EffectConfig?): Effect {
        return PlaceholderEffect(effectId, config)
    }
}

/**
 * Placeholder effect for built-in effects
 */
private class PlaceholderEffect(
    private val effectId: String,
    private val config: EffectConfig?
) : Effect {
    override val name: String = effectId
    override val version: String = "1.0.0"
    override val dependencies: Set<KClass<out Effect>> = emptySet()
    
    override fun apply(
        modifier: androidx.compose.ui.Modifier,
        config: EffectConfig,
        time: Float
    ): androidx.compose.ui.Modifier {
        return modifier
    }
    
    override fun defaultConfig(): EffectConfig = config ?: object : EffectConfig {}
}

/**
 * Effect lifecycle listener
 */
interface EffectLifecycleListener {
    fun onEffectLifecycleEvent(event: EffectLifecycleEvent, effectId: String, metadata: EffectMetadata)
}

/**
 * Custom exception for effect registry errors
 */
class EffectRegistryException(message: String, cause: Throwable? = null) : 
    Exception(message, cause)