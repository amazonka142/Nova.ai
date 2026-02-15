import Foundation
import SwiftUI
import SwiftData

enum UserPlan {
    case free
    case pro
    case max
}

enum ProjectManagerError: Error {
    case limitReached
}

final class ProjectManager {
    private let context: ModelContext
    
    init(context: ModelContext) {
        self.context = context
    }
    
    func maxProjects(for plan: UserPlan) -> Int? {
        switch plan {
        case .free: return 1
        case .pro: return 5
        case .max: return nil
        }
    }
    
    func canCreateProject(plan: UserPlan) -> Bool {
        if let max = maxProjects(for: plan) {
            return projectCount() < max
        }
        return true
    }
    
    func assertCanCreateProject(plan: UserPlan) throws {
        if !canCreateProject(plan: plan) {
            throw ProjectManagerError.limitReached
        }
    }
    
    func projectCount() -> Int {
        let descriptor = FetchDescriptor<Project>()
        return (try? context.fetch(descriptor).count) ?? 0
    }
    
    func createProject(name: String, icon: String, themeColor: Color, memoryScope: ProjectMemoryScope, plan: UserPlan) throws -> Project {
        try assertCanCreateProject(plan: plan)
        let project = Project(name: name, icon: icon, themeColor: themeColor, memoryScope: memoryScope)
        context.insert(project)
        try context.save()
        return project
    }
    
    func ensureDefaultProject() throws -> Project {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.createdAt, order: .forward)])
        if let existing = try? context.fetch(descriptor), let first = existing.first {
            return first
        }
        let project = Project(name: "Внешние чаты", icon: "📝", themeColor: .blue, memoryScope: .shared)
        context.insert(project)
        try context.save()
        return project
    }
}
