import SwiftUI

struct CollectionScreen: View {
    enum CollectionTab: String, CaseIterable {
        case favorites = "Treasure"
        case notes = "Insights"
        
        var icon: String {
            switch self {
            case .favorites: return "star.fill"
            case .notes: return "note.text"
            }
        }
    }
    
    @State private var selectedTab: CollectionTab = .favorites
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Collection", selection: $selectedTab) {
                    ForEach(CollectionTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                switch selectedTab {
                case .favorites:
                    FavoritesView()
                case .notes:
                    NotesView()
                }
            }
            .navigationTitle("Collection")
        }
    }
}

#Preview {
    CollectionScreen()
        .environment(AppSettings())
        .environment(TTSService())
}
