package com.bytecats.metanoia.bible.dao

import android.database.sqlite.SQLiteDatabase
import com.bytecats.metanoia.models.BOOKS
import com.bytecats.metanoia.models.HotChapter

class ReadingAnalyticsDao(private val openDb: () -> SQLiteDatabase) {

    fun recordChapterRead(book: String, chapter: Int) {
        val db = openDb()
        val now = System.currentTimeMillis()
        db.beginTransaction()
        try {
            val cursor = db.rawQuery(
                "SELECT read_count, first_read_at, reading_time_seconds FROM reading_progress WHERE book = ? AND chapter = ?",
                arrayOf(book, chapter.toString())
            )
            val existed = cursor.moveToFirst()
            val prevCount = if (existed) cursor.getInt(0) else 0
            val firstReadAt = if (existed) cursor.getLong(1) else now
            val prevTime = if (existed && cursor.columnCount > 2) cursor.getLong(2) else 0L
            cursor.close()
            db.execSQL(
                "INSERT OR REPLACE INTO reading_progress (book, chapter, first_read_at, last_read_at, read_count, reading_time_seconds) VALUES (?, ?, ?, ?, ?, ?)",
                arrayOf(book, chapter, firstReadAt, now, prevCount + 1, prevTime)
            )
            db.execSQL(
                "INSERT INTO reading_events (book, chapter, timestamp) VALUES (?, ?, ?)",
                arrayOf(book, chapter, now)
            )
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); db.close() }
    }

    fun recordReadingTime(book: String, chapter: Int, additionalSeconds: Long) {
        if (additionalSeconds <= 0) return
        val db = openDb()
        val now = System.currentTimeMillis()
        db.beginTransaction()
        try {
            val cursor = db.rawQuery(
                "SELECT read_count, first_read_at, reading_time_seconds FROM reading_progress WHERE book = ? AND chapter = ?",
                arrayOf(book, chapter.toString())
            )
            val existed = cursor.moveToFirst()
            val prevCount = if (existed) cursor.getInt(0) else 0
            val firstReadAt = if (existed) cursor.getLong(1) else now
            val prevTime = if (existed && cursor.columnCount > 2) cursor.getLong(2) else 0L
            cursor.close()

            db.execSQL(
                "INSERT OR REPLACE INTO reading_progress (book, chapter, first_read_at, last_read_at, read_count, reading_time_seconds) VALUES (?, ?, ?, ?, ?, ?)",
                arrayOf(book, chapter, firstReadAt, now, prevCount, prevTime + additionalSeconds)
            )
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); db.close() }
    }

    fun getChapterReadingTimes(book: String): Map<Int, Long> {
        val map = mutableMapOf<Int, Long>()
        val db = openDb()
        val cursor = db.rawQuery("SELECT chapter, reading_time_seconds FROM reading_progress WHERE book = ?", arrayOf(book))
        while (cursor.moveToNext()) {
            map[cursor.getInt(0)] = cursor.getLong(1)
        }
        cursor.close(); db.close()
        return map
    }

    fun getReadCompletion(): Map<String, Float> {
        val completion = mutableMapOf<String, Float>()
        val db = openDb()
        val cursor = db.rawQuery(
            "SELECT book, COUNT(DISTINCT chapter) FROM reading_progress WHERE read_count > 0 GROUP BY book", null
        )
        while (cursor.moveToNext()) {
            val name = cursor.getString(0)
            val readChapters = cursor.getInt(1)
            val totalChapters = BOOKS.find { it.name == name }?.chapters ?: 1
            completion[name] = readChapters.toFloat() / totalChapters.toFloat()
        }
        cursor.close(); db.close()
        return completion
    }

    fun getMostReadBooks(limit: Int = 5): List<Pair<String, Int>> {
        val list = mutableListOf<Pair<String, Int>>()
        val db = openDb()
        val cursor = db.rawQuery(
            "SELECT book, COUNT(*) as cnt FROM reading_events GROUP BY book ORDER BY cnt DESC LIMIT ?",
            arrayOf(limit.toString())
        )
        while (cursor.moveToNext()) list.add(cursor.getString(0) to cursor.getInt(1))
        cursor.close(); db.close()
        return list
    }

    fun getHotChapters(limit: Int = 10): List<HotChapter> {
        val list = mutableListOf<HotChapter>()
        val db = openDb()
        val cursor = db.rawQuery(
            "SELECT book, chapter, COUNT(*) as cnt FROM reading_events GROUP BY book, chapter ORDER BY cnt DESC LIMIT ?",
            arrayOf(limit.toString())
        )
        while (cursor.moveToNext()) list.add(HotChapter(cursor.getString(0), cursor.getInt(1), cursor.getInt(2)))
        cursor.close(); db.close()
        return list
    }

    fun getReadingEventCounts(sinceMillis: Long): Int {
        val db = openDb()
        val count = db.rawQuery(
            "SELECT COUNT(*) FROM reading_events WHERE timestamp >= ?", arrayOf(sinceMillis.toString())
        ).use { if (it.moveToFirst()) it.getInt(0) else 0 }
        db.close()
        return count
    }

    fun getFirstEverReadTimestamp(): Long? {
        val db = openDb()
        val cursor = db.rawQuery("SELECT MIN(timestamp) FROM reading_events", null)
        val result = if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
        cursor.close(); db.close()
        return result
    }

    private fun getAllEventTimestamps(): List<Long> {
        val db = openDb()
        val cursor = db.rawQuery("SELECT timestamp FROM reading_events", null)
        val list = mutableListOf<Long>()
        while (cursor.moveToNext()) list.add(cursor.getLong(0))
        cursor.close(); db.close()
        return list
    }

    fun getReadEpochDaysDescending(): List<Long> {
        val days = mutableSetOf<Long>()
        for (ts in getAllEventTimestamps()) {
            days.add(java.time.Instant.ofEpochMilli(ts).atZone(java.time.ZoneId.systemDefault()).toLocalDate().toEpochDay())
        }
        return days.sortedDescending()
    }

    fun getDailyReadCounts(days: Int): List<Pair<Long, Int>> {
        if (days <= 0) return emptyList()
        val byDay = mutableMapOf<Long, Int>()
        for (ts in getAllEventTimestamps()) {
            val epochDay = java.time.Instant.ofEpochMilli(ts).atZone(java.time.ZoneId.systemDefault()).toLocalDate().toEpochDay()
            byDay[epochDay] = (byDay[epochDay] ?: 0) + 1
        }
        val today = java.time.LocalDate.now().toEpochDay()
        val start = today - (days - 1)
        return (start..today).map { it to (byDay[it] ?: 0) }
    }

    fun getDayOfWeekCounts(): IntArray {
        val counts = IntArray(7)
        for (ts in getAllEventTimestamps()) {
            val zdt = java.time.Instant.ofEpochMilli(ts).atZone(java.time.ZoneId.systemDefault())
            counts[zdt.dayOfWeek.value % 7]++
        }
        return counts
    }

    fun getHourOfDayCounts(): IntArray {
        val counts = IntArray(24)
        for (ts in getAllEventTimestamps()) {
            val zdt = java.time.Instant.ofEpochMilli(ts).atZone(java.time.ZoneId.systemDefault())
            counts[zdt.hour]++
        }
        return counts
    }

    fun getTestamentReadCounts(): Map<String, Int> {
        val counts = mutableMapOf("Old" to 0, "New" to 0, "Eth" to 0)
        val db = openDb()
        val cursor = db.rawQuery(
            "SELECT book, COUNT(DISTINCT chapter) FROM reading_progress WHERE read_count > 0 GROUP BY book", null
        )
        while (cursor.moveToNext()) {
            val name = cursor.getString(0)
            val readChapters = cursor.getInt(1)
            val testament = BOOKS.find { it.name == name }?.testament
            if (testament != null) counts[testament] = (counts[testament] ?: 0) + readChapters
        }
        cursor.close(); db.close()
        return counts
    }

    fun clearReadingHistory() {
        val db = openDb()
        db.beginTransaction()
        try {
            db.execSQL("DELETE FROM reading_progress")
            db.execSQL("DELETE FROM reading_events")
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); db.close() }
    }
}
