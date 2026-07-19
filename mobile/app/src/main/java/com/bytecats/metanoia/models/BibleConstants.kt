package com.bytecats.metanoia.models

val BOOKS = listOf(
    BibleBook("Genesis", 50, "Old"), BibleBook("Exodus", 40, "Old"), BibleBook("Leviticus", 27, "Old"), BibleBook("Numbers", 36, "Old"), BibleBook("Deuteronomy", 34, "Old"), BibleBook("Joshua", 24, "Old"), BibleBook("Judges", 21, "Old"), BibleBook("Ruth", 4, "Old"), BibleBook("1Samuel", 31, "Old"), BibleBook("2Samuel", 24, "Old"), BibleBook("1Kings", 22, "Old"), BibleBook("2Kings", 25, "Old"), BibleBook("1Chronicles", 29, "Old"), BibleBook("2Chronicles", 36, "Old"), BibleBook("Ezra", 10, "Old"), BibleBook("Nehemiah", 13, "Old"), BibleBook("Tobit", 14, "Old"), BibleBook("Judith", 16, "Old"), BibleBook("Esther", 10, "Old"), BibleBook("1Meqabyan", 36, "Old"), BibleBook("2Meqabyan", 21, "Old"), BibleBook("3Meqabyan", 15, "Old"), BibleBook("Job", 42, "Old"), BibleBook("Psalms", 150, "Old"), BibleBook("Proverbs", 31, "Old"), BibleBook("Tegsas", 31, "Old"), BibleBook("Wisdom", 19, "Old"), BibleBook("Ecclesiastes", 12, "Old"), BibleBook("SongofSolomon", 8, "Old"), BibleBook("Sirach", 51, "Old"), BibleBook("Isaiah", 66, "Old"), BibleBook("Jeremiah", 52, "Old"), BibleBook("Lamentations", 5, "Old"), BibleBook("Ezekiel", 48, "Old"), BibleBook("Daniel", 12, "Old"), BibleBook("Hosea", 14, "Old"), BibleBook("Amos", 9, "Old"), BibleBook("Micah", 7, "Old"), BibleBook("Joel", 3, "Old"), BibleBook("Obadiah", 1, "Old"), BibleBook("Jonah", 4, "Old"), BibleBook("Nahum", 3, "Old"), BibleBook("Habakkuk", 3, "Old"), BibleBook("Zephaniah", 3, "Old"), BibleBook("Haggai", 2, "Old"), BibleBook("Zechariah", 14, "Old"), BibleBook("Malachi", 4, "Old"), BibleBook("Enoch", 108, "Old"), BibleBook("Jubilees", 50, "Old"),
    BibleBook("Matthew", 28, "New"), BibleBook("Mark", 16, "New"), BibleBook("Luke", 24, "New"), BibleBook("John", 21, "New"), BibleBook("Acts", 28, "New"), BibleBook("Romans", 16, "New"), BibleBook("1Corinthians", 16, "New"), BibleBook("2Corinthians", 13, "New"), BibleBook("Galatians", 6, "New"), BibleBook("Ephesians", 6, "New"), BibleBook("Philippians", 4, "New"), BibleBook("Colossians", 4, "New"), BibleBook("1Thessalonians", 5, "New"), BibleBook("2Thessalonians", 3, "New"), BibleBook("1Timothy", 6, "New"), BibleBook("2Timothy", 4, "New"), BibleBook("Titus", 3, "New"), BibleBook("Philemon", 1, "New"), BibleBook("Hebrews", 13, "New"), BibleBook("1Peter", 5, "New"), BibleBook("2Peter", 3, "New"), BibleBook("1John", 5, "New"), BibleBook("2John", 1, "New"), BibleBook("3John", 1, "New"), BibleBook("James", 5, "New"), BibleBook("Jude", 1, "New"), BibleBook("Revelation", 22, "New"),
    BibleBook("SirateTsion", 1, "Eth"), BibleBook("Tizaz", 1, "Eth"), BibleBook("Gitsiw", 1, "Eth"), BibleBook("Abtilis", 1, "Eth"), BibleBook("1Dominos", 1, "Eth"), BibleBook("2Dominos", 1, "Eth"), BibleBook("Qalementos", 1, "Eth"), BibleBook("Didasqalia", 1, "Eth")
)

/**
 * Strong's-number language prefix for a given canonical book name, derived
 * solely from [BOOKS] so it can never drift from the app's testament data
 * (the way tools/interlinear_scraper.py's old hardcoded `ot_books` list once
 * drifted from src/bible_db.zig's `BIBLE_BOOKS`).
 *
 * Old Testament books use Hebrew ("H"). Everything else — New Testament
 * *and* Ethiopian-canon-only books ("Eth", e.g. SirateTsion, Qalementos) —
 * uses Greek ("G"), mirroring tools/interlinear_scraper.py's
 * `language_prefix()` (`"H" if testament == "Old" else "G"`).
 *
 * Unrecognized book names also fall back to "G" (never silently mis-tag as
 * Hebrew), matching the Python scraper's fallback behavior.
 */
fun strongsLanguagePrefix(bookName: String): String =
    if (BOOKS.find { it.name == bookName }?.testament == "Old") "H" else "G"

val BIBLE_ABBREVIATIONS = mapOf(
    "gen" to "Genesis", "ex" to "Exodus", "lev" to "Leviticus", "num" to "Numbers", "deut" to "Deuteronomy",
    "josh" to "Joshua", "judg" to "Judges", "ruth" to "Ruth", "1sam" to "1Samuel", "2sam" to "2Samuel",
    "1ki" to "1Kings", "2ki" to "2Kings", "1chr" to "1Chronicles", "2chr" to "2Chronicles", "ezr" to "Ezra",
    "neh" to "Nehemiah", "ps" to "Psalms", "prov" to "Proverbs", "eccl" to "Ecclesiastes", "song" to "SongofSolomon",
    "isa" to "Isaiah", "jer" to "Jeremiah", "lam" to "Lamentations", "eze" to "Ezekiel", "dan" to "Daniel",
    "hos" to "Hosea", "joe" to "Joel", "am" to "Amos", "oba" to "Obadiah", "jon" to "Jonah", "mic" to "Micah",
    "nah" to "Nahum", "hab" to "Habakkuk", "zep" to "Zephaniah", "hag" to "Haggai", "zec" to "Zechariah", "mal" to "Malachi",
    "matt" to "Matthew", "mk" to "Mark", "lk" to "Luke", "jn" to "John", "act" to "Acts", "rom" to "Romans",
    "1cor" to "1Corinthians", "2cor" to "2Corinthians", "gal" to "Galatians", "eph" to "Ephesians", "phi" to "Philippians",
    "col" to "Colossians", "1the" to "1Thessalonians", "2the" to "2Thessalonians", "1tim" to "1Timothy", "2tim" to "2Timothy",
    "tit" to "Titus", "phm" to "Philemon", "heb" to "Hebrews", "jam" to "James", "1pet" to "1Peter", "2pet" to "2Peter",
    "1jn" to "1John", "2jn" to "2John", "3jn" to "3John", "jud" to "Jude", "rev" to "Revelation"
)
