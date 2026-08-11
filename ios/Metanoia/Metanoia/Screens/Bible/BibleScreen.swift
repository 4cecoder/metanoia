import SwiftUI

struct BibleScreen: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TTSService.self) private var ttsService

    @State private var selectedBook: BibleBook?
    @State private var selectedChapter: Int?
    @State private var searchText = ""
    @State private var verses: [Verse] = []
    @State private var isLoading = false
    @State private var showSearch = false
    @State private var isPlaying = false
    @State private var completedChapters: [String: Set<Int>] = [:]
    @State private var highlights: [String: Highlight] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                MetanoiaTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar

                    if selectedBook == nil {
                        BookGridView(
                            selectedBook: $selectedBook,
                            completedChapters: completedChapters
                        )
                    } else if selectedChapter == nil {
                        ChapterGridView(
                            book: selectedBook!,
                            selectedChapter: $selectedChapter,
                            completedChapters: completedChapters[selectedBook!.id] ?? []
                        )
                    } else {
                        verseReaderView
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedBook != nil {
                        Button(action: navigateBack) {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(MetanoiaTheme.primary)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: MetanoiaTheme.Spacing.md) {
                        Button(action: { showSearch = true }) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(MetanoiaTheme.text)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSearch) {
                SearchView(isPresented: $showSearch) { book, chapter, verse in
                    selectedBook = book
                    selectedChapter = chapter
                    showSearch = false
                    Task {
                        await loadVerses(bookId: book.id, chapter: chapter)
                    }
                }
            }
            .toolbarBackground(MetanoiaTheme.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(MetanoiaTheme.primary)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MetanoiaTheme.textDim)

            TextField("Search Bible...", text: $searchText)
                .font(.system(size: settings.englishFontSize))
                .foregroundStyle(MetanoiaTheme.text)
                .tint(MetanoiaTheme.primary)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MetanoiaTheme.textDim)
                }
            }
        }
        .padding(MetanoiaTheme.Spacing.md)
        .background(MetanoiaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: MetanoiaTheme.CornerRadius.md))
        .padding(.horizontal, MetanoiaTheme.Spacing.lg)
        .padding(.vertical, MetanoiaTheme.Spacing.sm)
    }

    private var verseReaderView: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .tint(MetanoiaTheme.primary)
                    .frame(maxHeight: .infinity)
            } else {
                VerseListView(
                    verses: verses,
                    fontSize: settings.englishFontSize,
                    highlights: highlights,
                    onVerseTap: { _ in },
                    onVerseLongPress: { verse in
                        toggleHighlight(for: verse)
                    }
                )
            }

            bottomToolbar
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: MetanoiaTheme.Spacing.xl) {
            Button(action: {
                Task {
                    await loadVerses(bookId: selectedBook?.id ?? "", chapter: max(1, (selectedChapter ?? 1) - 1))
                }
            }) {
                Image(systemName: "backward.fill")
                    .foregroundStyle(MetanoiaTheme.primary)
            }
            .disabled(selectedChapter ?? 1 <= 1)

            Spacer()

            Button(action: { isPlaying.toggle() }) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: MetanoiaTheme.FontSize.title3))
                    .foregroundStyle(MetanoiaTheme.primary)
            }

            Spacer()

            Button(action: {
                Task {
                    await loadVerses(bookId: selectedBook?.id ?? "", chapter: min(selectedBook?.chapterCount ?? 1, (selectedChapter ?? 1) + 1))
                }
            }) {
                Image(systemName: "forward.fill")
                    .foregroundStyle(MetanoiaTheme.primary)
            }
            .disabled(selectedChapter ?? 1 >= (selectedBook?.chapterCount ?? 1))
        }
        .padding(MetanoiaTheme.Spacing.lg)
        .background(MetanoiaTheme.surface)
    }

    private var navigationTitle: String {
        if let book = selectedBook, let chapter = selectedChapter {
            return "\(book.name) \(chapter)"
        } else if let book = selectedBook {
            return book.name
        }
        return "Bible"
    }

    private func navigateBack() {
        if selectedChapter != nil {
            selectedChapter = nil
            verses = []
        } else if selectedBook != nil {
            selectedBook = nil
        }
    }

    private func loadVerses(bookId: String, chapter: Int) async {
        isLoading = true
        defer { isLoading = false }

        selectedBook = BibleBook.book(byId: bookId)
        selectedChapter = chapter

        verses = (1...25).map { i in
            Verse(book: bookId, chapter: chapter, number: i, text: "Sample verse text for \(bookId) \(chapter):\(i). This is placeholder content for the Bible reader interface.")
        }
    }

    private func toggleHighlight(for verse: Verse) {
        let key = verse.id
        if highlights[key] != nil {
            highlights.removeValue(forKey: key)
        } else {
            highlights[key] = Highlight(book: verse.book, chapter: verse.chapter, verse: verse.number, color: 0)
        }
        if settings.hapticFeedbackEnabled {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
    }
}

#Preview {
    BibleScreen()
        .environment(AppSettings())
        .environment(TTSService())
}
