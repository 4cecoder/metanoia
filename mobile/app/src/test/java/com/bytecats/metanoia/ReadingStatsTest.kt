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

    // -------------------------------------------------------------------
    // currentStreak
    // -------------------------------------------------------------------

    @Test
    fun currentStreak_emptyInput_isZero() {
        assertEquals(0, ReadingStats.currentStreak(emptyList(), 100L))
    }

    @Test
    fun currentStreak_singleDayReadToday_isOne() {
        assertEquals(1, ReadingStats.currentStreak(listOf(100L), 100L))
    }

    @Test
    fun currentStreak_anchoredOnToday_countsConsecutiveDaysBack() {
        // Read on 98, 99, 100 (today) -- streak of 3.
        assertEquals(3, ReadingStats.currentStreak(listOf(100L, 99L, 98L), 100L))
    }

    @Test
    fun currentStreak_anchoredOnYesterday_stillAliveIfTodayNotYetRead() {
        // Today (100) hasn't been read yet, but yesterday (99) and the day
        // before (98) were -- streak is still "alive" at 2, not broken.
        assertEquals(2, ReadingStats.currentStreak(listOf(99L, 98L), 100L))
    }

    @Test
    fun currentStreak_brokenByGapOfTwoOrMoreDays_isZero() {
        // Last read was 3 days ago (97) -- neither today (100) nor
        // yesterday (99) is present, so the streak is broken.
        assertEquals(0, ReadingStats.currentStreak(listOf(97L, 96L, 95L), 100L))
    }

    @Test
    fun currentStreak_dedupesAndSortsDefensively() {
        // Unsorted, with duplicates -- should behave identically to the
        // clean, sorted, distinct equivalent (98, 99, 100).
        assertEquals(3, ReadingStats.currentStreak(listOf(99L, 100L, 98L, 99L, 100L), 100L))
    }

    // -------------------------------------------------------------------
    // longestStreak
    // -------------------------------------------------------------------

    @Test
    fun longestStreak_emptyInput_isZero() {
        assertEquals(0, ReadingStats.longestStreak(emptyList()))
    }

    @Test
    fun longestStreak_singleDay_isOne() {
        assertEquals(1, ReadingStats.longestStreak(listOf(42L)))
    }

    @Test
    fun longestStreak_differsFromCurrentStreak() {
        // A long-past 5-day run (1..5) followed by a gap, then a shorter
        // 2-day run ending yesterday relative to "today" = 10.
        val days = listOf(1L, 2L, 3L, 4L, 5L, 8L, 9L)
        assertEquals(5, ReadingStats.longestStreak(days))
        // Current streak (anchored on yesterday=9, since today=10 unread) is only 2.
        assertEquals(2, ReadingStats.currentStreak(days, 10L))
    }

    @Test
    fun longestStreak_dedupesAndHandlesUnsortedInput() {
        // Distinct values are {7, 8, 9, 10, 11} -- all consecutive, run of 5.
        assertEquals(5, ReadingStats.longestStreak(listOf(10L, 8L, 9L, 8L, 11L, 7L)))
    }

    // -------------------------------------------------------------------
    // mostActiveDayOfWeek
    // -------------------------------------------------------------------

    @Test
    fun mostActiveDayOfWeek_allZero_isNull() {
        assertEquals(null, ReadingStats.mostActiveDayOfWeek(IntArray(7)))
    }

    @Test
    fun mostActiveDayOfWeek_picksMaxIndex() {
        // 0=Sunday..6=Saturday; Wednesday (3) is the max.
        val counts = intArrayOf(1, 2, 3, 10, 4, 5, 6)
        assertEquals(3, ReadingStats.mostActiveDayOfWeek(counts))
    }

    @Test
    fun mostActiveDayOfWeek_tieBreaksToLowestIndex() {
        val counts = intArrayOf(0, 5, 0, 5, 0, 0, 0)
        assertEquals(1, ReadingStats.mostActiveDayOfWeek(counts))
    }

    // -------------------------------------------------------------------
    // mostActiveTimeOfDay
    // -------------------------------------------------------------------

    @Test
    fun mostActiveTimeOfDay_allZero_isNotEnoughData() {
        assertEquals(ReadingStats.NOT_ENOUGH_DATA, ReadingStats.mostActiveTimeOfDay(IntArray(24)))
    }

    @Test
    fun mostActiveTimeOfDay_morningBoundaries_5through11() {
        val counts = IntArray(24)
        counts[5] = 1; counts[11] = 1
        assertEquals("Morning", ReadingStats.mostActiveTimeOfDay(counts))
    }

    @Test
    fun mostActiveTimeOfDay_afternoonBoundaries_12through16() {
        val counts = IntArray(24)
        counts[12] = 1; counts[16] = 1
        assertEquals("Afternoon", ReadingStats.mostActiveTimeOfDay(counts))
    }

    @Test
    fun mostActiveTimeOfDay_eveningBoundaries_17through21() {
        val counts = IntArray(24)
        counts[17] = 1; counts[21] = 1
        assertEquals("Evening", ReadingStats.mostActiveTimeOfDay(counts))
    }

    @Test
    fun mostActiveTimeOfDay_nightBoundaries_wrapsPastMidnight_22through4() {
        val counts = IntArray(24)
        counts[22] = 1; counts[23] = 1; counts[0] = 1; counts[4] = 1
        assertEquals("Night", ReadingStats.mostActiveTimeOfDay(counts))
    }

    @Test
    fun mostActiveTimeOfDay_tieBreaksInMorningAfternoonEveningNightOrder() {
        val counts = IntArray(24)
        counts[6] = 3   // Morning
        counts[14] = 3  // Afternoon
        assertEquals("Morning", ReadingStats.mostActiveTimeOfDay(counts))
    }
}
