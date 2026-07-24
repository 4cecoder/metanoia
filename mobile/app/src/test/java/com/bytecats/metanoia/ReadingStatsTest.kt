package com.bytecats.metanoia

import com.bytecats.metanoia.bible.ReadingStats
import org.junit.Assert.assertEquals
import org.junit.Test

class ReadingStatsTest {

    // -------------------------------------------------------------------
    // Rolling-window cutoffs
    // -------------------------------------------------------------------

    @Test
    fun weekCutoff_isSevenDaysBeforeNow() {
        val now = 1_000_000_000_000L
        assertEquals(now - 7 * ReadingStats.DAY_MILLIS, ReadingStats.weekCutoff(now))
    }

    @Test
    fun monthCutoff_isThirtyDaysBeforeNow() {
        val now = 1_000_000_000_000L
        assertEquals(now - 30 * ReadingStats.DAY_MILLIS, ReadingStats.monthCutoff(now))
    }

    @Test
    fun yearCutoff_isThreeSixtyFiveDaysBeforeNow() {
        val now = 1_000_000_000_000L
        assertEquals(now - 365 * ReadingStats.DAY_MILLIS, ReadingStats.yearCutoff(now))
    }

    // -------------------------------------------------------------------
    // daysSince
    // -------------------------------------------------------------------

    @Test
    fun daysSince_computesWholeDays() {
        val since = 0L
        val now = 3 * ReadingStats.DAY_MILLIS
        assertEquals(3, ReadingStats.daysSince(since, now))
    }

    @Test
    fun daysSince_partialDayFloorsDown() {
        val since = 0L
        val now = 3 * ReadingStats.DAY_MILLIS + (ReadingStats.DAY_MILLIS / 2)
        assertEquals(3, ReadingStats.daysSince(since, now))
    }

    @Test
    fun daysSince_sameInstant_isZero() {
        assertEquals(0, ReadingStats.daysSince(5000L, 5000L))
    }

    @Test
    fun daysSince_neverNegative_evenIfSinceIsAfterNow() {
        // Defensive: a clock that appears to move backwards shouldn't yield a negative day count.
        assertEquals(0, ReadingStats.daysSince(sinceMillis = ReadingStats.DAY_MILLIS, nowMillis = 0L))
    }

    // -------------------------------------------------------------------
    // lerpColor
    // -------------------------------------------------------------------

    @Test
    fun lerpColor_atZero_returnsFromColor() {
        assertEquals(0x112233, ReadingStats.lerpColor(0x112233, 0xAABBCC, 0f))
    }

    @Test
    fun lerpColor_atOne_returnsToColor() {
        assertEquals(0xAABBCC, ReadingStats.lerpColor(0x112233, 0xAABBCC, 1f))
    }

    @Test
    fun lerpColor_atHalf_isMidpoint() {
        // 0x00 -> 0xFF at p=0.5 should land at 0x7F (127, integer-truncated).
        val result = ReadingStats.lerpColor(0x000000, 0xFFFFFF, 0.5f)
        assertEquals(0x7F7F7F, result)
    }

    @Test
    fun lerpColor_clampsBelowZero() {
        assertEquals(0x112233, ReadingStats.lerpColor(0x112233, 0xAABBCC, -1f))
    }

    @Test
    fun lerpColor_clampsAboveOne() {
        assertEquals(0xAABBCC, ReadingStats.lerpColor(0x112233, 0xAABBCC, 2f))
    }

    @Test
    fun lerpColor_sameColor_isStableAtAnyProgress() {
        assertEquals(0x9ece6a, ReadingStats.lerpColor(0x9ece6a, 0x9ece6a, 0.37f))
    }
}
