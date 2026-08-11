import Foundation
import GRDB

struct NotesDAO {
    private let db: DatabaseWriter

    init(db: DatabaseWriter) {
        self.db = db
    }

    func saveNote(book: String, chapter: Int, verse: Int, content: String) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO notes (book, chapter, verse, content) VALUES (?, ?, ?, ?)",
                arguments: [book, chapter, verse, content]
            )
        }
    }

    func getNotes(book: String, chapter: Int, verse: Int) throws -> [Note] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, content, timestamp FROM notes WHERE book=? AND chapter=? AND verse=? ORDER BY timestamp DESC",
                arguments: [book, chapter, verse]
            )
            return rows.map { row in
                Note(
                    id: row["id"],
                    book: book,
                    chapter: chapter,
                    verse: verse,
                    content: row["content"],
                    timestamp: row["timestamp"] ?? Date()
                )
            }
        }
    }

    func deleteNote(id: Int64) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM notes WHERE id = ?",
                arguments: [id]
            )
        }
    }
}
