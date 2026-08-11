import SwiftUI

struct BookGridView: View {
    @Binding var selectedBook: BibleBook?
    let completedChapters: [String: Set<Int>]

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: MetanoiaTheme.Spacing.md)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MetanoiaTheme.Spacing.xl) {
                ForEach(BibleSection.allCases) { section in
                    let books = BibleBook.books(for: section)
                    if !books.isEmpty {
                        sectionView(section: section, books: books)
                    }
                }
            }
            .padding(MetanoiaTheme.Spacing.lg)
        }
    }

    private func sectionView(section: BibleSection, books: [BibleBook]) -> some View {
        VStack(alignment: .leading, spacing: MetanoiaTheme.Spacing.md) {
            Text(section.rawValue)
                .font(.system(size: MetanoiaTheme.FontSize.title3, weight: .bold))
                .foregroundStyle(MetanoiaTheme.accent)
                .padding(.horizontal, MetanoiaTheme.Spacing.xs)

            LazyVGrid(columns: columns, spacing: MetanoiaTheme.Spacing.md) {
                ForEach(books) { book in
                    BookCard(
                        book: book,
                        completedChapters: completedChapters[book.id] ?? [],
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedBook = book
                            }
                        }
                    )
                }
            }
        }
    }
}

#Preview {
    ZStack {
        MetanoiaTheme.background.ignoresSafeArea()
        BookGridView(
            selectedBook: .constant(nil),
            completedChapters: [:]
        )
    }
}
