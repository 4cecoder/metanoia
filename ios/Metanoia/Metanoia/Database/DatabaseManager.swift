import Foundation
import GRDB

final class DatabaseManager {
    private let writer: DatabaseWriter
    private let reader: DatabaseReader

    private init(writer: DatabaseWriter, reader: DatabaseReader) {
        self.writer = writer
        self.reader = reader
    }

    static func open(readOnly: Bool = false) throws -> DatabaseManager {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleDB = Bundle.main.url(forResource: "bible", withExtension: "db")!
        let destDB = appSupport.appendingPathComponent("bible.db")

        if !FileManager.default.fileExists(atPath: destDB.path) {
            try FileManager.default.copyItem(at: bundleDB, to: destDB)
        }

        var config = Configuration()
        config.readonly = readOnly
        config.foreignKeysEnabled = true

        if readOnly {
            let db = try Database(path: destDB.path, configuration: config)
            return DatabaseManager(writer: db, reader: db)
        } else {
            let db = try DatabaseQueue(path: destDB.path, configuration: config)
            try migrate(db)
            return DatabaseManager(writer: db, reader: db)
        }
    }

    var verseDAO: VerseDAO { .init(db: reader, writer: writer) }
    var favoritesDAO: FavoritesDAO { .init(db: writer) }
    var highlightsDAO: HighlightsDAO { .init(db: writer) }
    var notesDAO: NotesDAO { .init(db: writer) }
    var lexiconDAO: LexiconDAO { .init(db: writer) }
    var interlinearDAO: InterlinearDAO { .init(db: writer) }
    var readingAnalyticsDAO: ReadingAnalyticsDAO { .init(db: writer) }

    var dbSizeMb: Double {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbPath = appSupport.appendingPathComponent("bible.db")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath.path),
              let size = attrs[.size] as? Double else { return 0 }
        return size / (1024.0 * 1024.0)
    }

    func getStats() -> LibraryStats {
        verseDAO.getStats(dbSizeMb: dbSizeMb)
    }

    // MARK: - Migrations

    private static func migrate(_ db: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "verses", ifNotExists: true) { t in
                t.column("book", .text).notNull()
                t.column("chapter", .integer).notNull()
                t.column("verse", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("version", .text)
                t.primaryKey(["book", "chapter", "verse"])
            }

            try db.create(table: "favorites", ifNotExists: true) { t in
                t.column("strongs", .text).notNull().primaryKey()
                t.column("lemma", .text)
                t.column("definition", .text)
            }

            try db.create(table: "highlights", ifNotExists: true) { t in
                t.column("book", .text).notNull()
                t.column("chapter", .integer).notNull()
                t.column("verse", .integer).notNull()
                t.column("color", .integer)
                t.primaryKey(["book", "chapter", "verse"])
            }

            try db.create(table: "notes", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey(autoincrement: true)
                t.column("book", .text).notNull()
                t.column("chapter", .integer).notNull()
                t.column("verse", .integer).notNull()
                t.column("content", .text).notNull()
                t.column("timestamp", .datetime).defaults(to: SQL("CURRENT_TIMESTAMP"))
            }

            try db.create(table: "lexicon", ifNotExists: true) { t in
                t.column("strongs", .text).notNull().primaryKey()
                t.column("language", .text)
                t.column("lemma", .text)
                t.column("transliteration", .text)
                t.column("definition", .text)
            }

            try db.create(table: "interlinear", ifNotExists: true) { t in
                t.column("book", .text).notNull()
                t.column("chapter", .integer).notNull()
                t.column("verse", .integer).notNull()
                t.column("word_index", .integer).notNull()
                t.column("original_text", .text)
                t.column("translation", .text)
                t.column("strongs", .text)
                t.primaryKey(["book", "chapter", "verse", "word_index"])
            }

            try db.create(table: "reading_progress", ifNotExists: true) { t in
                t.column("book", .text).notNull()
                t.column("chapter", .integer).notNull()
                t.column("first_read_at", .integer)
                t.column("last_read_at", .integer)
                t.column("read_count", .integer).defaults(to: 0)
                t.column("reading_time_seconds", .integer).defaults(to: 0)
                t.primaryKey(["book", "chapter"])
            }

            try db.create(table: "reading_events", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey(autoincrement: true)
                t.column("book", .text).notNull()
                t.column("chapter", .integer).notNull()
                t.column("timestamp", .integer).notNull()
            }

            // FTS4 virtual table for verse search
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS verses_fts USING fts4(book, chapter, verse, text)
            """)

            // Triggers to keep FTS in sync
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS verses_ai AFTER INSERT ON verses BEGIN
                  INSERT INTO verses_fts(docid, book, chapter, verse, text)
                  VALUES (new.rowid, new.book, new.chapter, new.verse, new.text);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS verses_ad AFTER DELETE ON verses BEGIN
                  INSERT INTO verses_fts(verses_fts, docid, book, chapter, verse, text)
                  VALUES('delete', old.rowid, old.book, old.chapter, old.verse, old.text);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS verses_au AFTER UPDATE ON verses BEGIN
                  INSERT INTO verses_fts(verses_fts, docid, book, chapter, verse, text)
                  VALUES('delete', old.rowid, old.book, old.chapter, old.verse, old.text);
                  INSERT INTO verses_fts(docid, book, chapter, verse, text)
                  VALUES (new.rowid, new.book, new.chapter, new.verse, new.text);
                END
            """)
        }

        try migrator.migrate(db)
    }
}
