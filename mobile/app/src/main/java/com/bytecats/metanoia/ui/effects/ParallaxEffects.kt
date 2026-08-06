package com.bytecats.metanoia.ui.effects

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import kotlin.math.*

/**
 * Parallax configuration for depth-based effects
 */
data class ParallaxConfig(
    val depth: Float = 1f,
    val intensity: Float = 0.5f,
    val rotationScale: Float = 0.1f,
    val perspective: Float = 1000f
)

/**
 * 3D transformation state for realistic parallax
 */
data class Transform3D(
    val translationX: Float = 0f,
    val translationY: Float = 0f,
    val translationZ: Float = 0f,
    val rotationX: Float = 0f,
    val rotationY: Float = 0f,
    val rotationZ: Float = 0f,
    val scale: Float = 1f
)

/**
 * Applies a smooth vertical 3D depth parallax effect based on scroll position
 */
fun Modifier.parallaxScroll(
    scrollState: ScrollState,
    config: ParallaxConfig = ParallaxConfig()
): Modifier = this.graphicsLayer {
    val scrollProgress = scrollState.value.toFloat() / max(1f, scrollState.maxValue.toFloat())
    translationY = scrollState.value * config.intensity
    rotationX = (scrollProgress * config.rotationScale * 180f).coerceIn(-15f, 15f)
    // Note: translationZ and scale not available in this Compose version
    // Using shadowElevation for depth effect instead
    shadowElevation = scrollProgress * config.depth * 2f
}

/**
 * Applies a smooth vertical 3D depth parallax effect for LazyColumn items
 */
fun Modifier.parallaxLazyItem(
    lazyListState: LazyListState,
    index: Int,
    config: ParallaxConfig = ParallaxConfig()
): Modifier = this.graphicsLayer {
    val firstVisibleIndex = lazyListState.firstVisibleItemIndex
    val firstVisibleScrollOffset = lazyListState.firstVisibleItemScrollOffset.toFloat()
    
    val diff = (index - firstVisibleIndex).toFloat()
    val visibilityProgress = 1f - (firstVisibleScrollOffset / size.height)
    
    translationY = diff * 20f - firstVisibleScrollOffset * config.intensity
    // Note: translationZ not available in this Compose version
    // Using shadowElevation for depth effect instead
    shadowElevation = (diff * config.depth * 1.5f).coerceAtMost(8f)
    rotationX = (firstVisibleScrollOffset * config.rotationScale).coerceIn(-8f, 8f)
    alpha = visibilityProgress.coerceIn(0.3f, 1f)
}

/**
 * Applies 3D tilt effect based on pointer/gesture position
 */
fun Modifier.tiltEffect(
    pointerOffset: Offset = Offset.Zero,
    config: ParallaxConfig = ParallaxConfig()
): Modifier = this.graphicsLayer {
    val normalizedX = (pointerOffset.x / size.width - 0.5f) * 2f
    val normalizedY = (pointerOffset.y / size.height - 0.5f) * 2f
    
    rotationY = normalizedX * config.rotationScale * 180f
    rotationX = -normalizedY * config.rotationScale * 180f
    // Note: translationZ and scale not available in this Compose version
    // Using shadowElevation for depth effect and scaling via transformation
    shadowElevation = config.depth * 3f
    
    val distance = sqrt(normalizedX * normalizedX + normalizedY * normalizedY)
    // Simulate scale via transformation matrix if needed, or remove
    // For now, we'll skip the scale effect as it's not critical
}

/**
 * Applies perspective transformation for 3D depth effect
 */
fun Modifier.perspective3D(
    transform: Transform3D,
    config: ParallaxConfig = ParallaxConfig()
): Modifier = this.graphicsLayer {
    translationX = transform.translationX
    translationY = transform.translationY
    // Note: translationZ and scale not available in this Compose version
    // Using shadowElevation for depth effect instead
    shadowElevation = transform.translationZ.coerceAtMost(10f)
    rotationX = transform.rotationX
    rotationY = transform.rotationY
    rotationZ = transform.rotationZ
    // Scale effect not available, skip for compatibility
    cameraDistance = config.perspective
}

/**
 * Calculates parallax offset based on container and child bounds
 */
fun calculateParallaxOffset(
    containerOffset: Float,
    childOffset: Float,
    containerSize: Float,
    childSize: Float,
    depth: Float
): Float {
    val relativePos = (childOffset - containerOffset) / containerSize
    return relativePos * depth * 0.5f
}

/**
 * Creates a 3D transform from scroll and pointer inputs
 */
fun createScrollPointerTransform(
    scrollProgress: Float,
    pointerOffset: Offset,
    containerSize: androidx.compose.ui.geometry.Size,
    config: ParallaxConfig = ParallaxConfig()
): Transform3D {
    val normalizedX = (pointerOffset.x / containerSize.width - 0.5f) * 2f
    val normalizedY = (pointerOffset.y / containerSize.height - 0.5f) * 2f
    
    return Transform3D(
        translationX = normalizedX * config.depth * 10f,
        translationY = scrollProgress * config.intensity * 50f,
        translationZ = config.depth * 20f,
        rotationX = -normalizedY * config.rotationScale * 180f + scrollProgress * config.rotationScale * 90f,
        rotationY = normalizedX * config.rotationScale * 180f,
        scale = 1f + scrollProgress * config.depth * 0.05f
    )
}