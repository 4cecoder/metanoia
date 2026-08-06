package com.bytecats.metanoia.ui.effects.fluid

import android.graphics.Bitmap
import android.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.colorspace.ColorSpaces
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Complete simulation state for fluid dynamics.
 * Manages velocity fields, pressure maps, density grids, and temporal history.
 *
 * Based on Structure of Arrays (SoA) pattern for optimal cache locality:
 * - Separate textures for velocity, pressure, density, divergence
 * - Enables selective updates and better GPU memory access patterns
 */
class FluidSimulationState(
    private val config: FluidPhysicsConfig = FluidPhysicsConfig()
) {
    // Current simulation state
    private var velocityField: FloatArray2D = FloatArray2D(config.physicsResolution)
    private var pressureField: FloatArray2D = FloatArray2D(config.physicsResolution)
    private var densityField: FloatArray2D = FloatArray2D(config.visualResolution)
    private var divergenceField: FloatArray2D = FloatArray2D(config.physicsResolution)
    private var vorticityField: FloatArray2D = FloatArray2D(config.physicsResolution)

    // Previous frame state (for temporal coherence and advection)
    private var previousVelocity: FloatArray2D = FloatArray2D(config.physicsResolution)
    private var previousDensity: FloatArray2D = FloatArray2D(config.visualResolution)

    // State management
    private var isInitialized = false
    private val stateMutex = Mutex()
    private var frameCount = 0
    private var lastUpdateTime = 0L
    private val historyBuffer = mutableListOf<SimulationSnapshot>()

    // Force application queue (to be processed per frame)
    private val pendingForces = mutableListOf<AppliedForce>()
    private val pendingDye = mutableListOf<AppliedDye>()

    /**
     * Initialize simulation state with default values
     */
    suspend fun initialize() = stateMutex.withLock {
        if (isInitialized) return@withLock

        // Clear all fields
        velocityField.fill(0f)
        pressureField.fill(0f)
        densityField.fill(0f)
        divergenceField.fill(0f)
        vorticityField.fill(0f)
        previousVelocity.fill(0f)
        previousDensity.fill(0f)

        isInitialized = true
        lastUpdateTime = System.currentTimeMillis()
    }

    /**
     * Reset simulation to initial state
     */
    suspend fun reset() = stateMutex.withLock {
        velocityField.fill(0f)
        pressureField.fill(0f)
        densityField.fill(0f)
        divergenceField.fill(0f)
        vorticityField.fill(0f)
        previousVelocity.fill(0f)
        previousDensity.fill(0f)
        pendingForces.clear()
        pendingDye.clear()
        frameCount = 0
        historyBuffer.clear()
    }

    /**
     * Get current velocity at normalized coordinates [0, 1]
     */
    suspend fun getVelocity(x: Float, y: Float): Float2D = stateMutex.withLock {
        val ix = (x * config.physicsResolution).toInt().coerceIn(0, config.physicsResolution - 1)
        val iy = (y * config.physicsResolution).toInt().coerceIn(0, config.physicsResolution - 1)
        return Float2D(velocityField[ix, iy, 0], velocityField[ix, iy, 1])
    }

    /**
     * Get current density at normalized coordinates [0, 1]
     */
    suspend fun getDensity(x: Float, y: Float): Float = stateMutex.withLock {
        val ix = (x * config.visualResolution).toInt().coerceIn(0, config.visualResolution - 1)
        val iy = (y * config.visualResolution).toInt().coerceIn(0, config.visualResolution - 1)
        return densityField[ix, iy, 0]
    }

    /**
     * Get current pressure at normalized coordinates [0, 1]
     */
    suspend fun getPressure(x: Float, y: Float): Float = stateMutex.withLock {
        val ix = (x * config.physicsResolution).toInt().coerceIn(0, config.physicsResolution - 1)
        val iy = (y * config.physicsResolution).toInt().coerceIn(0, config.physicsResolution - 1)
        return pressureField[ix, iy, 0]
    }

    /**
     * Get current vorticity magnitude at normalized coordinates [0, 1]
     */
    suspend fun getVorticity(x: Float, y: Float): Float = stateMutex.withLock {
        val ix = (x * config.physicsResolution).toInt().coerceIn(0, config.physicsResolution - 1)
        val iy = (y * config.physicsResolution).toInt().coerceIn(0, config.physicsResolution - 1)
        val vx = vorticityField[ix, iy, 0]
        val vy = vorticityField[ix, iy, 1]
        return sqrt(vx * vx + vy * vy)
    }

    /**
     * Add external force to velocity field
     */
    suspend fun addForce(x: Float, y: Float, fx: Float, fy: Float) = stateMutex.withLock {
        if (!isInitialized) return@withLock

        pendingForces.add(AppliedForce(
            x = x.coerceIn(0f, 1f),
            y = y.coerceIn(0f, 1f),
            fx = fx,
            fy = fy,
            timestamp = System.currentTimeMillis()
        ))
    }

    /**
     * Add dye/density to simulation
     */
    suspend fun addDye(x: Float, y: Float, amount: Float, color: Color? = null) = stateMutex.withLock {
        if (!isInitialized) return@withLock

        pendingDye.add(AppliedDye(
            x = x.coerceIn(0f, 1f),
            y = y.coerceIn(0f, 1f),
            amount = amount.coerceIn(0f, 1f),
            color = color,
            timestamp = System.currentTimeMillis()
        ))
    }

    /**
     * Apply pending forces and dye to simulation state
     */
    suspend fun applyPendingUpdates() = stateMutex.withLock {
        // Apply forces
        for (force in pendingForces) {
            val ix = (force.x * config.physicsResolution).toInt().coerceIn(0, config.physicsResolution - 1)
            val iy = (force.y * config.physicsResolution).toInt().coerceIn(0, config.physicsResolution - 1)

            // Apply force with Gaussian falloff
            val radius = config.forceRadius * config.physicsResolution
            for (dy in -radius.toInt()..radius.toInt()) {
                for (dx in -radius.toInt()..radius.toInt()) {
                    val nx = ix + dx
                    val ny = iy + dy
                    if (nx in 0 until config.physicsResolution && ny in 0 until config.physicsResolution) {
                        val dist = sqrt((dx * dx + dy * dy).toFloat())
                        val falloff = max(0f, 1f - dist / radius)
                        val strength = falloff * falloff * config.forceStrength

                        velocityField[nx, ny, 0] += force.fx * strength
                        velocityField[nx, ny, 1] += force.fy * strength
                    }
                }
            }
        }

        // Apply dye
        for (dye in pendingDye) {
            val ix = (dye.x * config.visualResolution).toInt().coerceIn(0, config.visualResolution - 1)
            val iy = (dye.y * config.visualResolution).toInt().coerceIn(0, config.visualResolution - 1)

            // Apply dye with Gaussian falloff
            val radius = config.forceRadius * config.visualResolution
            for (dy in -radius.toInt()..radius.toInt()) {
                for (dx in -radius.toInt()..radius.toInt()) {
                    val nx = ix + dx
                    val ny = iy + dy
                    if (nx in 0 until config.visualResolution && ny in 0 until config.visualResolution) {
                        val dist = sqrt((dx * dx + dy * dy).toFloat())
                        val falloff = max(0f, 1f - dist / radius)
                        val addition = dye.amount * falloff * falloff

                        densityField[nx, ny, 0] = min(config.maxDensity, densityField[nx, ny, 0] + addition)

                        // Store color information in other channels if provided
                        dye.color?.let { color ->
                            densityField[nx, ny, 1] = color.red() / 255f
                            densityField[nx, ny, 2] = color.green() / 255f
                            densityField[nx, ny, 3] = color.blue() / 255f
                        }
                    }
                }
            }
        }

        // Clear pending updates
        pendingForces.clear()
        pendingDye.clear()
    }

    /**
     * Swap current and previous states for temporal coherence
     */
    suspend fun swapStates() = stateMutex.withLock {
        // Swap velocity buffers
        val tempVelocity = velocityField
        velocityField = previousVelocity
        previousVelocity = tempVelocity

        // Swap density buffers
        val tempDensity = densityField
        densityField = previousDensity
        previousDensity = tempDensity
    }

    /**
     * Store current state in history buffer for temporal analysis
     */
    suspend fun captureSnapshot() = stateMutex.withLock {
        if (historyBuffer.size >= MAX_HISTORY_SIZE) {
            historyBuffer.removeAt(0)
        }

        historyBuffer.add(SimulationSnapshot(
            frameCount = frameCount,
            timestamp = System.currentTimeMillis(),
            velocityCopy = velocityField.copy(),
            densityCopy = densityField.copy(),
            pressureCopy = pressureField.copy()
        ))
    }

    /**
     * Get simulation statistics
     */
    suspend fun getStatistics(): SimulationStatistics = stateMutex.withLock {
        // Calculate velocity statistics
        var totalVelocity = 0f
        var maxVelocity = 0f
        var totalDensity = 0f
        var maxDensity = 0f

        for (x in 0 until config.physicsResolution) {
            for (y in 0 until config.physicsResolution) {
                val vx = velocityField[x, y, 0]
                val vy = velocityField[x, y, 1]
                val vel = sqrt(vx * vx + vy * vy)
                totalVelocity += vel
                maxVelocity = max(maxVelocity, vel)
            }
        }

        for (x in 0 until config.visualResolution) {
            for (y in 0 until config.visualResolution) {
                val density = densityField[x, y, 0]
                totalDensity += density
                maxDensity = max(maxDensity, density)
            }
        }

        val now = System.currentTimeMillis()
        val deltaTime = if (lastUpdateTime > 0) (now - lastUpdateTime) / 1000f else 0f
        lastUpdateTime = now

        return SimulationStatistics(
            frameCount = frameCount,
            averageVelocity = totalVelocity / (config.physicsResolution * config.physicsResolution),
            maxVelocity = maxVelocity,
            averageDensity = totalDensity / (config.visualResolution * config.visualResolution),
            maxDensity = maxDensity,
            deltaTime = deltaTime,
            estimatedFPS = if (deltaTime > 0) 1f / deltaTime else 60f,
            activeForces = pendingForces.size,
            activeDye = pendingDye.size,
            historySize = historyBuffer.size
        )
    }

    /**
     * Update frame counter
     */
    suspend fun incrementFrame() = stateMutex.withLock {
        frameCount++
    }

    /**
     * Direct access to internal fields (for shader operations)
     */
    suspend fun withVelocityField(block: (FloatArray2D) -> Unit) = stateMutex.withLock {
        block(velocityField)
    }

    suspend fun withPressureField(block: (FloatArray2D) -> Unit) = stateMutex.withLock {
        block(pressureField)
    }

    suspend fun withDensityField(block: (FloatArray2D) -> Unit) = stateMutex.withLock {
        block(densityField)
    }

    suspend fun withDivergenceField(block: (FloatArray2D) -> Unit) = stateMutex.withLock {
        block(divergenceField)
    }

    suspend fun withVorticityField(block: (FloatArray2D) -> Unit) = stateMutex.withLock {
        block(vorticityField)
    }

    suspend fun withPreviousVelocity(block: (FloatArray2D) -> Unit) = stateMutex.withLock {
        block(previousVelocity)
    }

    suspend fun withPreviousDensity(block: (FloatArray2D) -> Unit) = stateMutex.withLock {
        block(previousDensity)
    }

    /**
     * Convert density field to ImageBitmap for rendering
     */
    suspend fun densityToImageBitmap(): ImageBitmap = stateMutex.withLock {
        val width = config.visualResolution
        val height = config.visualResolution

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(width * height)

        for (y in 0 until height) {
            for (x in 0 until width) {
                val idx = y * width + x
                val density = densityField[x, y, 0]
                val r = (densityField[x, y, 1] * 255).toInt().coerceIn(0, 255)
                val g = (densityField[x, y, 2] * 255).toInt().coerceIn(0, 255)
                val b = (densityField[x, y, 3] * 255).toInt().coerceIn(0, 255)
                val a = (density * 255).toInt().coerceIn(0, 255)

                // Enhance contrast for better visualization
                val enhancedDensity = (density * density).toFloat()
                val alpha = (enhancedDensity * 255).toInt().coerceIn(0, 255)

                pixels[idx] = (alpha shl 24) or (b shl 16) or (g shl 8) or r
            }
        }

        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        return bitmap.asImageBitmap()
    }

    /**
     * Convert velocity field to ImageBitmap for visualization
     */
    suspend fun velocityToImageBitmap(): ImageBitmap = stateMutex.withLock {
        val width = config.physicsResolution
        val height = config.physicsResolution

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(width * height)

        for (y in 0 until height) {
            for (x in 0 until width) {
                val idx = y * width + x
                val vx = velocityField[x, y, 0]
                val vy = velocityField[x, y, 1]
                val magnitude = sqrt(vx * vx + vy * vy) / config.maxVelocity
                val angle = atan2(vy, vx) / (2f * kotlin.math.PI.toFloat())

                // Color by direction, brightness by magnitude
                val hue = ((angle + 1f) * 0.5f * 360f).toInt()
                val saturation = 100
                val brightness = (magnitude * 100).toInt().coerceIn(0, 100)

                val color = hsvToColor(hue, saturation, brightness)
                pixels[idx] = color
            }
        }

        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        return bitmap.asImageBitmap()
    }

    companion object {
        private const val MAX_HISTORY_SIZE = 10

        private fun hsvToColor(h: Int, s: Int, v: Int): Int {
            val c = v * s / 100
            val x = c * (1 - Math.abs(((h / 60) % 2) - 1))
            val m = v - c

            val r1: Int
            val g1: Int
            val b1: Int

            when (h / 60) {
                0 -> { r1 = c; g1 = x; b1 = 0 }
                1 -> { r1 = x; g1 = c; b1 = 0 }
                2 -> { r1 = 0; g1 = c; b1 = x }
                3 -> { r1 = 0; g1 = x; b1 = c }
                4 -> { r1 = x; g1 = 0; b1 = c }
                else -> { r1 = c; g1 = 0; b1 = x }
            }

            val r = (r1 + m).coerceIn(0, 255)
            val g = (g1 + m).coerceIn(0, 255)
            val b = (b1 + m).coerceIn(0, 255)

            return (255 shl 24) or (b shl 16) or (g shl 8) or r
        }
    }
}

/**
 * 2D float array with channel support for efficient GPU data transfer
 */
class FloatArray2D(
    private val width: Int,
    private val height: Int = width,
    private val channels: Int = 4
) {
    private val data = FloatArray(width * height * channels)

    operator fun get(x: Int, y: Int, channel: Int = 0): Float {
        val idx = ((y * width + x) * channels) + channel
        return data[idx]
    }

    operator fun set(x: Int, y: Int, channel: Int, value: Float) {
        val idx = ((y * width + x) * channels) + channel
        data[idx] = value
    }

    fun fill(value: Float) {
        data.fill(value)
    }

    fun copy(): FloatArray2D {
        val copy = FloatArray2D(width, height, channels)
        System.arraycopy(data, 0, copy.data, 0, data.size)
        return copy
    }

    fun toArray(): FloatArray = data.copyOf()

    fun toByteBuffer(): ByteBuffer {
        val buffer = ByteBuffer.allocate(data.size * 4)
        buffer.order(ByteOrder.nativeOrder())
        buffer.asFloatBuffer().put(data)
        buffer.rewind()
        return buffer
    }

    val size: Int get() = width * height * channels
}

/**
 * Data class for applied force
 */
data class AppliedForce(
    val x: Float,
    val y: Float,
    val fx: Float,
    val fy: Float,
    val timestamp: Long
)

/**
 * Data class for applied dye
 */
data class AppliedDye(
    val x: Float,
    val y: Float,
    val amount: Float,
    val color: Color?,
    val timestamp: Long
)

/**
 * Simulation snapshot for temporal analysis
 */
data class SimulationSnapshot(
    val frameCount: Int,
    val timestamp: Long,
    val velocityCopy: FloatArray2D,
    val densityCopy: FloatArray2D,
    val pressureCopy: FloatArray2D
)

/**
 * Simulation statistics
 */
data class SimulationStatistics(
    val frameCount: Int,
    val averageVelocity: Float,
    val maxVelocity: Float,
    val averageDensity: Float,
    val maxDensity: Float,
    val deltaTime: Float,
    val estimatedFPS: Float,
    val activeForces: Int,
    val activeDye: Int,
    val historySize: Int
)