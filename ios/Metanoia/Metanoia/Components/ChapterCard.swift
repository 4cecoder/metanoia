import SwiftUI

struct ChapterCard: View {
    let chapter: Int
    let isRead: Bool
    let isDownloaded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: MetanoiaTheme.Spacing.xs) {
                ZStack {
                    Circle()
                        .fill(isRead ? MetanoiaTheme.secondary.opacity(0.2) : MetanoiaTheme.surfaceBright)
                        .frame(width: 52, height: 52)

                    Text("\(chapter)")
                        .font(.system(size: MetanoiaTheme.FontSize.title3, weight: .semibold))
                        .foregroundStyle(isRead ? MetanoiaTheme.secondary : MetanoiaTheme.text)
                }

                if isDownloaded {
                    Circle()
                        .fill(MetanoiaTheme.primary)
                        .frame(width: 4, height: 4)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        MetanoiaTheme.background.ignoresSafeArea()
        HStack(spacing: 20) {
            ChapterCard(chapter: 1, isRead: true, isDownloaded: true, onTap: {})
            ChapterCard(chapter: 2, isRead: false, isDownloaded: false, onTap: {})
            ChapterCard(chapter: 3, isRead: false, isDownloaded: true, onTap: {})
        }
    }
}
