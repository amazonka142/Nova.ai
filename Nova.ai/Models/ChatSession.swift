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
    
    init(title: String = "New Chat", model: String = "openai") {
        self.uuid = UUID()
        self.title = title
        self.messages = []
        self.model = model
        self.lastModified = Date()
    }
}
