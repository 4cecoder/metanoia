import SwiftUI

struct FavoritesView: View {
    @State private var favorites: [Favorite] = []
    @State private var selectedEntry: Favorite?
    
    var body: some View {
        Group {
            if favorites.isEmpty {
                ContentUnavailableView(
                    "No Favorites Yet",
                    systemImage: "star.slash",
                    description: Text("Save lexicon entries while reading to review them here.")
                )
            } else {
                List {
                    ForEach(favorites) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            FavoriteRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteFavorites)
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $selectedEntry) { entry in
            LexiconDetailView(entry: entry)
        }
        .onAppear(perform: loadFavorites)
    }
    
    private func deleteFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        saveFavorites()
    }
    
    private func saveFavorites() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: "favorites")
    }
    
    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: "favorites"),
              let decoded = try? JSONDecoder().decode([Favorite].self, from: data) else { return }
        favorites = decoded
    }
}

private struct FavoriteRow: View {
    let entry: Favorite
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.lemma)
                    .font(.headline)
                Text(entry.strongs)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .clipShape(Capsule())
                Spacer()
            }
            Text(entry.definition)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

private struct LexiconDetailView: View {
    let entry: Favorite
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    detailSection
                }
                .padding()
            }
            .navigationTitle(entry.lemma)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.lemma)
                .font(.largeTitle.bold())
            Label(entry.strongs, systemImage: "number")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var detailSection: some View {
        GroupBox("Definition") {
            Text(entry.definition)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    FavoritesView()
}
