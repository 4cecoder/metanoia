import SwiftUI

struct ChapterGridView: View {
    let book: BibleBook
    @Binding var selectedChapter: Int?
    let completedChapters: Set<Int>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: MetanoiaTheme.Spacing.md), count: 5)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MetanoiaTheme.Spacing.xl) {
                headerSection

                LazyVGrid(columns: columns, spacing: MetanoiaTheme.Spacing.lg) {
                    ForEach(1...book.chapterCount, id: \.self) { chapter in
                        ChapterCard(
                            chapter: chapter,
                            isRead: completedChapters.contains(chapter),
                            isDownloaded: false,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedChapter = chapter
                                }
                            }
                        )
                    }
                }
                .padding(MetanoiaTheme.Spacing.lg)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: MetanoiaTheme.Spacing.sm) {
            Text(book.name)
                .font(.system(size: MetanoiaTheme.FontSize.largeTitle, weight: .bold))
                .foregroundStyle(MetanoiaTheme.text)

            Text("\(book.chapterCount) chapters")
                .font(.system(size: MetanoiaTheme.FontSize.body))
                .foregroundStyle(MetanoiaTheme.textDim)

            let readCount = completedChapters.count
            let fraction = Double(readCount) / Double(book.chapterCount)

            HStack {
                Text("\(readCount)/\(book.chapterCount) read")
                    .font(.system(size: MetanoiaTheme.FontSize.caption))
                    .foregroundStyle(MetanoiaTheme.textDim)

                Spacer()

                Text("\(Int(fraction * 100))%")
                    .font(.system(size: MetanoiaTheme.FontSize.caption, weight: .medium))
                    .foregroundStyle(MetanoiaTheme.primary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MetanoiaTheme.surfaceBright)
                        .frame(height: 4)
                    Capsule()
                        .fill(MetanoiaTheme.primary)
                        .frame(width: geometry.size.width * fraction, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(MetanoiaTheme.Spacing.lg)
    }
}

#Preview {
    ZStack {
        MetanoiaTheme.background.ignoresSafeArea()
        ChapterGridView(
            book: BibleBook.allBooks[0],
            selectedChapter: .constant(nil),
            completedChapters: [1, 2, 3]
        )
    }
}
