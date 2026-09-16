import SwiftUI

enum FolderTheme: String, CaseIterable, Identifiable {
    case `default`, cream, pink, blue, green, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .default: "기본"
        case .cream: "크림"
        case .pink: "핑크"
        case .blue: "블루"
        case .green: "그린"
        case .dark: "다크"
        }
    }
    var color: Color {
        switch self {
        case .default: .primary
        case .cream: .orange
        case .pink: .pink
        case .blue: .blue
        case .green: .green
        case .dark: .secondary
        }
    }
}
