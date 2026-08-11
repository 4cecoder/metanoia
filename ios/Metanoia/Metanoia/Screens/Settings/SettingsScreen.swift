import SwiftUI

struct SettingsScreen: View {
    @Environment(AppSettings.self) private var settings
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        AudioSettingsView()
                    } label: {
                        SettingsRow(icon: "waveform", title: "Audio", subtitle: "Voice and speech speed")
                    }
                    
                    NavigationLink {
                        ReaderSettingsView()
                    } label: {
                        SettingsRow(icon: "textformat.size", title: "Reader", subtitle: "Fonts and reading options")
                    }
                }
                
                Section("Display") {
                    Picker("Theme", selection: $settings.themeMode) {
                        ForEach(ThemeMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: mode.icon).tag(mode)
                        }
                    }
                    
                    Picker("Accent Color", selection: $settings.accentColor) {
                        Text("Blue").tag("blue")
                        Text("Red").tag("red")
                        Text("Orange").tag("orange")
                        Text("Yellow").tag("yellow")
                        Text("Green").tag("green")
                        Text("Purple").tag("purple")
                        Text("Pink").tag("pink")
                        Text("Teal").tag("teal")
                        Text("Indigo").tag("indigo")
                    }
                }
                
                Section {
                    NavigationLink {
                        ReadingAnalyticsView()
                    } label: {
                        SettingsRow(icon: "chart.bar", title: "Reading Analytics", subtitle: "Track your progress")
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2026.08.11")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(subtitle)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    SettingsScreen()
        .environment(AppSettings())
}
