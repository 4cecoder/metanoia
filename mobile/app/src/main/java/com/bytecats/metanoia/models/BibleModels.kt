package com.bytecats.metanoia.models

data class BibleBook(val name: String, val chapters: Int, val testament: String, val isApocrypha: Boolean = false)
data class InterlinearWord(val original: String, val strongs: String, val translation: String)
data class Favorite(val strongs: String, val lemma: String, val definition: String)
data class Highlight(val book: String, val chapter: Int, val verse: Int, val color: Int)
data class Note(val id: Int = 0, val book: String, val chapter: Int, val verse: Int, val content: String, val timestamp: Long)
data class SearchResult(val book: String, val chapter: Int, val verse: Int, val text: String)

data class Verse(val number: Int, val text: String)
data class LexiconEntry(val lemma: String, val definition: String)

data class LibraryStats(
    val versesOt: Int, val versesNt: Int,
    val lexiconHeb: Int, val lexiconGk: Int,
    val notesCount: Int, val highlightsCount: Int,
    val interlinearCount: Int,
    val dbSizeMb: Double
)
