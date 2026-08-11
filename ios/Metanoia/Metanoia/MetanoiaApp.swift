import SwiftUI

@main
struct MetanoiaApp: App {
    @State private var settings = AppSettings()
    @State private var ttsService = TTSService()
    @State private var databaseManager: DatabaseManager?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(ttsService)
                .task {
                    databaseManager = try? await DatabaseManager.open()
                }
        }
    }
}
