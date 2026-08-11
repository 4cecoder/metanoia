import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .bible
    
    enum Tab: String {
        case bible
        case collection
        case settings
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            BibleScreen()
                .tabItem {
                    Label("Bible", systemImage: "book.fill")
                }
                .tag(Tab.bible)
            
            CollectionScreen()
                .tabItem {
                    Label("Collection", systemImage: "star.fill")
                }
                .tag(Tab.collection)
            
            SettingsScreen()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
        .environment(TTSService())
}
