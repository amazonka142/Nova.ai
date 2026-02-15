import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ProjectSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ChatViewModel
    @Bindable var project: Project
    let selectedLanguage: AppLanguage
    
    @State private var showFileImporter = false
    @State private var showKnowledgeLimitAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        
                        Text(selectedLanguage == .russian
                             ? "Управляйте именем, памятью и базой знаний проекта."
                             : "Manage name, memory, and knowledge base for this project.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        
                        generalCard
                        memoryCard
                        brainCard
                        knowledgeCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onDisappear {
            viewModel.persistChanges()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: knowledgeFileTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let addResult = viewModel.addKnowledgeFile(to: project, url: url)
                    if case let .failure(error) = addResult {
                        if let kbError = error as? ChatViewModel.KnowledgeBaseError,
                           case .limitReached = kbError {
                            showKnowledgeLimitAlert = true
                        } else {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .alert(
            selectedLanguage == .russian ? "Лимит файлов" : "File Limit",
            isPresented: $showKnowledgeLimitAlert
        ) {
            Button(selectedLanguage == .russian ? "Обновить тариф" : "Upgrade") {
                viewModel.showSubscription = true
            }
            Button(selectedLanguage == .russian ? "Ок" : "OK", role: .cancel) { }
        } message: {
            Text(selectedLanguage == .russian
                 ? "Достигнут лимит файлов для базы знаний этого проекта."
                 : "You’ve reached the knowledge base file limit for this project.")
        }
    }
    
    private var header: some View {
        HStack {
            Circle()
                .fill(Color(.secondarySystemBackground))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.secondary)
                )
            
            Spacer()
            
            Text(selectedLanguage == .russian ? "Настройки проекта" : "Project Settings")
                .font(.headline)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                    )
            }
        }
    }
    
    private var generalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedLanguage == .russian ? "Основные" : "General")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            TextField(selectedLanguage == .russian ? "Название проекта" : "Project name", text: $project.name)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            HStack(spacing: 12) {
                TextField(selectedLanguage == .russian ? "Emoji / символ" : "Emoji / symbol", text: $project.icon)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                ColorPicker("", selection: Binding(
                    get: { project.themeColor },
                    set: { project.themeColor = $0 }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            HStack(spacing: 10) {
                ForEach(colorOptions.indices, id: \.self) { index in
                    let swatch = colorOptions[index]
                    let isSelected = project.themeColor.toHex() == swatch.toHex()
                    Circle()
                        .fill(swatch)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(isSelected ? 0.9 : 0.2), lineWidth: isSelected ? 2 : 1)
                        )
                        .onTapGesture { project.themeColor = swatch }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    
    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedLanguage == .russian ? "Память проекта" : "Project Memory")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                memoryOptionButton(
                    title: selectedLanguage == .russian ? "Общая память" : "Shared",
                    subtitle: selectedLanguage == .russian ? "Проект и внешние чаты делятся памятью" : "Shared with other chats",
                    isSelected: project.memoryScope == .shared
                ) {
                    project.memoryScope = .shared
                }
                
                memoryOptionButton(
                    title: selectedLanguage == .russian ? "Только проект" : "Project only",
                    subtitle: selectedLanguage == .russian ? "Память изолирована внутри проекта" : "Isolated inside this project",
                    isSelected: project.memoryScope == .projectOnly
                ) {
                    project.memoryScope = .projectOnly
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    
    private var brainCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedLanguage == .russian ? "Мозг проекта" : "Project Brain")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if viewModel.isMax {
                TextEditor(text: Binding(
                    get: { project.customSystemPrompt ?? "" },
                    set: { project.customSystemPrompt = $0 }
                ))
                .frame(minHeight: 160)
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                lockedCard(
                    title: selectedLanguage == .russian ? "Мозг проекта" : "Project Brain",
                    subtitle: selectedLanguage == .russian ? "Доступно только в Nova Max" : "Available in Nova Max"
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    
    private var knowledgeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedLanguage == .russian ? "База знаний" : "Knowledge Base")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if viewModel.isMax {
                Button(action: { showFileImporter = true }) {
                    Label(selectedLanguage == .russian ? "Добавить файл" : "Add File", systemImage: "paperclip")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                Text(knowledgeLimitText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if project.knowledgeBase.isEmpty {
                    Text(selectedLanguage == .russian ? "Файлов пока нет" : "No files yet")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(project.knowledgeBase) { file in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                        .font(.body)
                                        .lineLimit(1)
                                    Text(file.type)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    viewModel.removeKnowledgeFile(file, from: project)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 10)
                            
                            if file.id != project.knowledgeBase.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } else {
                lockedCard(
                    title: selectedLanguage == .russian ? "База знаний" : "Knowledge Base",
                    subtitle: selectedLanguage == .russian ? "Доступно только в Nova Max" : "Available in Nova Max"
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    
    private var knowledgeFileTypes: [UTType] {
        var types: [UTType] = [.pdf, .text, .plainText]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let pptx = UTType(filenameExtension: "pptx") { types.append(pptx) }
        return types
    }
    
    private var knowledgeLimitText: String {
        let limit = viewModel.knowledgeFileLimit
        let count = project.knowledgeBase.count
        if selectedLanguage == .russian {
            return "Лимит: \(count)/\(limit) файлов"
        }
        return "Limit: \(count)/\(limit) files"
    }
    
    private func memoryOptionButton(title: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.primary.opacity(0.12) : Color(.tertiarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.primary.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    private func lockedCard(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            Button(action: { viewModel.showSubscription = true }) {
                Text(selectedLanguage == .russian ? "Открыть доступ" : "Upgrade")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var colorOptions: [Color] {
        [.blue, .green, .orange, .purple, .pink, .red, .teal, .gray]
    }
}
