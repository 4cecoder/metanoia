import SwiftUI

struct BookCard: View {
    let book: BibleBook
    let completedChapters: Set<Int>
    let onTap: () -> Void

    private var isCompleted: Bool {
        completedChapters.count >= book.chapterCount
    }

    private var progressFraction: Double {
        guard book.chapterCount > 0 else { return 0 }
        return Double(completedChapters.count) / Double(book.chapterCount)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: MetanoiaTheme.Spacing.sm) {
                HStack {
                    if isCompleted {
                        Circle()
                            .fill(MetanoiaTheme.secondary)
                            .frame(width: 8, height: 8)
                    }
                    Spacer()
                }
                .frame(height: 8)

                Text(book.name)
                    .font(.system(size: MetanoiaTheme.FontSize.body, weight: .semibold))
                    .foregroundStyle(MetanoiaTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("\(book.chapterCount) ch")
                    .font(.system(size: MetanoiaTheme.FontSize.caption, weight: .medium))
                    .foregroundStyle(MetanoiaTheme.textDim)

                if !completedChapters.isEmpty && !isCompleted {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(MetanoiaTheme.surfaceBright)
                                .frame(height: 3)
                            Capsule()
                                .fill(MetanoiaTheme.primary)
                                .frame(width: geometry.size.width * progressFraction, height: 3)
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(MetanoiaTheme.Spacing.md)
            .background(MetanoiaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: MetanoiaTheme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: MetanoiaTheme.CornerRadius.md)
                    .stroke(isCompleted ? MetanoiaTheme.secondary.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        MetanoiaTheme.background.ignoresSafeArea()
        BookCard(
            book: BibleBook.allBooks[0],
            completedChapters: Set(1...10),
            onTap: {}
        )
        .frame(width: 120, height: 120)
    }
}
