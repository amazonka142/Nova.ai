import Foundation
import SwiftData

@Model
final class ChatSession {
    @Attribute(originalName: "id") var uuid: UUID?
    var title: String
    @Relationship(deleteRule: .cascade) var messages: [Message]
    var model: String
    var lastModified: Date
    var folder: ChatFolder?
    @Relationship(deleteRule: .nullify) var project: Project?
    
    init(title: String = "New Chat", model: String = "openai", project: Project? = nil) {
        self.uuid = UUID()
        self.title = title
        self.messages = []
        self.model = model
        self.lastModified = Date()
        self.project = project
    }
    
    func ensureUUID() -> UUID {
        if let existing = uuid { return existing }
        let newValue = UUID()
        uuid = newValue
        return newValue
    }
}
