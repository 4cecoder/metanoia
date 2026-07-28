package com.bytecats.metanoia.bible

import android.content.Context
import android.util.Log
import com.bytecats.metanoia.models.BibleBook
import com.bytecats.metanoia.models.BOOKS
import com.bytecats.metanoia.settings.SettingsManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext

/**
 * Coordinates cache-first fetching of Bible content.
 *
 * The app stores scraped/fetched data in [BibleDatabase]. This manager adds a
 * layer on top that tracks which chapters are already cached and can bulk
 * prefetch whole books (or the entire Bible) in the background.
 *
 * It is deliberately stateless with respect to the actual content: it only
 * tracks what is missing and asks the underlying [BibleManager] to fetch.
 */
class BibleCacheManager(
    private val context: Context,
    private val bibleManager: BibleManager,
    private val settings: SettingsManager,
) {
    private val _prefetchProgress = MutableStateFlow<Map<String, Float>>(emptyMap())
    val prefetchProgress: StateFlow<Map<String, Float>> = _prefetchProgress

    private val _prefetchErrors = MutableStateFlow<Map<String, String>>(emptyMap())
    val prefetchErrors: StateFlow<Map<String, String>> = _prefetchErrors

    /** Returns true if every chapter of the given book has at least one verse cached. */
    fun isBookCached(book: BibleBook): Boolean {
        return (1..book.chapters).all { ch ->
            bibleManager.getChapter(book.name, ch).isNotEmpty()
        }
    }

    /** Returns the number of cached chapters for a book. */
    fun cachedChapterCount(book: BibleBook): Int {
        return (1..book.chapters).count { ch ->
            bibleManager.getChapter(book.name, ch).isNotEmpty()
        }
    }

    /** Returns the fraction of cached chapters for a book (0..1). */
    fun cacheFraction(book: BibleBook): Float {
        return cachedChapterCount(book).toFloat() / book.chapters.toFloat()
    }

    /**
     * Fetches a single chapter if not already cached. Returns whether the
     * chapter now has content (locally cached or fetched).
     */
    suspend fun ensureChapter(book: String, chapter: Int): Boolean = withContext(Dispatchers.IO) {
        val local = bibleManager.getChapter(book, chapter)
        if (local.isNotEmpty()) return@withContext true
        try {
            bibleManager.fetchChapter(book, chapter, settings.bibleGatewayVersion)
            true
        } catch (e: Exception) {
            Log.w("BibleCacheManager", "ensureChapter failed: $book $chapter: ${e.message}")
            false
        }
    }

    /**
     * Prefetches all chapters of a book in the background. Progress and errors
     * are exposed via [prefetchProgress] and [prefetchErrors].
     */
    suspend fun prefetchBook(book: BibleBook) = withContext(Dispatchers.IO) {
        _prefetchProgress.value = _prefetchProgress.value + (book.name to 0f)
        _prefetchErrors.value = _prefetchErrors.value - book.name
        var cached = 0
        for (ch in 1..book.chapters) {
            if (ensureChapter(book.name, ch)) {
                cached++
            } else {
                _prefetchErrors.value = _prefetchErrors.value + (book.name to "Failed at chapter $ch")
            }
            _prefetchProgress.value = _prefetchProgress.value + (book.name to cached.toFloat() / book.chapters)
        }
        if ((_prefetchErrors.value[book.name]) == null) {
            // also prefetch interlinear for the first chapter as a smoke test
            try { bibleManager.fetchInterlinear(book.name, 1) } catch (_: Exception) { }
        }
    }

    /** Prefetch a list of books sequentially. */
    suspend fun prefetchBooks(books: List<BibleBook>) {
        books.forEach { prefetchBook(it) }
    }

    /** Prefetch the whole canonical Bible (OT + NT, excluding apocrypha/Ethiopian). */
    suspend fun prefetchWholeBible() {
        prefetchBooks(BOOKS.filter { it.testament in listOf("Old", "New") && !it.isApocrypha })
    }

    fun clearProgress() {
        _prefetchProgress.value = emptyMap()
        _prefetchErrors.value = emptyMap()
    }
}
