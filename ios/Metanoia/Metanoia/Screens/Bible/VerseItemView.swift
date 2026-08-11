import SwiftUI

struct VerseItemView: View {
    let verse: Verse
    let fontSize: CGFloat
    let highlight: Highlight?
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isInterlinearExpanded = false
    @State private var interlinearWords: [InterlinearWord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: MetanoiaTheme.Spacing.sm) {
            HStack(alignment: .top, spacing: MetanoiaTheme.Spacing.sm) {
                Text("\(verse.number)")
                    .font(.system(size: MetanoiaTheme.FontSize.caption, weight: .bold))
                    .foregroundStyle(MetanoiaTheme.primary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: MetanoiaTheme.Spacing.xs) {
                    Text(verse.text)
                        .font(.system(size: fontSize))
                        .foregroundStyle(MetanoiaTheme.text)
                        .lineSpacing(fontSize * 0.4)

                    if isInterlinearExpanded {
                        interlinearView
                    }
                }

                Spacer()

                if highlight != nil {
                    noteIndicator
                }
            }
            .padding(MetanoiaTheme.Spacing.md)
            .background(highlightColor)
            .clipShape(RoundedRectangle(cornerRadius: MetanoiaTheme.CornerRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: MetanoiaTheme.CornerRadius.sm)
                    .stroke(highlight != nil ? Color.clear : MetanoiaTheme.surfaceBright, lineWidth: 1)
            )
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isInterlinearExpanded.toggle()
                if isInterlinearExpanded && interlinearWords.isEmpty {
                    loadInterlinear()
                }
            }
            onTap()
        }
        .onLongPressGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            onLongPress()
        }
    }

    private var highlightColor: Color {
        guard let highlight else { return MetanoiaTheme.surface }
        switch highlight.color {
        case 0: return Color.yellow.opacity(0.2)
        case 1: return Color.green.opacity(0.2)
        case 2: return Color.blue.opacity(0.2)
        case 3: return Color.purple.opacity(0.2)
        case 4: return Color.red.opacity(0.2)
        default: return MetanoiaTheme.surface
        }
    }

    private var noteIndicator: some View {
        VStack {
            Image(systemName: "note.text")
                .font(.system(size: MetanoiaTheme.FontSize.caption))
                .foregroundStyle(MetanoiaTheme.warning)
            Spacer()
        }
    }

    private var interlinearView: some View {
        VStack(alignment: .leading, spacing: MetanoiaTheme.Spacing.sm) {
            Divider()
                .background(MetanoiaTheme.textDim.opacity(0.3))

            Text("Interlinear")
                .font(.system(size: MetanoiaTheme.FontSize.caption, weight: .semibold))
                .foregroundStyle(MetanoiaTheme.accent)

            ForEach(interlinearWords) { word in
                HStack(alignment: .top, spacing: MetanoiaTheme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(word.originalText)
                            .font(.system(size: MetanoiaTheme.FontSize.body, weight: .medium))
                            .foregroundStyle(MetanoiaTheme.secondary)

                        Text(word.translation)
                            .font(.system(size: MetanoiaTheme.FontSize.caption))
                            .foregroundStyle(MetanoiaTheme.textDim)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(word.translation)
                            .font(.system(size: MetanoiaTheme.FontSize.caption))
                            .foregroundStyle(MetanoiaTheme.text)

                        Text(word.strongs)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(MetanoiaTheme.primary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(MetanoiaTheme.primary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func loadInterlinear() {
        interlinearWords = [
            InterlinearWord(book: verse.book, chapter: verse.chapter, verse: verse.number, wordIndex: 0, originalText: "ὅτι", translation: "For", strongs: "G3754"),
            InterlinearWord(book: verse.book, chapter: verse.chapter, verse: verse.number, wordIndex: 1, originalText: "ὁ θεὸς", translation: "God", strongs: "G2316"),
            InterlinearWord(book: verse.book, chapter: verse.chapter, verse: verse.number, wordIndex: 2, originalText: "οὕτως", translation: "so", strongs: "G3779"),
            InterlinearWord(book: verse.book, chapter: verse.chapter, verse: verse.number, wordIndex: 3, originalText: "ἠγάπησεν", translation: "loved", strongs: "G25"),
        ]
    }
}

#Preview {
    let verse = Verse(book: "JHN", chapter: 3, number: 16, text: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.")

    ZStack {
        MetanoiaTheme.background.ignoresSafeArea()
        ScrollView {
            VerseItemView(
                verse: verse,
                fontSize: MetanoiaTheme.FontSize.body,
                highlight: nil,
                onTap: {},
                onLongPress: {}
            )
            .padding()
        }
    }
}
