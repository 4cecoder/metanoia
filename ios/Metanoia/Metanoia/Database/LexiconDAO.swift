import Foundation
import GRDB

struct LexiconDAO {
    private let db: DatabaseWriter

    init(db: DatabaseWriter) {
        self.db = db
    }

    func getLexiconDetail(strongs: String) throws -> LexiconEntry {
        try db.read { db in
            if let row = try Row.fetchOne(
                db,
                sql: "SELECT lemma, definition FROM lexicon WHERE strongs = ?",
                arguments: [strongs]
            ) {
                return LexiconEntry(
                    strongs: strongs,
                    language: "",
                    lemma: row["lemma"] ?? "",
                    transliteration: "",
                    definition: row["definition"] ?? ""
                )
            }

            // Try alternate Strong's number format
            let num = String(strongs.filter(\.isLetter.negated))
            let alt = strongs.allSatisfy(\.isLetter) ? "H\(num)" : num
            if let row = try Row.fetchOne(
                db,
                sql: "SELECT lemma, definition FROM lexicon WHERE strongs = ?",
                arguments: [alt]
            ) {
                return LexiconEntry(
                    strongs: strongs,
                    language: "",
                    lemma: row["lemma"] ?? "",
                    transliteration: "",
                    definition: row["definition"] ?? ""
                )
            }

            return LexiconEntry(strongs: strongs, language: "", lemma: "", transliteration: "", definition: "")
        }
    }

    func insertLexicon(strongs: String, language: String, lemma: String, transliteration: String, definition: String) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO lexicon (strongs, language, lemma, transliteration, definition) VALUES (?, ?, ?, ?, ?)",
                arguments: [strongs, language, lemma, transliteration, definition]
            )
        }
    }
}
