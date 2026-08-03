package com.bytecats.metanoia.models

/**
 * Biblical canon membership for a book.
 *
 * A book can belong to multiple canons simultaneously. For example:
 * - Psalms is in ALL canons
 * - Tobit is in Catholic and Orthodox, but NOT Protestant
 * - 3 Meqabyan is ONLY in Ethiopian canon
 */
enum class Canon {
    Protestant,
    Catholic,
    Orthodox,
    Ethiopian
}

/**
 * Textual tradition for Old Testament books.
 *
 * Distinguishes between the Masoretic Hebrew tradition (used by Judaism
 * and Protestantism) and the Greek Septuagint tradition (used by Catholic
 * and Orthodox churches, which includes the deuterocanonical books).
 */
enum class TextTradition {
    Masoretic,    // Hebrew/Aramaic, 39 books
    Septuagint,   // Greek, includes deuterocanonical books
    NewTestament, // Greek, 27 books
    Ethiopic      // Ge'ez, Ethiopian-canon-only books
}

/**
 * Sectional grouping of books within a testament.
 *
 * This provides logical grouping that transcends individual canons,
 * making it easier to navigate the Bible while still respecting
 * tradition-specific boundaries.
 */
enum class BookSection {
    // Old Testament
    Pentateuch,           // Law: Genesis–Deuteronomy
    Historical,           // Joshua–Esther
    Wisdom,               // Job, Psalms, Proverbs, Ecclesiastes, Song of Solomon
    MajorProphets,        // Isaiah, Jeremiah, Ezekiel, Daniel
    MinorProphets,        // Hosea–Malachi
    Deuterocanonical,     // Tobit, Judith, Wisdom, Sirach, Baruch, 1-2 Maccabees
    EthiopianCanon,       // Enoch, Jubilees, 1-3 Meqabyan, Tegsas, Ethiopian church books

    // New Testament
    Gospels,              // Matthew, Mark, Luke, John
    Acts,                 // Acts of the Apostles
    PaulineEpistles,      // Romans–Philemon
    GeneralEpistles,      // Hebrews–Jude
    Apocalyptic           // Revelation
}

/**
 * Extended Bible book model with canon and section metadata.
 *
 * This replaces the old simple `testament` string with a richer model
 * that supports:
 * - Multiple canons per book
 * - Textual tradition tracking (Masoretic vs Septuagint)
 * - Logical sectional grouping
 * - Clear canonical status display
 */
data class BibleBook(
    val name: String,
    val chapters: Int,
    val testament: String,
    val isApocrypha: Boolean = false,  // Deprecated: use canons instead
    val canons: Set<Canon> = setOf(Canon.Protestant),
    val textTradition: TextTradition = TextTradition.Masoretic,
    val section: BookSection = BookSection.Historical
) {
    /**
     * Returns true if this book is part of the Septuagint tradition.
     * This includes both Masoretic books (LXX translation) AND
     * deuterocanonical books (unique to LXX).
     */
    val isSeptuagint: Boolean
        get() = textTradition == TextTradition.Septuagint ||
                testament == "New" ||
                testament == "Eth"

    /**
     * Returns true if this book is deuterocanonical (not in Protestant canon).
     * Books that are in Catholic/Orthodox but NOT Protestant.
     */
    val isDeuterocanonical: Boolean
        get() = canons.contains(Canon.Catholic) &&
                !canons.contains(Canon.Protestant)

    /**
     * Returns true if this book is unique to Ethiopian canon.
     * Books that are in Ethiopian but NOT in Catholic/Orthodox.
     */
    val isEthiopianExclusive: Boolean
        get() = canons.contains(Canon.Ethiopian) &&
                !canons.contains(Canon.Catholic) &&
                !canons.contains(Canon.Protestant)

    /**
     * User-friendly description of canonical status.
     * Examples: "Protestant", "Catholic & Orthodox", "Ethiopian Only"
     */
    fun canonicalStatus(): String {
        return when {
            canons.size == 1 && canons.contains(Canon.Protestant) -> "Protestant"
            canons.size == 4 -> "Universal"  // All canons
            canons.contains(Canon.Ethiopian) && !canons.contains(Canon.Catholic) -> "Ethiopian Only"
            canons.contains(Canon.Catholic) && canons.contains(Canon.Orthodox) && !canons.contains(Canon.Protestant) -> "Catholic & Orthodox"
            canons.contains(Canon.Orthodox) && !canons.contains(Canon.Protestant) -> "Orthodox"
            else -> canons.joinToString(" & ") { it.name }
        }
    }

    /**
     * Returns the standard canonical order for this book.
     * Used for sorting books in a canon-aware way.
     *
     * Protestant order differs from Catholic/Orthodox order for
     * deuterocanonical books (which are interleaved in Catholic/Orthodox
     * but grouped separately in Protestant Bible apps).
     *
     * Uses explicit ordering maps for deterministic sorting instead of hash codes.
     */
    fun canonicalOrder(): Int {
        // Base order by section
        val sectionOrder = section.ordinal * 1000

        // Order within each section (explicit canonical order)
        val orderWithinSection = BOOK_ORDER_WITHIN_SECTION[section]?.indexOf(name) ?: name.hashCode().mod(1000)

        return sectionOrder + orderWithinSection
    }

    companion object {
        /**
         * Explicit canonical ordering within each section.
         * This ensures deterministic sorting regardless of hash codes.
         */
        private val BOOK_ORDER_WITHIN_SECTION = mapOf(
            BookSection.Pentateuch to listOf(
                "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy"
            ),
            BookSection.Historical to listOf(
                "Joshua", "Judges", "Ruth", "1Samuel", "2Samuel", "1Kings", "2Kings",
                "1Chronicles", "2Chronicles", "Ezra", "Nehemiah", "Esther"
            ),
            BookSection.Deuterocanonical to listOf(
                "Tobit", "Judith"
            ),
            BookSection.Wisdom to listOf(
                "Job", "Psalms", "Proverbs", "Ecclesiastes", "SongofSolomon", "Wisdom", "Sirach"
            ),
            BookSection.MajorProphets to listOf(
                "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel"
            ),
            BookSection.MinorProphets to listOf(
                "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk",
                "Zephaniah", "Haggai", "Zechariah", "Malachi"
            ),
            BookSection.EthiopianCanon to listOf(
                "Enoch", "Jubilees", "1Meqabyan", "2Meqabyan", "3Meqabyan", "Tegsas",
                "SirateTsion", "Tizaz", "Gitsiw", "Abtilis", "1Dominos", "2Dominos", "Qalementos", "Didasqalia"
            ),
            BookSection.Gospels to listOf(
                "Matthew", "Mark", "Luke", "John"
            ),
            BookSection.Acts to listOf("Acts"),
            BookSection.PaulineEpistles to listOf(
                "Romans", "1Corinthians", "2Corinthians", "Galatians", "Ephesians", "Philippians",
                "Colossians", "1Thessalonians", "2Thessalonians", "1Timothy", "2Timothy", "Titus", "Philemon"
            ),
            BookSection.GeneralEpistles to listOf(
                "Hebrews", "James", "1Peter", "2Peter", "1John", "2John", "3John", "Jude"
            ),
            BookSection.Apocalyptic to listOf("Revelation")
        )
    }
}

/**
 * Filter books by canon membership.
 *
 * Usage:
 * - BOOKS.filterByCanon(Canon.Protestant)  // 66 books
 * - BOOKS.filterByCanon(Canon.Catholic)    // 73 books
 * - BOOKS.filterByCanon(Canon.Ethiopian)   // 81 books
 */
fun List<BibleBook>.filterByCanon(vararg canons: Canon): List<BibleBook> {
    if (canons.isEmpty()) return this
    return filter { book -> canons.any { it in book.canons } }
}

/**
 * Filter books by textual tradition.
 *
 * Usage:
 * - BOOKS.filterByTradition(TextTradition.Masoretic)   // Hebrew OT
 * - BOOKS.filterByTradition(TextTradition.Septuagint)  // Greek OT + Deuterocanonical
 */
fun List<BibleBook>.filterByTradition(tradition: TextTradition): List<BibleBook> {
    return filter { it.textTradition == tradition }
}

/**
 * Filter books by sectional grouping.
 *
 * Usage:
 * - BOOKS.filterBySection(BookSection.Wisdom)  // All wisdom books across all canons
 */
fun List<BibleBook>.filterBySection(section: BookSection): List<BibleBook> {
    return filter { it.section == section }
}

/**
 * Group books by section, preserving canonical order within each section.
 */
fun List<BibleBook>.groupBySection(): Map<BookSection, List<BibleBook>> {
    return groupBy { it.section }.mapValues { (_, books) ->
        books.sortedBy { it.canonicalOrder() }
    }
}

/**
 * Returns books in canonical order for the specified canon.
 *
 * This respects the canonical ordering differences between traditions:
 * - Protestant: deuterocanonical books grouped at end (or omitted)
 * - Catholic: deuterocanonical books interleaved in OT
 * - Orthodox: follows Septuagint order
 */
fun List<BibleBook>.inCanonicalOrderFor(canons: Set<Canon>): List<BibleBook> {
    val included = this.filter { book -> canons.any { it in book.canons } }
    return included.sortedBy { it.canonicalOrder() }
}

/**
 * Canon presets for quick filtering.
 *
 * These represent the major canonical traditions used in Metanoia.
 */
object CanonPresets {
    /** Protestant canon: 66 books (39 OT + 27 NT) */
    val PROTESTANT = setOf(Canon.Protestant)

    /** Catholic canon: 73 books (46 OT + 27 NT) */
    val CATHOLIC = setOf(Canon.Protestant, Canon.Catholic)

    /** Eastern Orthodox canon: varies by tradition, typically 76-79 books */
    val ORTHODOX = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox)

    /** Ethiopian Orthodox Tewahedo canon: 81 books */
    val ETHIOPIAN = setOf(Canon.Protestant, Canon.Catholic, Canon.Orthodox, Canon.Ethiopian)

    /**
     * Get the most appropriate canon preset for a user's preference.
     *
     * @param showApocrypha   Include Catholic/Orthodox deuterocanonical books
     * @param showEthiopian   Include Ethiopian-canon-only books
     */
    fun fromUserPreferences(showApocrypha: Boolean, showEthiopian: Boolean): Set<Canon> {
        return when {
            showEthiopian -> ETHIOPIAN
            showApocrypha -> ORTHODOX
            else -> PROTESTANT
        }
    }
}