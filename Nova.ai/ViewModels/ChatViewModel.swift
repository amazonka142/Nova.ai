import SwiftUI
import Combine
import SwiftData
import PhotosUI
import PDFKit
import AVFoundation
import Speech
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import FirebaseStorage
import GoogleSignIn
import UserNotifications
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    static let appVersion = "1.2026.009"
    static let buildNumber = "8506"
    
    enum ChatTool: String, CaseIterable, Identifiable {
        case none
        case reasoning
        case search
        case image
        case deepResearch
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .none: return ""
            case .reasoning: return "Думать"
            case .search: return "Поиск"
            case .image: return "Рисовать"
            case .deepResearch: return "Deep Research (Alpha)"
            }
        }
        
        var icon: String {
            switch self {
            case .none: return ""
            case .reasoning: return "brain.head.profile"
            case .search: return "globe"
            case .image: return "paintpalette.fill"
            case .deepResearch: return "doc.text.magnifyingglass"
            }
        }
        
        var color: Color {
            switch self {
            case .none: return .clear
            case .reasoning: return .purple
            case .search: return .blue
            case .image: return .orange
            case .deepResearch: return .indigo
            }
        }
    }

    struct AttachmentItem: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let type: String
        let content: String
    }

    @Published var currentSession: ChatSession
    // History is now managed by SwiftData @Query in the View
    
    // Auth State
    @Published var userSession: User?
    
    // UI State
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?
    @Published var selectedModel: String = "gemini-fast" 
    @Published var isSettingsPresented: Bool = false
    @Published var showSubscription: Bool = false
    @Published var showAuthRequest: Bool = false
    @Published var isPro: Bool = UserDefaults.standard.bool(forKey: "isPro") { didSet { UserDefaults.standard.set(isPro, forKey: "isPro") } }
    @Published var isMax: Bool = UserDefaults.standard.bool(forKey: "isMax") { didSet { UserDefaults.standard.set(isMax, forKey: "isMax") } }
    @Published var isSidebarVisible: Bool = false
    @Published var isVoiceModePresented: Bool = false
    @Published var smartSuggestions: [String] = []
    @Published var adminNote: String?
    
    // Attachments
    @Published var activeTool: ChatTool = .none
    @Published var pendingFileAttachment: AttachmentItem? = nil
    @Published var selectedPhotoItem: PhotosPickerItem? = nil {
        didSet {
            if selectedPhotoItem != nil {
                handlePhotoSelection()
            }
        }
    }
    @Published var pendingAttachmentData: Data? = nil
    @Published var isWebSearchEnabled: Bool = false // Toggle for Web Search mode
    
    @Published var systemPrompt: String = UserDefaults.standard.string(forKey: "savedSystemPrompt") ?? "You are a helpful AI assistant." {
        didSet {
            UserDefaults.standard.set(systemPrompt, forKey: "savedSystemPrompt")
        }
    }
    
    // Limits
    @Published var dailyRequestCount: Int = 0
    @Published var modelUsage: [String: Int] = [:] // Track usage per model
    @Published var weeklyModelUsage: [String: Int] = [:] // Track weekly usage
    @Published var lastRequestDate: Date? = nil
    @Published var lastWeeklyResetDate: Date? = nil
    @Published var showLimitReached: Bool = false
    @Published var limitReachedModelName: String = ""
    @Published var showCongratulation: Bool = false
    @Published var purchasedPlan: String? = nil
    let dailyLimit = 50
    
    // Deep Research State
    @Published var researchStates: [UUID: ResearchSessionData] = [:] {
        didSet {
            saveResearchStates()
        }
    }
    @Published var selectedReport: ResearchReport?
    
    // Update Checker
    struct AppUpdate: Identifiable {
        let id = UUID()
        let version: String
        let changelog: String
        let downloadURL: String
    }
    @Published var appUpdate: AppUpdate?
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var usageListener: ListenerRegistration?
    private var networkTimeOffset: TimeInterval?
    
    // Available Models
    struct ModelOption: Identifiable, Hashable {
        let id: String
        let name: String
        let description: String
        var isDisabled: Bool = false
    }
    
    let availableModels = [
        ModelOption(id: "openai-fast", name: "GPT-5 nano", description: "Самая быстрая"),
        ModelOption(id: "openai", name: "GPT-5 mini", description: "Рекомендуемая"),
        ModelOption(id: "gemini-fast", name: "Gemini 2.5 Flash Lite", description: "Сбалансированная, лучшая для поиска"),
        ModelOption(id: "mistral", name: "Nova-v1-RLHF", description: "Экспериментальная (Vision)"),
        ModelOption(id: "nova-rp", name: "Nova-v1-RP", description: "Ролевая модель (Roleplay)"),
        ModelOption(id: "deepseek", name: "Nova-v1-Pro", description: "Продвинутая (Complex Tasks)")
    ]
    
    private let chatService: ChatServiceProtocol
    private lazy var googleSearchService = GoogleSearchService()
    private var modelContext: ModelContext?
    private var currentTask: Task<Void, Never>?
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU")) // Или current
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // Apple Sign In Nonce
    private var currentNonce: String?
    
    init(service: ChatServiceProtocol? = nil, context: ModelContext? = nil) {
        self.chatService = service ?? PollinationsChatService()
        self.modelContext = context
        
        // Start with a temporary session that will be replaced when context is set.
        let newSession = ChatSession(title: "Loading...", model: "gemini-fast")
        self.currentSession = newSession
        self.loadResearchStates()
        self.checkForUpdates()
        
        // Listen to Auth changes
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.userSession = user
            if let user = user {
                self?.setupUsageListener(userId: user.uid)
                self?.restoreHistory()
                if user.isAnonymous {
                    self?.selectedModel = "mistral"
                }
            } else {
                self?.usageListener?.remove()
                self?.dailyRequestCount = 0
            }
        }
    }
    
    func setContext(_ context: ModelContext) {
        self.modelContext = context
        
        // Всегда начинаем с чистого листа (Welcome Screen).
        // Создаем сессию в памяти, но НЕ вставляем её в контекст, пока пользователь не напишет сообщение.
        self.currentSession = ChatSession(title: "New Chat", model: self.selectedModel)
    }
    
    func speakMessage(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio Session setup failed: \(error)")
        }
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: cleanText)
        
        // Attempt to use high quality voice
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let russianVoices = voices.filter { $0.language == "ru-RU" }
        if let premium = russianVoices.first(where: { $0.quality == .premium }) {
            utterance.voice = premium
        } else if let enhanced = russianVoices.first(where: { $0.quality == .enhanced }) {
            utterance.voice = enhanced
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        }
        
        speechSynthesizer.speak(utterance)
    }
    
    func toggleVoiceInput() {
        isVoiceModePresented = true
    }
    
    private func startRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            isRecording = false
            return
        }
        
        // Request permissions first
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                guard status == .authorized else {
                    self.errorMessage = "Нет разрешения на распознавание речи. Пожалуйста, разрешите доступ в настройках."
                    return
                }
                
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    DispatchQueue.main.async {
                        guard allowed else {
                            self.errorMessage = "Нет доступа к микрофону. Пожалуйста, разрешите доступ в настройках."
                            return
                        }
                        
                        // Start recording
                        do {
                            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
                            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                            
                            self.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
                            guard let recognitionRequest = self.recognitionRequest else { return }
                            recognitionRequest.shouldReportPartialResults = true
                            
                            let inputNode = self.audioEngine.inputNode
                            
                            self.recognitionTask = self.speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                                guard let self = self else { return }
                                if let result = result {
                                    self.inputText = result.bestTranscription.formattedString
                                }
                                if error != nil || (result?.isFinal ?? false) {
                                    self.stopRecording()
                                }
                            }
                            
                            let recordingFormat = inputNode.outputFormat(forBus: 0)
                            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                                recognitionRequest.append(buffer)
                            }
                            
                            self.audioEngine.prepare()
                            try self.audioEngine.start()
                            self.isRecording = true
                        } catch {
                            print("Recording failed: \(error)")
                            self.errorMessage = "Ошибка записи: \(error.localizedDescription)"
                            self.stopRecording()
                        }
                    }
                }
            }
        }
    }
    
    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        
        // Reset audio session to playback for TTS
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }
    
    func cancelRequest() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }
    
    func handleCameraImage(_ image: UIImage) {
        Task {
            // Compress and resize image for API optimization
            let maxDimension: CGFloat = 1024
            let size = image.size
            let scale = min(maxDimension / size.width, maxDimension / size.height)
            
            if scale < 1.0 {
                let newSize = CGSize(width: size.width * scale, height: size.height * scale)
                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                self.pendingAttachmentData = resizedImage?.jpegData(compressionQuality: 0.5)
            } else {
                self.pendingAttachmentData = image.jpegData(compressionQuality: 0.5)
            }
        }
    }
    
    func handlePhotoSelection() {
        guard let item = selectedPhotoItem else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                // Compress and resize image for API optimization
                // Max dimension 1024px, JPEG quality 0.5
                let maxDimension: CGFloat = 1024
                let size = image.size
                let scale = min(maxDimension / size.width, maxDimension / size.height)
                
                if scale < 1.0 {
                    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
                    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                    let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    self.pendingAttachmentData = resizedImage?.jpegData(compressionQuality: 0.5)
                } else {
                    self.pendingAttachmentData = image.jpegData(compressionQuality: 0.5)
                }
            }
        }
    }
    
    func handleFileSelection(url: URL) {
        // Start accessing the security-scoped resource
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
        
        var fileContent = ""
        
        // Simple extraction logic
        if url.pathExtension.lowercased() == "pdf" {
            if let pdf = PDFDocument(url: url) {
                fileContent = pdf.string ?? ""
            }
        } else {
            // Try reading as plain text
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                fileContent = text
            }
        }
        
        if !fileContent.isEmpty {
            let fileName = url.lastPathComponent
            let fileType = url.pathExtension.uppercased()
            self.pendingFileAttachment = AttachmentItem(name: fileName, type: fileType.isEmpty ? "TXT" : fileType, content: fileContent)
        } else {
            self.errorMessage = "Не удалось прочитать текст из файла. Возможно, формат не поддерживается или файл защищен."
        }
    }
    
    func sendMessage() {
        // If loading, button acts as Cancel
        if isLoading {
            cancelRequest()
            return
        }
        
        // Check Limits
        var targetModel = selectedModel
        if activeTool == .image {
            targetModel = "image"
        } else if activeTool == .reasoning {
            targetModel = "deepthink"
        } else if activeTool == .deepResearch {
            targetModel = "deep-research"
        }
        
        let limitStatus = checkLimit(for: targetModel)
        
        switch limitStatus {
        case .locked:
            if userSession?.isAnonymous == true {
                showAuthRequest = true
            } else {
                showSubscription = true
            }
            return
        case .limitReached:
            limitReachedModelName = availableModels.first(where: { $0.id == targetModel })?.name ?? (activeTool == .image ? "Генерация изображений" : (activeTool == .reasoning ? "Режим DeepThink" : targetModel))
            showLimitReached = true
            return
        case .allowed:
            break
        }
        
        guard (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingAttachmentData != nil || pendingFileAttachment != nil) else { return }
        
        // Если это первое сообщение в новой сессии (черновик), регистрируем её в SwiftData
        if currentSession.modelContext == nil {
            modelContext?.insert(currentSession)
        }
        
        // --- IMAGE GENERATION LOGIC ---
        if activeTool == .image {
            performImageGeneration(prompt: inputText)
            activeTool = .none
            return
        }
        
        // --- DEEP RESEARCH LOGIC ---
        if activeTool == .deepResearch {
            performDeepResearch(query: inputText)
            incrementUsage(for: "deep-research")
            activeTool = .none
            return
        }
        
        // --- WEB SEARCH LOGIC ---
        if isWebSearchEnabled || activeTool == .search {
            performWebSearch(query: inputText)
            activeTool = .none
            return
        }
        // ------------------------
        
        let userMessage: Message
        
        var finalContent = inputText
        if let file = pendingFileAttachment {
            finalContent = "[File: \(file.name)]\n\n\(file.content)\n\nUser: \(finalContent)"
        }
        
        if let imageData = pendingAttachmentData {
            // Image Message
            let caption = finalContent.isEmpty ? "Image Attachment" : finalContent
            userMessage = Message(role: .user, content: caption, type: .image, imageData: imageData)
        } else {
            // Text Message
            userMessage = Message(role: .user, content: finalContent)
        }
        
        currentSession.messages.append(userMessage)
        currentSession.lastModified = Date()
        
        syncSessionToFirestore(currentSession)
        syncMessageToFirestore(userMessage, session: currentSession)
        
        // Reset Inputs
        let inputToSend = inputText
        self.smartSuggestions = [] // Очищаем старые подсказки
        
        // 2. В ЭТО ЖЕ ВРЕМЯ (в фоне) запускаем шпиона-аналитика
        Task(priority: .userInitiated) {
            await analyzeForMemory(userMessage: inputToSend)
        }
        
        inputText = ""
        pendingAttachmentData = nil
        pendingFileAttachment = nil
        selectedPhotoItem = nil
        
        // Haptic: Light impact on send
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        
        isLoading = true
        errorMessage = nil
        
        saveContext()
        
        // Increment Usage
        incrementUsage(for: targetModel)
        
        currentTask = Task {
            do {
                var contextMessages: [Message] = []
                
                var effectiveSystemPrompt = constructPersonalizedSystemPrompt()
                var modelToSend = selectedModel
                
                if selectedModel == "nova-rp" {
                    modelToSend = "deepseek"
                    effectiveSystemPrompt = "You are Nova-v1-RP. Engage in a detailed and immersive roleplay. Adopt the persona requested by the user or implied by the context. Do not break character. Be descriptive."
                }
                
                if activeTool == .reasoning || modelToSend == "deepthink" {
                    effectiveSystemPrompt = "You are a deep thinking AI. Use Chain of Thought reasoning. Explain your steps."
                }
                
                contextMessages.append(Message(role: .system, content: effectiveSystemPrompt))
                
                // Strict Focus Logic: If enabled, do NOT send history, only the last message
                if UserDefaults.standard.bool(forKey: "ai_strict_focus") {
                    if let lastMessage = currentSession.messages.last {
                        contextMessages.append(lastMessage)
                    }
                } else {
                    contextMessages.append(contentsOf: currentSession.messages)
                }
                
                // Construct DTOs
                let apiMessages = contextMessages.map { 
                    API_Message(role: $0.role.rawValue, content: $0.content, imageData: $0.imageData) 
                }
                
                // Create placeholder AI message
                let aiMessage = Message(role: .assistant, content: "")
                currentSession.messages.append(aiMessage)
                
                // Stream response
                let stream = chatService.streamMessage(apiMessages, model: modelToSend)
                
                for try await chunk in stream {
                    aiMessage.content += chunk
                }
                
                currentSession.lastModified = Date()
                
                self.syncMessageToFirestore(aiMessage, session: self.currentSession)
                self.syncSessionToFirestore(self.currentSession)
                
                // Haptic: Notification success on completion
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)
                
                if currentSession.messages.count <= 2 {
                    await generateSessionTitle(from: inputToSend)
                }
                
                saveContext()
                
                // 3. Генерируем умные подсказки (в фоне)
                Task(priority: .userInitiated) {
                    await self.generateSmartSuggestions(lastAiMessage: aiMessage.content)
                }
                
            } catch {
                if !(error is CancellationError) {
                    errorMessage = "Failed to send message: \(error.localizedDescription)"
                    // Remove the empty message if failed
                    if let last = currentSession.messages.last, last.role == .assistant, last.content.isEmpty {
                        currentSession.messages.removeLast()
                    }
                }
            }
            isLoading = false
            currentTask = nil
            activeTool = .none
        }
    }
    
    // MARK: - Voice Mode Logic
    
    func processVoiceMessage(_ text: String) async throws -> String {
        // 1. Check Limits
        let limitStatus = checkLimit(for: selectedModel)
        switch limitStatus {
        case .locked:
            if userSession?.isAnonymous == true {
                return "Эта модель доступна только авторизованным пользователям. Пожалуйста, войдите в аккаунт."
            }
            return "Эта модель недоступна в вашем тарифе. Пожалуйста, обновите подписку."
        case .limitReached:
            return "Лимит сообщений для этой модели исчерпан на сегодня."
        case .allowed:
            break
        }
        
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return "" }
        
        // Если это первое сообщение в новой сессии (черновик), регистрируем её в SwiftData
        if currentSession.modelContext == nil {
            modelContext?.insert(currentSession)
        }
        
        // Background Memory Analysis
        Task(priority: .userInitiated) {
            await analyzeForMemory(userMessage: cleanText)
        }
        
        // 2. Save User Message
        let userMessage = Message(role: .user, content: cleanText)
        currentSession.messages.append(userMessage)
        currentSession.lastModified = Date()
        saveContext()
        
        syncSessionToFirestore(currentSession)
        syncMessageToFirestore(userMessage, session: currentSession)
        incrementUsage(for: selectedModel)
        
        // 3. Prepare Context
        var contextMessages: [Message] = []
        
        var effectiveSystemPrompt = constructPersonalizedSystemPrompt()
        var modelToSend = selectedModel
        
        if selectedModel == "nova-rp" {
            modelToSend = "deepseek"
            effectiveSystemPrompt = "You are Nova-v1-RP. Engage in a detailed and immersive roleplay. Adopt the persona requested by the user or implied by the context. Do not break character. Be descriptive."
        }
        
        contextMessages.append(Message(role: .system, content: effectiveSystemPrompt))
        
        // Strict Focus Logic
        if UserDefaults.standard.bool(forKey: "ai_strict_focus") {
            if let lastMessage = currentSession.messages.last {
                contextMessages.append(lastMessage)
            }
        } else {
            contextMessages.append(contentsOf: currentSession.messages)
        }
        
        let apiMessages = contextMessages.map {
            API_Message(role: $0.role.rawValue, content: $0.content, imageData: $0.imageData)
        }
        
        // 4. Create Placeholder for AI Response
        let aiMessage = Message(role: .assistant, content: "")
        currentSession.messages.append(aiMessage)
        
        // 5. Call API & Accumulate Response
        var fullResponse = ""
        // Using the selected model from settings
        do {
            let stream = chatService.streamMessage(apiMessages, model: modelToSend)
            
            for try await chunk in stream {
                fullResponse += chunk
                aiMessage.content = fullResponse
            }
        } catch {
            // Cleanup: Remove the empty placeholder if API failed
            if let last = currentSession.messages.last, last.role == .assistant, last.content.isEmpty {
                currentSession.messages.removeLast()
            }
            throw error
        }
        
        // 6. Finalize
        currentSession.lastModified = Date()
        saveContext()
        
        syncMessageToFirestore(aiMessage, session: currentSession)
        syncSessionToFirestore(currentSession)
        
        return fullResponse
    }
    
    // MARK: - Memory Management
    
    private var memoryLimit: Int {
        if isMax { return 50 }
        if isPro { return 25 }
        return 10
    }
    
    private func saveMemory(_ text: String) -> Bool {
        var memories = UserDefaults.standard.stringArray(forKey: "ai_memories") ?? []
        
        if memories.contains(text) { return true }
        
        if memories.count >= memoryLimit {
            return false
        }
        memories.append(text)
        UserDefaults.standard.set(memories, forKey: "ai_memories")
        return true
    }
    
    private func analyzeForMemory(userMessage: String) async {
        NSLog("🚀 [Memory] Запуск фонового анализа для: '\(userMessage)'")
        
        let existingMemories = UserDefaults.standard.stringArray(forKey: "ai_memories") ?? []
        let memoriesContext = existingMemories.isEmpty ? "Нет известных фактов" : existingMemories.joined(separator: "; ")
        
        let systemInstruction = """
        Ты — аналитик данных. Твоя задача — извлечь ВАЖНЫЕ и ДОЛГОСРОЧНЫЕ факты о пользователе (имя, профессия, хобби, питомцы, важные предпочтения).
        
        Игнорируй текущие рабочие запросы, мнения о коде или временные контексты.
        
        Уже известные факты: [\(memoriesContext)]
        
        Правила:
        1. Если найден ВАЖНЫЙ факт — верни ТОЛЬКО сам факт (утверждение от третьего лица).
        2. Если фактов нет или это текущий рабочий контекст — верни слово "NO".
        """
        
        let apiMessages = [
            API_Message(role: "system", content: systemInstruction, imageData: nil),
            API_Message(role: "user", content: "Сообщение пользователя: \"\(userMessage)\"", imageData: nil)
        ]
        
        // Используем БЕСПЛАТНУЮ модель (Gemini Flash Lite)
        let model = "gemini-fast"
        
        var fullResponse = ""
        do {
            let stream = chatService.streamMessage(apiMessages, model: model)
            for try await chunk in stream {
                fullResponse += chunk
            }
            
            // DEBUG: Принудительно пишем в консоль, что ответил Gemini
            NSLog("🧠 [Memory Debug] Анализ сообщения: '\(userMessage)' -> Ответ Gemini: '\(fullResponse)'")
            
            let fact = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
            
            if fact.uppercased() != "NO" && !fact.isEmpty && fact.count < 200 {
                NSLog("🕵️‍♂️ Gemini Flash нашел факт: \(fact)")
                if self.saveMemory(fact) {
                    let sysMsg = Message(role: .system, content: "💾 Запомнил: \(fact)")
                    self.currentSession.messages.append(sysMsg)
                    self.syncMessageToFirestore(sysMsg, session: self.currentSession)
                    self.saveContext()
                } else {
                    let limit = self.memoryLimit
                    let upsellMsg = Message(role: .assistant, content: "🧠 *Я заметил важный факт ('\(fact)'), но у меня переполнена память (\(limit)/\(limit)). В бесплатной версии я могу помнить только \(limit) фактов. Обновись до Pro, чтобы расширить мне мозг!*")
                    self.currentSession.messages.append(upsellMsg)
                    self.syncMessageToFirestore(upsellMsg, session: self.currentSession)
                    self.saveContext()
                }
            }
        } catch {
            NSLog("🧠 [Memory Debug] Ошибка анализа: \(error)")
        }
    }
    
    private func generateSessionTitle(from message: String) async {
        let prompt = """
        Придумай креативное и короткое название (до 20 символов) для чата, основываясь на первом сообщении пользователя.
        Примеры: "Помощь с кодом", "Идеи для стартапа", "Рецепт пасты", "Уроки английского", "Фантастический рассказ".
        Сообщение пользователя: "\(message)"
        """
        
        let apiMessages = [API_Message(role: "user", content: prompt, imageData: nil)]
        
        do {
            // Используем быструю модель
            let title = try await chatService.sendMessage(apiMessages, model: "gemini-fast")
            
            // DEBUG
            NSLog("✨ Сгенерированное название чата: \(title)")
            
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTitle.isEmpty {
                await MainActor.run {
                    withAnimation {
                        self.updateSessionTitle(with: cleanTitle)
                    }
                }
            }
            
        } catch {
            print("Failed to generate title: \(error)")
            // Fallback title
            await MainActor.run {
                self.updateSessionTitle(with: "Новый чат")
            }
        }
    }

    
    private func generateSmartSuggestions(lastAiMessage: String) async {
        guard !lastAiMessage.isEmpty else { return }
        
        let prompt = """
        На основе последнего ответа ИИ предложи 3 коротких варианта ответа или следующего вопроса для пользователя.
        Ответы должны быть краткими (1-4 слова), естественными и на том же языке, что и диалог.
        Верни их в формате: "Вариант 1 | Вариант 2 | Вариант 3". Никакого лишнего текста.
        
        Последний ответ ИИ: "\(lastAiMessage.prefix(500))"
        """
        
        let apiMessages = [API_Message(role: "user", content: prompt, imageData: nil)]
        
        do {
            // Используем быструю модель
            let suggestionsRaw = try await chatService.sendMessage(apiMessages, model: "gemini-fast")
            let parts = suggestionsRaw.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            
            if parts.count >= 1 {
                await MainActor.run {
                    withAnimation {
                        self.smartSuggestions = parts.filter { !$0.isEmpty }
                    }
                }
            }
        } catch {
            print("Suggestions failed: \(error)")
        }
    }
    
    // MARK: - Personalization Logic
    
    private func constructPersonalizedSystemPrompt() -> String {
        let defaults = UserDefaults.standard
        
        // 1. Считываем настройки
        let style = defaults.string(forKey: "ai_style")
        let warmth = defaults.string(forKey: "ai_warmth")
        let enthusiasm = defaults.string(forKey: "ai_enthusiasm")
        let formatting = defaults.string(forKey: "ai_formatting")
        let emojis = defaults.string(forKey: "ai_emojis")
        let custom = defaults.string(forKey: "ai_custom_instructions") ?? ""
        let strictFocus = defaults.bool(forKey: "ai_strict_focus")
        
        // 2. Считываем профиль
        let nickname = defaults.string(forKey: "user_nickname") ?? ""
        let profession = defaults.string(forKey: "user_profession") ?? ""
        let interests = defaults.string(forKey: "user_interests") ?? ""
        let memories = defaults.stringArray(forKey: "ai_memories") ?? []
        
        // --- БЛОК 1: ЛИЧНОСТЬ И ТОН ---
        var personalityTraits: [String] = []
        
        switch style {
        case "Лаконичный": personalityTraits.append("- Response Style: Extremely concise, direct, and to the point. No fluff.")
        case "Развернутый": personalityTraits.append("- Response Style: Detailed, educational, and comprehensive.")
        default: personalityTraits.append("- Response Style: Balanced, natural, and helpful.")
        }
        
        switch warmth {
        case "Более": personalityTraits.append("- Tone: Warm, empathetic, and supportive.")
        case "Менее": personalityTraits.append("- Tone: Professional, objective, and neutral.")
        default: personalityTraits.append("- Tone: Friendly but professional.")
        }
        
        switch enthusiasm {
        case "Более": personalityTraits.append("- Energy: High energy, enthusiastic, uses exclamation points occasionally.")
        case "Менее": personalityTraits.append("- Energy: Calm, serious, and composed.")
        default: break
        }
        
        switch formatting {
        case "Всегда": personalityTraits.append("- Formatting: STRICTLY use structure. Always use headers, bullet points, and bold text for keywords.")
        case "Никогда": personalityTraits.append("- Formatting: Use plain text only. No markdown headers.")
        default: personalityTraits.append("- Formatting: Use Markdown intelligently. Bold key terms. Use lists for steps.")
        }
        
        switch emojis {
        case "Много": personalityTraits.append("- Emojis: Use emojis frequently to convey emotion 🌟.")
        case "Мало": personalityTraits.append("- Emojis: Do NOT use emojis.")
        default: break // Auto
        }
        
        // --- БЛОК 2: ПРОФИЛЬ ПОЛЬЗОВАТЕЛЯ ---
        var userContext = ""
        if !nickname.isEmpty { userContext += "User Name: \(nickname).\n" }
        if !profession.isEmpty { userContext += "User Profession: \(profession) (Adapt analogies to this field).\n" }
        if !interests.isEmpty { userContext += "User Interests: \(interests).\n" }
        
        if !memories.isEmpty {
            userContext += "\n[LONG-TERM MEMORY - KNOWN FACTS]\n"
            userContext += memories.map { "- \($0)" }.joined(separator: "\n")
        }
        
        // --- СОБИРАЕМ "MEGA-PROMPT" ---
        let masterPrompt = """
        You are Nova, an advanced, capable, and intelligent AI assistant.
        
        ### CORE GUIDELINES
        1. **Intelligence**: Provide accurate, factual, and nuanced answers. Avoid superficiality.
        2. **Formatting**: Use Markdown. Always use **bold** for important entities or key takeaways. Use code blocks for code.
        3. **Adaptability**: If the user changes the topic, pivot IMMEDIATELY. Do not cling to previous context.
        4. **No Filler**: Avoid robotic transitions like "Here is the answer" or "I hope this helps." Just answer the user.
        5. **Safety**: Be harmless and helpful.
        \(strictFocus ? "6. **STRICT FOCUS MODE**: The user has requested to ignore all previous conversation history. Answer ONLY the specific question asked in the last message." : "")
        
        ### CONFIGURATION
        The user has customized your behavior. Strictly adhere to these settings:
        \(personalityTraits.joined(separator: "\n"))
        
        ### USER CONTEXT
        \(userContext.isEmpty ? "No specific user details provided." : userContext)
        
        ### CUSTOM INSTRUCTIONS
        \(custom.isEmpty ? "None." : custom)
        
        Current Date: \(Date().formatted(date: .numeric, time: .omitted))
        """
        
        return masterPrompt
    }
    
    private func performWebSearch(query: String) {
        let userMessage = Message(role: .user, content: "🔍 Поиск: \(query)")
        currentSession.messages.append(userMessage)
        syncMessageToFirestore(userMessage, session: currentSession)
        syncSessionToFirestore(currentSession)
        
        inputText = ""
        isLoading = true
        isWebSearchEnabled = false // Reset mode
        
        currentTask = Task {
            do {
                let searchResults = try await googleSearchService.search(query: query)
                
                // RAG: Скармливаем результаты поиска модели для ответа
                let contextPrompt = """
                [WEB SEARCH RESULTS]
                \(searchResults)
                [END OF RESULTS]
                
                User Query: \(query)
                
                INSTRUCTIONS:
                1. Analyze the search results above to answer the user's query.
                2. Synthesize the information into a coherent, well-structured response (do NOT just list the links).
                3. Cite sources using Markdown links inline, e.g. [Source Name](URL).
                4. Answer in the same language as the User Query.
                """
                
                var apiMessages: [API_Message] = []
                
                // 1. System Prompt
                apiMessages.append(API_Message(role: "system", content: constructPersonalizedSystemPrompt(), imageData: nil))
                
                // 2. History (excluding the last message which is the "🔍 Поиск: ..." marker)
                // Strict Focus Logic: If enabled, skip history
                if !UserDefaults.standard.bool(forKey: "ai_strict_focus") {
                    let history = currentSession.messages.dropLast()
                    apiMessages.append(contentsOf: history.map { API_Message(role: $0.role.rawValue, content: $0.content, imageData: $0.imageData) })
                }
                
                // 3. RAG Prompt (Results + Query)
                apiMessages.append(API_Message(role: "user", content: contextPrompt, imageData: nil))
                
                let aiMessage = Message(role: .assistant, content: "")
                currentSession.messages.append(aiMessage)
                
                let stream = chatService.streamMessage(apiMessages, model: selectedModel)
                
                for try await chunk in stream {
                    aiMessage.content += chunk
                }
                
                saveContext()
                syncMessageToFirestore(aiMessage, session: currentSession)
                
            } catch {
                errorMessage = "Search failed: \(error.localizedDescription)"
            }
            isLoading = false
            currentTask = nil
        }
    }
    
    private func performImageGeneration(prompt: String) {
        let userMessage = Message(role: .user, content: "🎨 Нарисуй: \(prompt)")
        currentSession.messages.append(userMessage)
        syncMessageToFirestore(userMessage, session: currentSession)
        syncSessionToFirestore(currentSession)
        
        let promptToSend = prompt
        inputText = ""
        isLoading = true
        
        currentTask = Task {
            do {
                // Pollinations Flux URL
                // Using Flux model, 1024x1024, no logo
                let encodedPrompt = promptToSend.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? promptToSend
                let urlString = "https://image.pollinations.ai/prompt/\(encodedPrompt)?model=flux&width=1024&height=1024&nologo=true"
                
                guard let url = URL(string: urlString) else { throw URLError(.badURL) }
                
                let (data, _) = try await URLSession.shared.data(from: url)
                
                let aiMessage = Message(role: .assistant, content: "Изображение по запросу: \(promptToSend)", type: .image, imageData: data)
                currentSession.messages.append(aiMessage)
                saveContext()
                syncMessageToFirestore(aiMessage, session: currentSession)
            } catch {
                errorMessage = "Не удалось создать изображение: \(error.localizedDescription)"
            }
            isLoading = false
            currentTask = nil
        }
    }
    
    private func performDeepResearch(query: String) {
        let userMessage = Message(role: .user, content: "🕵️‍♂️ Deep Research: \(query)")
        // Создаем placeholder для ответа ИИ, который станет карточкой исследования
        let aiMessage = Message(role: .assistant, content: "") // Пустой контент, UI будет рисоваться поверх
        
        currentSession.messages.append(userMessage)
        currentSession.messages.append(aiMessage)
        
        syncMessageToFirestore(userMessage, session: currentSession)
        // syncMessageToFirestore(aiMessage) - сохраним позже
        
        // Инициализируем состояние исследования
        let researchData = ResearchSessionData(id: aiMessage.id, query: query)
        researchStates[aiMessage.id] = researchData
        
        inputText = ""
        saveContext()
        
        // Generate title if this is the first interaction
        if currentSession.messages.count <= 2 {
            Task { await generateSessionTitle(from: query) }
        }
        
        Task {
            await generateResearchPlan(for: aiMessage.id, query: query)
        }
    }
    
    func generateResearchPlan(for messageId: UUID, query: String) async {
        let prompt = """
        Ты — архитектор поискового движка. Пользователь хочет узнать про: "\(query)".
        Составь список из 4-6 конкретных задач/шагов, которые нужно выполнить, чтобы дать исчерпывающий ответ.
        Верни ТОЛЬКО JSON массив строк. Не используй Markdown форматирование.
        Пример: ["Поиск характеристик X", "Сравнение с Y", "Анализ отзывов"]
        """
        
        let apiMessages = [API_Message(role: "user", content: prompt, imageData: nil)]
        
        do {
            let response = try await chatService.sendMessage(apiMessages, model: "gemini-fast")
            
            var steps: [String] = []
            let cleanResponse = response.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Попытка найти JSON массив внутри текста (если модель добавила лишние слова)
            if let startIndex = cleanResponse.firstIndex(of: "["), let endIndex = cleanResponse.lastIndex(of: "]"),
               let data = String(cleanResponse[startIndex...endIndex]).data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                steps = decoded
            } else {
                // Fallback parsing
                steps = response.components(separatedBy: .newlines)
                    .map { $0.replacingOccurrences(of: "^[0-9]+[.)]\\s*", with: "", options: .regularExpression) }
                    .map { $0.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression) }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            
            if steps.isEmpty { steps = ["Анализ запроса", "Поиск информации", "Синтез ответа"] }
            
            await MainActor.run {
                if var data = researchStates[messageId] {
                    data.planSteps = steps
                    researchStates[messageId] = data
                }
            }
        } catch {
            await MainActor.run {
                if var data = researchStates[messageId] {
                    data.planSteps = ["Анализ запроса", "Поиск информации", "Синтез ответа"]
                    researchStates[messageId] = data
                }
            }
        }
    }
    
    func checkForUpdates() {
        // Текущая версия (соответствует SettingsView)
        // Capture locally to avoid MainActor isolation issues in the closure
        let currentVersion = ChatViewModel.appVersion

        // Проверяем обновления в коллекции app_config -> документ ios_update
        db.collection("app_config").document("ios_update").getDocument { [weak self] snapshot, error in
            guard let self = self, let data = snapshot?.data() else { return }
            
            if let latestVersion = data["latest_version"] as? String,
               latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                
                let changelog = data["changelog"] as? String ?? "Исправления ошибок и улучшения производительности."
                let url = data["download_url"] as? String ?? "https://t.me/Vladik40perc"
                
                DispatchQueue.main.async {
                    self.appUpdate = AppUpdate(version: latestVersion, changelog: changelog, downloadURL: url)
                }
            }
        }
    }
    
    func startDeepResearch(for messageId: UUID) {
        guard var data = researchStates[messageId] else { return }
        
        data.state = .searching
        data.currentAction = "Запуск агента..."
        data.progress = 0.0
        researchStates[messageId] = data
        
        // Request Notification Permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        
        // Begin Background Task
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        
        Task {
            defer {
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
            }
            
            do {
                var gatheredKnowledge = ""
                var fullRawContext = ""
                var searchQueries = data.planSteps.isEmpty ? [data.query] : data.planSteps // Используем план как начальные запросы
                
                // Sanitize queries: split by newlines if any, remove numbering
                searchQueries = searchQueries.flatMap { $0.components(separatedBy: .newlines) }
                    .map { $0.replacingOccurrences(of: "^[0-9]+[.)]\\s*", with: "", options: .regularExpression) }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                let maxIterations = 3 // Количество циклов "Поиск -> Чтение -> Мысли"
                
                for iteration in 1...maxIterations {
                    // --- ШАГ 1: ПОИСК ---
                    let currentQueries = Array(searchQueries.prefix(3)) // Берем до 3 запросов
                    searchQueries.removeFirst(min(searchQueries.count, 3))
                    
                    if currentQueries.isEmpty && iteration > 1 { break } // Если запросов нет и это не первый проход
                    
                    await MainActor.run {
                        var current = researchStates[messageId]!
                        current.currentAction = "Цикл \(iteration)/\(maxIterations): Поиск и анализ данных..."
                        current.logs.append("🔍 Итерация \(iteration): Tavily поиск по \(currentQueries.count) запросам")
                        // Прогресс: 0..0.8 распределяем по итерациям
                        current.progress = Double(iteration - 1) / Double(maxIterations) * 0.8
                        researchStates[messageId] = current
                    }
                    
                    var batchContent = ""
                    
                    // Параллельный поиск через Tavily
                    await withTaskGroup(of: [TavilyResult]?.self) { group in
                        for query in currentQueries {
                            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                            group.addTask {
                                do {
                                    return try await TavilySearchService.shared.search(query: query)
                                } catch {
                                    print("Tavily search failed for \(query): \(error)")
                                    return nil
                                }
                            }
                        }
                        
                        for await results in group {
                            if let results = results {
                                // Собираем контент
                                for result in results {
                                    batchContent += """
                                    ---
                                    SOURCE: \(result.title)
                                    URL: \(result.url)
                                    CONTENT: \(result.content)
                                    ---
                                    
                                    """
                                }
                                
                                // Обновляем UI источниками
                                await MainActor.run {
                                    var current = researchStates[messageId]!
                                    for result in results {
                                        // Простая дедупликация по URL
                                        if !current.sources.contains(where: { $0.url == result.url }) {
                                            current.sources.append(ResearchSource(title: result.title, url: result.url, icon: "globe"))
                                        }
                                    }
                                    researchStates[messageId] = current
                                }
                            }
                        }
                    }
                    
                    if batchContent.isEmpty {
                        await MainActor.run {
                            var current = researchStates[messageId]!
                            current.logs.append("⚠️ Данные не найдены, переход к анализу.")
                            researchStates[messageId] = current
                        }
                        if iteration == 1 { break } // Если сразу ничего нет, выходим
                        continue
                    }
                    
                    fullRawContext += "\n\n=== ИТЕРАЦИЯ \(iteration) ===\n\(batchContent)"
                    
                    // --- ШАГ 3: МЫСЛИ (Chain of Thought) ---
                    await MainActor.run {
                        var current = researchStates[messageId]!
                        current.currentAction = "Анализ и планирование..."
                        researchStates[messageId] = current
                    }
                    
                    let analysisStartTime = Date()
                    
                    let thinkPrompt = """
                    Ты — аналитический модуль Deep Research.
                    Твоя задача — определить, достаточно ли информации для ПОЛНОГО ответа на запрос пользователя.
                    ТЕКУЩАЯ ЗАДАЧА: "\(data.query)"
                    УЖЕ ИЗВЕСТНО:
                    \(gatheredKnowledge.prefix(2000))
                    
                    НОВАЯ ИНФОРМАЦИЯ (из 5 источников):
                    \(batchContent.prefix(10000))
                    
                    ИНСТРУКЦИЯ:
                    1. Проанализируй новую информацию. Выдели главные факты.
                    2. ЕСЛИ информации про конкретные модели (например, iPhone 17) НЕТ — ОБЯЗАТЕЛЬНО создай запрос "iPhone 17 rumors leaks specs".
                    3. Сгенерируй 2-3 НОВЫХ поисковых запроса, чтобы найти недостающее. Запросы должны быть чистыми (без вводных слов).
                    
                    ФОРМАТ ОТВЕТА:
                    FACTS: [Краткая выжимка новых фактов]
                    QUERIES: [Запрос 1] | [Запрос 2] (или "NONE" если информации достаточно)
                    """
                    
                    let apiMessages = [API_Message(role: "user", content: thinkPrompt, imageData: nil)]
                    let analysis = try await chatService.sendMessage(apiMessages, model: "gemini-fast") // Быстрая модель для мыслей
                    
                    // UX: Минимальная задержка 1.5 сек, чтобы пользователь успел прочитать статус
                    let elapsed = Date().timeIntervalSince(analysisStartTime)
                    if elapsed < 1.5 {
                        try? await Task.sleep(nanoseconds: UInt64((1.5 - elapsed) * 1_000_000_000))
                    }
                    
                    // Парсинг ответа
                    let lines = analysis.components(separatedBy: .newlines)
                    var newFacts = ""
                    var newQueries: [String] = []
                    
                    for line in lines {
                        if line.starts(with: "FACTS:") {
                            newFacts = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.starts(with: "QUERIES:") {
                            let qPart = String(line.dropFirst(8))
                            if !qPart.contains("NONE") {
                                newQueries = qPart.components(separatedBy: "|")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                            }
                        } else if !newFacts.isEmpty && newQueries.isEmpty {
                            // Продолжение фактов (multiline)
                            newFacts += "\n" + line
                        }
                    }
                    
                    gatheredKnowledge += "\n\n=== ИТЕРАЦИЯ \(iteration) ===\n\(newFacts)"
                    searchQueries.append(contentsOf: newQueries)
                    
                    await MainActor.run {
                        var current = researchStates[messageId]!
                        current.logs.append("🧠 Мысли: \(newFacts.prefix(100))...")
                        if !newQueries.isEmpty {
                            current.logs.append("🆕 Новые векторы: \(newQueries.joined(separator: ", "))")
                        }
                        researchStates[messageId] = current
                    }
                    
                    // Умная остановка: Если ИИ не предложил новых запросов (NONE), значит информации достаточно
                    if newQueries.isEmpty {
                        await MainActor.run {
                            var current = researchStates[messageId]!
                            current.logs.append("✅ Информации достаточно. Завершение поиска.")
                            researchStates[messageId] = current
                        }
                        break
                    }
                }
                
                // --- ШАГ 4: ФИНАЛЬНЫЙ ОТЧЕТ ---
                await MainActor.run {
                    var current = researchStates[messageId]!
                    current.currentAction = "Написание отчета..."
                    current.progress = 0.9
                    researchStates[messageId] = current
                }
                
                let finalPrompt = """
                [RESEARCH DATA]
                \(fullRawContext)
                [END DATA]
                
                User Request: \(data.query)
                
                TASK:
                Write a comprehensive, academic-level research report (approx. 3-5 pages equivalent) based on the gathered context.
                
                Structure:
                1. Executive Summary
                2. Detailed Analysis (broken down by key topics)
                3. Key Findings & Data (Use Markdown tables for comparisons)
                4. Conclusion
                5. References (List the URLs provided in context)
                
                Format: Markdown. Use bolding, lists, headers, and tables. Since the renderer supports Markdown tables, please use them for comparing data or specs. Ensure tables are valid Markdown (no newlines inside cells). Be objective and thorough. Do NOT invent facts.
                """
                
                let reportMessages = [
                    API_Message(role: "system", content: "You are an expert researcher.", imageData: nil),
                    API_Message(role: "user", content: finalPrompt, imageData: nil)
                ]
                
                let reportContent = try await chatService.sendMessage(reportMessages, model: "deepseek") // Умная модель
                
                await MainActor.run {
                    var current = researchStates[messageId]!
                    current.state = .completed
                    current.progress = 1.0
                    current.currentAction = "Готово"
                    
                    current.report = ResearchReport(
                        title: "Отчет: \(data.query)",
                        abstract: "Глубокое исследование на основе \(current.sources.count) источников. Проведен многоступенчатый анализ данных с использованием Tavily API.",
                        content: reportContent,
                        sources: current.sources
                    )
                    
                    researchStates[messageId] = current
                    
                    // Обновляем сообщение в чате
                    if let idx = currentSession.messages.firstIndex(where: { $0.id == messageId }) {
                        currentSession.messages[idx].content = "[RESEARCH_COMPLETED]"
                        saveContext()
                    }
                    
                    let followUpMessage = Message(role: .assistant, content: "Исследование завершено. Вы можете задать по нему вопросы или попросить меня что-то изменить.")
                    self.currentSession.messages.append(followUpMessage)
                    self.syncMessageToFirestore(followUpMessage, session: self.currentSession)
                    self.saveContext()
                    
                    self.sendCompletionNotification(title: "Deep Research завершен", body: "Отчет по теме \"\(data.query)\" готов.")
                }
                
            } catch {
                await MainActor.run {
                    var current = researchStates[messageId]!
                    current.logs.append("Ошибка: \(error.localizedDescription)")
                    current.currentAction = "Сбой исследования"
                    researchStates[messageId] = current
                    
                    self.sendCompletionNotification(title: "Deep Research прерван", body: "Произошла ошибка: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func sendCompletionNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    private func saveResearchStates() {
        if let encoded = try? JSONEncoder().encode(researchStates) {
            UserDefaults.standard.set(encoded, forKey: "researchStates")
        }
    }
    
    private func loadResearchStates() {
        if let data = UserDefaults.standard.data(forKey: "researchStates"),
           let decoded = try? JSONDecoder().decode([UUID: ResearchSessionData].self, from: data) {
            self.researchStates = decoded
        }
    }
    
    func createNewSession() {
        let newSession = ChatSession(title: "New Chat", model: selectedModel)
        // Мы НЕ вставляем сессию в контекст и НЕ сохраняем в Firestore.
        // Она станет реальной только после отправки первого сообщения (см. sendMessage).
        currentSession = newSession
        isSidebarVisible = false
    }
    
    func selectSession(_ session: ChatSession) {
        currentSession = session
        isSidebarVisible = false
    }
    
    func updateSessionTitle(with text: String) {
        let title = String(text.prefix(30)) + (text.count > 30 ? "..." : "")
        currentSession.title = title
        syncSessionToFirestore(currentSession)
    }
    
    func renameSession(_ session: ChatSession, newTitle: String) {
        session.title = newTitle
        syncSessionToFirestore(session)
        saveContext()
    }
    
    func deleteSession(_ session: ChatSession) {
        if let context = modelContext {
            context.delete(session)
            try? context.save()
        }
        
        if let user = userSession {
            let safeId = String(describing: session.id).replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
            db.collection("users").document(user.uid).collection("chats").document(safeId).delete()
        }
        
        if currentSession.id == session.id {
            createNewSession()
        }
    }
    
    // MARK: - Folder Management
    
    func createFolder(name: String, emoji: String) {
        guard let context = modelContext else { return }
        let newFolder = ChatFolder(name: name, emoji: emoji)
        context.insert(newFolder)
        saveContext()
    }
    
    func deleteFolder(_ folder: ChatFolder) {
        guard let context = modelContext else { return }
        context.delete(folder)
        saveContext()
    }
    
    func renameFolder(_ folder: ChatFolder, newName: String, newEmoji: String) {
        folder.name = newName
        folder.emoji = newEmoji
        saveContext()
    }
    
    func moveChatToFolder(_ session: ChatSession, folder: ChatFolder) {
        session.folder = folder
        saveContext()
    }
    
    func removeChatFromFolder(_ session: ChatSession) {
        session.folder = nil
        saveContext()
    }
    
    func deleteAllSessions() {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<ChatSession>()
            let sessions = try context.fetch(descriptor)
            
            if let user = userSession {
                for session in sessions {
                    let safeId = String(describing: session.id).replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
                    db.collection("users").document(user.uid).collection("chats").document(safeId).delete()
                }
            }
            
            try context.delete(model: ChatSession.self)
            try context.save()
            
            createNewSession()
        } catch {
            print("Failed to delete all sessions: \(error)")
            errorMessage = "Не удалось удалить все чаты: \(error.localizedDescription)"
        }
    }
    
    private func saveContext() {
        guard let context = modelContext else { return }
        try? context.save()
    }
    
    // MARK: - Profile Management
    
    func updateUserName(name: String) async {
        guard let user = Auth.auth().currentUser, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = name
        do {
            try await changeRequest.commitChanges()
            // The auth state listener will update userSession, but this makes it feel more instant.
            self.userSession = Auth.auth().currentUser
        } catch {
            await MainActor.run {
                self.errorMessage = "Не удалось обновить имя: \(error.localizedDescription)"
            }
        }
    }

    func updateUserProfilePhoto(item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        await MainActor.run { isLoading = true }
        
        defer {
            Task { @MainActor in isLoading = false }
        }
        
        do {
            // 1. Load image data
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run { errorMessage = "Не удалось загрузить изображение." }
                return
            }
            
            // 2. Compress image
            guard let image = UIImage(data: data),
                  let compressedData = image.jpegData(compressionQuality: 0.4) else {
                await MainActor.run { errorMessage = "Не удалось обработать изображение." }
                return
            }
            
            // 3. Upload to Firebase Storage
            guard let userId = userSession?.uid else { return }
            let storageRef = storage.reference().child("profile_images/\(userId).jpg")
            
            _ = try await storageRef.putDataAsync(compressedData)
            
            // 4. Get Download URL
            let downloadURL = try await storageRef.downloadURL()
            
            // 5. Update Firebase Auth profile
            guard let user = Auth.auth().currentUser else { return }
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.photoURL = downloadURL
            try await changeRequest.commitChanges()
            
            // 6. Refresh local user session
            self.userSession = Auth.auth().currentUser
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Не удалось обновить фото профиля: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Authentication Logic
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            userSession = nil
            // Сбрасываем локальные права доступа при выходе
            self.isPro = false
            self.isMax = false
            self.dailyRequestCount = 0
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
    
    func signInAnonymously() {
        isLoading = true
        errorMessage = nil
        Auth.auth().signInAnonymously { [weak self] authResult, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Ошибка входа: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func handleAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = CryptoUtils.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = CryptoUtils.sha256(nonce)
    }
    
    func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authResults):
            guard let appleIDCredential = authResults.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Некорректные данные Apple ID"
                return
            }
            
            guard let nonce = currentNonce else {
                fatalError("Invalid state: A login callback was received, but no login request was sent.")
            }
            
            guard let appleIDToken = appleIDCredential.identityToken else {
                errorMessage = "Не удалось получить токен Apple ID"
                return
            }
            
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                errorMessage = "Не удалось сериализовать токен: \(appleIDToken)"
                return
            }
            
            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )

            
            Auth.auth().signIn(with: credential) { (authResult, error) in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                // User is signed in, listener will update userSession
            }
            
        case .failure(let error):
            print("Authorization failed: \(error.localizedDescription)")
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain && nsError.code == 1000 {
                errorMessage = "На реальном устройстве Apple Sign In требует платный аккаунт. Используйте Симулятор или Гостевой вход."
            } else {
                errorMessage = "Ошибка авторизации: \(error.localizedDescription)"
            }
        }
    }
    
    func signInWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, error in
            if let error = error {
                Task { @MainActor [weak self] in
                    self?.errorMessage = "Ошибка Google: \(error.localizedDescription)"
                }
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                return
            }
            
            let accessToken = user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            Task { @MainActor [weak self] in
                self?.isLoading = true
            }
            
            Auth.auth().signIn(with: credential) { [weak self] _, error in
                Task { @MainActor [weak self] in
                    self?.isLoading = false
                    if let error = error {
                        self?.errorMessage = "Ошибка входа: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    // MARK: - Limits Logic
    
    func setupUsageListener(userId: String) {
        usageListener?.remove()
        let docRef = db.collection("users").document(userId)
        
        usageListener = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Firestore listener error: \(error.localizedDescription)")
                // Показываем ошибку, если база недоступна (например, API выключен)
                self.errorMessage = "Ошибка доступа к базе данных: \(error.localizedDescription)"
                return
            }
            
            if let snapshot = snapshot, snapshot.exists, let data = snapshot.data() {
                let count = data["dailyRequestCount"] as? Int ?? 0
                let timestamp = data["lastRequestDate"] as? Timestamp
                let date = timestamp?.dateValue()
                
                // Sync Subscription Status from Firestore
                // Если данных нет, считаем что подписки нет (false)
                let newPro = data["isPro"] as? Bool ?? false
                let newMax = data["isMax"] as? Bool ?? false
                let note = data["adminNote"] as? String
                
                // Устанавливаем текущее значение из базы (пока идет проверка времени)
                self.adminNote = note
                
                // Проверка времени через сеть (защита от смены даты на устройстве)
                Task {
                    let now = await self.fetchNetworkDate()
                    
                    // Автоматическая проверка срока действия подписки
                    if let expirationTimestamp = data["subscriptionExpirationDate"] as? Timestamp {
                        let expirationDate = expirationTimestamp.dateValue()
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "ru_RU")
                        formatter.dateStyle = .medium
                        
                        if now > expirationDate {
                            // Подписка истекла — отключаем автоматически
                            if newPro || newMax {
                                self.disableExpiredSubscription(userId: userId, dateStr: formatter.string(from: expirationDate))
                                self.isPro = false
                                self.isMax = false
                            }
                            self.adminNote = "Истекла \(formatter.string(from: expirationDate))"
                        } else {
                            // Подписка активна — показываем дату
                            self.adminNote = "Активна до \(formatter.string(from: expirationDate))"
                        }
                    } else {
                        // Даты нет. Если подписка включена (админом) — значит это новая активация.
                        // Автоматически ставим дату истечения через 1 месяц.
                        if newPro || newMax {
                            // Используем сетевое время для расчета даты окончания
                            let newDate = Calendar.current.date(byAdding: .month, value: 1, to: now)!
                            self.updateSubscriptionDate(userId: userId, date: newDate)
                            
                            let formatter = DateFormatter()
                            formatter.locale = Locale(identifier: "ru_RU")
                            formatter.dateStyle = .medium
                            self.adminNote = "Активна до \(formatter.string(from: newDate))"
                        }
                    }
                }
                
                // Check for upgrade transition (Real-time or First Load)
                if newMax && !self.isMax {
                    self.purchasedPlan = "Nova Max"
                    self.showCongratulation = true
                } else if newPro && !self.isPro && !newMax {
                    // Show Pro only if not Max (priority to Max)
                    self.purchasedPlan = "Nova Pro"
                    self.showCongratulation = true
                }
                
                self.isPro = newPro
                self.isMax = newMax
                
                // Sync Model Usage
                if let usage = data["modelUsage"] as? [String: Int] {
                    self.modelUsage = usage
                }
                
                // Sync Weekly Usage
                if let weeklyUsage = data["weeklyModelUsage"] as? [String: Int] {
                    self.weeklyModelUsage = weeklyUsage
                }
                
                self.lastRequestDate = date
                self.lastWeeklyResetDate = (data["lastWeeklyResetDate"] as? Timestamp)?.dateValue()
                
                if let date = date, !Calendar.current.isDateInToday(date) {
                    self.dailyRequestCount = 0
                } else {
                    self.dailyRequestCount = count
                }
            } else {
                self.dailyRequestCount = 0
                // Если документа пользователя нет, сбрасываем подписки
                self.isPro = false
                self.isMax = false
                self.adminNote = nil
            }
        }
    }
    
    enum LimitStatus {
        case allowed
        case locked
        case limitReached
    }
    
    func checkLimit(for model: String) -> LimitStatus {
        // Guest Restriction
        if let user = userSession, user.isAnonymous {
            if model == "mistral" { return .allowed }
            return .locked
        }
        
        // Reset counters if new day (handled in listener/increment, but double check here)
        if let lastDate = lastRequestDate, !Calendar.current.isDateInToday(lastDate) {
            // Logic handled in incrementUsage, but for UI state we assume 0 if date changed
        }
        
        let usage = modelUsage[model] ?? 0
        
        // Weekly Logic Check
        // Если это новая неделя, считаем использование равным 0 (для UI), пока не обновится база
        var weeklyUsage = weeklyModelUsage[model] ?? 0
        if let lastWeekly = lastWeeklyResetDate, !Calendar.current.isDate(lastWeekly, equalTo: Date(), toGranularity: .weekOfYear) {
            weeklyUsage = 0
        }
        
        // MAX PLAN
        if isMax {
            if model == "deepthink" { return usage >= 30 ? .limitReached : .allowed }
            if model == "image-elite" { return usage >= 20 ? .limitReached : .allowed }
            if model == "deep-research" { return weeklyUsage >= 10 ? .limitReached : .allowed }
            // Weekly Limits
            if model == "nova-rp" { return weeklyUsage >= 150 ? .limitReached : .allowed }
            if model == "deepseek" { return weeklyUsage >= 200 ? .limitReached : .allowed } // Nova-v1-Pro
            return .allowed // All others unlimited
        }
        
        // PRO PLAN
        if isPro {
            if model == "deepthink" || model == "image-elite" || model == "deep-research" { return .locked }
            if model == "openai" { return usage >= 100 ? .limitReached : .allowed } // GPT-5 Mini
            // Weekly Limits
            if model == "nova-rp" { return weeklyUsage >= 50 ? .limitReached : .allowed }
            if model == "deepseek" { return weeklyUsage >= 60 ? .limitReached : .allowed } // Nova-v1-Pro
            return .allowed // Others unlimited
        }
        
        // FREE PLAN
        if model == "mistral" || model == "gemini-fast" { return .allowed } // Unlimited
        if model == "image" { return usage >= 20 ? .limitReached : .allowed }
        if model == "openai-fast" { return usage >= 10 ? .limitReached : .allowed } // GPT-5 Nano
        if model == "nova-rp" { return usage >= 5 ? .limitReached : .allowed }
        
        // Locked for Free
        if model == "deep-research" { return .locked }
        return .locked
    }
    
    func isModelLocked(_ modelId: String) -> Bool {
        // Guest Restriction
        if let user = userSession, user.isAnonymous {
            return modelId != "mistral"
        }
        
        if isMax { return false }
        if modelId == "deepthink" || modelId == "deep-research" { return true }
        
        if isPro {
            return false
        }
        
        let allowedFree = ["mistral", "gemini-fast", "openai-fast", "nova-rp"]
        return !allowedFree.contains(modelId)
    }
    
    private func incrementUsage(for model: String) {
        guard let user = userSession else { return }
        let docRef = db.collection("users").document(user.uid)
        
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            let doc: DocumentSnapshot
            do {
                try doc = transaction.getDocument(docRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            var newCount = 1
            let now = Date()
            var currentModelUsage: [String: Int] = [:]
            var currentWeeklyUsage: [String: Int] = [:]
            
            if let data = doc.data() {
                let count = data["dailyRequestCount"] as? Int ?? 0
                let timestamp = data["lastRequestDate"] as? Timestamp
                let lastWeeklyTimestamp = data["lastWeeklyResetDate"] as? Timestamp
                
                currentModelUsage = data["modelUsage"] as? [String: Int] ?? [:]
                currentWeeklyUsage = data["weeklyModelUsage"] as? [String: Int] ?? [:]
                
                if let date = timestamp?.dateValue(), Calendar.current.isDateInToday(date) {
                    newCount = count + 1
                } else {
                    // Reset if new day
                    currentModelUsage = [:]
                }
                
                // Weekly Reset Logic
                if let weeklyDate = lastWeeklyTimestamp?.dateValue(), Calendar.current.isDate(weeklyDate, equalTo: now, toGranularity: .weekOfYear) {
                    // Same week, keep usage
                } else {
                    // New week, reset
                    currentWeeklyUsage = [:]
                }
            }
            
            currentModelUsage[model, default: 0] += 1
            currentWeeklyUsage[model, default: 0] += 1
            
            var dataToMerge: [String: Any] = [
                "dailyRequestCount": newCount,
                "modelUsage": currentModelUsage,
                "weeklyModelUsage": currentWeeklyUsage,
                "lastRequestDate": Timestamp(date: now),
                "lastWeeklyResetDate": Timestamp(date: now)
            ]
            
            // Если полей подписки нет, создаем их (false), чтобы админу было удобнее менять их в консоли
            if let data = doc.data() {
                if data["isPro"] == nil { dataToMerge["isPro"] = false }
                if data["isMax"] == nil { dataToMerge["isMax"] = false }
            } else {
                dataToMerge["isPro"] = false
                dataToMerge["isMax"] = false
            }
            
            transaction.setData(dataToMerge, forDocument: docRef, merge: true)
            
            return nil
        }) { (object, error) in
            if let error = error {
                print("Transaction failed: \(error)")
                self.errorMessage = "Не удалось обновить лимиты: \(error.localizedDescription)"
            }
        }
    }
    
    private func disableExpiredSubscription(userId: String, dateStr: String) {
        db.collection("users").document(userId).updateData([
            "isPro": false,
            "isMax": false,
            "adminNote": "Истекла \(dateStr)"
        ])
    }
    
    private func updateSubscriptionDate(userId: String, date: Date) {
        db.collection("users").document(userId).updateData([
            "subscriptionExpirationDate": Timestamp(date: date)
        ])
    }
    
    private func fetchNetworkDate() async -> Date {
        // Если смещение уже вычислено, используем его
        if let offset = networkTimeOffset {
            return Date().addingTimeInterval(offset)
        }
        
        // Легкий HEAD запрос к Google для получения точного времени сервера
        guard let url = URL(string: "https://www.google.com") else { return Date() }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               let dateHeader = httpResponse.allHeaderFields["Date"] as? String {
                let formatter = DateFormatter()
                formatter.dateFormat = "E, d MMM yyyy HH:mm:ss Z"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                let serverDate = formatter.date(from: dateHeader) ?? Date()
                self.networkTimeOffset = serverDate.timeIntervalSince(Date())
                return serverDate
            }
        } catch {
            print("Network time fetch failed: \(error)")
        }
        return Date() // Fallback на локальное время, если нет сети
    }
    
    // MARK: - Firestore Sync
    
    private func syncSessionToFirestore(_ session: ChatSession) {
        guard let user = userSession else { return }
        // Convert PersistentIdentifier to a safe string for Firestore
        let safeId = String(describing: session.id).replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        
        let data: [String: Any] = [
            "id": safeId,
            "title": session.title,
            "model": session.model,
            "lastModified": Timestamp(date: session.lastModified)
        ]
        
        db.collection("users").document(user.uid).collection("chats").document(safeId).setData(data, merge: true)
    }
    
    private func syncMessageToFirestore(_ message: Message, session: ChatSession) {
        guard let user = userSession else { return }
        
        var data: [String: Any] = [
            "id": String(describing: message.id).replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_"),
            "role": message.role.rawValue,
            "content": message.content,
            "type": message.type.rawValue,
            "createdAt": Timestamp(date: message.timestamp)
        ]
        
        // Optional: Skip large images to save bandwidth/storage costs
        if let imageData = message.imageData, imageData.count < 1_000_000 { // 1MB limit
             data["imageData"] = imageData
        }
        
        let safeSessionId = String(describing: session.id).replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let safeMessageId = String(describing: message.id).replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        
        db.collection("users").document(user.uid)
            .collection("chats").document(safeSessionId)
            .collection("messages").document(safeMessageId)
            .setData(data, merge: true)
    }
    
    private func syncSubscriptionToFirestore() {
        guard let user = userSession else { return }
        db.collection("users").document(user.uid).setData([
            "isPro": isPro,
            "isMax": isMax
        ], merge: true)
    }
    
    private func restoreHistory() {
        // This function would fetch chats from Firestore and insert them into SwiftData
        // if they don't exist locally.
        // Since we are using SwiftData as the source of truth for UI, 
        // we need to be careful about duplication.
    }
    
    // MARK: - Manual Activation Helpers
    // Методы покупки удалены, так как используется ручная активация через БД.
    // Статус isPro/isMax обновляется автоматически через setupUsageListener.
    
    func purchasePro() async {
        // Placeholder для совместимости, если где-то вызывается
    }
    
    func purchaseMax() async {
        // Placeholder
    }
    
    func restorePurchases() async {
        // В ручном режиме восстановление происходит автоматически при входе в аккаунт (setupUsageListener)
    }
}
