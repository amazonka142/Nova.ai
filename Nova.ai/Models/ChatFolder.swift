import Foundation
import SwiftData

@Model
final class ChatFolder {
    var id: UUID
    var name: String
    var emoji: String
    var creationDate: Date
    
    @Relationship(deleteRule: .nullify, inverse: \ChatSession.folder)
    var sessions: [ChatSession]? = []
    
    init(name: String, emoji: String) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.creationDate = Date()
    }
}
