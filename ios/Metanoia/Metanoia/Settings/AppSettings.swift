import SwiftUI
import AVFoundation

@Observable
class AppSettings {
    private let defaults = UserDefaults.standard
    
    // MARK: - Audio Settings
    
    var selectedVoice: String {
        get { defaults.string(forKey: Keys.selectedVoice) ?? "default" }
        set { defaults.set(newValue, forKey: Keys.selectedVoice) }
    }
    
    var speechSpeed: Float {
        get {
            let speed = defaults.float(forKey: Keys.speechSpeed)
            return speed == 0 ? AVSpeechUtteranceDefaultSpeechRate : speed
        }
        set { defaults.set(newValue, forKey: Keys.speechSpeed) }
    }
    
    var speechPitch: Float {
        get {
            let pitch = defaults.float(forKey: Keys.speechPitch)
            return pitch == 0 ? 1.0 : pitch
        }
        set { defaults.set(newValue, forKey: Keys.speechPitch) }
    }
    
    var autoScrollDuringTTS: Bool {
        get { defaults.bool(forKey: Keys.autoScrollDuringTTS) }
        set { defaults.set(newValue, forKey: Keys.autoScrollDuringTTS) }
    }
    
    // MARK: - Reader Settings
    
    var englishFontSize: CGFloat {
        get {
            let size = defaults.double(forKey: Keys.englishFontSize)
            return size == 0 ? 18 : CGFloat(size)
        }
        set { defaults.set(Double(newValue), forKey: Keys.englishFontSize) }
    }
    
    var ancientFontSize: CGFloat {
        get {
            let size = defaults.double(forKey: Keys.ancientFontSize)
            return size == 0 ? 20 : CGFloat(size)
        }
        set { defaults.set(Double(newValue), forKey: Keys.ancientFontSize) }
    }
    
    var lineHeight: CGFloat {
        get {
            let height = defaults.double(forKey: Keys.lineHeight)
            return height == 0 ? 1.6 : CGFloat(height)
        }
        set { defaults.set(Double(newValue), forKey: Keys.lineHeight) }
    }
    
    var serifFontEnabled: Bool {
        get { defaults.bool(forKey: Keys.serifFontEnabled) }
        set { defaults.set(newValue, forKey: Keys.serifFontEnabled) }
    }
    
    var showVerseNumbers: Bool {
        get {
            if defaults.object(forKey: Keys.showVerseNumbers) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.showVerseNumbers)
        }
        set { defaults.set(newValue, forKey: Keys.showVerseNumbers) }
    }
    
    var showChapterNumbers: Bool {
        get {
            if defaults.object(forKey: Keys.showChapterNumbers) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.showChapterNumbers)
        }
        set { defaults.set(newValue, forKey: Keys.showChapterNumbers) }
    }
    
    // MARK: - Display Settings
    
    var showEthiopianCanon: Bool {
        get { defaults.bool(forKey: Keys.showEthiopianCanon) }
        set { defaults.set(newValue, forKey: Keys.showEthiopianCanon) }
    }
    
    var showApocrypha: Bool {
        get { defaults.bool(forKey: Keys.showApocrypha) }
        set { defaults.set(newValue, forKey: Keys.showApocrypha) }
    }
    
    var themeMode: ThemeMode {
        get {
            let raw = defaults.string(forKey: Keys.themeMode) ?? "system"
            return ThemeMode(rawValue: raw) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.themeMode) }
    }
    
    var accentColor: String {
        get { defaults.string(forKey: Keys.accentColor) ?? "blue" }
        set { defaults.set(newValue, forKey: Keys.accentColor) }
    }
    
    var hapticFeedbackEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.hapticFeedbackEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.hapticFeedbackEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.hapticFeedbackEnabled) }
    }
    
    var reduceAnimations: Bool {
        get { defaults.bool(forKey: Keys.reduceAnimations) }
        set { defaults.set(newValue, forKey: Keys.reduceAnimations) }
    }
    
    // MARK: - Bible Settings
    
    var bibleGatewayVersion: String {
        get { defaults.string(forKey: Keys.bibleGatewayVersion) ?? "NKJV" }
        set { defaults.set(newValue, forKey: Keys.bibleGatewayVersion) }
    }
    
    var speakDefinitionsOnTap: Bool {
        get { defaults.bool(forKey: Keys.speakDefinitionsOnTap) }
        set { defaults.set(newValue, forKey: Keys.speakDefinitionsOnTap) }
    }
    
    var showInterlinear: Bool {
        get { defaults.bool(forKey: Keys.showInterlinear) }
        set { defaults.set(newValue, forKey: Keys.showInterlinear) }
    }
    
    var defaultBook: String {
        get { defaults.string(forKey: Keys.defaultBook) ?? "John" }
        set { defaults.set(newValue, forKey: Keys.defaultBook) }
    }
    
    var defaultChapter: Int {
        let chapter = defaults.integer(forKey: Keys.defaultChapter)
        return chapter == 0 ? 1 : chapter
    }
    func setDefaultChapter(_ chapter: Int) {
        defaults.set(chapter, forKey: Keys.defaultChapter)
    }
    
    // MARK: - Reading Settings
    
    var readingGoalChaptersPerDay: Int {
        let goal = defaults.integer(forKey: Keys.readingGoalChaptersPerDay)
        return goal == 0 ? 1 : goal
    }
    func setReadingGoal(_ chapters: Int) {
        defaults.set(chapters, forKey: Keys.readingGoalChaptersPerDay)
    }
    
    var bookmarkLastPosition: Bool {
        get {
            if defaults.object(forKey: Keys.bookmarkLastPosition) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.bookmarkLastPosition)
        }
        set { defaults.set(newValue, forKey: Keys.bookmarkLastPosition) }
    }
    
    // MARK: - Sync Settings
    
    var iCloudSyncEnabled: Bool {
        get { defaults.bool(forKey: Keys.iCloudSyncEnabled) }
        set { defaults.set(newValue, forKey: Keys.iCloudSyncEnabled) }
    }
    
    var autoBackupEnabled: Bool {
        get { defaults.bool(forKey: Keys.autoBackupEnabled) }
        set { defaults.set(newValue, forKey: Keys.autoBackupEnabled) }
    }
    
    // MARK: - Notification Settings
    
    var dailyReminderEnabled: Bool {
        get { defaults.bool(forKey: Keys.dailyReminderEnabled) }
        set { defaults.set(newValue, forKey: Keys.dailyReminderEnabled) }
    }
    
    var reminderTime: Date {
        get {
            if let data = defaults.data(forKey: Keys.reminderTime),
               let date = try? JSONDecoder().decode(Date.self, from: data) {
                return date
            }
            // Default to 8:00 AM
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = 8
            components.minute = 0
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.reminderTime)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var resolvedAccentColor: Color {
        switch accentColor {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "purple": return .purple
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        default: return .blue
        }
    }
    
    var colorScheme: ColorScheme? {
        switch themeMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
    
    // MARK: - Reset
    
    func resetToDefaults() {
        let domain = Bundle.main.bundleIdentifier ?? "com.metanoia.app"
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()
    }
    
    func resetAudioSettings() {
        defaults.removeObject(forKey: Keys.selectedVoice)
        defaults.removeObject(forKey: Keys.speechSpeed)
        defaults.removeObject(forKey: Keys.speechPitch)
        defaults.removeObject(forKey: Keys.autoScrollDuringTTS)
    }
    
    func resetReaderSettings() {
        defaults.removeObject(forKey: Keys.englishFontSize)
        defaults.removeObject(forKey: Keys.ancientFontSize)
        defaults.removeObject(forKey: Keys.lineHeight)
        defaults.removeObject(forKey: Keys.serifFontEnabled)
        defaults.removeObject(forKey: Keys.showVerseNumbers)
        defaults.removeObject(forKey: Keys.showChapterNumbers)
    }
    
    func resetDisplaySettings() {
        defaults.removeObject(forKey: Keys.themeMode)
        defaults.removeObject(forKey: Keys.accentColor)
        defaults.removeObject(forKey: Keys.hapticFeedbackEnabled)
        defaults.removeObject(forKey: Keys.reduceAnimations)
    }
}

// MARK: - Theme Mode

enum ThemeMode: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
    
    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - Keys

extension AppSettings {
    private enum Keys {
        static let selectedVoice = "selected_voice"
        static let speechSpeed = "speech_speed"
        static let speechPitch = "speech_pitch"
        static let autoScrollDuringTTS = "auto_scroll_tts"
        
        static let englishFontSize = "english_font_size"
        static let ancientFontSize = "ancient_font_size"
        static let lineHeight = "line_height"
        static let serifFontEnabled = "serif_font_enabled"
        static let showVerseNumbers = "show_verse_numbers"
        static let showChapterNumbers = "show_chapter_numbers"
        
        static let showEthiopianCanon = "show_ethiopian_canon"
        static let showApocrypha = "show_apocrypha"
        static let themeMode = "theme_mode"
        static let accentColor = "accent_color"
        static let hapticFeedbackEnabled = "haptic_feedback"
        static let reduceAnimations = "reduce_animations"
        
        static let bibleGatewayVersion = "bible_gateway_version"
        static let speakDefinitionsOnTap = "speak_definitions"
        static let showInterlinear = "show_interlinear"
        static let defaultBook = "default_book"
        static let defaultChapter = "default_chapter"
        
        static let readingGoalChaptersPerDay = "reading_goal"
        static let bookmarkLastPosition = "bookmark_position"
        
        static let iCloudSyncEnabled = "icloud_sync"
        static let autoBackupEnabled = "auto_backup"
        
        static let dailyReminderEnabled = "daily_reminder"
        static let reminderTime = "reminder_time"
    }
}
