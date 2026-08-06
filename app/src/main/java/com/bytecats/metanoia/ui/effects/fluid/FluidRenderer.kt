package com.bytecats.metanoia.ui.effects.fluid

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.withMatrix
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * Fluid renderer with advanced visualization capabilities.
 * Features vorticity visualization, curl detection, adaptive density rendering,
 * and color mapping for visual appeal.
 *
 * Mobile-optimized rendering with:
 * - Half-float textures for memory efficiency
 * - Adaptive resolution scaling
 * - Efficient color mapping
 * - Temporal anti-aliasing
 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
class FluidRenderer(
    private val config: FluidPhysicsConfig = FluidPhysicsConfig(),
    private val state: FluidSimulationState = FluidSimulationState(config)
) {
    // Visualization modes
    enum class VisualizationMode {
        DENSITY,
        VELOCITY,
        PRESSURE,
        VORTICITY,
        CURL,
        CURL_NOISE,
        MULTI_CHANNEL,
        HEATMAP
    }

    // Current visualization mode
    var visualizationMode: VisualizationMode = VisualizationMode.DENSITY
        private set

    // Color palettes for different visualization modes
    private val densityPalette = createDensityPalette()
    private val velocityPalette = createVelocityPalette()
    private val pressurePalette = createPressurePalette()
    private val vorticityPalette = createVorticityPalette()

    // Rendering shaders
    private val displayShader: RuntimeShader
    private val colorMapShader: RuntimeShader
    private val vorticityShader: RuntimeShader
    private val curlNoiseShader: RuntimeShader
    private val multiChannelShader: RuntimeShader
    private val heatmapShader: RuntimeShader

    // Rendering parameters
    private var brightness = 1.0f
    private var contrast = 1.0f
    private var saturation = 1.0f
    private var gamma = 1.0f

    // Adaptive rendering
    private var currentResolution = config.visualResolution
    private var renderScale = 1.0f

    // Temporal anti-aliasing
    private var taaEnabled = false
    private var taaWeight = 0.9f
    private var previousFrame: IntArray? = null

    init {
        // Initialize rendering shaders
        displayShader = createDisplayShader()
        colorMapShader = createColorMapShader()
        vorticityShader = createVorticityVisualizationShader()
        curlNoiseShader = createCurlNoiseShader()
        multiChannelShader = createMultiChannelShader()
        heatmapShader = createHeatmapShader()

        // Initialize rendering
        state.initialize()
    }

    /**
     * Main rendering method - renders current simulation state to canvas
     */
    suspend fun render(
        drawScope: DrawScope,
        viewportWidth: Float,
        viewportHeight: Float
    ) {
        // Calculate render scale based on viewport
        updateRenderScale(viewportWidth, viewportHeight)

        // Get visualization bitmap
        val bitmap = when (visualizationMode) {
            VisualizationMode.DENSITY -> renderDensityVisualization()
            VisualizationMode.VELOCITY -> renderVelocityVisualization()
            VisualizationMode.PRESSURE -> renderPressureVisualization()
            VisualizationMode.VORTICITY -> renderVorticityVisualization()
            VisualizationMode.CURL -> renderCurlVisualization()
            VisualizationMode.CURL_NOISE -> renderCurlNoiseVisualization()
            VisualizationMode.MULTI_CHANNEL -> renderMultiChannelVisualization()
            VisualizationMode.HEATMAP -> renderHeatmapVisualization()
        }

        // Apply post-processing
        val processedBitmap = applyPostProcessing(bitmap)

        // Apply temporal anti-aliasing if enabled
        val finalBitmap = if (taaEnabled) {
            applyTemporalAntiAliasing(processedBitmap)
        } else {
            processedBitmap
        }

        // Draw to canvas
        drawScope.drawBitmap(
            image = finalBitmap.asImageBitmap(),
            srcOffset = androidx.compose.ui.unit.IntOffset.Zero,
            dstOffset = androidx.compose.ui.unit.IntOffset.Zero,
            dstSize = androidx.compose.ui.unit.IntSize(
                width = currentResolution,
                height = currentResolution
            )
        )

        // Store for TAA
        previousFrame = finalBitmap
    }

    /**
     * Render density field with adaptive density rendering
     */
    private suspend fun renderDensityVisualization(): Bitmap {
        val width = currentResolution
        val height = currentResolution

        state.withDensityField { density ->
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val pixels = IntArray(width * height)

            for (y in 0 until height) {
                for (x in 0 until width) {
                    val idx = y * width + x

                    // Sample density with adaptive scaling
                    val densityValue = density[x, y, 0]

                    // Enhance contrast for better visibility
                    val enhancedDensity = enhanceDensity(densityValue)

                    // Get color from palette
                    val color = getDensityColor(enhancedDensity)

                    // Apply brightness and contrast
                    val finalColor = applyColorAdjustments(color)

                    pixels[idx] = finalColor
                }
            }

            bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
            return bitmap
        }
    }

    /**
     * Render velocity field with directional coloring
     */
    private suspend fun renderVelocityVisualization(): Bitmap {
        val width = config.physicsResolution
        val height = config.physicsResolution

        state.withVelocityField { velocity ->
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val pixels = IntArray(width * height)

            for (y in 0 until height) {
                for (x in 0 until width) {
                    val idx = y * width + x

                    val vx = velocity[x, y, 0]
                    val vy = velocity[x, y, 1]

                    // Calculate magnitude and direction
                    val magnitude = sqrt(vx * vx + vy * vy)
                    val normalizedMagnitude = (magnitude / config.maxVelocity).coerceIn(0f, 1f)

                    // Calculate direction angle (-π to π)
                    val angle = atan2(vy, vx)

                    // Map to color palette
                    val color = getVelocityColor(normalizedMagnitude, angle)

                    pixels[idx] = color
                }
            }

            bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
            return bitmap
        }
    }

    /**
     * Render pressure field
     */
    private suspend fun renderPressureVisualization(): Bitmap {
        val width = config.physicsResolution
        val height = config.physicsResolution

        state.withPressureField { pressure ->
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val pixels = IntArray(width * height)

            // Find pressure range for normalization
            var minPressure = Float.MAX_VALUE
            var maxPressure = Float.MIN_VALUE

            for (y in 0 until height) {
                for (x in 0 until width) {
                    val p = pressure[x, y, 0]
                    minPressure = min(minPressure, p)
                    maxPressure = max(maxPressure, p)
                }
            }

            val pressureRange = maxPressure - minPressure

            for (y in 0 until height) {
                for (x in 0 until width) {
                    val idx = y * width + x

                    // Normalize pressure to [0, 1]
                    val normalizedPressure = if (pressureRange > 0) {
                        (pressure[x, y, 0] - minPressure) / pressureRange
                    } else {
                        0.5f
                    }

                    // Map to color palette
                    val color = getPressureColor(normalizedPressure)

                    pixels[idx] = color
                }
            }

            bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
            return bitmap
        }
    }

    /**
     * Render vorticity field with curl detection
     */
    private suspend fun renderVorticityVisualization(): Bitmap {
        val width = config.physicsResolution
        val height = config.physicsResolution

        state.withVorticityField { vorticity ->
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val pixels = IntArray(width * height)

            for (y in 0 until height) {
                for (x in 0 until width) {
                    val idx = y * width + x

                    val vorticityValue = vorticity[x, y, 0]
                    val vorticityMagnitude = vorticity[x, y, 1]

                    // Normalize for visualization
                    val normalizedVorticity = (abs(vorticityValue) / 10f).coerceIn(0f, 1f)

                    // Detect curl regions
                    val isCurl = normalizedVorticity > 0.3f

                    // Map to color palette
                    val color = getVorticityColor(normalizedVorticity, isCurl)

                    pixels[idx] = color
                }
            }

            bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
            return bitmap
        }
    }

    /**
     * Render curl noise visualization
     */
    private suspend fun renderCurlVisualization(): Bitmap {
        val width = config.physicsResolution
        val height = config.physicsResolution

        state.withVelocityField { velocity ->
            state.withVorticityField { vorticity ->
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val pixels = IntArray(width * height)

                for (y in 0 until height) {
                    for (x in 0 until width) {
                        val idx = y * width + x

                        // Calculate curl (2D analog)
                        val curl = calculateCurl(velocity, x, y)
                        val normalizedCurl = (abs(curl) / 5f).coerceIn(0f, 1f)

                        // Get color
                        val color = getCurlColor(normalizedCurl, curl)

                        pixels[idx] = color
                    }
                }

                bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
                return bitmap
            }
        }
    }

    /**
     * Render curl noise with procedural noise
     */
    private suspend fun renderCurlNoiseVisualization(): Bitmap {
        val width = currentResolution
        val height = currentResolution

        state.withVelocityField { velocity ->
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val pixels = IntArray(width * height)

            for (y in 0 until height) {
                for (x in 0 until width) {
                    val idx = y * width + x

                    // Generate curl noise
                    val noise = generateCurlNoise(x.toFloat() / width, y.toFloat() / height)

                    // Get color
                    val color = getCurlNoiseColor(noise)

                    pixels[idx] = color
                }
            }

            bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
            return bitmap
        }
    }

    /**
     * Render multi-channel visualization (density + velocity + pressure)
     */
    private suspend fun renderMultiChannelVisualization(): Bitmap {
        val width = config.physicsResolution
        val height = config.physicsResolution

        state.withDensityField { density ->
            state.withVelocityField { velocity ->
                state.withPressureField { pressure ->
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    val pixels = IntArray(width * height)

                    for (y in 0 until height) {
                        for (x in 0 until width) {
                            val idx = y * width + x

                            // Map each field to different color channels
                            val d = density[x, y, 0]
                            val v = sqrt(velocity[x, y, 0].pow(2) + velocity[x, y, 1].pow(2)) / config.maxVelocity
                            val p = pressure[x, y, 0]

                            // Compose color
                            val r = (d * 255).toInt().coerceIn(0, 255)
                            val g = (v * 255).toInt().coerceIn(0, 255)
                            val b = ((p + 0.5f) * 127).toInt().coerceIn(0, 255)

                            pixels[idx] = (255 shl 24) or (b shl 16) or (g shl 8) or r
                        }
                    }

                    bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
                    return bitmap
                }
            }
        }
    }

    /**
     * Render heatmap visualization
     */
    private suspend fun renderHeatmapVisualization(): Bitmap {
        val width = currentResolution
        val height = currentResolution

        state.withDensityField { density ->
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val pixels = IntArray(width * height)

            for (y in 0 until height) {
                for (x in 0 until width) {
                    val idx = y * width + x

                    val densityValue = density[x, y, 0]
                    val enhancedDensity = enhanceDensity(densityValue)

                    // Heatmap color mapping
                    val color = getHeatmapColor(enhancedDensity)

                    pixels[idx] = color
                }
            }

            bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
            return bitmap
        }
    }

    /**
     * Apply post-processing effects
     */
    private fun applyPostProcessing(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        for (i in pixels.indices) {
            pixels[i] = applyPixelPostProcessing(pixels[i])
        }

        val processedBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        processedBitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        return processedBitmap
    }

    /**
     * Apply post-processing to individual pixel
     */
    private fun applyPixelPostProcessing(pixel: Int): Int {
        val a = (pixel shr 24) and 0xFF
        var r = (pixel shr 16) and 0xFF
        var g = (pixel shr 8) and 0xFF
        var b = pixel and 0xFF

        // Apply brightness
        r = ((r / 255f) * brightness * 255).toInt().coerceIn(0, 255)
        g = ((g / 255f) * brightness * 255).toInt().coerceIn(0, 255)
        b = ((b / 255f) * brightness * 255).toInt().coerceIn(0, 255)

        // Apply contrast
        val factor = (259f * (contrast + 255f)) / (255f * (259f - contrast))
        r = (factor * (r - 128) + 128).toInt().coerceIn(0, 255)
        g = (factor * (g - 128) + 128).toInt().coerceIn(0, 255)
        b = (factor * (b - 128) + 128).toInt().coerceIn(0, 255)

        // Apply saturation
        val gray = (0.299f * r + 0.587f * g + 0.114f * b).toInt()
        r = (gray + saturation * (r - gray)).toInt().coerceIn(0, 255)
        g = (gray + saturation * (g - gray)).toInt().coerceIn(0, 255)
        b = (gray + saturation * (b - gray)).toInt().coerceIn(0, 255)

        // Apply gamma correction
        r = (255f * (r / 255f).pow(1f / gamma)).toInt().coerceIn(0, 255)
        g = (255f * (g / 255f).pow(1f / gamma)).toInt().coerceIn(0, 255)
        b = (255f * (b / 255f).pow(1f / gamma)).toInt().coerceIn(0, 255)

        return (a shl 24) or (b shl 16) or (g shl 8) or r
    }

    /**
     * Apply temporal anti-aliasing
     */
    private fun applyTemporalAntiAliasing(currentFrame: Bitmap): Bitmap {
        if (previousFrame == null) return currentFrame

        val width = currentFrame.width
        val height = currentFrame.height
        val currentPixels = IntArray(width * height)
        val previousPixels = IntArray(width * height)
        val blendedPixels = IntArray(width * height)

        currentFrame.getPixels(currentPixels, 0, width, 0, 0, width, height)

        for (i in currentPixels.indices) {
            val curr = currentPixels[i]
            val prev = previousFrame!![i]

            // Blend frames
            val a = ((curr shr 24) and 0xFF * taaWeight + (prev shr 24) and 0xFF * (1f - taaWeight)).toInt().coerceIn(0, 255)
            val r = ((curr shr 16) and 0xFF * taaWeight + (prev shr 16) and 0xFF * (1f - taaWeight)).toInt().coerceIn(0, 255)
            val g = ((curr shr 8) and 0xFF * taaWeight + (prev shr 8) and 0xFF * (1f - taaWeight)).toInt().coerceIn(0, 255)
            val b = (curr and 0xFF * taaWeight + (prev and 0xFF) * (1f - taaWeight)).toInt().coerceIn(0, 255)

            blendedPixels[i] = (a shl 24) or (b shl 16) or (g shl 8) or r
        }

        val blendedBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        blendedBitmap.setPixels(blendedPixels, 0, width, 0, 0, width, height)
        return blendedBitmap
    }

    /**
     * Calculate curl at position
     */
    private fun calculateCurl(velocity: FloatArray2D, x: Int, y: Int): Float {
        val res = config.physicsResolution

        val vyL = if (x > 0) velocity[x - 1, y, 1] else 0f
        val vyR = if (x < res - 1) velocity[x + 1, y, 1] else 0f
        val vxB = if (y > 0) velocity[x, y - 1, 0] else 0f
        val vxT = if (y < res - 1) velocity[x, y + 1, 0] else 0f

        val dvy_dx = vyR - vyL
        val dvx_dy = vxT - vxB

        return dvy_dx - dvx_dy
    }

    /**
     * Generate curl noise at UV coordinates
     */
    private fun generateCurlNoise(u: Float, v: Float): Float2D {
        val scale = 10f

        // Simple procedural noise approximation
        val nx = kotlin.math.sin(u * scale) * kotlin.math.cos(v * scale)
        val ny = kotlin.math.cos(u * scale) * kotlin.math.sin(v * scale)

        return Float2D(nx, ny)
    }

    /**
     * Enhance density for better visibility
     */
    private fun enhanceDensity(density: Float): Float {
        // Gamma correction for better contrast
        return density.pow(0.7f).coerceIn(0f, 1f)
    }

    /**
     * Get color from density palette
     */
    private fun getDensityColor(density: Float): Int {
        val index = (density * (densityPalette.size - 1)).toInt().coerceIn(0, densityPalette.size - 1)
        return densityPalette[index]
    }

    /**
     * Get color from velocity palette based on magnitude and direction
     */
    private fun getVelocityColor(magnitude: Float, angle: Float): Int {
        // Map angle to hue [0, 360]
        val hue = ((angle / kotlin.math.PI + 1f) * 0.5f * 360f).toInt()

        // Saturation based on magnitude
        val saturation = (magnitude * 100).toInt().coerceIn(0, 100)

        // Value based on magnitude
        val value = (magnitude * 100).toInt().coerceIn(20, 100)

        return hsvToColor(hue, saturation, value)
    }

    /**
     * Get color from pressure palette
     */
    private fun getPressureColor(pressure: Float): Int {
        val index = (pressure * (pressurePalette.size - 1)).toInt().coerceIn(0, pressurePalette.size - 1)
        return pressurePalette[index]
    }

    /**
     * Get color from vorticity palette
     */
    private fun getVorticityColor(vorticity: Float, isCurl: Boolean): Int {
        val index = (vorticity * (vorticityPalette.size - 1)).toInt().coerceIn(0, vorticityPalette.size - 1)
        return if (isCurl) {
            // Highlight curl regions with brighter colors
            val baseColor = vorticityPalette[index]
            val a = (baseColor shr 24) and 0xFF
            val r = ((baseColor shr 16) and 0xFF).coerceAtMost(255)
            val g = ((baseColor shr 8) and 0xFF).coerceAtMost(255)
            val b = (baseColor and 0xFF).coerceAtMost(255)
            (a shl 24) or (b shl 16) or (g shl 8) or r
        } else {
            vorticityPalette[index]
        }
    }

    /**
     * Get color from curl palette
     */
    private fun getCurlColor(curlMagnitude: Float, curlValue: Float): Int {
        val index = (curlMagnitude * (vorticityPalette.size - 1)).toInt().coerceIn(0, vorticityPalette.size - 1)
        val color = vorticityPalette[index]

        // Tint based on curl direction
        val r = if (curlValue > 0) {
            ((color shr 16) and 0xFF).coerceAtMost(255)
        } else {
            ((color shr 16) and 0xFF).coerceAtMost(200)
        }
        val b = if (curlValue < 0) {
            ((color and 0xFF)).coerceAtMost(255)
        } else {
            ((color and 0xFF)).coerceAtMost(200)
        }

        return (color and 0xFF000000.toInt()) or (b shl 16) or ((color shr 8) and 0xFF shl 8) or r
    }

    /**
     * Get color from curl noise palette
     */
    private fun getCurlNoiseColor(noise: Float2D): Int {
        val magnitude = sqrt(noise.x * noise.x + noise.y * noise.y)
        val normalizedMagnitude = magnitude.coerceIn(0f, 1f)

        val index = (normalizedMagnitude * (velocityPalette.size - 1)).toInt().coerceIn(0, velocityPalette.size - 1)
        return velocityPalette[index]
    }

    /**
     * Get color from heatmap palette
     */
    private fun getHeatmapColor(value: Float): Int {
        val index = (value * (densityPalette.size - 1)).toInt().coerceIn(0, densityPalette.size - 1)
        return densityPalette[index]
    }

    /**
     * Apply color adjustments
     */
    private fun applyColorAdjustments(color: Int): Int {
        var r = (color shr 16) and 0xFF
        var g = (color shr 8) and 0xFF
        var b = color and 0xFF

        // Apply brightness
        r = ((r / 255f) * brightness * 255).toInt().coerceIn(0, 255)
        g = ((g / 255f) * brightness * 255).toInt().coerceIn(0, 255)
        b = ((b / 255f) * brightness * 255).toInt().coerceIn(0, 255)

        // Apply contrast
        val factor = (259f * (contrast + 255f)) / (255f * (259f - contrast))
        r = (factor * (r - 128) + 128).toInt().coerceIn(0, 255)
        g = (factor * (g - 128) + 128).toInt().coerceIn(0, 255)
        b = (factor * (b - 128) + 128).toInt().coerceIn(0, 255)

        // Apply saturation
        val gray = (0.299f * r + 0.587f * g + 0.114f * b).toInt()
        r = (gray + saturation * (r - gray)).toInt().coerceIn(0, 255)
        g = (gray + saturation * (g - gray)).toInt().coerceIn(0, 255)
        b = (gray + saturation * (b - gray)).toInt().coerceIn(0, 255)

        return (255 shl 24) or (b shl 16) or (g shl 8) or r
    }

    /**
     * Update render scale based on viewport
     */
    private fun updateRenderScale(viewportWidth: Float, viewportHeight: Float) {
        val aspectRatio = viewportWidth / viewportHeight

        if (config.enableAdaptiveQuality) {
            // Adjust resolution based on viewport size
            currentResolution = when {
                viewportWidth < 500f -> config.visualResolution / 2
                viewportWidth < 1000f -> config.visualResolution
                else -> config.visualResolution
            }
        }

        renderScale = viewportWidth / currentResolution
    }

    /**
     * HSV to RGB color conversion
     */
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

    /**
     * Create density color palette (blue -> cyan -> white)
     */
    private fun createDensityPalette(): IntArray {
        val palette = IntArray(256)
        for (i in 0 until 256) {
            val t = i / 255f
            val r = (t * 255).toInt()
            val g = (t * 200 + t * t * 55).toInt()
            val b = 255
            palette[i] = (255 shl 24) or (b shl 16) or (g shl 8) or r
        }
        return palette
    }

    /**
     * Create velocity color palette (hue wheel)
     */
    private fun createVelocityPalette(): IntArray {
        val palette = IntArray(256)
        for (i in 0 until 256) {
            val hue = (i / 255f * 360f).toInt()
            palette[i] = hsvToColor(hue, 100, 100)
        }
        return palette
    }

    /**
     * Create pressure color palette (blue -> gray -> red)
     */
    private fun createPressurePalette(): IntArray {
        val palette = IntArray(256)
        for (i in 0 until 256) {
            val t = i / 255f
            val r = if (t < 0.5f) 0 else ((t - 0.5f) * 2 * 255).toInt()
            val g = (t * 128).toInt()
            val b = if (t < 0.5f) ((0.5f - t) * 2 * 255).toInt() else 0
            palette[i] = (255 shl 24) or (b shl 16) or (g shl 8) or r
        }
        return palette
    }

    /**
     * Create vorticity color palette (green -> yellow -> red)
     */
    private fun createVorticityPalette(): IntArray {
        val palette = IntArray(256)
        for (i in 0 until 256) {
            val t = i / 255f
            val r = (t * 255).toInt()
            val g = ((1f - t) * 255).toInt()
            val b = 0
            palette[i] = (255 shl 24) or (b shl 16) or (g shl 8) or r
        }
        return palette
    }

    /**
     * Set visualization mode
     */
    fun setVisualizationMode(mode: VisualizationMode) {
        visualizationMode = mode
    }

    /**
     * Set brightness [0, 2]
     */
    fun setBrightness(value: Float) {
        brightness = value.coerceIn(0f, 2f)
    }

    /**
     * Set contrast [0, 2]
     */
    fun setContrast(value: Float) {
        contrast = value.coerceIn(0f, 2f)
    }

    /**
     * Set saturation [0, 2]
     */
    fun setSaturation(value: Float) {
        saturation = value.coerceIn(0f, 2f)
    }

    /**
     * Set gamma [0.5, 2]
     */
    fun setGamma(value: Float) {
        gamma = value.coerceIn(0.5f, 2f)
    }

    /**
     * Enable/disable temporal anti-aliasing
     */
    fun setTAAEnabled(enabled: Boolean) {
        taaEnabled = enabled
    }

    /**
     * Set TAA blend weight [0, 1]
     */
    fun setTAAWeight(weight: Float) {
        taaWeight = weight.coerceIn(0f, 1f)
    }

    /**
     * AGSL Shader creation methods
     */

    private fun createDisplayShader(): RuntimeShader {
        val shaderCode = """
            uniform shader uInput;
            uniform float2 uResolution;
            uniform float uBrightness;
            uniform float uContrast;
            uniform float uSaturation;
            uniform float uGamma;

            vec4 applyPostProcessing(vec4 color) {
                // Apply brightness
                color.rgb *= uBrightness;
                
                // Apply contrast
                float factor = (259.0 * (uContrast + 255.0)) / (255.0 * (259.0 - uContrast));
                color.rgb = factor * (color.rgb - 0.5) + 0.5;
                
                // Apply saturation
                float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
                color.rgb = mix(vec3(gray), color.rgb, uSaturation);
                
                // Apply gamma correction
                color.rgb = pow(color.rgb, vec3(1.0 / uGamma));
                
                return color;
            }

            vec4 main(vec2 coords) {
                vec4 color = uInput.eval(coords);
                return applyPostProcessing(color);
            }
        """
        return RuntimeShader(shaderCode)
    }

    private fun createColorMapShader(): RuntimeShader {
        val shaderCode = """
            uniform sampler2D uInput;
            uniform sampler2D uPalette;
            uniform float uScale;
            uniform float uOffset;

            vec4 main(vec2 coords) {
                float value = texture(uInput, coords).r;
                float paletteCoord = value * uScale + uOffset;
                return texture(uPalette, vec2(paletteCoord, 0.5));
            }
        """
        return RuntimeShader(shaderCode)
    }

    private fun createVorticityVisualizationShader(): RuntimeShader {
        val shaderCode = """
            uniform sampler2D uVorticity;
            uniform float uEnhancement;

            vec4 main(vec2 coords) {
                float vorticity = texture(uVorticity, coords).r;
                float magnitude = texture(uVorticity, coords).g;
                
                float enhancedVorticity = abs(vorticity) * uEnhancement;
                enhancedVorticity = clamp(enhancedVorticity, 0.0, 1.0);
                
                // Color based on vorticity direction
                float direction = sign(vorticity);
                vec3 color;
                if (direction > 0.0) {
                    color = mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0), enhancedVorticity);
                } else {
                    color = mix(vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0), enhancedVorticity);
                }
                
                return vec4(color, 1.0);
            }
        """
        return RuntimeShader(shaderCode)
    }

    private fun createCurlNoiseShader(): RuntimeShader {
        val shaderCode = """
            uniform sampler2D uVelocity;
            uniform float2 uTexelSize;
            uniform float uScale;
            uniform float uTime;

            float2 noise2D(vec2 p) {
                return fract(sin(vec2(dot(p, vec2(12.9898, 78.233)), dot(p, vec2(53.5, 87.3)))) * 43758.5453) * 2.0 - 1.0;
            }

            vec4 main(vec2 coords) {
                vec2 noiseUV = coords * uScale;
                vec2 noise = noise2D(noiseUV + uTime * 0.1);
                
                float magnitude = length(noise);
                float enhancedMagnitude = clamp(magnitude * 2.0, 0.0, 1.0);
                
                vec3 color = mix(vec3(0.0), vec3(0.0, 0.8, 1.0), enhancedMagnitude);
                
                return vec4(color, 1.0);
            }
        """
        return RuntimeShader(shaderCode)
    }

    private fun createMultiChannelShader(): RuntimeShader {
        val shaderCode = """
            uniform sampler2D uDensity;
            uniform sampler2D uVelocity;
            uniform sampler2D uPressure;

            vec4 main(vec2 coords) {
                float density = texture(uDensity, coords).r;
                float2 velocity = texture(uVelocity, coords).rg;
                float pressure = texture(uPressure, coords).r;
                
                float velocityMagnitude = length(velocity);
                
                // Map to RGB channels
                float r = density;
                float g = velocityMagnitude;
                float b = pressure + 0.5;
                
                return vec4(r, g, b, 1.0);
            }
        """
        return RuntimeShader(shaderCode)
    }

    private fun createHeatmapShader(): RuntimeShader {
        val shaderCode = """
            uniform sampler2D uInput;
            uniform float uMinValue;
            uniform float uMaxValue;

            vec3 heatmap(float value) {
                float t = (value - uMinValue) / (uMaxValue - uMinValue);
                t = clamp(t, 0.0, 1.0);
                
                vec3 color;
                if (t < 0.25) {
                    color = mix(vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), t * 4.0);
                } else if (t < 0.5) {
                    color = mix(vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), (t - 0.25) * 4.0);
                } else if (t < 0.75) {
                    color = mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0), (t - 0.5) * 4.0);
                } else {
                    color = mix(vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), (t - 0.75) * 4.0);
                }
                
                return color;
            }

            vec4 main(vec2 coords) {
                float value = texture(uInput, coords).r;
                vec3 color = heatmap(value);
                return vec4(color, 1.0);
            }
        """
        return RuntimeShader(shaderCode)
    }

    /**
     * Get current configuration
     */
    fun getConfig(): FluidPhysicsConfig = config

    /**
     * Get current simulation state
     */
    fun getState(): FluidSimulationState = state
}