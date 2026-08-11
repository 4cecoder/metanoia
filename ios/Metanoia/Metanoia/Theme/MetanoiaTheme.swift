import SwiftUI

enum MetanoiaTheme {
    static let background = Color(red: 0.10, green: 0.10, blue: 0.15)
    static let surface = Color(red: 0.13, green: 0.13, blue: 0.18)
    static let surfaceBright = Color(red: 0.16, green: 0.16, blue: 0.21)
    static let primary = Color(red: 0.48, green: 0.64, blue: 0.97)
    static let secondary = Color(red: 0.55, green: 0.82, blue: 0.76)
    static let accent = Color(red: 0.75, green: 0.54, blue: 0.84)
    static let text = Color(red: 0.83, green: 0.84, blue: 0.88)
    static let textDim = Color(red: 0.50, green: 0.51, blue: 0.56)
    static let error = Color(red: 0.95, green: 0.36, blue: 0.36)
    static let warning = Color(red: 0.99, green: 0.67, blue: 0.36)

    enum FontSize {
        static let caption: CGFloat = 12
        static let body: CGFloat = 16
        static let title3: CGFloat = 18
        static let title2: CGFloat = 22
        static let title: CGFloat = 28
        static let largeTitle: CGFloat = 34
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum CornerRadius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
    }
}
