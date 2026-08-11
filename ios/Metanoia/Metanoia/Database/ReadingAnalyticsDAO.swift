import Foundation
import GRDB

struct ReadingAnalyticsDAO {
    private let db: DatabaseWriter

    init(db: DatabaseWriter) {
        self.db = db
    }

    func recordChapterRead(book: String, chapter: Int) throws {
        try db.write { db in
            let now = Int(Date().timeIntervalSince1970 * 1000)

            let existing = try Row.fetchOne(
                db,
                sql: "SELECT read_count, first_read_at, reading_time_seconds FROM reading_progress WHERE book = ? AND chapter = ?",
                arguments: [book, chapter]
            )

            let prevCount: Int = existing?["read_count"] ?? 0
            let firstReadAt: Int = existing?["first_read_at"] ?? now
            let prevTime: Int = existing?["reading_time_seconds"] ?? 0

            try db.execute(
                sql: "INSERT OR REPLACE INTO reading_progress (book, chapter, first_read_at, last_read_at, read_count, reading_time_seconds) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [book, chapter, firstReadAt, now, prevCount + 1, prevTime]
            )

            try db.execute(
                sql: "INSERT INTO reading_events (book, chapter, timestamp) VALUES (?, ?, ?)",
                arguments: [book, chapter, now]
            )
        }
    }

    func recordReadingTime(book: String, chapter: Int, additionalSeconds: Int) throws {
        guard additionalSeconds > 0 else { return }
        try db.write { db in
            let now = Int(Date().timeIntervalSince1970 * 1000)

            let existing = try Row.fetchOne(
                db,
                sql: "SELECT read_count, first_read_at, reading_time_seconds FROM reading_progress WHERE book = ? AND chapter = ?",
                arguments: [book, chapter]
            )

            let prevCount: Int = existing?["read_count"] ?? 0
            let firstReadAt: Int = existing?["first_read_at"] ?? now
            let prevTime: Int = existing?["reading_time_seconds"] ?? 0

            try db.execute(
                sql: "INSERT OR REPLACE INTO reading_progress (book, chapter, first_read_at, last_read_at, read_count, reading_time_seconds) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [book, chapter, firstReadAt, now, prevCount, prevTime + additionalSeconds]
            )
        }
    }

    func getChapterReadingTimes(book: String) throws -> [Int: Int] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT chapter, reading_time_seconds FROM reading_progress WHERE book = ?",
                arguments: [book]
            )
            var map: [Int: Int] = [:]
            for row in rows {
                map[row["chapter"]] = row["reading_time_seconds"]
            }
            return map
        }
    }

    func getReadCompletion() throws -> [String: Double] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT book, COUNT(DISTINCT chapter) FROM reading_progress WHERE read_count > 0 GROUP BY book"
            )
            var completion: [String: Double] = [:]
            for row in rows {
                let name: String = row["book"]
                let readChapters: Int = row["chapter"]
                let totalChapters = Double(BOOKS.first(where: { $0.name == name })?.chapters ?? 1)
                completion[name] = Double(readChapters) / totalChapters
            }
            return completion
        }
    }

    func getMostReadBooks(limit: Int = 5) throws -> [(String, Int)] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT book, COUNT(*) as cnt FROM reading_events GROUP BY book ORDER BY cnt DESC LIMIT ?",
                arguments: [limit]
            )
            return rows.map { ($0["book"] as String, $0["cnt"] as Int) }
        }
    }

    func getHotChapters(limit: Int = 10) throws -> [HotChapter] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT book, chapter, COUNT(*) as cnt FROM reading_events GROUP BY book, chapter ORDER BY cnt DESC LIMIT ?",
                arguments: [limit]
            )
            return rows.map { HotChapter(book: $0["book"], chapter: $0["chapter"], views: $0["cnt"]) }
        }
    }

    func getReadingEventCounts(sinceMilliseconds: Int) throws -> Int {
        try db.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM reading_events WHERE timestamp >= ?",
                arguments: [sinceMilliseconds]
            )
            return row?["COUNT(*)"] as? Int ?? 0
        }
    }

    func getFirstEverReadTimestamp() throws -> Int? {
        try db.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT MIN(timestamp) FROM reading_events")
            return row?["MIN(timestamp)"] as? Int
        }
    }

    func getReadEpochDaysDescending() throws -> [Int] {
        let timestamps = try getAllEventTimestamps()
        let cal = Calendar.current
        let uniqueDays = Set(timestamps.map { ts -> Int in
            let date = Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0)
            return cal.startOfDay(for: date).timeIntervalSince1970.toEpochDay
        })
        return Array(uniqueDays).sorted(by: >)
    }

    func getDailyReadCounts(days: Int) throws -> [(Int, Int)] {
        guard days > 0 else { return [] }
        let timestamps = try getAllEventTimestamps()
        let cal = Calendar.current
        let now = Date()

        var byDay: [Int: Int] = [:]
        for ts in timestamps {
            let date = Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0)
            let day = cal.startOfDay(for: date).timeIntervalSince1970.toEpochDay
            byDay[day, default: 0] += 1
        }

        let today = now.timeIntervalSince1970.toEpochDay
        let start = today - (days - 1)
        return (start...today).map { ($0, byDay[$0] ?? 0) }
    }

    func getDayOfWeekCounts() -> [Int] {
        var counts = Array(repeating: 0, count: 7)
        guard let timestamps = try? getAllEventTimestamps() else { return counts }
        let cal = Calendar.current
        for ts in timestamps {
            let date = Date(timeIntervalSince1970: TimeInterval(ts) * 1000)
            let dow = cal.component(.weekday, from: date) // 1=Sun, 7=Sat
            counts[dow % 7] += 1
        }
        return counts
    }

    func getHourOfDayCounts() -> [Int] {
        var counts = Array(repeating: 0, count: 24)
        guard let timestamps = try? getAllEventTimestamps() else { return counts }
        let cal = Calendar.current
        for ts in timestamps {
            let date = Date(timeIntervalSince1970: TimeInterval(ts) * 1000)
            let hour = cal.component(.hour, from: date)
            counts[hour] += 1
        }
        return counts
    }

    func getTestamentReadCounts() throws -> [String: Int] {
        var counts: [String: Int] = ["Old": 0, "New": 0, "Eth": 0]
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT book, COUNT(DISTINCT chapter) FROM reading_progress WHERE read_count > 0 GROUP BY book"
            )
            for row in rows {
                let name: String = row["book"]
                let readChapters: Int = row["chapter"]
                if let testament = BOOKS.first(where: { $0.name == name })?.testament {
                    counts[testament, default: 0] += readChapters
                }
            }
        }
        return counts
    }

    func clearReadingHistory() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM reading_progress")
            try db.execute(sql: "DELETE FROM reading_events")
        }
    }

    private func getAllEventTimestamps() throws -> [Int] {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT timestamp FROM reading_events")
            return rows.map { $0["timestamp"] as Int }
        }
    }
}

private extension TimeInterval {
    var toEpochDay: Int {
        Int(self / 86400.0)
    }
}
