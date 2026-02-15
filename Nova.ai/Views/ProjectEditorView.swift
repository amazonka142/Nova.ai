import SwiftUI
import UIKit

struct ProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ChatViewModel
    let selectedLanguage: AppLanguage
    
    @State private var name: String = ""
    @State private var icon: String = "📁"
    @State private var color: Color = .blue
    @State private var memoryScope: ProjectMemoryScope = .shared
    @State private var showLimitAlert = false
    @State private var showCreateError = false
    @State private var createErrorMessage = ""
    @State private var didInitializeName = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        
                        Text(selectedLanguage == .russian
                             ? "Проекты предоставляют общий контекст из разных чатов и файлов, доступный в одной точке."
                             : "Projects combine context from chats and files into a single workspace.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        
                        nameField
                        presetsRow
                        appearanceCard
                        memoryCard
                        
                        Button(action: createProject) {
                            Text(selectedLanguage == .russian ? "Создать проект" : "Create Project")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.systemGray4))
                                .clipShape(Capsule())
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1.0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            if !didInitializeName && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = selectedLanguage == .russian ? "Новый проект" : "New Project"
                didInitializeName = true
            }
        }
        .alert(
            selectedLanguage == .russian ? "Лимит проектов" : "Project Limit",
            isPresented: $showLimitAlert
        ) {
            Button(selectedLanguage == .russian ? "Обновить тариф" : "Upgrade") {
                viewModel.showSubscription = true
            }
            Button(selectedLanguage == .russian ? "Ок" : "OK", role: .cancel) { }
        } message: {
            Text(selectedLanguage == .russian
                 ? "Достигнут лимит проектов для вашего тарифа."
                 : "You’ve reached the project limit for your plan.")
        }
        .alert(
            selectedLanguage == .russian ? "Не удалось создать" : "Create Failed",
            isPresented: $showCreateError
        ) {
            Button(selectedLanguage == .russian ? "Ок" : "OK", role: .cancel) { }
        } message: {
            Text(createErrorMessage)
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
            
            Text(selectedLanguage == .russian ? "Новый проект" : "New Project")
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
    
    private var nameField: some View {
        HStack(spacing: 12) {
            Image(systemName: "face.smiling")
                .foregroundColor(.secondary)
            TextField(
                selectedLanguage == .russian ? "Название проекта" : "Project name",
                text: $name
            )
            .textInputAutocapitalization(.words)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private var presetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(presets) { preset in
                    Button {
                        name = preset.name
                        icon = preset.icon
                        color = preset.color
                    } label: {
                        HStack(spacing: 8) {
                            Text(preset.icon)
                            Text(preset.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
    
    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedLanguage == .russian ? "Внешний вид" : "Appearance")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                TextField(selectedLanguage == .russian ? "Emoji / символ" : "Emoji / symbol", text: $icon)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            HStack(spacing: 10) {
                ForEach(colorOptions.indices, id: \.self) { index in
                    let swatch = colorOptions[index]
                    let isSelected = color.toHex() == swatch.toHex()
                    Circle()
                        .fill(swatch)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(isSelected ? 0.9 : 0.2), lineWidth: isSelected ? 2 : 1)
                        )
                        .onTapGesture { color = swatch }
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
                    isSelected: memoryScope == .shared
                ) {
                    memoryScope = .shared
                }
                
                memoryOptionButton(
                    title: selectedLanguage == .russian ? "Только проект" : "Project only",
                    subtitle: selectedLanguage == .russian ? "Память изолирована внутри проекта" : "Isolated inside this project",
                    isSelected: memoryScope == .projectOnly
                ) {
                    memoryScope = .projectOnly
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
    
    private var presets: [ProjectPreset] {
        if selectedLanguage == .russian {
            return [
                ProjectPreset(name: "Инвестиции", icon: "💵", color: .green),
                ProjectPreset(name: "Домашняя работа", icon: "🎓", color: .blue),
                ProjectPreset(name: "Кодинг", icon: "💻", color: .purple),
                ProjectPreset(name: "Путешествия", icon: "✈️", color: .orange)
            ]
        }
        return [
            ProjectPreset(name: "Investments", icon: "💵", color: .green),
            ProjectPreset(name: "Homework", icon: "🎓", color: .blue),
            ProjectPreset(name: "Coding", icon: "💻", color: .purple),
            ProjectPreset(name: "Travel", icon: "✈️", color: .orange)
        ]
    }
    
    private var colorOptions: [Color] {
        [.blue, .green, .orange, .purple, .pink, .red, .teal, .gray]
    }
    
    private func createProject() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalIcon: String
        if trimmedIcon.isEmpty {
            finalIcon = "📁"
        } else if UIImage(systemName: trimmedIcon) != nil {
            finalIcon = trimmedIcon
        } else {
            finalIcon = String(trimmedIcon.prefix(2))
        }
        
        do {
            _ = try viewModel.createProject(name: trimmedName, icon: finalIcon, themeColor: color, memoryScope: memoryScope)
            dismiss()
        } catch ProjectManagerError.limitReached {
            showLimitAlert = true
        } catch {
            createErrorMessage = error.localizedDescription
            showCreateError = true
        }
    }
}

private struct ProjectPreset: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
}
