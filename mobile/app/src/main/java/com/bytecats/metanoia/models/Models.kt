package com.bytecats.metanoia.models

/**
 * Data models for the Metanoia app.
 * Shared across Bible, TTS, STT, and UI layers.
 */

data class BibleBook(
    val name: String,
    val chapters: Int,
    val testament: String
)

data class SearchResult(
    val book: String,
    val chapter: Int,
    val verse: Int,
    val text: String
)

data class InterlinearWord(
    val original: String,
    val strongs: String,
    val translation: String
)

data class Note(
    val id: Int,
    val book: String,
    val chapter: Int,
    val verse: Int,
    val content: String,
    val timestamp: Long
)

data class Favorite(
    val strongs: String,
    val lemma: String,
    val definition: String
)

data class LibraryStats(
    val versesOt: Int,
    val versesNt: Int,
    val lexiconHeb: Int,
    val lexiconGk: Int,
    val notesCount: Int,
    val highlights: Int,
    val interlinearCount: Int,
    val dbSizeMb: Double
)

/**
 * Bible book abbreviation map.
 * Keys are lowercase, no spaces.
 */
val BIBLE_ABBREVIATIONS: Map<String, String> = mapOf(
    "gen" to "Genesis", "ex" to "Exodus", "exod" to "Exodus", "lev" to "Leviticus",
    "num" to "Numbers", "deut" to "Deuteronomy", "dt" to "Deuteronomy",
    "josh" to "Joshua", "judg" to "Judges", "jdgs" to "Judges",
    "ruth" to "Ruth", "ru" to "Ruth",
    "1sam" to "1Samuel", "1sm" to "1Samuel", "2sam" to "2Samuel", "2sm" to "2Samuel",
    "1kgs" to "1Kings", "1ki" to "1Kings", "2kgs" to "2Kings", "2ki" to "2Kings",
    "1chr" to "1Chronicles", "2chr" to "2Chronicles",
    "ezra" to "Ezra", "neh" to "Nehemiah", "est" to "Esther", "esth" to "Esther",
    "tob" to "Tobit", "tobit" to "Tobit", "jdth" to "Judith", "judith" to "Judith",
    "1macc" to "1Meqabyan", "2macc" to "2Meqabyan", "3macc" to "3Meqabyan",
    "job" to "Job", "ps" to "Psalms", "psa" to "Psalms", "psalm" to "Psalms",
    "prov" to "Proverbs", "prv" to "Proverbs",
    "eccl" to "Ecclesiastes", "qoh" to "Ecclesiastes",
    "song" to "SongofSolomon", "sos" to "SongofSolomon", "cant" to "SongofSolomon",
    "wis" to "Wisdom", "wisdom" to "Wisdom",
    "sir" to "Sirach", "sirach" to "Sirach", "ecclus" to "Sirach",
    "isa" to "Isaiah", "is" to "Isaiah", "jer" to "Jeremiah",
    "lam" to "Lamentations", "ezek" to "Ezekiel", "ez" to "Ezekiel",
    "dan" to "Daniel", "dn" to "Daniel",
    "hos" to "Hosea", "joel" to "Joel", "amos" to "Amos", "am" to "Amos",
    "obad" to "Obadiah", "ob" to "Obadiah", "jon" to "Jonah", "jonah" to "Jonah",
    "mic" to "Micah", "nah" to "Nahum", "hab" to "Habakkuk",
    "zeph" to "Zephaniah", "hag" to "Haggai", "zech" to "Zechariah", "zec" to "Zechariah",
    "mal" to "Malachi",
    "eno" to "Enoch", "enoch" to "Enoch", "jub" to "Jubilees", "jubilees" to "Jubilees",
    "tegsas" to "Tegsas",
    "matt" to "Matthew", "mt" to "Matthew",
    "mark" to "Mark", "mk" to "Mark", "mar" to "Mark",
    "luke" to "Luke", "lk" to "Luke", "luk" to "Luke",
    "john" to "John", "jn" to "John", "joh" to "John",
    "acts" to "Acts", "ac" to "Acts",
    "rom" to "Romans", "ro" to "Romans",
    "1cor" to "1Corinthians", "1co" to "1Corinthians",
    "2cor" to "2Corinthians", "2co" to "2Corinthians",
    "gal" to "Galatians", "ga" to "Galatians",
    "eph" to "Ephesians",
    "phil" to "Philippians", "php" to "Philippians",
    "col" to "Colossians",
    "1thess" to "1Thessalonians", "1th" to "1Thessalonians",
    "2thess" to "2Thessalonians", "2th" to "2Thessalonians",
    "1tim" to "1Timothy", "1ti" to "1Timothy",
    "2tim" to "2Timothy", "2ti" to "2Timothy",
    "titus" to "Titus", "tit" to "Titus",
    "phlm" to "Philemon", "philem" to "Philemon",
    "heb" to "Hebrews",
    "1pet" to "1Peter", "1pe" to "1Peter", "1p" to "1Peter",
    "2pet" to "2Peter", "2pe" to "2Peter", "2p" to "2Peter",
    "1john" to "1John", "1jn" to "1John", "1jo" to "1John",
    "2john" to "2John", "2jn" to "2John", "2jo" to "2John",
    "3john" to "3John", "3jn" to "3John", "3jo" to "3John",
    "james" to "James", "jas" to "James", "jam" to "James",
    "jude" to "Jude", "jd" to "Jude",
    "rev" to "Revelation", "revelation" to "Revelation", "re" to "Revelation",
    "apoc" to "Revelation"
)
