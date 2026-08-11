import Foundation
import GRDB

struct InterlinearDAO {
    private let db: DatabaseWriter

    init(db: DatabaseWriter) {
        self.db = db
    }

    func getInterlinear(book: String, chapter: Int, verse: Int) throws -> [InterlinearWord] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT original_text, strongs, translation FROM interlinear WHERE book = ? AND chapter = ? AND verse = ? ORDER BY word_index ASC",
                arguments: [book, chapter, verse]
            )
            return rows.enumerated().map { idx, row in
                InterlinearWord(
                    book: book,
                    chapter: chapter,
                    verse: verse,
                    wordIndex: idx,
                    originalText: row["original_text"] ?? "",
                    translation: row["translation"] ?? "",
                    strongs: row["strongs"] ?? ""
                )
            }
        }
    }

    func insertInterlinearWords(book: String, chapter: Int, words: [(verse: Int, wordIndex: Int, original: String, translation: String, strongs: String)]) throws {
        try db.write { db in
            for w in words {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO interlinear (book, chapter, verse, word_index, original_text, translation, strongs) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    arguments: [book, chapter, w.verse, w.wordIndex, w.original, w.translation, w.strongs]
                )
            }
        }
    }
}
