import SwiftUI
import FirebaseAuth

struct LimitsDashboardView: View {
    @ObservedObject var viewModel: ChatViewModel
    let selectedLanguage: AppLanguage
    
    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "gauge")
                        .foregroundColor(.blue)
                    Text(planTitle)
                        .fontWeight(.semibold)
                    Spacer()
                    if let note = viewModel.adminNote, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if !dailyItems.isEmpty {
                Section(header: Text(selectedLanguage == .russian ? "Дневные лимиты" : "Daily Limits")) {
                    ForEach(dailyItems) { item in
                        LimitRow(
                            title: item.title,
                            icon: item.icon,
                            color: item.color,
                            state: item.state,
                            usage: usage(for: item.id, period: .daily),
                            language: selectedLanguage
                        )
                    }
                }
            }
            
            if !weeklyItems.isEmpty {
                Section(header: Text(selectedLanguage == .russian ? "Недельные лимиты" : "Weekly Limits")) {
                    ForEach(weeklyItems) { item in
                        LimitRow(
                            title: item.title,
                            icon: item.icon,
                            color: item.color,
                            state: item.state,
                            usage: usage(for: item.id, period: .weekly),
                            language: selectedLanguage
                        )
                    }
                }
            }
            
            if !unlimitedItems.isEmpty {
                Section(header: Text(selectedLanguage == .russian ? "Безлимит" : "Unlimited")) {
                    ForEach(unlimitedItems) { item in
                        LimitRow(
                            title: item.title,
                            icon: item.icon,
                            color: item.color,
                            state: item.state,
                            usage: 0,
                            language: selectedLanguage
                        )
                    }
                }
            }
            
            if !lockedItems.isEmpty {
                Section(header: Text(selectedLanguage == .russian ? "Недоступно" : "Locked")) {
                    ForEach(lockedItems) { item in
                        LimitRow(
                            title: item.title,
                            icon: item.icon,
                            color: item.color,
                            state: item.state,
                            usage: 0,
                            language: selectedLanguage
                        )
                    }
                }
            }
        }
        .navigationTitle(selectedLanguage == .russian ? "Лимиты" : "Limits")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Data
    
    private var planTitle: String {
        if viewModel.userSession?.isAnonymous == true {
            return selectedLanguage == .russian ? "Гостевой доступ" : "Guest Access"
        }
        if viewModel.isMax {
            return selectedLanguage == .russian ? "План: Nova Max" : "Plan: Nova Max"
        }
        if viewModel.isPro {
            return selectedLanguage == .russian ? "План: Nova Pro" : "Plan: Nova Pro"
        }
        return selectedLanguage == .russian ? "План: Free" : "Plan: Free"
    }
    
    private var limitItems: [LimitItem] {
        [
            LimitItem(id: "openai-fast", title: modelTitle("openai-fast"), icon: "bolt.fill", color: .orange),
            LimitItem(id: "openai", title: modelTitle("openai"), icon: "sparkles", color: .blue),
            LimitItem(id: "gemini-fast", title: modelTitle("gemini-fast"), icon: "globe", color: .teal),
            LimitItem(id: "mistral", title: modelTitle("mistral"), icon: "brain.head.profile", color: .purple),
            LimitItem(id: "nova-rp", title: modelTitle("nova-rp"), icon: "theatermasks", color: .indigo),
            LimitItem(id: "deepseek", title: modelTitle("deepseek"), icon: "cpu", color: .gray),
            LimitItem(id: "deepthink", title: toolTitle("deepthink"), icon: "brain", color: .purple),
            LimitItem(id: "image", title: toolTitle("image"), icon: "paintpalette.fill", color: .orange),
            LimitItem(id: "deep-research", title: toolTitle("deep-research"), icon: "doc.text.magnifyingglass", color: .indigo)
        ]
    }
    
    private var resolvedItems: [LimitItemResolved] {
        limitItems.map { item in
            LimitItemResolved(id: item.id, title: item.title, icon: item.icon, color: item.color, state: limitState(for: item.id))
        }
    }
    
    private var dailyItems: [LimitItemResolved] {
        resolvedItems.filter { $0.state.period == .daily && !$0.state.locked }
    }
    
    private var weeklyItems: [LimitItemResolved] {
        resolvedItems.filter { $0.state.period == .weekly && !$0.state.locked }
    }
    
    private var unlimitedItems: [LimitItemResolved] {
        resolvedItems.filter { $0.state.unlimited && !$0.state.locked }
    }
    
    private var lockedItems: [LimitItemResolved] {
        resolvedItems.filter { $0.state.locked }
    }
    
    private func modelTitle(_ id: String) -> String {
        if let model = viewModel.availableModels.first(where: { $0.id == id }) {
            return model.name
        }
        return id
    }
    
    private func toolTitle(_ id: String) -> String {
        switch id {
        case "image":
            return selectedLanguage == .russian ? "Генерация изображений" : "Image Generation"
        case "deepthink":
            return "DeepThink"
        case "deep-research":
            return "Deep Research"
        default:
            return id
        }
    }
    
    private func usage(for modelId: String, period: LimitPeriod) -> Int {
        switch period {
        case .daily:
            return viewModel.modelUsage[modelId] ?? 0
        case .weekly:
            return viewModel.weeklyModelUsage[modelId] ?? 0
        case .none:
            return 0
        }
    }
    
    private func limitState(for modelId: String) -> LimitState {
        if viewModel.userSession?.isAnonymous == true {
            return modelId == "mistral"
                ? LimitState(unlimited: true)
                : LimitState(locked: true)
        }
        
        if viewModel.isMax {
            if modelId == "deepthink" { return LimitState(limit: 30, period: .daily) }
            if modelId == "image-elite" { return LimitState(limit: 20, period: .daily) }
            if modelId == "deep-research" { return LimitState(limit: 10, period: .weekly) }
            if modelId == "nova-rp" { return LimitState(limit: 150, period: .weekly) }
            if modelId == "deepseek" { return LimitState(limit: 200, period: .weekly) }
            return LimitState(unlimited: true)
        }
        
        if viewModel.isPro {
            if modelId == "deepthink" || modelId == "image-elite" || modelId == "deep-research" {
                return LimitState(locked: true)
            }
            if modelId == "openai" { return LimitState(limit: 100, period: .daily) }
            if modelId == "nova-rp" { return LimitState(limit: 50, period: .weekly) }
            if modelId == "deepseek" { return LimitState(limit: 60, period: .weekly) }
            return LimitState(unlimited: true)
        }
        
        // Free
        if modelId == "mistral" || modelId == "gemini-fast" { return LimitState(unlimited: true) }
        if modelId == "image" { return LimitState(limit: 20, period: .daily) }
        if modelId == "openai-fast" { return LimitState(limit: 10, period: .daily) }
        if modelId == "nova-rp" { return LimitState(limit: 5, period: .daily) }
        if modelId == "deep-research" { return LimitState(locked: true) }
        return LimitState(locked: true)
    }
}

private struct LimitItem {
    let id: String
    let title: String
    let icon: String
    let color: Color
}

private struct LimitItemResolved: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let state: LimitState
}

private enum LimitPeriod {
    case daily
    case weekly
    case none
}

private struct LimitState {
    let limit: Int?
    let period: LimitPeriod
    let locked: Bool
    let unlimited: Bool
    
    init(limit: Int, period: LimitPeriod) {
        self.limit = limit
        self.period = period
        self.locked = false
        self.unlimited = false
    }
    
    init(locked: Bool = false, unlimited: Bool = false) {
        self.limit = nil
        self.period = .none
        self.locked = locked
        self.unlimited = unlimited
    }
}

private struct LimitRow: View {
    let title: String
    let icon: String
    let color: Color
    let state: LimitState
    let usage: Int
    let language: AppLanguage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundColor(color)
                    )
                
                Text(title)
                    .font(.body)
                
                Spacer()
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let limit = state.limit, !state.locked {
                ProgressView(value: progressValue(limit: limit))
                    .tint(color)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusText: String {
        if state.locked {
            return language == .russian ? "Недоступно" : "Locked"
        }
        if state.unlimited {
            return language == .russian ? "Безлимит" : "Unlimited"
        }
        if let limit = state.limit {
            let periodText = state.period == .weekly
                ? (language == .russian ? "нед." : "wk")
                : (language == .russian ? "день" : "day")
            return "\(usage)/\(limit) · \(periodText)"
        }
        return ""
    }
    
    private func progressValue(limit: Int) -> Double {
        guard limit > 0 else { return 0 }
        return min(Double(usage) / Double(limit), 1.0)
    }
}
