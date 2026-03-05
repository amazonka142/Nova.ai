import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum MessageType: String, Codable {
    case text
    case image
    // Future: tool_use, audio, etc.
}

enum FeedbackStatus: String, Codable {
    case none
    case liked
    case disliked
}

@Model
final class Message {
    var id: UUID
    var role: MessageRole
    var content: String
    var type: MessageType
    var timestamp: Date
    @Attribute(.externalStorage) var imageData: Data? // Store images efficiently
    var feedback: FeedbackStatus? = FeedbackStatus.none // Optional for safer migration
    
    // Relationship - inverse is optional to avoid strict dependency cycles during init
    // var session: ChatSession? 
    
    init(role: MessageRole, content: String, type: MessageType = .text, imageData: Data? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.type = type
        self.imageData = imageData
        self.timestamp = Date()
        self.feedback = FeedbackStatus.none
    }
}
