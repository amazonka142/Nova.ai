import SwiftUI
import SwiftData
import FirebaseAuth

@MainActor
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .forward) private var projects: [Project]
    @StateObject private var viewModel = ChatViewModel()
    @AppStorage("appTheme") private var selectedTheme: AppTheme = .system
    @AppStorage("appAccentColor") private var selectedAccentColor: AppAccentColor = .blue
    @AppStorage("appLanguage") private var selectedLanguage: AppLanguage = .russian
    
    // Drawer State
    @State private var isMenuOpen = false
    @State private var isSidebarExpanded = false
    // Tools Sheet State
    @State private var showTools = false
    @State private var welcomeText = ""
    @State private var showProjectSettings = false
    
    var body: some View {
        if viewModel.userSession == nil {
            AuthenticationView(viewModel: viewModel)
                .transition(.opacity)
        } else {
        ZStack {
            // Main Content
            mainContentLayer
                .opacity(isMenuOpen ? 0.3 : 1.0)
                .disabled(isMenuOpen)
                .onTapGesture {
                    if isMenuOpen { withAnimation { isMenuOpen = false } }
                }
            
            // Header (Always Top)
            VStack {
                simpleHeader
                    .zIndex(200)
                Spacer()
            }
            
            // Sidebar Drawer
            if isMenuOpen {
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { isMenuOpen = false } }
                    
                    SidebarView(viewModel: viewModel, isMenuOpen: $isMenuOpen, isExpanded: $isSidebarExpanded)
                        .frame(width: isSidebarExpanded ? UIScreen.main.bounds.width : 280)
                        .background(Color(UIColor.systemBackground))
                        .transition(.move(edge: .leading))
                }
                .zIndex(300)
            }
            
            // Limit Reached Overlay (Уведомление о лимитах)
            if viewModel.showLimitReached {
                LimitReachedOverlay(
                    modelName: viewModel.limitReachedModelName,
                    isPro: viewModel.isPro,
                    isMax: viewModel.isMax,
                    onUpgrade: {
                        viewModel.showLimitReached = false
                        viewModel.showSubscription = true
                    },
                    onSwitchToFree: {
                        viewModel.selectedModel = "mistral" // Переключение на Nova v1-RLHF (Free)
                        viewModel.showLimitReached = false
                    },
                    onClose: { viewModel.showLimitReached = false }
                )
                .zIndex(400)
            }
            
            // Congratulation Overlay (Поздравление с подпиской)
            if viewModel.showCongratulation, let plan = viewModel.purchasedPlan {
                CongratulationOverlay(
                    planName: plan,
                    onClose: {
                        viewModel.showCongratulation = false
                    }
                )
                .zIndex(500)
            }
        }
        .onAppear {
            viewModel.setContext(modelContext)
        }
        .onChange(of: isMenuOpen) { open in
            if !open {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isSidebarExpanded = false
                }
            }
        }
        .preferredColorScheme(scheme)
        .tint(selectedAccentColor.color)
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showProjectSettings) {
            if let project = viewModel.currentProject {
                ProjectSettingsView(viewModel: viewModel, project: project, selectedLanguage: selectedLanguage)
            }
        }
        .sheet(isPresented: $viewModel.showAuthRequest) {
            AuthenticationView(viewModel: viewModel)
        }
        // Tools Menu Sheet
        .sheet(isPresented: $showTools) {
            ToolsMenuView(
                selectedTool: $viewModel.activeTool,
                selectedPhotoItem: $viewModel.selectedPhotoItem,
                isMax: viewModel.isMax,
                onUpgrade: { 
                    showTools = false
                    if viewModel.userSession?.isAnonymous == true {
                        viewModel.showAuthRequest = true
                    } else {
                        viewModel.showSubscription = true 
                    }
                },
                onFileSelected: { url in viewModel.handleFileSelection(url: url) },
                onCameraCaptured: { image in viewModel.handleCameraImage(image) }
            )
            .presentationDetents([.fraction(0.45), .large])
            .presentationDragIndicator(.hidden)
        }
        .fullScreenCover(isPresented: $viewModel.isVoiceModePresented) {
            VoiceChatView(chatViewModel: viewModel)
        }
        }
    }
    
    // MARK: - Helpers
    
    private var scheme: ColorScheme? {
        switch selectedTheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
    
    // MARK: - Components
    
    private var mainContentLayer: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Spacer for header
                Spacer().frame(height: 60)
                
                if viewModel.currentSession.messages.isEmpty {
                    welcomeInterface
                } else {
                    ChatView(viewModel: viewModel)
                }
                
                // Input Field for empty state
                if viewModel.currentSession.messages.isEmpty {
                    VStack {
                        Spacer()
                        simpleInputArea
                            // Removed .padding(.bottom, 20)
                    }
                }
            }
        }
    }
    
    private var simpleHeader: some View {
        HStack(spacing: 16) {
            Button(action: {
                withAnimation(.spring()) { isMenuOpen.toggle() }
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            
            Text("nova.ai")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            // Simple Menu
            Menu {
                // Main Models
                ForEach(viewModel.availableModels.filter { !["nova-rp", "deepseek"].contains($0.id) }) { model in
                    if viewModel.isModelLocked(model.id) {
                        Button(action: {
                            if viewModel.userSession?.isAnonymous == true {
                                viewModel.showAuthRequest = true
                            } else {
                                viewModel.showSubscription = true
                            }
                        }) {
                            HStack {
                                Text(model.name)
                                Image(systemName: "lock.fill")
                            }
                        }
                    } else {
                        Button(action: { viewModel.selectedModel = model.id }) {
                            HStack {
                                Text(model.name)
                                if viewModel.selectedModel == model.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                // Additional Models Sub-menu
                Menu("Дополнительные модели") {
                    ForEach(viewModel.availableModels.filter { ["nova-rp", "deepseek"].contains($0.id) }) { model in
                        if viewModel.isModelLocked(model.id) {
                            Button(action: {
                                if viewModel.userSession?.isAnonymous == true {
                                    viewModel.showAuthRequest = true
                                } else {
                                    viewModel.showSubscription = true
                                }
                            }) {
                                HStack {
                                    Text(model.name)
                                    Image(systemName: "lock.fill")
                                }
                            }
                        } else {
                            Button(action: { viewModel.selectedModel = model.id }) {
                                HStack {
                                    Text(model.name)
                                    if viewModel.selectedModel == model.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.availableModels.first(where: { $0.id == viewModel.selectedModel })?.name ?? "Model")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Spacer()
            
            Button(action: { showProjectSettings = true }) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
            .disabled(viewModel.currentProject == nil)

            Button(action: { viewModel.isSettingsPresented = true }) {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .background(
            Color(UIColor.systemBackground)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(Divider(), alignment: .bottom)
    }
    
    private var welcomeInterface: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(welcomeText)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .onAppear {
                    startTypewriterAnimation()
                }
            Spacer()
            Spacer()
        }
    }
    
    private func startTypewriterAnimation() {
        let userName = viewModel.userSession?.displayName ?? (viewModel.userSession?.isAnonymous == true ? (selectedLanguage == .russian ? "Гость" : "Guest") : (selectedLanguage == .russian ? "Пользователь" : "User"))
        
        // Daily Greeting Logic
        let russianQuestions = [
            "Что сегодня в повестке дня?",
            "Какие планы на сегодня?",
            "Готов решать новые задачи?",
            "Давай придумаем что-то гениальное.",
            "Я готов помочь. С чего начнем?",
            "О чем ты думаешь прямо сейчас?",
            "Время действовать. Что сделаем?",
            "Какие идеи хочешь обсудить?",
            "Я весь во внимании.",
            "Давай создадим что-то крутое.",
            "Какая цель на сегодня?",
            "Жду твоих указаний.",
            "Вместе мы свернем горы.",
            "Что тебя вдохновляет сегодня?",
            "Готов к мозговому штурму?",
            "Давай разберемся с делами.",
            "Какой вопрос не дает покоя?",
            "Я здесь, чтобы помочь тебе.",
            "Сделаем этот день продуктивным?",
            "Твой личный ассистент на связи."
        ]
        
        let englishQuestions = [
            "What's on the agenda today?",
            "What are the plans for today?",
            "Ready for new challenges?",
            "Let's invent something genius.",
            "Ready to help. Where to start?",
            "What's on your mind right now?",
            "Time to act. What shall we do?",
            "What ideas do you want to discuss?",
            "I'm all ears.",
            "Let's create something cool.",
            "What's the goal for today?",
            "Awaiting your instructions.",
            "Together we'll move mountains.",
            "What inspires you today?",
            "Ready for a brainstorm?",
            "Let's get things done.",
            "What question is on your mind?",
            "I'm here to help you.",
            "Shall we make this day productive?",
            "Your personal assistant is online."
        ]
        
        let list = selectedLanguage == .russian ? russianQuestions : englishQuestions
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let dailyQuestion = list[dayOfYear % list.count]
        
        let greeting = selectedLanguage == .russian ? "Привет, \(userName)" : "Hello, \(userName)"
        let fullText = "\(greeting)\n\(dailyQuestion)"
        
        welcomeText = ""
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            for char in fullText {
                welcomeText.append(char)
                generator.impactOccurred()
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
    }
    
    private var simpleInputArea: some View {
        InputView(
            text: $viewModel.inputText,
            onMenuTap: { 
                showTools = true
            },
            attachmentData: viewModel.pendingAttachmentData,
            onSend: viewModel.sendMessage,
            isLoading: viewModel.isLoading,
            isRecording: viewModel.isRecording,
            onVoiceToggle: viewModel.toggleVoiceInput,
            activeTool: $viewModel.activeTool,
            fileAttachment: $viewModel.pendingFileAttachment,
            attachmentDataBinding: $viewModel.pendingAttachmentData
        )
        .padding(.bottom, 0) // InputView has its own padding
    }
}

// MARK: - Congratulation Components

struct CongratulationOverlay: View {
    let planName: String
    let onClose: () -> Void
    @State private var animate = false
    @State private var currentPage = 0
    
    var features: [String] {
        if planName == "Nova Max" {
            return [
                "Все функции Pro",
                "Режим DeepThink",
                "Поиск в интернете",
                "Генерация изображений (Flux)",
                "Анализ файлов",
                "Максимальная память (50 фактов)"
            ]
        } else {
            return [
                "Доступ к GPT-5 mini",
                "Безлимитные сообщения",
                "Голосовой чат",
                "Увеличенная память (25 фактов)",
                "Доступ к Nova-v1-Pro",
                "Приоритетная поддержка"
            ]
        }
    }
    
    var featuresPage1: [String] {
        let mid = (features.count + 1) / 2
        return Array(features.prefix(mid))
    }
    
    var featuresPage2: [String] {
        let mid = (features.count + 1) / 2
        return Array(features.suffix(from: mid))
    }
    
    var body: some View {
        ZStack {
            // Confetti Background
            ConfettiView()
                .ignoresSafeArea()
            
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
            
            VStack {
                Spacer()
                
                VStack(spacing: 0) {
                    TabView(selection: $currentPage) {
                        // Page 1: Intro
                        VStack(spacing: 20) {
                            Spacer()
                            
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 80, height: 80)
                                    .shadow(color: .purple.opacity(0.5), radius: 20, x: 0, y: 10)
                                
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                            }
                            .scaleEffect(animate ? 1.0 : 0.5)
                            .opacity(animate ? 1.0 : 0.0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: animate)
                            
                            Text("Спасибо за приобретение \(planName)!")
                                .font(.title2)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Text("Теперь вы можете работать с более умными моделями (включая GPT-5 mini), и модель может больше о вас запомнить.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation { currentPage = 1 }
                            }) {
                                Text("Ознакомиться с контентом")
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                    .cornerRadius(14)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 30)
                        }
                        .tag(0)
                        
                        // Page 2: Features Part 1
                        VStack(spacing: 20) {
                            Text("Ваши возможности (1/2)")
                                .font(.headline)
                                .padding(.top, 30)
                            
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(featuresPage1, id: \.self) { feature in
                                    HStack(spacing: 12) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.title3)
                                        Text(feature)
                                            .font(.body)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 30)
                            
                            Spacer()
                        }
                        .tag(1)
                        
                        // Page 3: Features Part 2
                        VStack(spacing: 20) {
                            Text("Ваши возможности (2/2)")
                                .font(.headline)
                                .padding(.top, 30)
                            
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(featuresPage2, id: \.self) { feature in
                                    HStack(spacing: 12) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.title3)
                                        Text(feature)
                                            .font(.body)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 30)
                            
                            Spacer()
                        }
                        .tag(2)
                        
                        // Page 4: Close
                        VStack(spacing: 20) {
                            Spacer()
                            
                            Image(systemName: "rocket.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .padding(.bottom, 10)
                            
                            Text("Вы готовы!")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Наслаждайтесь общением с Nova.")
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(action: onClose) {
                                Text("Закрыть")
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(14)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 30)
                        }
                        .tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .frame(height: 450)
                }
                .background(Color(UIColor.systemBackground))
                .cornerRadius(24)
                .shadow(radius: 30)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .onAppear {
            animate = true
        }
    }
}

struct ConfettiView: View {
    @State private var animate = false
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<50 {
                    let x = (Double(i * 13 + 50) + time * 40).truncatingRemainder(dividingBy: Double(size.width))
                    let y = (Double(i * 29 + 100) + time * 120).truncatingRemainder(dividingBy: Double(size.height))
                    
                    let color = [Color.blue, .purple, .red, .yellow, .green, .orange].randomElement()!
                    
                    let rect = CGRect(x: x, y: y, width: 8, height: 8)
                    
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
    }
}
