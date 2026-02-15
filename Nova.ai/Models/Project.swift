import SwiftUI
import SwiftData

enum ProjectMemoryScope: String, CaseIterable, Codable {
    case shared
    case projectOnly
}

@Model
final class Project {
    var id: UUID
    var name: String
    var icon: String
    var themeColorHex: String
    var createdAt: Date
    var memoryScopeRaw: String?
    var customSystemPrompt: String?
    @Relationship(deleteRule: .cascade) var knowledgeBase: [ProjectFile]
    @Relationship(deleteRule: .cascade, inverse: \ChatSession.project) var chats: [ChatSession]
    
    init(
        name: String,
        icon: String,
        themeColor: Color,
        memoryScope: ProjectMemoryScope = .shared,
        customSystemPrompt: String? = nil,
        knowledgeBase: [ProjectFile] = []
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.themeColorHex = themeColor.toHex()
        self.createdAt = Date()
        self.memoryScopeRaw = memoryScope.rawValue
        self.customSystemPrompt = customSystemPrompt
        self.knowledgeBase = knowledgeBase
        self.chats = []
    }
    
    var themeColor: Color {
        get { Color(hex: themeColorHex) }
        set { themeColorHex = newValue.toHex() }
    }
    
    var memoryScope: ProjectMemoryScope {
        get {
            if let raw = memoryScopeRaw, let scope = ProjectMemoryScope(rawValue: raw) {
                return scope
            }
            memoryScopeRaw = ProjectMemoryScope.shared.rawValue
            return .shared
        }
        set { memoryScopeRaw = newValue.rawValue }
    }
}
