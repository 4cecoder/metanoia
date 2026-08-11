import Foundation
import GRDB

struct VerseDAO {
    private let db: DatabaseReader
    private let writer: DatabaseWriter

    init(db: DatabaseReader, writer: DatabaseWriter) {
        self.db = db
        self.writer = writer
    }

    func getChapter(book: String, chapter: Int) throws -> [Verse] {
        try db.read { db in
            try Verse
                .filter(Column("book") == book && Column("chapter") == chapter)
                .order(Column("verse"))
                .fetchAll(db)
        }
    }

    func insertVerses(book: String, chapter: Int, verses: [Verse], version: String) throws {
        try writer.write { db in
            for v in verses {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
                    arguments: [book, chapter, v.number, v.text, version]
                )
            }
        }
    }

    func searchVerses(query: String) throws -> [SearchResult] {
        guard query.count >= 2 else { return [] }

        let refRegex = /^[1-3]?\s?[a-zA-Z]+\s?\d+(?::\d+)?$/
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try reference lookup first
        if trimmed.range(of: refRegex, options: .regularExpression) != nil {
            let parts = trimmed.lowercased().replacingOccurrences(of: " ", with: "")
            let bookPart: String
            if parts.hasPrefix("1") || parts.hasPrefix("2") || parts.hasPrefix("3") {
                bookPart = String(parts.dropFirst())
            } else {
                bookPart = parts
            }

            if let resolvedBook = BIBLE_ABBREVIATIONS[bookPart]
                ?? BOOKS.first(where: { $0.name.lowercased() == bookPart })?.name
            {
                let components = trimmed.components(separatedBy: CharacterSet(charactersIn: ": "))
                // Re-parse: could be "Genesis 1:3" or "Genesis 1"
                let matches = try db.read { db -> [SearchResult] in
                    let bookNameComp = trimmed
                        .replacingOccurrences(of: #"\d+.*"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                    let numberPart = trimmed
                        .replacingOccurrences(of: #"[a-zA-Z\s]+"#, with: "", options: .regularExpression)

                    if numberPart.contains(":") {
                        let nums = numberPart.components(separatedBy: ":")
                        let ch = Int(nums[0]) ?? 1
                        let vs = Int(nums[1]) ?? 1
                        let rows = try Row.fetchAll(
                            db,
                            sql: "SELECT book, chapter, verse, text FROM verses WHERE book=? AND chapter=? AND verse=?",
                            arguments: [resolvedBook, ch, vs]
                        )
                        return rows.map { SearchResult(book: $0["book"], chapter: $0["chapter"], verse: $0["verse"], text: $0["text"]) }
                    } else {
                        let ch = Int(numberPart) ?? 1
                        let rows = try Row.fetchAll(
                            db,
                            sql: "SELECT book, chapter, verse, text FROM verses WHERE book=? AND chapter=? LIMIT 100",
                            arguments: [resolvedBook, ch]
                        )
                        return rows.map { SearchResult(book: $0["book"], chapter: $0["chapter"], verse: $0["verse"], text: $0["text"]) }
                    }
                }
                if !matches.isEmpty { return matches }
            }
        }

        // Fall back to FTS search
        return try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT book, chapter, verse, text FROM verses_fts WHERE text MATCH ? LIMIT 50",
                arguments: ["\(query)*"]
            )
            return rows.map { SearchResult(book: $0["book"], chapter: $0["chapter"], verse: $0["verse"], text: $0["text"]) }
        }
    }

    func getDownloadedChapters(book: String) throws -> [Int] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT DISTINCT chapter FROM verses WHERE book = ?",
                arguments: [book]
            )
            return rows.map { $0["chapter"] as Int }
        }
    }

    func getBookCompletion(book: String) throws -> [String: Double] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT book, COUNT(DISTINCT chapter) FROM verses GROUP BY book"
            )
            var completion: [String: Double] = [:]
            for row in rows {
                let name: String = row["book"]
                let cachedChapters: Int = row["chapter"]
                let totalChapters = Double(BOOKS.first(where: { $0.name == name })?.chapters ?? 1)
                completion[name] = Double(cachedChapters) / totalChapters
            }
            return completion
        }
    }

    func getStats(dbSizeMb: Double) -> LibraryStats {
        do {
            return try db.read { db in
                var vOt = 0
                var vNt = 0
                let bookRows = try Row.fetchAll(db, sql: "SELECT book, COUNT(*) FROM verses GROUP BY book")
                for row in bookRows {
                    let name: String = row["book"]
                    let count: Int = row["COUNT(*)"]
                    if BOOKS.first(where: { $0.name == name })?.testament == "Old" {
                        vOt += count
                    } else {
                        vNt += count
                    }
                }

                let lHeb: Int = try Row.fetchAll(db, sql: "SELECT COUNT(*) FROM lexicon WHERE language = 'hebrew'")
                    .first?["COUNT(*)"] ?? 0
                let lGk: Int = try Row.fetchAll(db, sql: "SELECT COUNT(*) FROM lexicon WHERE language = 'greek'")
                    .first?["COUNT(*)"] ?? 0
                let n: Int = try Row.fetchAll(db, sql: "SELECT COUNT(*) FROM notes")
                    .first?["COUNT(*)"] ?? 0
                let h: Int = try Row.fetchAll(db, sql: "SELECT COUNT(*) FROM highlights")
                    .first?["COUNT(*)"] ?? 0
                let i: Int = try Row.fetchAll(db, sql: "SELECT COUNT(*) FROM interlinear")
                    .first?["COUNT(*)"] ?? 0

                return LibraryStats(
                    versesOt: vOt, versesNt: vNt,
                    lexiconHeb: lHeb, lexiconGk: lGk,
                    notesCount: n, highlightsCount: h,
                    interlinearCount: i, dbSizeMb: dbSizeMb
                )
            }
        } catch {
            return LibraryStats(versesOt: 0, versesNt: 0, lexiconHeb: 0, lexiconGk: 0,
                                notesCount: 0, highlightsCount: 0, interlinearCount: 0, dbSizeMb: dbSizeMb)
        }
    }

    func clearTable(_ tableName: String) throws {
        let allowed = ["favorites", "lexicon", "interlinear", "highlights", "notes", "verses"]
        guard allowed.contains(tableName) else { return }
        try writer.write { db in
            try db.execute(sql: "DELETE FROM \(tableName)")
            try db.execute(sql: "VACUUM")
        }
    }

    func factoryReset() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM verses")
            try db.execute(sql: "DELETE FROM lexicon")
            try db.execute(sql: "DELETE FROM interlinear")
            try db.execute(sql: "DELETE FROM highlights")
            try db.execute(sql: "DELETE FROM notes")
            try db.execute(sql: "DELETE FROM favorites")
            try db.execute(sql: "VACUUM")
        }
    }

    func checkIntegrity() throws -> String {
        try db.read { db in
            let row = try Row.fetchOne(db, sql: "PRAGMA integrity_check")
            return row?["integrity_check"] as? String ?? "Unknown"
        }
    }
}
