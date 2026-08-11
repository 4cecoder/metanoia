import SwiftUI

struct VerseListView: View {
    let verses: [Verse]
    let fontSize: CGFloat
    let highlights: [String: Highlight]
    let onVerseTap: (Verse) -> Void
    let onVerseLongPress: (Verse) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MetanoiaTheme.Spacing.lg) {
                    ForEach(verses) { verse in
                        VerseItemView(
                            verse: verse,
                            fontSize: fontSize,
                            highlight: highlights[verse.id],
                            onTap: { onVerseTap(verse) },
                            onLongPress: { onVerseLongPress(verse) }
                        )
                        .id(verse.id)
                    }
                }
                .padding(MetanoiaTheme.Spacing.lg)
            }
        }
    }
}

#Preview {
    let sampleVerses = [
        Verse(book: "JHN", chapter: 3, number: 16, text: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life."),
        Verse(book: "JHN", chapter: 3, number: 17, text: "For God did not send his Son into the world to condemn the world, but to save the world through him.")
    ]

    ZStack {
        MetanoiaTheme.background.ignoresSafeArea()
        VerseListView(
            verses: sampleVerses,
            fontSize: MetanoiaTheme.FontSize.body,
            highlights: [:],
            onVerseTap: { _ in },
            onVerseLongPress: { _ in }
        )
    }
}
