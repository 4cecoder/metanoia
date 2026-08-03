package com.bytecats.metanoia.models

val BOOKS = listOf(
    // ===== PENTATEUCH (Law) - Masoretic, Universal =====
    BibleBook("Genesis", 50, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Pentateuch
    ),
    BibleBook("Exodus", 40, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Pentateuch
    ),
    BibleBook("Leviticus", 27, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Pentateuch
    ),
    BibleBook("Numbers", 36, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Pentateuch
    ),
    BibleBook("Deuteronomy", 34, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Pentateuch
    ),

    // ===== HISTORICAL BOOKS - Masoretic/Septuagint, Universal =====
    BibleBook("Joshua", 24, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Historical
    ),
    BibleBook("Judges", 21, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Historical
    ),
    BibleBook("Ruth", 4, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Historical
    ),
    BibleBook("1Samuel", 31, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Historical
    ),
    BibleBook("2Samuel", 24, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Historical
    ),
    BibleBook("1Kings", 22, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Historical
    ),
    BibleBook("2Kings", 25, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Historical
    ),
    BibleBook("1Chronicles", 29, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Historical
    ),
    BibleBook("2Chronicles", 36, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Historical
    ),
    BibleBook("Ezra", 10, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Historical
    ),
    BibleBook("Nehemiah", 13, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Historical
    ),
    BibleBook("Esther", 10, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Historical
    ),

    // ===== DEUTEROCANONAL BOOKS - Septuagint, Catholic & Orthodox only =====
    BibleBook("Tobit", 14, "Old",
        canons = setOf(Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Septuagint,
        section = BookSection.Deuterocanonical,
        isApocrypha = true
    ),
    BibleBook("Judith", 16, "Old",
        canons = setOf(Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Septuagint,
        section = BookSection.Deuterocanonical,
        isApocrypha = true
    ),

    // ===== WISDOM LITERATURE - Masoretic, Universal =====
    BibleBook("Job", 42, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Wisdom
    ),
    BibleBook("Psalms", 150, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Wisdom
    ),
    BibleBook("Proverbs", 31, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Wisdom
    ),
    BibleBook("Ecclesiastes", 12, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Wisdom
    ),
    BibleBook("SongofSolomon", 8, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.Wisdom
    ),
    // Deuterocanonical wisdom books - classified as Wisdom content-wise
    BibleBook("Wisdom", 19, "Old",
        canons = setOf(Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Septuagint,
        section = BookSection.Wisdom,
        isApocrypha = true
    ),
    BibleBook("Sirach", 51, "Old",
        canons = setOf(Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Septuagint,
        section = BookSection.Wisdom,
        isApocrypha = true
    ),

    // ===== MAJOR PROPHETS - Masoretic, Universal =====
    BibleBook("Isaiah", 66, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MajorProphets
    ),
    BibleBook("Jeremiah", 52, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MajorProphets
    ),
    BibleBook("Lamentations", 5, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MajorProphets
    ),
    BibleBook("Ezekiel", 48, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MajorProphets
    ),
    BibleBook("Daniel", 12, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MajorProphets
    ),

    // ===== MINOR PROPHETS - Masoretic, Universal =====
    BibleBook("Hosea", 14, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MinorProphets
    ),
    BibleBook("Joel", 3, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MinorProphets
    ),
    BibleBook("Amos", 9, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MinorProphets
    ),
    BibleBook("Obadiah", 1, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MinorProphets
    ),
    BibleBook("Jonah", 4, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MinorProphets
    ),
    BibleBook("Micah", 7, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MinorProphets
    ),
    BibleBook("Nahum", 3, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MinorProphets
    ),
    BibleBook("Habakkuk", 3, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MinorProphets
    ),
    BibleBook("Zephaniah", 3, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MinorProphets
    ),
    BibleBook("Haggai", 2, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MinorProphets
    ),
    BibleBook("Zechariah", 14, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MinorProphets
    ),
    BibleBook("Malachi", 4, "Old",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.Masoretic,
        section = BookSection.MinorProphets
    ),

    // ===== ETHIOPIAN-CANON ONLY BOOKS - Ethiopic tradition =====
    BibleBook("Enoch", 108, "Old",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("Jubilees", 50, "Old",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("1Meqabyan", 36, "Old",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("2Meqabyan", 21, "Old",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("3Meqabyan", 15, "Old",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("Tegsas", 31, "Old",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("SirateTsion", 1, "Eth",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("Tizaz", 1, "Eth",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("Gitsiw", 1, "Eth",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("Abtilis", 1, "Eth",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("1Dominos", 1, "Eth",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("2Dominos", 1, "Eth",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("Qalementos", 1, "Eth",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),
    BibleBook("Didasqalia", 1, "Eth",
        canons = setOf(Canon.Ethiopian),
        textTradition = TextTradition.Ethiopic,
        section = BookSection.EthiopianCanon
    ),

    // ===== NEW TESTAMENT - Gospels - Universal =====
    BibleBook("Matthew", 28, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.Gospels
    ),
    BibleBook("Mark", 16, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.Gospels
    ),
    BibleBook("Luke", 24, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.Gospels
    ),
    BibleBook("John", 21, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.Gospels
    ),

    // ===== NEW TESTAMENT - Acts - Universal =====
    BibleBook("Acts", 28, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.Acts
    ),

    // ===== NEW TESTAMENT - Pauline Epistles - Universal =====
    BibleBook("Romans", 16, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("1Corinthians", 16, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("2Corinthians", 13, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("Galatians", 6, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("Ephesians", 6, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("Philippians", 4, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("Colossians", 4, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("1Thessalonians", 5, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("2Thessalonians", 3, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("1Timothy", 6, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("2Timothy", 4, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("Titus", 3, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("Philemon", 1, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.PaulineEpistles
    ),
    BibleBook("Hebrews", 13, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.GeneralEpistles
    ),
    BibleBook("James", 5, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.GeneralEpistles
    ),
    BibleBook("1Peter", 5, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.GeneralEpistles
    ),
    BibleBook("2Peter", 3, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.GeneralEpistles
    ),
    BibleBook("1John", 5, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.GeneralEpistles
    ),
    BibleBook("2John", 1, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.GeneralEpistles
    ),
    BibleBook("3John", 1, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.GeneralEpistles
    ),
    BibleBook("Jude", 1, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.GeneralEpistles
    ),

    // ===== NEW TESTAMENT - Apocalyptic - Universal =====
    BibleBook("Revelation", 22, "New",
        canons = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian),
        textTradition = TextTradition.NewTestament,
        section = BookSection.Apocalyptic
    )
)

/**
 * Strong's-number language prefix for a given canonical book name, derived
 * solely from [BOOKS] so it can never drift from the app's testament data
 * (the way tools/interlinear_scraper.py's old hardcoded `ot_books` list once
 * drifted from src/bible_db.zig's `BIBLE_BOOKS`).
 *
 * Masoretic (Hebrew) books use "H". Everything else — Septuagint (Greek),
 * New Testament (Greek), and Ethiopian-canon-only books (Ge'ez) — uses "G".
 * This correctly handles deuterocanonical books like Wisdom which are in the
 * Old Testament but are part of the Greek Septuagint tradition.
 *
 * Unrecognized book names also fall back to "G" (never silently mis-tag as
 * Hebrew), matching the Python scraper's fallback behavior.
 */
fun strongsLanguagePrefix(bookName: String): String =
    if (BOOKS.find { it.name == bookName }?.textTradition == TextTradition.Masoretic) "H" else "G"

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