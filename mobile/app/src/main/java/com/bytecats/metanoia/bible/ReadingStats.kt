package com.bytecats.metanoia.bible

/**
 * Pure (no-Android-dependency) math backing the reading/usage analytics
 * screen and the book-card read-progress gradient -- kept separate from
 * BibleDatabase/BibleScreen so it's directly unit-testable on the JVM
 * without Robolectric, the same split DeepLink.kt uses for its parsing logic.
 */
object ReadingStats {
    const val DAY_MILLIS = 24 * 60 * 60 * 1000L

    // Rolling windows, not calendar-boundary buckets (this week starting
    // Monday, etc.) -- simpler, avoids timezone edge cases, and matches what
    // a casual "how much have I read this week" figure actually needs.
    fun weekCutoff(nowMillis: Long): Long = nowMillis - 7 * DAY_MILLIS
    fun monthCutoff(nowMillis: Long): Long = nowMillis - 30 * DAY_MILLIS
    fun yearCutoff(nowMillis: Long): Long = nowMillis - 365 * DAY_MILLIS

    /** Whole days between `sinceMillis` and `nowMillis`, floored at 0 (never negative for a clock that hasn't moved backwards). */
    fun daysSince(sinceMillis: Long, nowMillis: Long): Int =
        ((nowMillis - sinceMillis) / DAY_MILLIS).toInt().coerceAtLeast(0)

    /**
     * Linear-interpolates between two 0xRRGGBB colors (no alpha) by
     * `progress` (clamped to [0,1]). Returned as a packed Int rather than a
     * Compose Color so this stays a plain-Kotlin function callable from a
     * JVM unit test; callers on the UI side wrap the result in
     * androidx.compose.ui.graphics.Color(...).
     */
    fun lerpColor(from: Int, to: Int, progress: Float): Int {
        val p = progress.coerceIn(0f, 1f)
        val fr = (from shr 16) and 0xFF; val fg = (from shr 8) and 0xFF; val fb = from and 0xFF
        val tr = (to shr 16) and 0xFF; val tg = (to shr 8) and 0xFF; val tb = to and 0xFF
        val r = (fr + (tr - fr) * p).toInt().coerceIn(0, 255)
        val g = (fg + (tg - fg) * p).toInt().coerceIn(0, 255)
        val b = (fb + (tb - fb) * p).toInt().coerceIn(0, 255)
        return (r shl 16) or (g shl 8) or b
    }
}
