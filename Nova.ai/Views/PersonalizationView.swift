import SwiftUI

// MARK: - Enums for Options

enum AIStyle: String, CaseIterable, Identifiable {
    case standard = "По умолчанию"
    case concise = "Лаконичный"
    case verbose = "Развернутый"
    var id: String { rawValue }
}

enum AITraitLevel: String, CaseIterable, Identifiable {
    case standard = "По умолчанию"
    case more = "Более"
    case less = "Менее"
    var id: String { rawValue }
}

enum AIFormatting: String, CaseIterable, Identifiable {
    case auto = "Авто"
    case always = "Всегда"
    case never = "Никогда"
    var id: String { rawValue }
}

enum AIEmoji: String, CaseIterable, Identifiable {
    case auto = "Авто"
    case many = "Много"
    case few = "Мало"
    var id: String { rawValue }
}

struct PersonalizationView: View {
    @Environment(\.dismiss) var dismiss
    
    // MARK: - Persistent Storage
    @AppStorage("ai_style") private var selectedStyle: AIStyle = .standard
    @AppStorage("ai_strict_focus") private var strictFocus: Bool = false
    
    @AppStorage("ai_warmth") private var warmthLevel: AITraitLevel = .standard
    @AppStorage("ai_enthusiasm") private var enthusiasmLevel: AITraitLevel = .standard
    @AppStorage("ai_formatting") private var formattingPref: AIFormatting = .auto
    @AppStorage("ai_emojis") private var emojiPref: AIEmoji = .auto
    
    @AppStorage("ai_custom_instructions") private var customInstructions: String = ""
    
    @AppStorage("user_nickname") private var userNickname: String = ""
    @AppStorage("user_profession") private var userProfession: String = ""
    @AppStorage("user_interests") private var userInterests: String = ""
    
    @State private var isAdvancedExpanded: Bool = false
    
    var body: some View {
            Form {
                // 2. СЕКЦИЯ "Базовый стиль и тон"
                Section(
                    header: Text("Базовый стиль и тон"),
                    footer: Text("Это основной стиль общения и тон, который использует Nova в обсуждениях с вами. Вы можете изменить это в любой момент.")
                ) {
                    Picker(selection: $selectedStyle) {
                        ForEach(AIStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    } label: {
                        Label("Стиль общения", systemImage: "bubble.left.and.bubble.right")
                    }
                    .pickerStyle(.menu)
                    
                    Toggle(isOn: $strictFocus) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Строгий фокус")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("Отвечать только на последний вопрос, игнорируя уход от темы в истории.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "target")
                        }
                    }
                }
                
                // 3. СЕКЦИЯ "Характеристики"
                Section(
                    header: Text("Характеристики"),
                    footer: Text("Выберите дополнительные параметры настройки личности ИИ.")
                ) {
                    Picker(selection: $warmthLevel) {
                        ForEach(AITraitLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    } label: {
                        Label("Теплый", systemImage: "thermometer.sun")
                    }
                    
                    Picker(selection: $enthusiasmLevel) {
                        ForEach(AITraitLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    } label: {
                        Label("Восторженный", systemImage: "sparkles")
                    }
                    
                    Picker(selection: $formattingPref) {
                        ForEach(AIFormatting.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    } label: {
                        Label("Заголовки и списки", systemImage: "list.bullet.clipboard")
                    }
                    
                    Picker(selection: $emojiPref) {
                        ForEach(AIEmoji.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    } label: {
                        Label("Эмодзи", systemImage: "face.smiling")
                    }
                }
                
                // 4. СЕКЦИЯ "Пользовательские инструкции"
                Section(header: Text("Пользовательские инструкции")) {
                    ZStack(alignment: .topLeading) {
                        if customInstructions.isEmpty {
                            Text("Поделитесь чем-нибудь еще, что Nova должна знать о ваших предпочтениях...")
                                .foregroundColor(Color(UIColor.placeholderText))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        
                        TextEditor(text: $customInstructions)
                            .frame(minHeight: 100)
                            .padding(.horizontal, -4) // Align with placeholder
                    }
                }
                
                // 5. СЕКЦИЯ "О пользователе"
                Section(header: Text("О пользователе")) {
                    HStack {
                        Text("Ваш псевдоним")
                            .frame(width: 120, alignment: .leading)
                        Divider()
                        TextField("Имя", text: $userNickname)
                    }
                    
                    HStack {
                        Text("Ваша профессия")
                            .frame(width: 120, alignment: .leading)
                        Divider()
                        TextField("Профессия", text: $userProfession)
                    }
                    
                    HStack {
                        Text("Больше о вас")
                            .frame(width: 120, alignment: .leading)
                        Divider()
                        TextField("Интересы, ценности", text: $userInterests)
                    }
                }
                
                // 6. СЕКЦИЯ "Память"
                Section {
                    NavigationLink {
                        MemoryView()
                    } label: {
                        Label("Память", systemImage: "brain.head.profile")
                    }
                }
                
                // 7. НИЖНЯЯ СЕКЦИЯ (Расширенные настройки)
                Section {
                    DisclosureGroup("Расширенные настройки", isExpanded: $isAdvancedExpanded) {
                        Toggle("Отладка контекста", isOn: .constant(false))
                        Toggle("Сырой вывод модели", isOn: .constant(false))
                        
                        Button("Сбросить все настройки") {
                            resetSettings()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Персонализация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        // @AppStorage saves automatically, so we just close
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
    }
    
    private func resetSettings() {
        selectedStyle = .standard
        warmthLevel = .standard
        enthusiasmLevel = .standard
        formattingPref = .auto
        emojiPref = .auto
        customInstructions = ""
        userNickname = ""
        userProfession = ""
        userInterests = ""
    }
}