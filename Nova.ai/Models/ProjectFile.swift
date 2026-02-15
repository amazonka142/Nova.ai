import Foundation
import SwiftData

@Model
final class ProjectFile {
    var id: UUID
    var name: String
    var type: String
    var content: String
    var createdAt: Date
    
    init(name: String, type: String, content: String) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.content = content
        self.createdAt = Date()
    }
}
