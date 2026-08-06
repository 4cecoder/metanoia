package com.bytecats.metanoia.ui.effects.core

import android.app.ActivityManager
import android.content.Context
import android.hardware.display.DisplayManager
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.GLES20
import android.os.Build
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min

/**
 * Graphics quality manager for dynamic quality adjustment and performance optimization.
 * Manages quality presets, device capability matching, and performance monitoring.
 * 
 * @property context Android context for system access
 */
class GraphicsQualityManager(
    private val context: Context
) {
    private val scope = CoroutineScope(Dispatchers.Default)
    
    private val _currentQuality = MutableStateFlow(GraphicsQuality.MEDIUM)
    val currentQuality: StateFlow<GraphicsQuality> = _currentQuality.asStateFlow()
    
    private val _deviceCapabilities = MutableStateFlow<DeviceCapabilities?>(null)
    val deviceCapabilities: StateFlow<DeviceCapabilities?> = _deviceCapabilities.asStateFlow()
    
    private val _performanceMetrics = MutableStateFlow<PerformanceMetrics>(PerformanceMetrics())
    val performanceMetrics: StateFlow<PerformanceMetrics> = _performanceMetrics.asStateFlow()
    
    private val _adaptiveQualityEnabled = MutableStateFlow(true)
    val adaptiveQualityEnabled: StateFlow<Boolean> = _adaptiveQualityEnabled.asStateFlow()
    
    private var performanceMonitorJob: Job? = null
    private var adaptiveQualityJob: Job? = null
    
    private val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    
    // Quality presets configuration
    private val qualityPresets = mapOf(
        GraphicsQuality.LOW to QualityPreset(
            maxEffects = 3,
            maxTextureResolution = 512,
            enableShadows = false,
            enableLighting = false,
            enableReflections = false,
            enablePostProcessing = false,
            targetFps = 30f,
            maxMemoryMb = 100f,
            shaderQuality = ShaderQuality.LOW,
            antialiasing = Antialiasing.NONE
        ),
        GraphicsQuality.MEDIUM to QualityPreset(
            maxEffects = 6,
            maxTextureResolution = 1024,
            enableShadows = true,
            enableLighting = true,
            enableReflections = false,
            enablePostProcessing = true,
            targetFps = 45f,
            maxMemoryMb = 200f,
            shaderQuality = ShaderQuality.MEDIUM,
            antialiasing = Antialiasing.MSAA_2X
        ),
        GraphicsQuality.HIGH to QualityPreset(
            maxEffects = 10,
            maxTextureResolution = 2048,
            enableShadows = true,
            enableLighting = true,
            enableReflections = true,
            enablePostProcessing = true,
            targetFps = 60f,
            maxMemoryMb = 400f,
            shaderQuality = ShaderQuality.HIGH,
            antialiasing = Antialiasing.MSAA_4X
        ),
        GraphicsQuality.ULTRA to QualityPreset(
            maxEffects = 16,
            maxTextureResolution = 4096,
            enableShadows = true,
            enableLighting = true,
            enableReflections = true,
            enablePostProcessing = true,
            targetFps = 60f,
            maxMemoryMb = 800f,
            shaderQuality = ShaderQuality.ULTRA,
            antialiasing = Antialiasing.MSAA_8X
        )
    )

    companion object {
        private const val TAG = "GraphicsQualityManager"
        private const val MONITOR_INTERVAL_MS = 1000L
        private const val ADAPTIVE_QUALITY_INTERVAL_MS = 5000L
        private const val FPS_HISTORY_SIZE = 60
        private const val MIN_ADAPTIVE_SAMPLES = 10
    }

    /**
     * Initialize the quality manager and detect device capabilities
     */
    fun initialize() {
        try {
            // Detect device capabilities
            val capabilities = detectDeviceCapabilities()
            _deviceCapabilities.value = capabilities
            
            // Set initial quality based on device
            val initialQuality = determineInitialQuality(capabilities)
            _currentQuality.value = initialQuality
            
            // Start performance monitoring
            startPerformanceMonitoring()
            
            // Start adaptive quality adjustment
            startAdaptiveQuality()
            
            Log.i(TAG, "GraphicsQualityManager initialized with quality: $initialQuality")
            Log.i(TAG, "Device capabilities: $capabilities")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize GraphicsQualityManager", e)
            _currentQuality.value = GraphicsQuality.LOW
        }
    }

    /**
     * Set quality level manually
     */
    fun setQuality(quality: GraphicsQuality) {
        _adaptiveQualityEnabled.value = false
        applyQuality(quality)
        Log.i(TAG, "Quality set manually to: $quality")
    }

    /**
     * Enable or disable adaptive quality
     */
    fun setAdaptiveQualityEnabled(enabled: Boolean) {
        _adaptiveQualityEnabled.value = enabled
        
        if (enabled) {
            startAdaptiveQuality()
        } else {
            adaptiveQualityJob?.cancel()
        }
        
        Log.i(TAG, "Adaptive quality ${if (enabled) "enabled" else "disabled"}")
    }

    /**
     * Check if an effect should be applied based on current quality
     */
    fun shouldApplyEffect(effect: Effect): Boolean {
        val preset = getCurrentPreset()
        val effectResourceCost = estimateResourceCost(effect)
        
        return when {
            !preset.enableShadows && effect.name.contains("shadow", ignoreCase = true) -> false
            !preset.enableLighting && effect.name.contains("light", ignoreCase = true) -> false
            !preset.enableReflections && effect.name.contains("reflection", ignoreCase = true) -> false
            !preset.enablePostProcessing && effect.name.contains("post", ignoreCase = true) -> false
            effectResourceCost > preset.maxMemoryMb -> false
            else -> true
        }
    }

    /**
     * Get current quality preset
     */
    fun getCurrentPreset(): QualityPreset {
        return qualityPresets[_currentQuality.value] ?: qualityPresets[GraphicsQuality.MEDIUM]!!
    }

    /**
     * Get quality preset for a specific quality level
     */
    fun getPreset(quality: GraphicsQuality): QualityPreset {
        return qualityPresets[quality] ?: qualityPresets[GraphicsQuality.MEDIUM]!!
    }

    /**
     * Apply quality settings
     */
    private fun applyQuality(quality: GraphicsQuality) {
        _currentQuality.value = quality
        
        // Apply quality-specific settings
        val preset = getPreset(quality)
        
        // Update display metrics if needed
        updateDisplaySettings(preset)
        
        // Clear caches when quality changes significantly
        if (isSignificantQualityChange(quality)) {
            clearQualityCaches()
        }
    }

    /**
     * Start performance monitoring
     */
    private fun startPerformanceMonitoring() {
        performanceMonitorJob?.cancel()
        
        performanceMonitorJob = scope.launch {
            val fpsHistory = mutableListOf<Float>()
            var frameCount = 0
            var lastTime = System.currentTimeMillis()
            
            while (isActive) {
                val currentTime = System.currentTimeMillis()
                val deltaTime = currentTime - lastTime
                
                if (deltaTime >= MONITOR_INTERVAL_MS) {
                    val fps = (frameCount * 1000f) / deltaTime
                    
                    fpsHistory.add(fps)
                    if (fpsHistory.size > FPS_HISTORY_SIZE) {
                        fpsHistory.removeAt(0)
                    }
                    
                    val avgFps = fpsHistory.average().toFloat()
                    val memoryInfo = ActivityManager.MemoryInfo()
                    activityManager.getMemoryInfo(memoryInfo)
                    
                    val usedMemoryMb = (memoryInfo.totalMem - memoryInfo.availMem) / (1024f * 1024f)
                    val totalMemoryMb = memoryInfo.totalMem / (1024f * 1024f)
                    
                    _performanceMetrics.value = PerformanceMetrics(
                        fps = avgFps,
                        frameTimeMs = 1000f / avgFps,
                        memoryUsedMb = usedMemoryMb,
                        memoryTotalMb = totalMemoryMb,
                        memoryAvailableMb = memoryInfo.availMem / (1024f * 1024f),
                        gpuUsage = estimateGpuUsage(),
                        cpuUsage = estimateCpuUsage(),
                        thermalState = getThermalState(),
                        lastUpdate = currentTime
                    )
                    
                    frameCount = 0
                    lastTime = currentTime
                }
                
                frameCount++
                delay(16) // ~60 FPS
            }
        }
    }

    /**
     * Start adaptive quality adjustment
     */
    private fun startAdaptiveQuality() {
        adaptiveQualityJob?.cancel()
        
        adaptiveQualityJob = scope.launch {
            var qualityChangeCount = 0
            val qualityHistory = mutableListOf<GraphicsQuality>()
            
            while (isActive && _adaptiveQualityEnabled.value) {
                delay(ADAPTIVE_QUALITY_INTERVAL_MS)
                
                if (!_adaptiveQualityEnabled.value) continue
                
                val metrics = _performanceMetrics.value
                val currentQuality = _currentQuality.value
                
                // Check if we have enough samples
                if (qualityHistory.size < MIN_ADAPTIVE_SAMPLES) {
                    qualityHistory.add(currentQuality)
                    continue
                }
                
                val targetFps = getCurrentPreset().targetFps
                val fpsRatio = metrics.fps / targetFps
                val memoryRatio = metrics.memoryUsedMb / getCurrentPreset().maxMemoryMb
                
                val newQuality = when {
                    fpsRatio < 0.7f || memoryRatio > 0.9f -> {
                        // Performance issues detected, lower quality
                        when (currentQuality) {
                            GraphicsQuality.ULTRA -> GraphicsQuality.HIGH
                            GraphicsQuality.HIGH -> GraphicsQuality.MEDIUM
                            GraphicsQuality.MEDIUM -> GraphicsQuality.LOW
                            GraphicsQuality.LOW -> GraphicsQuality.LOW
                        }
                    }
                    fpsRatio > 1.2f && memoryRatio < 0.5f && qualityChangeCount < 3 -> {
                        // Performance is good, try higher quality
                        when (currentQuality) {
                            GraphicsQuality.LOW -> GraphicsQuality.MEDIUM
                            GraphicsQuality.MEDIUM -> GraphicsQuality.HIGH
                            GraphicsQuality.HIGH -> GraphicsQuality.ULTRA
                            GraphicsQuality.ULTRA -> GraphicsQuality.ULTRA
                        }
                    }
                    else -> currentQuality
                }
                
                if (newQuality != currentQuality) {
                    qualityChangeCount++
                    qualityHistory.add(newQuality)
                    if (qualityHistory.size > MIN_ADAPTIVE_SAMPLES) {
                        qualityHistory.removeAt(0)
                    }
                    
                    applyQuality(newQuality)
                    Log.i(TAG, "Adaptive quality adjusted: $currentQuality -> $newQuality")
                    Log.i(TAG, "Metrics - FPS: ${metrics.fps}, Memory: ${metrics.memoryUsedMb}MB")
                } else {
                    qualityChangeCount = 0
                }
            }
        }
    }

    /**
     * Detect device capabilities
     */
    private fun detectDeviceCapabilities(): DeviceCapabilities {
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        
        val displayMetrics = DisplayMetrics()
        windowManager.defaultDisplay.getMetrics(displayMetrics)
        
        val displayManager = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val displays = displayManager.displays
        val primaryDisplay = displays.firstOrNull()
        
        val refreshRate = primaryDisplay?.mode?.refreshRate ?: 60f
        val density = displayMetrics.densityDpi
        
        val gpuInfo = detectGpuInfo()
        val cpuInfo = detectCpuInfo()
        
        return DeviceCapabilities(
            totalMemoryMb = memoryInfo.totalMem / (1024f * 1024f),
            availableMemoryMb = memoryInfo.availMem / (1024f * 1024f),
            screenWidth = displayMetrics.widthPixels,
            screenHeight = displayMetrics.heightPixels,
            screenDensity = density,
            refreshRate = refreshRate,
            gpuModel = gpuInfo.model,
            gpuVendor = gpuInfo.vendor,
            supportsShaders = supportsShaders(),
            supportsComputeShaders = supportsComputeShaders(),
            cpuCores = Runtime.getRuntime().availableProcessors(),
            cpuFrequency = cpuInfo.frequency,
            apiLevel = Build.VERSION.SDK_INT
        )
    }

    /**
     * Determine initial quality based on device capabilities
     */
    private fun determineInitialQuality(capabilities: DeviceCapabilities): GraphicsQuality {
        val memoryScore = capabilities.totalMemoryMb / 1000f // 0-4 scale
        val gpuScore = if (capabilities.supportsShaders) 2f else 0f
        val cpuScore = capabilities.cpuCores / 4f // 0-4 scale
        
        val totalScore = (memoryScore + gpuScore + cpuScore) / 3f
        
        return when {
            totalScore >= 3f -> GraphicsQuality.ULTRA
            totalScore >= 2f -> GraphicsQuality.HIGH
            totalScore >= 1f -> GraphicsQuality.MEDIUM
            else -> GraphicsQuality.LOW
        }
    }

    /**
     * Detect GPU information
     */
    private fun detectGpuInfo(): GpuInfo {
        return try {
            val extensions = GLES20.glGetString(GLES20.GL_EXTENSIONS)
            val renderer = GLES20.glGetString(GLES20.GL_RENDERER)
            val vendor = GLES20.glGetString(GLES20.GL_VENDOR)
            
            GpuInfo(
                model = renderer ?: "Unknown",
                vendor = vendor ?: "Unknown",
                extensions = extensions ?: "",
                maxTextureSize = getMaxTextureSize()
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to detect GPU info", e)
            GpuInfo("Unknown", "Unknown", "", 1024)
        }
    }

    /**
     * Detect CPU information
     */
    private fun detectCpuInfo(): CpuInfo {
        return try {
            val cores = Runtime.getRuntime().availableProcessors()
            val freq = getCpuFrequency()
            
            CpuInfo(
                cores = cores,
                frequency = freq
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to detect CPU info", e)
            CpuInfo(4, 0f)
        }
    }

    /**
     * Check if device supports shaders
     */
    private fun supportsShaders(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
    }

    /**
     * Check if device supports compute shaders
     */
    private fun supportsComputeShaders(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
    }

    /**
     * Get maximum texture size
     */
    private fun getMaxTextureSize(): Int {
        return try {
            val maxTextureSize = IntArray(1)
            GLES20.glGetIntegerv(GLES20.GL_MAX_TEXTURE_SIZE, maxTextureSize, 0)
            maxTextureSize[0]
        } catch (e: Exception) {
            1024
        }
    }

    /**
     * Get CPU frequency in MHz
     */
    private fun getCpuFrequency(): Float {
        return try {
            // Read CPU frequency from system files
            val freqFile = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
            val content = java.io.File(freqFile).readText().trim()
            content.toFloat() / 1000f // Convert to MHz
        } catch (e: Exception) {
            1200f // Default to 1.2 GHz
        }
    }

    /**
     * Estimate GPU usage
     */
    private fun estimateGpuUsage(): Float {
        // This is a simplified estimation
        return try {
            val fps = _performanceMetrics.value.fps
            val targetFps = getCurrentPreset().targetFps
            min(1f, max(0f, 1f - (fps / targetFps)))
        } catch (e: Exception) {
            0f
        }
    }

    /**
     * Estimate CPU usage
     */
    private fun estimateCpuUsage(): Float {
        return try {
            val memoryUsage = _performanceMetrics.value.memoryUsedMb
            val maxMemory = getCurrentPreset().maxMemoryMb
            min(1f, max(0f, memoryUsage / maxMemory))
        } catch (e: Exception) {
            0f
        }
    }

    /**
     * Get thermal state
     */
    private fun getThermalState(): ThermalState {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                when (powerManager.getCurrentThermalStatus()) {
                    android.os.PowerManager.THERMAL_STATUS_NONE -> ThermalState.NORMAL
                    android.os.PowerManager.THERMAL_STATUS_LIGHT -> ThermalState.LIGHT
                    android.os.PowerManager.THERMAL_STATUS_MODERATE -> ThermalState.MODERATE
                    android.os.PowerManager.THERMAL_STATUS_SEVERE -> ThermalState.SEVERE
                    android.os.PowerManager.THERMAL_STATUS_CRITICAL -> ThermalState.CRITICAL
                    android.os.PowerManager.THERMAL_STATUS_EMERGENCY -> ThermalState.CRITICAL
                    android.os.PowerManager.THERMAL_STATUS_SHUTDOWN -> ThermalState.CRITICAL
                    else -> ThermalState.NORMAL
                }
            } else {
                ThermalState.NORMAL
            }
        } catch (e: Exception) {
            ThermalState.NORMAL
        }
    }

    /**
     * Estimate resource cost for an effect
     */
    private fun estimateResourceCost(effect: Effect): Float {
        return when {
            effect.name.contains("lighting", ignoreCase = true) -> 16f
            effect.name.contains("shadow", ignoreCase = true) -> 12f
            effect.name.contains("reflection", ignoreCase = true) -> 24f
            effect.name.contains("post", ignoreCase = true) -> 8f
            else -> 4f
        }
    }

    /**
     * Check if quality change is significant
     */
    private fun isSignificantQualityChange(quality: GraphicsQuality): Boolean {
        val current = _currentQuality.value
        val qualityDifference = kotlin.math.abs(current.ordinal - quality.ordinal)
        return qualityDifference > 1
    }

    /**
     * Clear quality-related caches
     */
    private fun clearQualityCaches() {
        // Clear any cached resources that depend on quality level
        Log.i(TAG, "Quality caches cleared")
    }

    /**
     * Update display settings based on quality preset
     */
    private fun updateDisplaySettings(preset: QualityPreset) {
        // Apply display settings if needed
        // This would typically involve window flags and display modes
    }

    /**
     * Get quality statistics
     */
    fun getQualityStatistics(): QualityStatistics {
        return QualityStatistics(
            currentQuality = _currentQuality.value,
            adaptiveQualityEnabled = _adaptiveQualityEnabled.value,
            deviceCapabilities = _deviceCapabilities.value,
            currentPreset = getCurrentPreset(),
            performanceMetrics = _performanceMetrics.value
        )
    }

    /**
     * Shutdown the quality manager
     */
    fun shutdown() {
        performanceMonitorJob?.cancel()
        adaptiveQualityJob?.cancel()
        performanceMonitorJob = null
        adaptiveQualityJob = null
        
        Log.i(TAG, "GraphicsQualityManager shutdown")
    }
}

/**
 * Graphics quality levels
 */
enum class GraphicsQuality {
    LOW,
    MEDIUM,
    HIGH,
    ULTRA
}

/**
 * Quality preset configuration
 */
data class QualityPreset(
    val maxEffects: Int,
    val maxTextureResolution: Int,
    val enableShadows: Boolean,
    val enableLighting: Boolean,
    val enableReflections: Boolean,
    val enablePostProcessing: Boolean,
    val targetFps: Float,
    val maxMemoryMb: Float,
    val shaderQuality: ShaderQuality,
    val antialiasing: Antialiasing
)

/**
 * Shader quality levels
 */
enum class ShaderQuality {
    LOW,
    MEDIUM,
    HIGH,
    ULTRA
}

/**
 * Antialiasing modes
 */
enum class Antialiasing {
    NONE,
    FXAA,
    MSAA_2X,
    MSAA_4X,
    MSAA_8X
}

/**
 * Device capabilities
 */
data class DeviceCapabilities(
    val totalMemoryMb: Float,
    val availableMemoryMb: Float,
    val screenWidth: Int,
    val screenHeight: Int,
    val screenDensity: Int,
    val refreshRate: Float,
    val gpuModel: String,
    val gpuVendor: String,
    val supportsShaders: Boolean,
    val supportsComputeShaders: Boolean,
    val cpuCores: Int,
    val cpuFrequency: Float,
    val apiLevel: Int
)

/**
 * GPU information
 */
data class GpuInfo(
    val model: String,
    val vendor: String,
    val extensions: String,
    val maxTextureSize: Int
)

/**
 * CPU information
 */
data class CpuInfo(
    val cores: Int,
    val frequency: Float
)

/**
 * Performance metrics
 */
data class PerformanceMetrics(
    val fps: Float = 60f,
    val frameTimeMs: Float = 16.67f,
    val memoryUsedMb: Float = 0f,
    val memoryTotalMb: Float = 0f,
    val memoryAvailableMb: Float = 0f,
    val gpuUsage: Float = 0f,
    val cpuUsage: Float = 0f,
    val thermalState: ThermalState = ThermalState.NORMAL,
    val lastUpdate: Long = System.currentTimeMillis()
)

/**
 * Thermal states
 */
enum class ThermalState {
    NORMAL,
    LIGHT,
    MODERATE,
    SEVERE,
    CRITICAL
}

/**
 * Quality statistics
 */
data class QualityStatistics(
    val currentQuality: GraphicsQuality,
    val adaptiveQualityEnabled: Boolean,
    val deviceCapabilities: DeviceCapabilities?,
    val currentPreset: QualityPreset,
    val performanceMetrics: PerformanceMetrics
)