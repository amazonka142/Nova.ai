import SwiftUI

enum ChatTool: Equatable {
    case none
    case reasoning
    case search
    case image

    var title: String {
        switch self {
        case .none: return ""
        case .reasoning: return "Думать"
        case .search: return "Поиск"
        case .image: return "Рисовать"
        }
    }

    var icon: String {
        switch self {
        case .none: return ""
        case .reasoning: return "brain.head.profile"
        case .search: return "globe"
        case .image: return "paintpalette.fill"
        }
    }

    var color: Color {
        switch self {
        case .none: return .clear
        case .reasoning: return .purple
        case .search: return .blue
        case .image: return .orange
        }
    }
}
