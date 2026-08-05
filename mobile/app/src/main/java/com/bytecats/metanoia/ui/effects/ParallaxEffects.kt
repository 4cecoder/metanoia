package com.bytecats.metanoia.ui.effects

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer

/**
 * Applies a smooth vertical 3D depth parallax effect based on scroll position.
 */
fun Modifier.parallaxScroll(
    scrollState: ScrollState,
    speed: Float = 0.3f
): Modifier = this.graphicsLayer {
    translationY = scrollState.value * speed
    rotationX = (scrollState.value * 0.02f).coerceIn(-10f, 10f)
}

/**
 * Applies a smooth vertical 3D depth parallax effect for LazyColumn items based on LazyListState.
 */
fun Modifier.parallaxLazyItem(
    lazyListState: LazyListState,
    index: Int,
    speed: Float = 0.25f
): Modifier = this.graphicsLayer {
    val firstVisibleIndex = lazyListState.firstVisibleItemIndex
    val firstVisibleScrollOffset = lazyListState.firstVisibleItemScrollOffset
    
    val diff = (index - firstVisibleIndex)
    translationY = (diff * 20f - firstVisibleScrollOffset * speed)
}
