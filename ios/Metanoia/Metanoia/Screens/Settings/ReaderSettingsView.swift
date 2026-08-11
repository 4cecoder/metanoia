import SwiftUI

struct ReaderSettingsView: View {
    @Environment(AppSettings.self) private var settings
    
    var body: some View {
        Form {
            Section("English Text") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Aa")
                            .font(.system(size: 12))
                        Slider(value: $settings.englishFontSize, in: 10...48, step: 1)
                        Text("Aa")
                            .font(.system(size: 24))
                    }
                    Text("Size: \(Int(settings.englishFontSize))pt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Ancient Text") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Αλφα")
                            .font(.system(size: 12))
                        Slider(value: $settings.ancientFontSize, in: 10...48, step: 1)
                        Text("Αλφα")
                            .font(.system(size: 24))
                    }
                    Text("Size: \(Int(settings.ancientFontSize))pt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Reading Experience") {
                Toggle(isOn: $settings.hapticFeedbackEnabled) {
                    Label("Haptic Feedback", systemImage: "iphone.radiowaves.left.and.right")
                }
                
                Toggle(isOn: $settings.serifFontEnabled) {
                    Label("Serif Font", systemImage: "textformat")
                }
                
                Toggle(isOn: $settings.showVerseNumbers) {
                    Label("Show Verse Numbers", systemImage: "number")
                }
                
                Toggle(isOn: $settings.showChapterNumbers) {
                    Label("Show Chapter Numbers", systemImage: "book.closed")
                }
            }
            
            Section("Canons") {
                Toggle(isOn: $settings.showEthiopianCanon) {
                    Label("Ethiopian Canon", systemImage: "globe.africa.fill")
                }
                
                Toggle(isOn: $settings.showApocrypha) {
                    Label("Apocrypha", systemImage: "book.closed.fill")
                }
            }
            
            Section("Line Spacing") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("1.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.lineHeight, in: 1.0...3.0, step: 0.1)
                        Text("3.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Line height: \(String(format: "%.1f", settings.lineHeight))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Reader Settings")
    }
}

#Preview {
    NavigationStack {
        ReaderSettingsView()
            .environment(AppSettings())
    }
}
