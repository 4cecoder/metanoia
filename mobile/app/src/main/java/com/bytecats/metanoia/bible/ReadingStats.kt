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

    // -----------------------------------------------------------------
    // Streaks
    // -----------------------------------------------------------------

    /**
     * Length of the current unbroken run of local-calendar days (each day
     * represented as a java.time epoch-day integer, per
     * BibleDatabase.getReadEpochDaysDescending's KDoc) ending at "now".
     *
     * `readEpochDaysDescending` is expected to already be distinct and
     * descending (that's what the DB layer returns), but this dedupes via a
     * Set regardless of order or duplicates, rather than trusting the caller.
     *
     * Semantics: if `todayEpochDay` was read on, count consecutive days
     * backward from today. If today was NOT read on but yesterday
     * (`todayEpochDay - 1`) was, the streak is still "alive" -- today isn't
     * over yet -- so count backward from yesterday instead. If neither today
     * nor yesterday appears, the streak is broken: 0.
     */
    fun currentStreak(readEpochDaysDescending: List<Long>, todayEpochDay: Long): Int {
        val days = readEpochDaysDescending.toHashSet()
        if (days.isEmpty()) return 0
        val anchor = when {
            todayEpochDay in days -> todayEpochDay
            (todayEpochDay - 1) in days -> todayEpochDay - 1
            else -> return 0
        }
        var streak = 0
        var day = anchor
        while (day in days) {
            streak++
            day--
        }
        return streak
    }

    /**
     * Longest run of consecutive integers anywhere in `readEpochDays`
     * (possibly unsorted/duplicated -- dedupes via a Set first). Independent
     * of "now", unlike currentStreak.
     */
    fun longestStreak(readEpochDays: List<Long>): Int {
        val days = readEpochDays.toHashSet()
        var longest = 0
        for (day in days) {
            // Only measure from the start of each run (no predecessor in the
            // set) so every run is counted exactly once instead of once per
            // member of the run.
            if ((day - 1) !in days) {
                var length = 1
                var next = day + 1
                while (next in days) {
                    length++
                    next++
                }
                if (length > longest) longest = length
            }
        }
        return longest
    }

    // -----------------------------------------------------------------
    // Day-of-week / time-of-day habits
    // -----------------------------------------------------------------

    /**
     * Index of the day-of-week with the highest reading_events count, or
     * null if every bucket is zero. Expects `counts` in SQLite's `%w`
     * convention -- index 0=Sunday, 1=Monday, ..., 6=Saturday -- matching
     * BibleDatabase.getDayOfWeekCounts()'s KDoc. Ties are broken by lowest
     * index (first max wins).
     */
    fun mostActiveDayOfWeek(counts: IntArray): Int? {
        var bestIdx = -1
        var bestVal = 0
        for (i in counts.indices) {
            if (counts[i] > bestVal) {
                bestVal = counts[i]
                bestIdx = i
            }
        }
        return if (bestIdx == -1) null else bestIdx
    }

    /** Sentinel returned by mostActiveTimeOfDay when there's no reading history to bucket at all. */
    const val NOT_ENOUGH_DATA = "Not enough data"

    /**
     * Buckets a 24-entry (index = local hour 0-23, matching
     * BibleDatabase.getHourOfDayCounts()'s KDoc) hour histogram into
     * Morning(5-11) / Afternoon(12-16) / Evening(17-21) / Night(22-4, wraps
     * past midnight), and returns the label of whichever bucket has the
     * highest summed count. Ties are broken in Morning/Afternoon/Evening/Night
     * order (first max wins). Returns [NOT_ENOUGH_DATA] if every hour is zero.
     */
    fun mostActiveTimeOfDay(hourCounts: IntArray): String {
        val morning = (5..11).sumOf { hourCounts.getOrElse(it) { 0 } }
        val afternoon = (12..16).sumOf { hourCounts.getOrElse(it) { 0 } }
        val evening = (17..21).sumOf { hourCounts.getOrElse(it) { 0 } }
        val night = (22..23).sumOf { hourCounts.getOrElse(it) { 0 } } + (0..4).sumOf { hourCounts.getOrElse(it) { 0 } }
        val buckets = listOf("Morning" to morning, "Afternoon" to afternoon, "Evening" to evening, "Night" to night)
        val best = buckets.maxByOrNull { it.second }
        return if (best == null || best.second == 0) NOT_ENOUGH_DATA else best.first
    }

    /**
     * Calculates the overall completion fraction across all books.
     */
    fun calculateOverallCompletion(readCompletion: Map<String, Float>, getBookTotalChapters: (String) -> Int, totalChapters: Int): Float {
        val readChapters = readCompletion.entries.sumOf { (name, frac) ->
            (frac * getBookTotalChapters(name)).toInt()
        }
        return if (totalChapters > 0) readChapters.toFloat() / totalChapters else 0f
    }

    fun calculateWordCount(text: String): Int {
        if (text.isBlank()) return 0
        return text.trim().split("\\s+".toRegex()).size
    }

    fun formatReadingTime(wordCount: Int, wordsPerMinute: Int = 200): String {
        val minutes = wordCount / wordsPerMinute
        if (minutes < 1) return "< 1 min"
        return "$minutes min"
    }

    fun calculateBookWordCount(chapterWordCounts: Map<Int, Int>): Int {
        return chapterWordCounts.values.sum()
    }
}
