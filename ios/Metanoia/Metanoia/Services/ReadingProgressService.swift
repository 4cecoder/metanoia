import Foundation

@Observable
class ReadingProgressService {
    var currentStreak = 0
    var longestStreak = 0
    var todayChaptersRead = 0
    var totalChaptersRead = 0
    var totalReadingTimeMinutes: TimeInterval = 0
    var readingHistory: [ReadingSession] = []
    
    private let storageKey = "reading_progress"
    private let calendar = Calendar.current
    
    init() {
        loadProgress()
    }
    
    // MARK: - Recording
    
    func recordChapterRead(book: String, chapter: Int) async {
        let today = calendar.startOfDay(for: Date())
        
        // Check if we already recorded this chapter today
        let alreadyRead = readingHistory.contains { session in
            calendar.isDate(session.date, inSameDayAs: today) &&
            session.book == book &&
            session.chapter == chapter
        }
        
        guard !alreadyRead else { return }
        
        let session = ReadingSession(
            book: book,
            chapter: chapter,
            date: Date(),
            duration: 0
        )
        
        readingHistory.append(session)
        todayChaptersRead += 1
        totalChaptersRead += 1
        
        await calculateStreaks()
        saveProgress()
    }
    
    func recordReadingTime(minutes: TimeInterval) async {
        totalReadingTimeMinutes += minutes
        
        // Update today's session duration if exists
        let today = calendar.startOfDay(for: Date())
        if let lastIndex = readingHistory.indices.last,
           calendar.isDate(readingHistory[lastIndex].date, inSameDayAs: today) {
            readingHistory[lastIndex].duration += minutes
        }
        
        saveProgress()
    }
    
    // MARK: - Streaks
    
    func calculateStreaks() async {
        let sortedSessions = readingHistory
            .map { calendar.startOfDay(for: $0.date) }
            .sorted(by: >)
            .removingDuplicates()
        
        guard !sortedSessions.isEmpty else {
            currentStreak = 0
            longestStreak = 0
            return
        }
        
        var streak = 1
        var maxStreak = 1
        var today = calendar.startOfDay(for: Date())
        
        // Check if today has been read
        let todayRead = sortedSessions.contains { calendar.isDate($0, inSameDayAs: today) }
        
        // Check if yesterday has been read (to continue streak)
        if !todayRead {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  sortedSessions.contains(where: { calendar.isDate($0, inSameDayAs: yesterday) }) else {
                currentStreak = 0
                longestStreak = max(maxStreak, longestStreak)
                return
            }
            today = yesterday
        }
        
        // Calculate current streak
        var checkDate = today
        for _ in 1..<365 {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            
            if sortedSessions.contains(where: { calendar.isDate($0, inSameDayAs: previousDay) }) {
                streak += 1
                checkDate = previousDay
            } else {
                break
            }
        }
        
        // Calculate longest streak
        var tempStreak = 1
        for i in 1..<sortedSessions.count {
            let current = sortedSessions[i]
            let previous = sortedSessions[i - 1]
            
            if let dayBetween = calendar.date(byAdding: .day, value: -1, to: previous),
               calendar.isDate(current, inSameDayAs: dayBetween) {
                tempStreak += 1
            } else {
                tempStreak = 1
            }
            
            maxStreak = max(maxStreak, tempStreak)
        }
        
        currentStreak = streak
        longestStreak = max(maxStreak, longestStreak)
    }
    
    // MARK: - Statistics
    
    func getReadingStats() async -> ReadingStats {
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: today)!
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: today)!
        
        let todaySessions = readingHistory.filter {
            calendar.isDate($0.date, inSameDayAs: today)
        }
        
        let weekSessions = readingHistory.filter {
            $0.date >= weekAgo
        }
        
        let monthSessions = readingHistory.filter {
            $0.date >= monthAgo
        }
        
        let yearSessions = readingHistory.filter {
            $0.date >= yearAgo
        }
        
        let uniqueBooksRead = Set(readingHistory.map { $0.book }).count
        
        let averageDailyChapters: Double = {
            guard !readingHistory.isEmpty else { return 0 }
            let firstDate = readingHistory.map(\.date).min() ?? today
            let days = max(1, calendar.dateComponents([.day], from: firstDate, to: today).day ?? 1)
            return Double(readingHistory.count) / Double(days)
        }()
        
        return ReadingStats(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            todayChaptersRead: todaySessions.count,
            weekChaptersRead: weekSessions.count,
            monthChaptersRead: monthSessions.count,
            yearChaptersRead: yearSessions.count,
            totalChaptersRead: totalChaptersRead,
            totalReadingTimeMinutes: totalReadingTimeMinutes,
            uniqueBooksRead: uniqueBooksRead,
            averageDailyChapters: averageDailyChapters,
            lastReadDate: readingHistory.map(\.date).max()
        )
    }
    
    // MARK: - Queries
    
    func hasReadChapter(_ book: String, chapter: Int) -> Bool {
        readingHistory.contains { $0.book == book && $0.chapter == chapter }
    }
    
    func lastReadChapter(for book: String) -> ReadingSession? {
        readingHistory
            .filter { $0.book == book }
            .max(by: { $0.date < $1.date })
    }
    
    func chaptersRead(for book: String) -> Set<Int> {
        Set(readingHistory.filter { $0.book == book }.map(\.chapter))
    }
    
    func recentBooks(limit: Int = 5) -> [String] {
        var bookDates: [String: Date] = [:]
        for session in readingHistory {
            if let existing = bookDates[session.book] {
                if session.date > existing {
                    bookDates[session.book] = session.date
                }
            } else {
                bookDates[session.book] = session.date
            }
        }
        
        return bookDates
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }
    
    // MARK: - Persistence
    
    private func saveProgress() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(readingHistory)
            UserDefaults.standard.set(data, forKey: storageKey)
            UserDefaults.standard.set(totalChaptersRead, forKey: "\(storageKey)_total")
            UserDefaults.standard.set(totalReadingTimeMinutes, forKey: "\(storageKey)_time")
            UserDefaults.standard.set(longestStreak, forKey: "\(storageKey)_longest")
        } catch {
            print("Failed to save reading progress: \(error)")
        }
    }
    
    private func loadProgress() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            readingHistory = try decoder.decode([ReadingSession].self, from: data)
            totalChaptersRead = UserDefaults.standard.integer(forKey: "\(storageKey)_total")
            totalReadingTimeMinutes = UserDefaults.standard.double(forKey: "\(storageKey)_time")
            longestStreak = UserDefaults.standard.integer(forKey: "\(storageKey)_longest")
            
            // Recalculate today's count
            let today = calendar.startOfDay(for: Date())
            todayChaptersRead = readingHistory.filter {
                calendar.isDate($0.date, inSameDayAs: today)
            }.count
            
            Task {
                await calculateStreaks()
            }
        } catch {
            print("Failed to load reading progress: \(error)")
        }
    }
    
    func resetProgress() {
        readingHistory = []
        currentStreak = 0
        longestStreak = 0
        todayChaptersRead = 0
        totalChaptersRead = 0
        totalReadingTimeMinutes = 0
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: "\(storageKey)_total")
        UserDefaults.standard.removeObject(forKey: "\(storageKey)_time")
        UserDefaults.standard.removeObject(forKey: "\(storageKey)_longest")
    }
}

// MARK: - Models

struct ReadingSession: Codable, Identifiable {
    let id: UUID
    let book: String
    let chapter: Int
    let date: Date
    var duration: TimeInterval
    
    init(book: String, chapter: Int, date: Date, duration: TimeInterval) {
        self.id = UUID()
        self.book = book
        self.chapter = chapter
        self.date = date
        self.duration = duration
    }
}

struct ReadingStats {
    let currentStreak: Int
    let longestStreak: Int
    let todayChaptersRead: Int
    let weekChaptersRead: Int
    let monthChaptersRead: Int
    let yearChaptersRead: Int
    let totalChaptersRead: Int
    let totalReadingTimeMinutes: TimeInterval
    let uniqueBooksRead: Int
    let averageDailyChapters: Double
    let lastReadDate: Date?
    
    var formattedReadingTime: String {
        let hours = Int(totalReadingTimeMinutes) / 60
        let minutes = Int(totalReadingTimeMinutes) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    var formattedAverageDaily: String {
        String(format: "%.1f", averageDailyChapters)
    }
}

// MARK: - Helpers

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
