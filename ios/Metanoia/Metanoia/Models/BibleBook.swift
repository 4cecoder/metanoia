import Foundation

enum Canon: String, CaseIterable, Codable {
    case protestant = "Protestant"
    case catholic = "Catholic"
    case orthodox = "Orthodox"
    case ethiopian = "Ethiopian"
}

enum TextTradition: String, Codable {
    case masoretic
    case septuagint
    case newTestament
    case ethiopic
}

enum BookSection: String, CaseIterable, Codable {
    case pentateuch
    case historical
    case wisdom
    case majorProphets
    case minorProphets
    case deuterocanonical
    case ethiopianCanon
    case gospels
    case acts
    case paulineEpistles
    case generalEpistles
    case apocalyptic

    var displayName: String {
        switch self {
        case .pentateuch: return "Pentateuch"
        case .historical: return "Historical"
        case .wisdom: return "Wisdom"
        case .majorProphets: return "Major Prophets"
        case .minorProphets: return "Minor Prophets"
        case .deuterocanonical: return "Deuterocanonical"
        case .ethiopianCanon: return "Ethiopian Canon"
        case .gospels: return "Gospels"
        case .acts: return "Acts"
        case .paulineEpistles: return "Pauline Epistles"
        case .generalEpistles: return "General Epistles"
        case .apocalyptic: return "Apocalyptic"
        }
    }

    var ordinal: Int {
        switch self {
        case .pentateuch: return 0
        case .historical: return 1
        case .deuterocanonical: return 2
        case .wisdom: return 3
        case .majorProphets: return 4
        case .minorProphets: return 5
        case .ethiopianCanon: return 6
        case .gospels: return 7
        case .acts: return 8
        case .paulineEpistles: return 9
        case .generalEpistles: return 10
        case .apocalyptic: return 11
        }
    }
}

struct BibleBook: Identifiable, Hashable {
    let name: String
    let chapters: Int
    let testament: String
    let isApocrypha: Bool
    let canons: Set<Canon>
    let textTradition: TextTradition
    let section: BookSection

    var id: String { name }

    var chapterCount: Int { chapters }

    var isSeptuagint: Bool {
        textTradition == .septuagint || testament == "New" || testament == "Eth"
    }

    var isDeuterocanonical: Bool {
        canons.contains(.catholic) && !canons.contains(.protestant)
    }

    var isEthiopianExclusive: Bool {
        canons.contains(.ethiopian) && !canons.contains(.catholic) && !canons.contains(.protestant)
    }

    func canonicalStatus() -> String {
        if canons.count == 1 && canons.contains(.protestant) { return "Protestant" }
        if canons.count == 4 { return "Universal" }
        if canons.contains(.ethiopian) && !canons.contains(.catholic) { return "Ethiopian Only" }
        if canons.contains(.catholic) && canons.contains(.orthodox) && !canons.contains(.protestant) {
            return "Catholic & Orthodox"
        }
        if canons.contains(.orthodox) && !canons.contains(.protestant) { return "Orthodox" }
        return canons.map(\.rawValue).joined(separator: " & ")
    }

    func canonicalOrder() -> Int {
        let sectionOrder = section.ordinal * 1000
        let orderWithin = Self.bookOrderWithinSection[section]?.firstIndex(of: name) ?? 0
        return sectionOrder + orderWithin
    }

    init(
        name: String,
        chapters: Int,
        testament: String,
        isApocrypha: Bool = false,
        canons: Set<Canon> = [.protestant],
        textTradition: TextTradition = .masoretic,
        section: BookSection = .historical
    ) {
        self.name = name
        self.chapters = chapters
        self.testament = testament
        self.isApocrypha = isApocrypha
        self.canons = canons
        self.textTradition = textTradition
        self.section = section
    }

    private static let bookOrderWithinSection: [BookSection: [String]] = [
        .pentateuch: ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy"],
        .historical: [
            "Joshua", "Judges", "Ruth", "1Samuel", "2Samuel", "1Kings", "2Kings",
            "1Chronicles", "2Chronicles", "Ezra", "Nehemiah", "Esther"
        ],
        .deuterocanonical: ["Tobit", "Judith"],
        .wisdom: ["Job", "Psalms", "Proverbs", "Ecclesiastes", "SongofSolomon", "Wisdom", "Sirach"],
        .majorProphets: ["Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel"],
        .minorProphets: [
            "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk",
            "Zephaniah", "Haggai", "Zechariah", "Malachi"
        ],
        .ethiopianCanon: [
            "Enoch", "Jubilees", "1Meqabyan", "2Meqabyan", "3Meqabyan", "Tegsas",
            "SirateTsion", "Tizaz", "Gitsiw", "Abtilis", "1Dominos", "2Dominos",
            "Qalementos", "Didasqalia"
        ],
        .gospels: ["Matthew", "Mark", "Luke", "John"],
        .acts: ["Acts"],
        .paulineEpistles: [
            "Romans", "1Corinthians", "2Corinthians", "Galatians", "Ephesians", "Philippians",
            "Colossians", "1Thessalonians", "2Thessalonians", "1Timothy", "2Timothy", "Titus", "Philemon"
        ],
        .generalEpistles: ["Hebrews", "James", "1Peter", "2Peter", "1John", "2John", "3John", "Jude"],
        .apocalyptic: ["Revelation"]
    ]

    static func book(byId id: String) -> BibleBook? {
        BOOKS.first { $0.name == id }
    }

    static func book(byName name: String) -> BibleBook? {
        BOOKS.first { $0.name.lowercased() == name.lowercased() }
    }

    static func books(for section: BookSection) -> [BibleBook] {
        BOOKS.filter { $0.section == section }
    }

    static var allBooks: [BibleBook] { BOOKS }
}

extension BibleBook {
    static let allCanons: Set<Canon> = [.protestant, .catholic, .orthodox, .ethiopian]

    static func books(for canons: Set<Canon>) -> [BibleBook] {
        BOOKS.filter { book in canons.contains(where: { book.canons.contains($0) }) }
    }
}

extension Array where Element == BibleBook {
    func filterByCanon(_ canons: Canon...) -> [BibleBook] {
        guard !canons.isEmpty else { return self }
        return filter { book in canons.contains(where: { $0 ∈ book.canons }) }
    }

    func filterByTradition(_ tradition: TextTradition) -> [BibleBook] {
        filter { $0.textTradition == tradition }
    }

    func filterBySection(_ section: BookSection) -> [BibleBook] {
        filter { $0.section == section }
    }

    func groupBySection() -> [(BookSection, [BibleBook])] {
        var result: [(BookSection, [BibleBook])] = []
        for section in BookSection.allCases {
            let books = self.filter { $0.section == section }.sorted { $0.canonicalOrder() < $1.canonicalOrder() }
            if !books.isEmpty {
                result.append((section, books))
            }
        }
        return result
    }

    func inCanonicalOrder(for canons: Set<Canon>) -> [BibleBook] {
        filter { book in canons.contains(where: { book.canons.contains($0) }) }
            .sorted { $0.canonicalOrder() < $1.canonicalOrder() }
    }
}

enum CanonPresets {
    static let protestant: Set<Canon> = [.protestant]
    static let catholic: Set<Canon> = [.protestant, .catholic]
    static let orthodox: Set<Canon> = [.protestant, .catholic, .orthodox]
    static let ethiopian: Set<Canon> = [.protestant, .catholic, .orthodox, .ethiopian]

    static func fromUserPreferences(showApocrypha: Bool, showEthiopian: Bool) -> Set<Canon> {
        if showEthiopian { return ethiopian }
        if showApocrypha { return orthodox }
        return protestant
    }
}

func strongsLanguagePrefix(forBookName bookName: String) -> String {
    if BOOKS.first(where: { $0.name == bookName })?.textTradition == .masoretic { return "H" }
    return "G"
}

// MARK: - All 81 Books

let BOOKS: [BibleBook] = [
    // Pentateuch - Masoretic, Universal
    BibleBook(name: "Genesis", chapters: 50, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .pentateuch),
    BibleBook(name: "Exodus", chapters: 40, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .pentateuch),
    BibleBook(name: "Leviticus", chapters: 27, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .pentateuch),
    BibleBook(name: "Numbers", chapters: 36, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .pentateuch),
    BibleBook(name: "Deuteronomy", chapters: 34, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .pentateuch),

    // Historical - Masoretic/Septuagint, Universal
    BibleBook(name: "Joshua", chapters: 24, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .historical),
    BibleBook(name: "Judges", chapters: 21, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .historical),
    BibleBook(name: "Ruth", chapters: 4, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .historical),
    BibleBook(name: "1Samuel", chapters: 31, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .historical),
    BibleBook(name: "2Samuel", chapters: 24, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .historical),
    BibleBook(name: "1Kings", chapters: 22, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .historical),
    BibleBook(name: "2Kings", chapters: 25, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .historical),
    BibleBook(name: "1Chronicles", chapters: 29, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .historical),
    BibleBook(name: "2Chronicles", chapters: 36, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .historical),
    BibleBook(name: "Ezra", chapters: 10, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .historical),
    BibleBook(name: "Nehemiah", chapters: 13, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .historical),
    BibleBook(name: "Esther", chapters: 10, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .historical),

    // Deuterocanonical - Septuagint, Catholic & Orthodox only
    BibleBook(name: "Tobit", chapters: 14, testament: "Old",
              isApocrypha: true, canons: [.catholic, .orthodox, .ethiopian],
              textTradition: .septuagint, section: .deuterocanonical),
    BibleBook(name: "Judith", chapters: 16, testament: "Old",
              isApocrypha: true, canons: [.catholic, .orthodox, .ethiopian],
              textTradition: .septuagint, section: .deuterocanonical),

    // Wisdom - Masoretic, Universal
    BibleBook(name: "Job", chapters: 42, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .wisdom),
    BibleBook(name: "Psalms", chapters: 150, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .wisdom),
    BibleBook(name: "Proverbs", chapters: 31, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .wisdom),
    BibleBook(name: "Ecclesiastes", chapters: 12, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .wisdom),
    BibleBook(name: "SongofSolomon", chapters: 8, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .wisdom),

    // Deuterocanonical wisdom
    BibleBook(name: "Wisdom", chapters: 19, testament: "Old",
              isApocrypha: true, canons: [.catholic, .orthodox, .ethiopian],
              textTradition: .septuagint, section: .wisdom),
    BibleBook(name: "Sirach", chapters: 51, testament: "Old",
              isApocrypha: true, canons: [.catholic, .orthodox, .ethiopian],
              textTradition: .septuagint, section: .wisdom),

    // Major Prophets - Masoretic, Universal
    BibleBook(name: "Isaiah", chapters: 66, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .majorProphets),
    BibleBook(name: "Jeremiah", chapters: 52, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .majorProphets),
    BibleBook(name: "Lamentations", chapters: 5, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .majorProphets),
    BibleBook(name: "Ezekiel", chapters: 48, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .majorProphets),
    BibleBook(name: "Daniel", chapters: 12, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .majorProphets),

    // Minor Prophets - Masoretic, Universal
    BibleBook(name: "Hosea", chapters: 14, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .minorProphets),
    BibleBook(name: "Joel", chapters: 3, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .minorProphets),
    BibleBook(name: "Amos", chapters: 9, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .minorProphets),
    BibleBook(name: "Obadiah", chapters: 1, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .minorProphets),
    BibleBook(name: "Jonah", chapters: 4, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .minorProphets),
    BibleBook(name: "Micah", chapters: 7, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .minorProphets),
    BibleBook(name: "Nahum", chapters: 3, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .minorProphets),
    BibleBook(name: "Habakkuk", chapters: 3, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .minorProphets),
    BibleBook(name: "Zephaniah", chapters: 3, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .minorProphets),
    BibleBook(name: "Haggai", chapters: 2, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .minorProphets),
    BibleBook(name: "Zechariah", chapters: 14, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .minorProphets),
    BibleBook(name: "Malachi", chapters: 4, testament: "Old",
              canons: BibleBook.allCanons, textTradition: .masoretic, section: .minorProphets),

    // Ethiopian Canon Only - Ethiopic tradition
    BibleBook(name: "Enoch", chapters: 108, testament: "Old",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "Jubilees", chapters: 50, testament: "Old",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "1Meqabyan", chapters: 36, testament: "Old",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "2Meqabyan", chapters: 21, testament: "Old",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "3Meqabyan", chapters: 15, testament: "Old",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "Tegsas", chapters: 31, testament: "Old",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "SirateTsion", chapters: 1, testament: "Eth",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "Tizaz", chapters: 1, testament: "Eth",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "Gitsiw", chapters: 1, testament: "Eth",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "Abtilis", chapters: 1, testament: "Eth",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "1Dominos", chapters: 1, testament: "Eth",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "2Dominos", chapters: 1, testament: "Eth",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "Qalementos", chapters: 1, testament: "Eth",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),
    BibleBook(name: "Didasqalia", chapters: 1, testament: "Eth",
              canons: [.ethiopian], textTradition: .ethiopic, section: .ethiopianCanon),

    // New Testament - Gospels - Universal
    BibleBook(name: "Matthew", chapters: 28, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .gospels),
    BibleBook(name: "Mark", chapters: 16, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .gospels),
    BibleBook(name: "Luke", chapters: 24, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .gospels),
    BibleBook(name: "John", chapters: 21, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .gospels),

    // New Testament - Acts - Universal
    BibleBook(name: "Acts", chapters: 28, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .acts),

    // New Testament - Pauline Epistles - Universal
    BibleBook(name: "Romans", chapters: 16, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),
    BibleBook(name: "1Corinthians", chapters: 16, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),
    BibleBook(name: "2Corinthians", chapters: 13, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),
    BibleBook(name: "Galatians", chapters: 6, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),
    BibleBook(name: "Ephesians", chapters: 6, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),
    BibleBook(name: "Philippians", chapters: 4, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),
    BibleBook(name: "Colossians", chapters: 4, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),
    BibleBook(name: "1Thessalonians", chapters: 5, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),
    BibleBook(name: "2Thessalonians", chapters: 3, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),
    BibleBook(name: "1Timothy", chapters: 6, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),
    BibleBook(name: "2Timothy", chapters: 4, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),
    BibleBook(name: "Titus", chapters: 3, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),
    BibleBook(name: "Philemon", chapters: 1, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .paulineEpistles),

    // New Testament - General Epistles - Universal
    BibleBook(name: "Hebrews", chapters: 13, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .generalEpistles),
    BibleBook(name: "James", chapters: 5, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .generalEpistles),
    BibleBook(name: "1Peter", chapters: 5, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .generalEpistles),
    BibleBook(name: "2Peter", chapters: 3, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .generalEpistles),
    BibleBook(name: "1John", chapters: 5, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .generalEpistles),
    BibleBook(name: "2John", chapters: 1, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .generalEpistles),
    BibleBook(name: "3John", chapters: 1, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .generalEpistles),
    BibleBook(name: "Jude", chapters: 1, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .generalEpistles),

    // New Testament - Apocalyptic - Universal
    BibleBook(name: "Revelation", chapters: 22, testament: "New",
              canons: BibleBook.allCanons, textTradition: .newTestament, section: .apocalyptic),
]

let BIBLE_ABBREVIATIONS: [String: String] = [
    "gen": "Genesis", "ex": "Exodus", "lev": "Leviticus", "num": "Numbers",
    "deut": "Deuteronomy", "josh": "Joshua", "judg": "Judges", "ruth": "Ruth",
    "1sam": "1Samuel", "2sam": "2Samuel", "1ki": "1Kings", "2ki": "2Kings",
    "1chr": "1Chronicles", "2chr": "2Chronicles", "ezr": "Ezra", "neh": "Nehemiah",
    "ps": "Psalms", "prov": "Proverbs", "eccl": "Ecclesiastes",
    "song": "SongofSolomon", "isa": "Isaiah", "jer": "Jeremiah",
    "lam": "Lamentations", "eze": "Ezekiel", "dan": "Daniel", "hos": "Hosea",
    "joe": "Joel", "am": "Amos", "oba": "Obadiah", "jon": "Jonah", "mic": "Micah",
    "nah": "Nahum", "hab": "Habakkuk", "zep": "Zephaniah", "hag": "Haggai",
    "zec": "Zechariah", "mal": "Malachi", "matt": "Matthew", "mk": "Mark",
    "lk": "Luke", "jn": "John", "act": "Acts", "rom": "Romans",
    "1cor": "1Corinthians", "2cor": "2Corinthians", "gal": "Galatians",
    "eph": "Ephesians", "phi": "Philippians", "col": "Colossians",
    "1the": "1Thessalonians", "2the": "2Thessalonians", "1tim": "1Timothy",
    "2tim": "2Timothy", "tit": "Titus", "phm": "Philemon", "heb": "Hebrews",
    "jam": "James", "1pet": "1Peter", "2pet": "2Peter", "1jn": "1John",
    "2jn": "2John", "3jn": "3John", "jud": "Jude", "rev": "Revelation"
]
