import Foundation

struct Verse: Identifiable, Codable, Hashable {
    let book: String
    let chapter: Int
    let number: Int
    let text: String
    var id: String { "\(book)-\(chapter)-\(number)" }
    var reference: String { "\(book) \(chapter):\(number)" }
}

struct InterlinearWord: Identifiable, Codable {
    let book: String
    let chapter: Int
    let verse: Int
    let wordIndex: Int
    let originalText: String
    let translation: String
    let strongs: String
    var id: String { "\(book)-\(chapter)-\(verse)-\(wordIndex)" }
}

struct Favorite: Identifiable, Codable {
    let strongs: String
    let lemma: String
    let definition: String
    var id: String { strongs }
}

struct Highlight: Identifiable, Codable {
    let book: String
    let chapter: Int
    let verse: Int
    let color: Int
    var id: String { "\(book)-\(chapter)-\(verse)" }
}

struct Note: Identifiable, Codable {
    let id: Int64
    let book: String
    let chapter: Int
    let verse: Int
    let content: String
    let timestamp: Date
}

struct SearchResult: Identifiable {
    let book: String
    let chapter: Int
    let verse: Int
    let text: String
    var id: String { "\(book)-\(chapter)-\(verse)" }
}

struct ReadingProgress: Codable {
    let book: String
    let chapter: Int
    let firstReadAt: Date?
    let lastReadAt: Date?
    let readCount: Int
    let readingTimeSeconds: Int
}

struct LibraryStats {
    let versesOt: Int
    let versesNt: Int
    let lexiconHeb: Int
    let lexiconGk: Int
    let notesCount: Int
    let highlightsCount: Int
    let interlinearCount: Int
    let dbSizeMb: Double
}

struct HotChapter: Identifiable {
    let book: String
    let chapter: Int
    let views: Int
    var id: String { "\(book)-\(chapter)" }
}
