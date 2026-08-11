import Foundation
import GRDB

struct FavoritesDAO {
    private let db: DatabaseWriter

    init(db: DatabaseWriter) {
        self.db = db
    }

    func saveFavorite(strongs: String, lemma: String, definition: String) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO favorites (strongs, lemma, definition) VALUES (?, ?, ?)",
                arguments: [strongs, lemma, definition]
            )
        }
    }

    func getFavorites() throws -> [Favorite] {
        try db.read { db in
            try Favorite.fetchAll(db, sql: "SELECT strongs, lemma, definition FROM favorites")
        }
    }

    func deleteFavorite(strongs: String) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM favorites WHERE strongs = ?",
                arguments: [strongs]
            )
        }
    }
}
