import SwiftUI

struct ReadingAnalyticsView: View {
    @State private var dailyCounts: [(Int, Int)] = []
    @State private var longestStreak: Int = 0
    @State private var totalChaptersRead: Int = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    streakSection
                    statsSection
                    chartSection
                }
                .padding()
            }
            .navigationTitle("Reading Analytics")
            .onAppear(perform: loadData)
        }
    }
    
    private var streakSection: some View {
        HStack(spacing: 32) {
            StatBadge(
                title: "Current Streak",
                value: "\(calculateCurrentStreak())",
                unit: "days",
                icon: "flame.fill",
                color: .orange
            )
            StatBadge(
                title: "Longest Streak",
                value: "\(longestStreak)",
                unit: "days",
                icon: "trophy.fill",
                color: .yellow
            )
        }
    }
    
    private var statsSection: some View {
        HStack(spacing: 32) {
            StatBadge(
                title: "Total Chapters",
                value: "\(totalChaptersRead)",
                unit: "read",
                icon: "book.fill",
                color: .blue
            )
            StatBadge(
                title: "Days Active",
                value: "\(dailyCounts.filter { $0.1 > 0 }.count)",
                unit: "days",
                icon: "calendar",
                color: .green
            )
        }
    }
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days")
                .font(.headline)
            
            let last7 = Array(dailyCounts.suffix(7))
            
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(last7.indices, id: \.self) { index in
                    let entry = last7[index]
                    VStack(spacing: 4) {
                        if entry.1 > 0 {
                            Text("\(entry.1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(entry.1 > 0 ? Color.blue : Color.gray.opacity(0.2))
                            .frame(
                                width: 32,
                                height: max(4, CGFloat(entry.1) * 20)
                            )
                        Text(dayLabel(for: entry.0))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func calculateCurrentStreak() -> Int {
        guard !dailyCounts.isEmpty else { return 0 }
        let reversed = dailyCounts.map { $0.1 }.reversed()
        var streak = 0
        for count in reversed {
            guard count > 0 else { break }
            streak += 1
        }
        return streak
    }
    
    private func dayLabel(for epochDay: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochDay) * 86400)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private func loadData() {
        guard let db = try? DatabaseManager.open() else { return }
        let dao = db.readingAnalyticsDAO
        
        dailyCounts = (try? dao.getDailyReadCounts(days: 30)) ?? []
        
        let epochDays = (try? dao.getReadEpochDaysDescending()) ?? []
        longestStreak = calculateLongestStreak(from: epochDays)
        
        let readBooks = (try? dao.getReadCompletion()) ?? [:]
        totalChaptersRead = readBooks.values.reduce(0) { $0 + Int($1 * 100) }
    }
    
    private func calculateLongestStreak(from epochDays: [Int]) -> Int {
        guard !epochDays.isEmpty else { return 0 }
        let sorted = epochDays.sorted()
        var longest = 1
        var current = 1
        
        for i in 1..<sorted.count {
            if sorted[i] - sorted[i - 1] == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        
        return longest
    }
}

private struct StatBadge: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ReadingAnalyticsView()
}
