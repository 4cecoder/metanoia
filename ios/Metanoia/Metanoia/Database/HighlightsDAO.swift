import Foundation
import GRDB

struct HighlightsDAO {
    private let db: DatabaseWriter

    init(db: DatabaseWriter) {
        self.db = db
    }

    func setHighlight(book: String, chapter: Int, verse: Int, color: Int) throws {
        try db.write { db in
            if color == 0 {
                try db.execute(
                    sql: "DELETE FROM highlights WHERE book=? AND chapter=? AND verse=?",
                    arguments: [book, chapter, verse]
                )
            } else {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO highlights (book, chapter, verse, color) VALUES (?, ?, ?, ?)",
                    arguments: [book, chapter, verse, color]
                )
            }
        }
    }

    func getHighlights(book: String, chapter: Int) throws -> [Int: Int] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT verse, color FROM highlights WHERE book=? AND chapter=?",
                arguments: [book, chapter]
            )
            var map: [Int: Int] = [:]
            for row in rows {
                map[row["verse"]] = row["color"]
            }
            return map
        }
    }
}
