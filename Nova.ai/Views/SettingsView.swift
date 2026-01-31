import SwiftUI
import FirebaseAuth
import PhotosUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case russian = "Русский"
    case english = "English"
    
    var id: String { rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "Системная"
    case light = "Светлая"
    case dark = "Темная"
    
    var id: String { self.rawValue }
    
    func localized(language: AppLanguage) -> String {
        switch language {
        case .russian: return self.rawValue
        case .english:
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }
}

enum AppAccentColor: String, CaseIterable, Identifiable {
    case blue = "Синий"
    case purple = "Фиолетовый"
    case orange = "Оранжевый"
    case green = "Зеленый"
    case pink = "Розовый"
    case teal = "Бирюзовый"
    case gold = "Золотой"
    case black = "Черный"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .blue: return Color(red: 0.45, green: 0.62, blue: 0.79)   // Пастельный синий
        case .purple: return Color(red: 0.67, green: 0.58, blue: 0.82) // Пастельный фиолетовый
        case .orange: return Color(red: 0.92, green: 0.68, blue: 0.55) // Пастельный оранжевый
        case .green: return Color(red: 0.52, green: 0.74, blue: 0.65)  // Пастельный зеленый
        case .pink: return Color(red: 0.88, green: 0.60, blue: 0.70)   // Пастельный розовый
        case .teal: return Color(red: 0.42, green: 0.72, blue: 0.72)   // Пастельный бирюзовый
        case .gold: return Color(red: 0.85, green: 0.65, blue: 0.13)   // Золотой (темный для контраста)
        case .black: return Color.black                                // Черный
        }
    }
    
    func localized(language: AppLanguage) -> String {
        switch language {
        case .russian: return self.rawValue
        case .english:
            switch self {
            case .blue: return "Blue"
            case .purple: return "Purple"
            case .orange: return "Orange"
            case .green: return "Green"
            case .pink: return "Pink"
            case .teal: return "Teal"
            case .gold: return "Gold"
            case .black: return "Black"
            }
        }
    }
}

enum AppChatStyle: String, CaseIterable, Identifiable {
    case bubble = "bubble"
    case minimal = "minimal"
    
    var id: String { rawValue }
    
    func localized(language: AppLanguage) -> String {
        switch language {
        case .russian: return self == .bubble ? "Пузыри" : "Текст (без фона)"
        case .english: return self == .bubble ? "Bubbles" : "Text (No Bubble)"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: ChatViewModel
    @AppStorage("appTheme") private var selectedTheme: AppTheme = .system
    @AppStorage("appAccentColor") private var selectedAccentColor: AppAccentColor = .blue
    @AppStorage("appLanguage") private var selectedLanguage: AppLanguage = .russian
    @AppStorage("appChatStyle") private var chatStyle: AppChatStyle = .bubble
    @State private var showSubscription = false
    @State private var showDeleteAllAlert = false
    @State private var showAuthView = false
    @State private var showChangelog = false
    
    // Profile Editing State
    @State private var showEditProfileOptions = false
    @State private var showNameEditor = false
    @State private var newDisplayName: String = ""
    @State private var showPhotoPicker = false
    @State private var selectedProfilePhotoItem: PhotosPickerItem?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProfileHeaderView(viewModel: viewModel, language: selectedLanguage) {
                        if let user = viewModel.userSession, !user.isAnonymous {
                            newDisplayName = user.displayName ?? ""
                            showEditProfileOptions = true
                        } else {
                            showAuthView = true
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                
                Section {
                    Button(action: {
                        showSubscription = true
                    }) {
                        subscriptionRowView
                    }
                }
                
                Section(header: Text(selectedLanguage == .russian ? "Приложение" : "Application")) {
                    Picker(selectedLanguage == .russian ? "Язык" : "Language", selection: $selectedLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.rawValue).tag(lang)
                        }
                    }
                    
                    Picker(selectedLanguage == .russian ? "Тема" : "Theme", selection: $selectedTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.localized(language: selectedLanguage)).tag(theme)
                        }
                    }
                    
                    Picker(selectedLanguage == .russian ? "Внешний вид чата" : "Chat Appearance", selection: $chatStyle) {
                        ForEach(AppChatStyle.allCases) { style in
                            Text(style.localized(language: selectedLanguage)).tag(style)
                        }
                    }
                    
                    NavigationLink {
                        AccentColorSettingsView(
                            selectedAccentColor: $selectedAccentColor,
                            selectedLanguage: selectedLanguage,
                            viewModel: viewModel,
                            showSubscription: $showSubscription
                        )
                    } label: {
                        HStack {
                            Text(selectedLanguage == .russian ? "Акцентный цвет" : "Accent Color")
                            Spacer()
                            Circle()
                                .fill(selectedAccentColor.color)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                
                Section(header: Text(selectedLanguage == .russian ? "Выбор модели" : "Model Selection")) {
                    NavigationLink {
                        ModelSelectionSettingsView(
                            viewModel: viewModel,
                            selectedLanguage: selectedLanguage,
                            showSubscription: $showSubscription,
                            showAuthView: $showAuthView
                        )
                    } label: {
                        HStack {
                            Text(selectedLanguage == .russian ? "Модель" : "Model")
                            Spacer()
                            if let model = viewModel.availableModels.first(where: { $0.id == viewModel.selectedModel }) {
                                Text(model.name)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section(header: Text(selectedLanguage == .russian ? "Интеллект" : "Intelligence")) {
                    NavigationLink {
                        PersonalizationView()
                    } label: {
                        Label(selectedLanguage == .russian ? "Персонализация" : "Personalization", systemImage: "person.text.rectangle")
                    }
                    
                    NavigationLink {
                        Form {
                            Section(header: Text(selectedLanguage == .russian ? "Системная инструкция" : "System Instruction"), footer: Text(selectedLanguage == .russian ? "Опишите, как ИИ должен себя вести. Например: 'Ты опытный программист на Swift' или 'Отвечай кратко и по делу'." : "Describe how AI should behave. E.g., 'You are an experienced Swift programmer' or 'Answer briefly'.")) {
                                TextEditor(text: $viewModel.systemPrompt)
                                    .frame(minHeight: 150)
                            }
                        }
                        .navigationTitle(selectedLanguage == .russian ? "Инструкции" : "Instructions")
                    } label: {
                        Label(selectedLanguage == .russian ? "Системная инструкция" : "System Instruction", systemImage: "person.fill.questionmark")
                    }
                }
                
                Section(header: Text(selectedLanguage == .russian ? "Элементы управления данными" : "Data Controls")) {
                    Button(role: .destructive, action: {
                        showDeleteAllAlert = true
                    }) {
                        Label(selectedLanguage == .russian ? "Удалить все чаты" : "Delete All Chats", systemImage: "trash")
                    }
                }
                
                Section {
                    Button(role: .destructive, action: {
                        viewModel.signOut()
                        dismiss()
                    }) {
                        Text(selectedLanguage == .russian ? "Выйти из аккаунта" : "Sign Out")
                    }
                }
                
                Section {
                    Button(action: { showChangelog = true }) {
                        Text("Version \(ChatViewModel.appVersion) (Build \(ChatViewModel.buildNumber))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle(selectedLanguage == .russian ? "Настройки" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectedLanguage == .russian ? "Готово" : "Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showSubscription) {
                SubscriptionView(viewModel: viewModel)
            }
            .sheet(isPresented: $showChangelog) {
                ChangelogView()
            }
            .alert(selectedLanguage == .russian ? "Удалить все чаты?" : "Delete all chats?", isPresented: $showDeleteAllAlert) {
                Button(selectedLanguage == .russian ? "Удалить" : "Delete", role: .destructive) {
                    viewModel.deleteAllSessions()
                }
                Button(selectedLanguage == .russian ? "Отмена" : "Cancel", role: .cancel) { }
            } message: {
                Text(selectedLanguage == .russian ? "Это действие необратимо. Все ваши диалоги будут удалены с устройства и из облака." : "This action is irreversible. All your dialogs will be deleted from the device and cloud.")
            }
            .sheet(isPresented: $showAuthView) {
                AuthenticationView(viewModel: viewModel)
            }
            .onChange(of: viewModel.userSession?.uid) { _ in
                if let user = viewModel.userSession, !user.isAnonymous {
                    showAuthView = false
                }
            }
            .confirmationDialog(selectedLanguage == .russian ? "Редактировать профиль" : "Edit Profile", isPresented: $showEditProfileOptions, titleVisibility: .visible) {
                Button(selectedLanguage == .russian ? "Изменить имя" : "Change Name") {
                    showNameEditor = true
                }
                Button(selectedLanguage == .russian ? "Изменить фото" : "Change Photo") {
                    showPhotoPicker = true
                }
                Button(selectedLanguage == .russian ? "Отмена" : "Cancel", role: .cancel) { }
            }
            .alert(selectedLanguage == .russian ? "Изменить имя" : "Change Name", isPresented: $showNameEditor) {
                TextField(selectedLanguage == .russian ? "Новое имя" : "New Name", text: $newDisplayName)
                Button(selectedLanguage == .russian ? "Сохранить" : "Save") {
                    Task {
                        await viewModel.updateUserName(name: newDisplayName)
                    }
                }
                Button(selectedLanguage == .russian ? "Отмена" : "Cancel", role: .cancel) { }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedProfilePhotoItem, matching: .images)
            .onChange(of: selectedProfilePhotoItem) { newItem in
                Task {
                    await viewModel.updateUserProfilePhoto(item: newItem)
                }
            }
        }
    }
    
    private var subscriptionStatusTitle: String {
        if viewModel.isMax {
            return "Nova Max Активен"
        } else if viewModel.isPro {
            return "Nova Pro Активен"
        } else {
            return "Перейти на Pro"
        }
    }
    
    private var subscriptionSubtitle: String {
        selectedLanguage == .russian ? "Безлимит и лучшие модели" : "Unlimited & Best Models"
    }
    
    private var subscriptionRowView: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(subscriptionStatusTitle)
                    .foregroundColor(.primary)
                    .fontWeight(.medium)
                
                if !viewModel.isPro && !viewModel.isMax {
                    Text(subscriptionSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if !viewModel.isPro && !viewModel.isMax {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ChangelogView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("v\(ChatViewModel.appVersion) (\(ChatViewModel.buildNumber))")
                                .font(.headline)
                            
                            Text("Актуальная")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        
                        Text("Что нового:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.top, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ChangelogFeatureRow(icon: "photo.stack", color: .orange, text: "Галерея генераций: Просматривайте и делитесь всеми созданными изображениями.")
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("История версий")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("v1.2026.003 (8501)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• Интерактивные Артефакты: Предпросмотр HTML кода прямо в чате.")
                            Text("• Строгий фокус: Функция для точных ответов.")
                            Text("• Обновлен системный промпт: ИИ теперь меньше галлюцинирует.")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("v1.2026.0 (8492)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("• Инструмент Deep Research (Alpha) для глубокого анализа вашего запроса.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Список изменений")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

struct ChangelogFeatureRow: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20, alignment: .center)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct AccentColorSettingsView: View {
    @Binding var selectedAccentColor: AppAccentColor
    var selectedLanguage: AppLanguage
    @ObservedObject var viewModel: ChatViewModel
    @Binding var showSubscription: Bool
    
    var body: some View {
        List {
            ForEach(AppAccentColor.allCases) { color in
                let isLocked = (color == .gold && !viewModel.isPro && !viewModel.isMax) || (color == .black && !viewModel.isMax)
                
                Button {
                    if isLocked {
                        showSubscription = true
                    } else {
                        selectedAccentColor = color
                    }
                } label: {
                    HStack {
                        Circle()
                            .fill(color.color)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        
                        Text(color.localized(language: selectedLanguage))
                            .foregroundColor(isLocked ? .secondary : .primary)
                        
                        Spacer()
                        
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary)
                        } else if selectedAccentColor == color {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(selectedLanguage == .russian ? "Акцентный цвет" : "Accent Color")
    }
}

struct ModelSelectionSettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    var selectedLanguage: AppLanguage
    @Binding var showSubscription: Bool
    @Binding var showAuthView: Bool
    
    var body: some View {
        List {
            ForEach(viewModel.availableModels.filter { !$0.isDisabled }) { model in
                let isLocked = viewModel.isModelLocked(model.id)
                Button {
                    if isLocked {
                        if viewModel.userSession?.isAnonymous == true {
                            showAuthView = true
                        } else {
                            showSubscription = true
                        }
                    } else {
                        viewModel.selectedModel = model.id
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.name)
                                .font(.headline)
                                .foregroundColor(isLocked ? .secondary : .primary)
                            Text(model.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary)
                        } else if viewModel.selectedModel == model.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(selectedLanguage == .russian ? "Выбор модели" : "Select Model")
    }
}

struct ProfileHeaderView: View {
    @ObservedObject var viewModel: ChatViewModel
    var language: AppLanguage
    var onProfileTap: () -> Void
    
    @State private var isIdCopied = false
    var user: User? { viewModel.userSession }
    
    var initials: String {
        guard let user = user, let name = user.displayName, !name.isEmpty else {
            return user?.email?.prefix(1).uppercased() ?? "?"
        }
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: name) {
            formatter.style = .abbreviated
            return formatter.string(from: components)
        }
        return String(name.prefix(2)).uppercased()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Аватар
                if let user = user, let photoURL = user.photoURL {
                    AsyncImage(url: photoURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } placeholder: {
                        avatarPlaceholder
                    }
                } else {
                    avatarPlaceholder
                }
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
            
            // Текст
            VStack(spacing: 4) {
                if let user = user, !user.isAnonymous {
                    Text(user.displayName ?? "Пользователь")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    if let email = user.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    // Кнопка копирования ID
                    Button(action: {
                        UIPasteboard.general.string = user.uid
                        withAnimation { isIdCopied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { isIdCopied = false }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(idButtonText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 200)
                            
                            if !isIdCopied {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    // Заметка от администратора (например, статус оплаты)
                    if let note = viewModel.adminNote, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                } else {
                    Text(language == .russian ? "Гость" : "Guest")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            
            // Кнопка
            Button(action: {
                onProfileTap()
            }) {
                Text(profileActionButtonText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
    
    var avatarPlaceholder: some View {
        Circle()
            .fill(Color.orange.opacity(0.8))
            .frame(width: 80, height: 80)
            .overlay(
                Text(initials)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            )
    }
    
    private var idButtonText: String {
        if isIdCopied {
            return language == .russian ? "Скопировано!" : "Copied!"
        } else {
            return "ID: \(user?.uid ?? "")"
        }
    }
    
    private var profileActionButtonText: String {
        if let user = user, !user.isAnonymous {
            return language == .russian ? "Редактировать профиль" : "Edit Profile"
        } else {
            return language == .russian ? "Войти / Регистрация" : "Sign In / Register"
        }
    }
}