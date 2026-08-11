import SwiftUI

struct SearchView: View {
    @Binding var isPresented: Bool
    let onNavigate: (BibleBook, Int, Int) -> Void

    @State private var searchText = ""
    @State private var searchResults: [BibleSearchResult] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            ZStack {
                MetanoiaTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar

                    if isSearching {
                        ProgressView()
                            .tint(MetanoiaTheme.primary)
                            .frame(maxHeight: .infinity)
                    } else if searchResults.isEmpty && !searchText.isEmpty {
                        emptyState
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(MetanoiaTheme.primary)
                }
            }
            .toolbarBackground(MetanoiaTheme.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MetanoiaTheme.textDim)

            TextField("Search or enter reference", text: $searchText)
                .font(.system(size: MetanoiaTheme.FontSize.body))
                .foregroundStyle(MetanoiaTheme.text)
                .tint(MetanoiaTheme.primary)
                .onSubmit {
                    performSearch()
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    searchResults = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MetanoiaTheme.textDim)
                }
            }
        }
        .padding(MetanoiaTheme.Spacing.md)
        .background(MetanoiaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: MetanoiaTheme.CornerRadius.md))
        .padding(MetanoiaTheme.Spacing.lg)
    }

    private var emptyState: some View {
        VStack(spacing: MetanoiaTheme.Spacing.lg) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(MetanoiaTheme.textDim)

            Text("No results found")
                .font(.system(size: MetanoiaTheme.FontSize.title3, weight: .semibold))
                .foregroundStyle(MetanoiaTheme.text)

            Text("Try searching for a word or reference")
                .font(.system(size: MetanoiaTheme.FontSize.body))
                .foregroundStyle(MetanoiaTheme.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxHeight: .infinity)
        .padding(MetanoiaTheme.Spacing.xl)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { result in
                    Button(action: {
                        onNavigate(result.book, result.chapter, result.verse)
                    }) {
                        HStack(alignment: .top, spacing: MetanoiaTheme.Spacing.md) {
                            VStack(alignment: .leading, spacing: MetanoiaTheme.Spacing.xs) {
                                Text(result.reference)
                                    .font(.system(size: MetanoiaTheme.FontSize.body, weight: .semibold))
                                    .foregroundStyle(MetanoiaTheme.primary)

                                Text(result.text)
                                    .font(.system(size: MetanoiaTheme.FontSize.caption))
                                    .foregroundStyle(MetanoiaTheme.text)
                                    .lineLimit(3)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: MetanoiaTheme.FontSize.caption))
                                .foregroundStyle(MetanoiaTheme.textDim)
                        }
                        .padding(MetanoiaTheme.Spacing.lg)
                        .background(MetanoiaTheme.surface)

                        Divider()
                            .background(MetanoiaTheme.surfaceBright)
                            .padding(.leading, MetanoiaTheme.Spacing.lg)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isSearching = true

        if let parsed = parseReference(searchText) {
            searchResults = [parsed]
            isSearching = false
            return
        }

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            searchResults = generatePlaceholderResults(for: searchText)
            isSearching = false
        }
    }

    private func parseReference(_ text: String) -> BibleSearchResult? {
        let pattern = #"^(\d?\s?[A-Za-z]+)\s+(\d+):(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        let bookName = String(text[Range(match.range(at: 1), in: text)!])
        let chapter = Int(text[Range(match.range(at: 2), in: text)!]) ?? 1
        let verse = Int(text[Range(match.range(at: 3), in: text)!]) ?? 1

        guard let book = BibleBook.book(byName: bookName) else { return nil }

        return BibleSearchResult(
            book: book,
            chapter: chapter,
            verse: verse,
            text: "\(book.name) \(chapter):\(verse)"
        )
    }

    private func generatePlaceholderResults(for query: String) -> [BibleSearchResult] {
        guard let book = BibleBook.book(byName: query) else {
            return [
                BibleSearchResult(
                    book: BibleBook.allBooks[0],
                    chapter: 1,
                    verse: 1,
                    text: "Sample result for search query"
                )
            ]
        }

        return [
            BibleSearchResult(book: book, chapter: 1, verse: 1, text: "\(book.name) chapter 1, verse 1 - matching search..."),
            BibleSearchResult(book: book, chapter: 1, verse: 2, text: "\(book.name) chapter 1, verse 2 - another match...")
        ]
    }
}

struct BibleSearchResult: Identifiable {
    let id = UUID()
    let book: BibleBook
    let chapter: Int
    let verse: Int
    let text: String

    var reference: String {
        "\(book.name) \(chapter):\(verse)"
    }
}

#Preview {
    SearchView(isPresented: .constant(true)) { _, _, _ in }
}
