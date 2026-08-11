import SwiftUI
import AVFoundation

struct AudioSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TTSService.self) private var ttsService
    @State private var isTesting = false
    
    private let availableVoices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language.hasPrefix("en") }
        .sorted { $0.name < $1.name }
    
    var body: some View {
        Form {
            Section("Voice") {
                Picker("Voice", selection: $settings.selectedVoice) {
                    ForEach(availableVoices, id: \.identifier) { voice in
                        VStack(alignment: .leading) {
                            Text(voice.name)
                            Text(voice.identifier)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(voice.identifier)
                    }
                }
            }
            
            Section("Speech Speed") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("0.5x")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.speechSpeed, in: 0.5...2.0, step: 0.1)
                        Text("2.0x")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Speed: \(String(format: "%.1f", settings.speechSpeed))x")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Speech Pitch") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("0.5")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.speechPitch, in: 0.5...2.0, step: 0.1)
                        Text("2.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Pitch: \(String(format: "%.1f", settings.speechPitch))x")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Toggle(isOn: $settings.autoScrollDuringTTS) {
                    Label("Auto-scroll during TTS", systemImage: "arrow.down")
                }
            }
            
            Section {
                Button {
                    testTTS()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Label(isTesting ? "Stop" : "Test Voice", systemImage: isTesting ? "stop.fill" : "play.fill")
                    }
                }
                .disabled(isTesting)
            }
        }
        .navigationTitle("Audio Settings")
    }
    
    private func testTTS() {
        if isTesting {
            ttsService.stop()
            isTesting = false
        } else {
            isTesting = true
            ttsService.speak(
                "The Lord is my shepherd; I shall not want. He makes me lie down in green pastures.",
                voice: settings.selectedVoice,
                rate: settings.speechSpeed
            )
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                ttsService.stop()
                isTesting = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        AudioSettingsView()
            .environment(AppSettings())
            .environment(TTSService())
    }
}
