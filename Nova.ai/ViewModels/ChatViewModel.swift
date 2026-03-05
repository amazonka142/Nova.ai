import SwiftUI
import Foundation
import ZIPFoundation
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
    static let appVersion = "1.2026.012"
    static let buildNumber = "8512"
    
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
    
    enum KnowledgeBaseError: LocalizedError {
        case limitReached(limit: Int)
        case maxOnly
        
        var errorDescription: String? {
            switch self {
            case .limitReached(let limit):
                return "Достигнут лимит файлов (\(limit))."
            case .maxOnly:
                return "База знаний доступна только в Nova Max."
            }
        }
    }

    @Published var currentSession: ChatSession
    @Published var currentProject: Project?
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
    private let maxFileSizeBytes = 5 * 1024 * 1024
    private let maxFileTextChars = 100_000
    private let maxKnowledgeChars = 20_000
    private let maxFirestoreContentChars = 200_000
    private let currentProjectIdKey = "current_project_id"
    private let maxContextMessageCount = 24
    private let maxContextCharacterBudget = 24_000
    private let eagerMessageRestoreLimit = 20
    
    // Deep Research State
    @Published var researchStates: [UUID: ResearchSessionData] = [:] {
        didSet {
            scheduleResearchStateSave()
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
    private var researchSaveWorkItem: DispatchWorkItem?
    private var lastSyncedSessionSignatures: [String: String] = [:]
    private var lastSyncedMessageSignatures: [String: String] = [:]
    private var restoredMessageChatIds: Set<String> = []
    private let researchSaveDelay: TimeInterval = 0.75
    
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
        let newSession = ChatSession(title: "Loading...", model: "gemini-fast", project: nil)
        self.currentSession = newSession
        self.currentProject = nil
        self.loadResearchStates()
        self.checkForUpdates()
        
        // Listen to Auth changes
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.userSession = user
            if let user = user {
                self?.restoredMessageChatIds.removeAll()
                self?.setupUsageListener(userId: user.uid)
                self?.restoreHistory()
                if user.isAnonymous {
                    self?.selectedModel = "mistral"
                }
            } else {
                self?.usageListener?.remove()
                self?.dailyRequestCount = 0
                self?.lastSyncedSessionSignatures.removeAll()
                self?.lastSyncedMessageSignatures.removeAll()
                self?.restoredMessageChatIds.removeAll()
            }
        }
    }
    
    func setContext(_ context: ModelContext) {
        self.modelContext = context

        initializeProjects()
        if userSession != nil {
            restoreHistory()
        }
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

    private func requestMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(completion)
        }
    }
    
    private func startRecording() {
        if audioEngine.isRunning {
            stopRecording()
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
                
                self.requestMicrophonePermission { allowed in
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

    private func shouldFallbackFromStream(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorBadServerResponse {
            return true
        }
        return false
    }

    private func isOpenAIModel(_ model: String) -> Bool {
        let lowered = model.lowercased()
        return lowered.contains("openai") || lowered.contains("gpt")
    }

    private func isAzureContentFilterError(_ error: Error) -> Bool {
        let message = (error as NSError).localizedDescription.lowercased()
        return message.contains("azure-openai") &&
            (message.contains("content management policy") || message.contains("response was filtered"))
    }

    private func userFacingSendErrorMessage(_ error: Error) -> String {
        if isAzureContentFilterError(error) {
            return "GPT-5 отклонил запрос фильтром контента. Переформулируй сообщение или используй Gemini 2.5 Flash Lite."
        }
        return "Failed to send message: \(error.localizedDescription)"
    }

    private func streamOrRequestResponse(_ apiMessages: [API_Message], model: String) async throws -> String {
        do {
            var response = ""
            let stream = chatService.streamMessage(apiMessages, model: model)
            for try await chunk in stream {
                response += chunk
            }
            return response
        } catch {
            guard shouldFallbackFromStream(error) else { throw error }
            return try await chatService.sendMessage(apiMessages, model: model)
        }
    }

    private func compactConversationHistory(_ messages: [Message], strictFocus: Bool) -> [Message] {
        let conversation = messages.filter { $0.role != .system }
        guard !conversation.isEmpty else { return [] }

        if strictFocus {
            return Array(conversation.suffix(1))
        }

        var selected: [Message] = []
        var totalChars = 0

        for message in conversation.reversed() {
            let messageChars = message.content.count
            let messageImageWeight = (message.imageData?.count ?? 0) / 4
            let estimatedWeight = messageChars + messageImageWeight

            if !selected.isEmpty &&
                (selected.count >= maxContextMessageCount || totalChars + estimatedWeight > maxContextCharacterBudget) {
                break
            }

            selected.append(message)
            totalChars += estimatedWeight
        }

        return selected.reversed()
    }

    private func buildAPIContext(systemPrompt: String, messages: [Message], strictFocus: Bool) -> [API_Message] {
        var apiMessages: [API_Message] = [
            API_Message(role: "system", content: systemPrompt, imageData: nil)
        ]

        let history = compactConversationHistory(messages, strictFocus: strictFocus)
        apiMessages.append(contentsOf: history.map {
            API_Message(role: $0.role.rawValue, content: $0.content, imageData: $0.imageData)
        })

        return apiMessages
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
        
        do {
            self.pendingFileAttachment = try readAttachmentItem(url: url)
        } catch {
            self.errorMessage = error.localizedDescription
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
            if currentSession.project == nil {
                currentSession.project = currentProject
            }
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
        let sessionForMemory = currentSession
        let projectForMemory = currentProject
        self.smartSuggestions = [] // Очищаем старые подсказки
        
        // 2. В ЭТО ЖЕ ВРЕМЯ (в фоне) запускаем шпиона-аналитика
        Task(priority: .userInitiated) {
            await analyzeForMemory(userMessage: inputToSend, in: sessionForMemory, project: projectForMemory)
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
                var effectiveSystemPrompt = buildEffectiveSystemPrompt()
                var modelToSend = selectedModel
                
                if activeTool == .reasoning {
                    modelToSend = "deepthink"
                }
                
                if modelToSend == "deepthink" {
                    effectiveSystemPrompt = "You are a deep thinking AI. Use Chain of Thought reasoning. Explain your steps."
                } else if selectedModel == "nova-rp" {
                    modelToSend = "deepseek"
                    effectiveSystemPrompt = "You are Nova-v1-RP. Engage in a detailed and immersive roleplay. Adopt the persona requested by the user or implied by the context. Do not break character. Be descriptive."
                }
                
                effectiveSystemPrompt = appendKnowledgeBase(to: effectiveSystemPrompt)
                let strictFocus = UserDefaults.standard.bool(forKey: "ai_strict_focus")
                let apiMessages = buildAPIContext(
                    systemPrompt: effectiveSystemPrompt,
                    messages: currentSession.messages,
                    strictFocus: strictFocus
                )
                
                // Create placeholder AI message
                let aiMessage = Message(role: .assistant, content: "")
                currentSession.messages.append(aiMessage)
                
                // Primary request + transport fallback; if GPT-* is content-filtered by Azure, auto-fallback to Gemini.
                do {
                    aiMessage.content = try await streamOrRequestResponse(apiMessages, model: modelToSend)
                } catch {
                    if isOpenAIModel(modelToSend) && isAzureContentFilterError(error) {
                        aiMessage.content = try await streamOrRequestResponse(apiMessages, model: "gemini-fast")
                    } else {
                        throw error
                    }
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
                    errorMessage = userFacingSendErrorMessage(error)
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
            if currentSession.project == nil {
                currentSession.project = currentProject
            }
            modelContext?.insert(currentSession)
        }
        
        // Background Memory Analysis
        let sessionForMemory = currentSession
        let projectForMemory = currentProject
        Task(priority: .userInitiated) {
            await analyzeForMemory(userMessage: cleanText, in: sessionForMemory, project: projectForMemory)
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
        var effectiveSystemPrompt = buildEffectiveSystemPrompt()
        var modelToSend = selectedModel
        
        if selectedModel == "nova-rp" {
            modelToSend = "deepseek"
            effectiveSystemPrompt = "You are Nova-v1-RP. Engage in a detailed and immersive roleplay. Adopt the persona requested by the user or implied by the context. Do not break character. Be descriptive."
        }
        
        effectiveSystemPrompt = appendKnowledgeBase(to: effectiveSystemPrompt)
        let strictFocus = UserDefaults.standard.bool(forKey: "ai_strict_focus")
        let apiMessages = buildAPIContext(
            systemPrompt: effectiveSystemPrompt,
            messages: currentSession.messages,
            strictFocus: strictFocus
        )
        
        // 4. Create Placeholder for AI Response
        let aiMessage = Message(role: .assistant, content: "")
        currentSession.messages.append(aiMessage)
        
        // 5. Call API & Accumulate Response
        // Using the selected model from settings
        do {
            do {
                let primaryResponse = try await streamOrRequestResponse(apiMessages, model: modelToSend)
                aiMessage.content = primaryResponse
            } catch {
                if isOpenAIModel(modelToSend) && isAzureContentFilterError(error) {
                    let fallbackResponse = try await streamOrRequestResponse(apiMessages, model: "gemini-fast")
                    aiMessage.content = fallbackResponse
                } else {
                    throw error
                }
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
        
        return aiMessage.content
    }
    
    // MARK: - Memory Management
    
    private var memoryLimit: Int {
        if isMax { return 50 }
        if isPro { return 25 }
        return 10
    }
    
    private func memoryKey(for project: Project?) -> String {
        guard let project = project else { return "ai_memories" }
        if project.memoryScope == .projectOnly {
            return "ai_memories_project_\(project.id.uuidString)"
        }
        return "ai_memories"
    }
    
    private func loadMemories(for project: Project?) -> [String] {
        UserDefaults.standard.stringArray(forKey: memoryKey(for: project)) ?? []
    }
    
    private func saveMemories(_ memories: [String], for project: Project?) {
        UserDefaults.standard.set(memories, forKey: memoryKey(for: project))
    }
    
    private func saveMemory(_ text: String, for project: Project?) -> Bool {
        var memories = loadMemories(for: project)
        
        if memories.contains(text) { return true }
        
        if memories.count >= memoryLimit {
            return false
        }
        memories.append(text)
        saveMemories(memories, for: project)
        return true
    }
    
    private func analyzeForMemory(userMessage: String, in session: ChatSession, project: Project?) async {
        NSLog("🚀 [Memory] Запуск фонового анализа для: '\(userMessage)'")
        
        let targetProject = project
        let existingMemories = loadMemories(for: targetProject)
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
                if self.saveMemory(fact, for: targetProject) {
                    let sysMsg = Message(role: .system, content: "💾 Запомнил: \(fact)")
                    session.messages.append(sysMsg)
                    self.syncMessageToFirestore(sysMsg, session: session)
                    self.saveContext()
                } else {
                    let limit = self.memoryLimit
                    let upsellMsg = Message(role: .assistant, content: "🧠 *Я заметил важный факт ('\(fact)'), но у меня переполнена память (\(limit)/\(limit)). В бесплатной версии я могу помнить только \(limit) фактов. Обновись до Pro, чтобы расширить мне мозг!*")
                    session.messages.append(upsellMsg)
                    self.syncMessageToFirestore(upsellMsg, session: session)
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
        let memories = loadMemories(for: currentProject)
        
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
        6. **Relevance First**: Start by answering the user's latest request directly. Do not ignore the main question.
        7. **Memory Discipline**: Use profile/memory only when directly relevant. Avoid unsolicited personal greetings or side comments.
        \(strictFocus ? "8. **STRICT FOCUS MODE**: The user has requested to ignore all previous conversation history. Answer ONLY the specific question asked in the last message." : "")
        
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
    
    private func buildEffectiveSystemPrompt() -> String {
        var prompt = constructPersonalizedSystemPrompt()
        
        if isMax, let projectPrompt = currentProject?.customSystemPrompt {
            let trimmed = projectPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                prompt = trimmed
            }
        }
        return prompt
    }
    
    private func buildKnowledgeBaseContext() -> String? {
        guard isMax, let project = currentProject, !project.knowledgeBase.isEmpty else { return nil }
        var context = "[PROJECT KNOWLEDGE BASE]\n"
        let limit = knowledgeFileLimit
        for file in project.knowledgeBase.prefix(limit) {
            context += "FILE: \(file.name)\n"
            context += file.content
            context += "\n\n"
        }
        if context.count > maxKnowledgeChars {
            context = String(context.prefix(maxKnowledgeChars)) + "\n[TRUNCATED]"
        }
        return context
    }
    
    private func appendKnowledgeBase(to prompt: String) -> String {
        guard let knowledgeContext = buildKnowledgeBaseContext() else { return prompt }
        return prompt + "\n\n" + knowledgeContext
    }
    
    private func performWebSearch(query: String) {
        let userMessage = Message(role: .user, content: "🔍 Поиск: \(query)")
        currentSession.messages.append(userMessage)
        currentSession.lastModified = Date()
        syncMessageToFirestore(userMessage, session: currentSession)
        syncSessionToFirestore(currentSession)
        incrementUsage(for: selectedModel)
        
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
                
                let strictFocus = UserDefaults.standard.bool(forKey: "ai_strict_focus")
                var apiMessages: [API_Message] = [
                    API_Message(
                        role: "system",
                        content: appendKnowledgeBase(to: buildEffectiveSystemPrompt()),
                        imageData: nil
                    )
                ]

                // History excludes the "🔍 Поиск: ..." marker already appended above.
                if !strictFocus {
                    let history = compactConversationHistory(Array(currentSession.messages.dropLast()), strictFocus: false)
                    apiMessages.append(contentsOf: history.map {
                        API_Message(role: $0.role.rawValue, content: $0.content, imageData: $0.imageData)
                    })
                }
                
                // 3. RAG Prompt (Results + Query)
                apiMessages.append(API_Message(role: "user", content: contextPrompt, imageData: nil))
                
                let aiMessage = Message(role: .assistant, content: "")
                currentSession.messages.append(aiMessage)
                
                let stream = chatService.streamMessage(apiMessages, model: selectedModel)
                
                for try await chunk in stream {
                    aiMessage.content += chunk
                }
                
                currentSession.lastModified = Date()
                saveContext()
                syncMessageToFirestore(aiMessage, session: currentSession)
                syncSessionToFirestore(currentSession)
                
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
        currentSession.lastModified = Date()
        syncMessageToFirestore(userMessage, session: currentSession)
        syncSessionToFirestore(currentSession)
        incrementUsage(for: "image")
        
        let promptToSend = prompt
        inputText = ""
        isLoading = true
        
        currentTask = Task {
            do {
                // Pollinations unified image endpoint (gen.pollinations.ai)
                // Using Flux model, 1024x1024, no logo
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
                let encodedPrompt = promptToSend.addingPercentEncoding(withAllowedCharacters: allowed)
                    ?? promptToSend.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                    ?? ""
                guard !encodedPrompt.isEmpty else { throw URLError(.badURL) }
                let urlString = "https://gen.pollinations.ai/image/\(encodedPrompt)?model=flux&width=1024&height=1024&nologo=true"
                
                guard let url = URL(string: urlString) else { throw URLError(.badURL) }

                guard let apiKey = AppSecrets.pollinationsAPIKey else {
                    throw URLError(.userAuthenticationRequired)
                }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    let rawBody = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? "Unknown server error"
                    let description = "Image API \(httpResponse.statusCode): \(rawBody)"
                    throw NSError(
                        domain: NSURLErrorDomain,
                        code: NSURLErrorBadServerResponse,
                        userInfo: [NSLocalizedDescriptionKey: description]
                    )
                }
                
                let aiMessage = Message(role: .assistant, content: "Изображение по запросу: \(promptToSend)", type: .image, imageData: data)
                currentSession.messages.append(aiMessage)
                currentSession.lastModified = Date()
                saveContext()
                syncMessageToFirestore(aiMessage, session: currentSession)
                syncSessionToFirestore(currentSession)
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
        currentSession.lastModified = Date()
        
        syncMessageToFirestore(userMessage, session: currentSession)
        syncSessionToFirestore(currentSession)
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
                let url = sanitizeUpdateURLString(data["download_url"] as? String)
                
                DispatchQueue.main.async {
                    self.appUpdate = AppUpdate(version: latestVersion, changelog: changelog, downloadURL: url)
                }
            }
        }
    }

    func validatedUpdateURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        let allowedHosts = ["github.com", "raw.githubusercontent.com", "testflight.apple.com", "apps.apple.com", "t.me", "telegram.me"]
        let isAllowedHost = allowedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
        return isAllowedHost ? url : nil
    }

    private func sanitizeUpdateURLString(_ candidate: String?) -> String {
        let fallback = "https://t.me/Vladik40perc"
        guard let candidate, let url = validatedUpdateURL(from: candidate) else { return fallback }
        return url.absoluteString
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
        let backgroundTaskId = backgroundTask
        
        let query = data.query
        let planSteps = data.planSteps
        let chatService = self.chatService
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            defer {
                Task { @MainActor in
                    if backgroundTaskId != .invalid {
                        UIApplication.shared.endBackgroundTask(backgroundTaskId)
                    }
                }
            }
            
            do {
                var gatheredKnowledge = ""
                var fullRawContext = ""
                var searchQueries = planSteps.isEmpty ? [query] : planSteps // Используем план как начальные запросы
                
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
                        guard var current = self.researchStates[messageId] else { return }
                        current.currentAction = "Цикл \(iteration)/\(maxIterations): Поиск и анализ данных..."
                        current.logs.append("🔍 Итерация \(iteration): Tavily поиск по \(currentQueries.count) запросам")
                        // Прогресс: 0..0.8 распределяем по итерациям
                        current.progress = Double(iteration - 1) / Double(maxIterations) * 0.8
                        self.researchStates[messageId] = current
                    }
                    
                    var batchContent = ""
                    
                    // Параллельный поиск через Tavily
                    await withTaskGroup(of: [TavilyResult]?.self) { group in
                        for searchQuery in currentQueries {
                            guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                            group.addTask {
                                do {
                                    return try await TavilySearchService.shared.search(query: searchQuery)
                                } catch {
                                    print("Tavily search failed for \(searchQuery): \(error)")
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
                                    guard var current = self.researchStates[messageId] else { return }
                                    for result in results {
                                        // Простая дедупликация по URL
                                        if !current.sources.contains(where: { $0.url == result.url }) {
                                            current.sources.append(ResearchSource(title: result.title, url: result.url, icon: "globe"))
                                        }
                                    }
                                    self.researchStates[messageId] = current
                                }
                            }
                        }
                    }
                    
                    if batchContent.isEmpty {
                        await MainActor.run {
                            guard var current = self.researchStates[messageId] else { return }
                            current.logs.append("⚠️ Данные не найдены, переход к анализу.")
                            self.researchStates[messageId] = current
                        }
                        if iteration == 1 { break } // Если сразу ничего нет, выходим
                        continue
                    }
                    
                    fullRawContext += "\n\n=== ИТЕРАЦИЯ \(iteration) ===\n\(batchContent)"
                    
                    // --- ШАГ 3: МЫСЛИ (Chain of Thought) ---
                    await MainActor.run {
                        guard var current = self.researchStates[messageId] else { return }
                        current.currentAction = "Анализ и планирование..."
                        self.researchStates[messageId] = current
                    }
                    
                    let analysisStartTime = Date()
                    
                    let thinkPrompt = """
                    Ты — аналитический модуль Deep Research.
                    Твоя задача — определить, достаточно ли информации для ПОЛНОГО ответа на запрос пользователя.
                    ТЕКУЩАЯ ЗАДАЧА: "\(query)"
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
                    let factsForLog = newFacts
                    let queriesForLog = newQueries
                    
                    await MainActor.run {
                        guard var current = self.researchStates[messageId] else { return }
                        current.logs.append("🧠 Мысли: \(factsForLog.prefix(100))...")
                        if !queriesForLog.isEmpty {
                            current.logs.append("🆕 Новые векторы: \(queriesForLog.joined(separator: ", "))")
                        }
                        self.researchStates[messageId] = current
                    }
                    
                    // Умная остановка: Если ИИ не предложил новых запросов (NONE), значит информации достаточно
                    if newQueries.isEmpty {
                        await MainActor.run {
                            guard var current = self.researchStates[messageId] else { return }
                            current.logs.append("✅ Информации достаточно. Завершение поиска.")
                            self.researchStates[messageId] = current
                        }
                        break
                    }
                }
                
                // --- ШАГ 4: ФИНАЛЬНЫЙ ОТЧЕТ ---
                await MainActor.run {
                    guard var current = self.researchStates[messageId] else { return }
                    current.currentAction = "Написание отчета..."
                    current.progress = 0.9
                    self.researchStates[messageId] = current
                }
                
                let finalPrompt = """
                [RESEARCH DATA]
                \(fullRawContext)
                [END DATA]
                
                User Request: \(query)
                
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
                    guard var current = self.researchStates[messageId] else { return }
                    current.state = .completed
                    current.progress = 1.0
                    current.currentAction = "Готово"
                    
                    current.report = ResearchReport(
                        title: "Отчет: \(query)",
                        abstract: "Глубокое исследование на основе \(current.sources.count) источников. Проведен многоступенчатый анализ данных с использованием Tavily API.",
                        content: reportContent,
                        sources: current.sources
                    )
                    
                    self.researchStates[messageId] = current
                    
                    // Обновляем сообщение в чате
                    if let idx = self.currentSession.messages.firstIndex(where: { $0.id == messageId }) {
                        self.currentSession.messages[idx].content = "[RESEARCH_COMPLETED]"
                        self.saveContext()
                    }
                    
                    let followUpMessage = Message(role: .assistant, content: "Исследование завершено. Вы можете задать по нему вопросы или попросить меня что-то изменить.")
                    self.currentSession.messages.append(followUpMessage)
                    self.syncMessageToFirestore(followUpMessage, session: self.currentSession)
                    self.currentSession.lastModified = Date()
                    self.syncSessionToFirestore(self.currentSession)
                    self.saveContext()
                    
                    self.sendCompletionNotification(title: "Deep Research завершен", body: "Отчет по теме \"\(query)\" готов.")
                }
                
            } catch {
                await MainActor.run {
                    guard var current = self.researchStates[messageId] else { return }
                    current.logs.append("Ошибка: \(error.localizedDescription)")
                    current.currentAction = "Сбой исследования"
                    self.researchStates[messageId] = current
                    
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
    
    private var researchStatesFileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("NovaAI", isDirectory: true)
        return dir.appendingPathComponent("researchStates.json")
    }
    
    private func scheduleResearchStateSave() {
        researchSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveResearchStates()
        }
        researchSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + researchSaveDelay, execute: workItem)
    }
    
    private func saveResearchStates() {
        let states = researchStates
        guard let url = researchStatesFileURL else { return }
        
        Task.detached {
            do {
                let data = try JSONEncoder().encode(states)
                let dir = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
            } catch {
                NSLog("Failed to save research states: \(error)")
            }
        }
    }
    
    private func loadResearchStates() {
        if let url = researchStatesFileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([UUID: ResearchSessionData].self, from: data) {
            self.researchStates = decoded
            return
        }
        
        if let data = UserDefaults.standard.data(forKey: "researchStates"),
           let decoded = try? JSONDecoder().decode([UUID: ResearchSessionData].self, from: data) {
            self.researchStates = decoded
        }
    }
    
    // MARK: - Project Management
    
    private var userPlan: UserPlan {
        if isMax { return .max }
        if isPro { return .pro }
        return .free
    }
    
    var knowledgeFileLimit: Int {
        switch userPlan {
        case .free: return 3
        case .pro: return 10
        case .max: return 20
        }
    }
    
    private func initializeProjects() {
        guard let context = modelContext else { return }
        let manager = ProjectManager(context: context)
        do {
            let fallbackProject = try manager.ensureDefaultProject()
            normalizeProjectsIfNeeded()
            assignOrphanSessions(to: fallbackProject)
            
            if let savedId = UserDefaults.standard.string(forKey: currentProjectIdKey),
               let uuid = UUID(uuidString: savedId),
               let savedProject = fetchProject(by: uuid) {
                selectProject(savedProject)
            } else {
                selectProject(fallbackProject)
            }
            // On app launch, always start from a fresh empty session (welcome screen),
            // instead of auto-opening the most recent chat.
            createNewSession()
        } catch {
            errorMessage = "Не удалось подготовить проекты: \(error.localizedDescription)"
            if let firstProject = fetchFirstProject() {
                selectProject(firstProject)
                createNewSession()
            } else {
                let tempProject = Project(name: "Внешние чаты", icon: "📝", themeColor: .blue, memoryScope: .shared)
                currentProject = tempProject
                currentSession = ChatSession(title: "New Chat", model: selectedModel, project: tempProject)
            }
        }
    }

    private func fetchFirstProject() -> Project? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.createdAt, order: .forward)])
        return (try? context.fetch(descriptor))?.first
    }
    
    private func normalizeProjectsIfNeeded() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Project>()
        guard let projects = try? context.fetch(descriptor) else { return }
        
        var didChange = false
        for project in projects {
            if project.memoryScopeRaw == nil || ProjectMemoryScope(rawValue: project.memoryScopeRaw ?? "") == nil {
                project.memoryScope = .shared
                didChange = true
            }
            if project.name == "Черновик" && project.icon == "📝" {
                project.name = "Внешние чаты"
                didChange = true
            }
        }
        if didChange {
            try? context.save()
        }
    }
    
    private func assignOrphanSessions(to project: Project) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<ChatSession>()
        if let sessions = try? context.fetch(descriptor) {
            let orphaned = sessions.filter { $0.project == nil }
            if !orphaned.isEmpty {
                orphaned.forEach { $0.project = project }
                saveContext()
            }
        }
    }
    
    private func fetchProject(by id: UUID) -> Project? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<Project>()
        if let projects = try? context.fetch(descriptor) {
            return projects.first(where: { $0.id == id })
        }
        return nil
    }
    
    private func mostRecentSession(for project: Project) -> ChatSession? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<ChatSession>(sortBy: [SortDescriptor(\.lastModified, order: .reverse)])
        if let sessions = try? context.fetch(descriptor) {
            return sessions.first(where: { $0.project?.id == project.id })
        }
        return nil
    }
    
    func selectProject(_ project: Project) {
        currentProject = project
        UserDefaults.standard.set(project.id.uuidString, forKey: currentProjectIdKey)
        
        if let session = mostRecentSession(for: project) {
            currentSession = session
        } else {
            let newSession = ChatSession(title: "New Chat", model: selectedModel, project: project)
            currentSession = newSession
        }
        isSidebarVisible = false
    }
    
    func createProject(name: String, icon: String, themeColor: Color, memoryScope: ProjectMemoryScope) throws -> Project {
        guard let context = modelContext else { throw ProjectManagerError.limitReached }
        let manager = ProjectManager(context: context)
        let project = try manager.createProject(name: name, icon: icon, themeColor: themeColor, memoryScope: memoryScope, plan: userPlan)
        selectProject(project)
        return project
    }
    
    func updateProject(_ project: Project, name: String, icon: String, themeColor: Color) {
        project.name = name
        project.icon = icon
        project.themeColor = themeColor
        saveContext()
    }
    
    func addKnowledgeFile(to project: Project, url: URL) -> Result<ProjectFile, Error> {
        do {
            guard isMax else {
                return .failure(KnowledgeBaseError.maxOnly)
            }
            let limit = knowledgeFileLimit
            if project.knowledgeBase.count >= limit {
                return .failure(KnowledgeBaseError.limitReached(limit: limit))
            }
            let item = try readFileForProject(url: url)
            let file = ProjectFile(name: item.name, type: item.type, content: item.content)
            project.knowledgeBase.append(file)
            saveContext()
            return .success(file)
        } catch {
            return .failure(error)
        }
    }
    
    func removeKnowledgeFile(_ file: ProjectFile, from project: Project) {
        if let index = project.knowledgeBase.firstIndex(where: { $0.id == file.id }) {
            project.knowledgeBase.remove(at: index)
            saveContext()
        }
    }
    
    private func readAttachmentItem(url: URL) throws -> AttachmentItem {
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = values.fileSize,
           fileSize > maxFileSizeBytes {
            let sizeMb = Double(fileSize) / (1024 * 1024)
            throw NSError(domain: "ProjectFile", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(format: "Файл слишком большой (%.1f MB). Максимум: 5 MB.", sizeMb)
            ])
        }
        
        var fileContent = try extractTextFromFile(url: url)
        
        if fileContent.isEmpty {
            throw NSError(domain: "ProjectFile", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Не удалось прочитать текст из файла."
            ])
        }
        
        if fileContent.count > maxFileTextChars {
            let truncated = String(fileContent.prefix(maxFileTextChars))
            fileContent = truncated + "\n\n[...текст обрезан...]"
        }
        
        let fileName = url.lastPathComponent
        let fileType = url.pathExtension.uppercased()
        return AttachmentItem(name: fileName, type: fileType.isEmpty ? "TXT" : fileType, content: fileContent)
    }
    
    private func extractTextFromFile(url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        
        if ext == "pdf" {
            if let pdf = PDFDocument(url: url) {
                return pdf.string ?? ""
            }
            return ""
        }
        
        if ext == "docx" {
            return try extractTextFromDocx(url: url) ?? ""
        }
        
        if ext == "pptx" {
            return try extractTextFromPptx(url: url) ?? ""
        }
        
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    
    private func extractTextFromDocx(url: URL) throws -> String? {
        let archive = try Archive(url: url, accessMode: .read)
        guard let xml = try readZipEntryText(archive: archive, path: "word/document.xml") else { return nil }
        return stripXMLTags(from: xml)
    }
    
    private func extractTextFromPptx(url: URL) throws -> String? {
        let archive = try Archive(url: url, accessMode: .read)
        let slides = archive.filter { entry in
            entry.path.hasPrefix("ppt/slides/slide") && entry.path.hasSuffix(".xml")
        }.sorted { $0.path < $1.path }
        
        var combined = ""
        for entry in slides {
            var data = Data()
            _ = try archive.extract(entry, consumer: { chunk in
                data.append(chunk)
            })
            if let xml = String(data: data, encoding: .utf8) {
                combined += xml + "\n"
            }
        }
        if combined.isEmpty { return nil }
        return stripXMLTags(from: combined)
    }
    
    private func readZipEntryText(archive: Archive, path: String) throws -> String? {
        guard let entry = archive[path] else { return nil }
        var data = Data()
        _ = try archive.extract(entry, consumer: { chunk in
            data.append(chunk)
        })
        return String(data: data, encoding: .utf8)
    }
    
    private func stripXMLTags(from xml: String) -> String {
        var text = xml
        text = text.replacingOccurrences(of: "</w:p>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</a:p>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<w:br\\s*/>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<a:br\\s*/>", with: "\n", options: .regularExpression)
        
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        
        text = decodeXMLEntities(text)
        text = text.replacingOccurrences(of: "\\s+\\n", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func decodeXMLEntities(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        return result
    }
    
    private func readFileForProject(url: URL) throws -> AttachmentItem {
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
        return try readAttachmentItem(url: url)
    }
    
    func createNewSession() {
        let newSession = ChatSession(title: "New Chat", model: selectedModel, project: currentProject)
        // Мы НЕ вставляем сессию в контекст и НЕ сохраняем в Firestore.
        // Она станет реальной только после отправки первого сообщения (см. sendMessage).
        currentSession = newSession
        isSidebarVisible = false
    }
    
    func selectSession(_ session: ChatSession) {
        if let project = session.project, project.id != currentProject?.id {
            currentProject = project
            UserDefaults.standard.set(project.id.uuidString, forKey: currentProjectIdKey)
        }
        currentSession = session
        if let user = userSession, session.messages.isEmpty {
            let safeId = session.ensureUUID().uuidString
            restoreMessagesFromFirestore(userId: user.uid, chatId: safeId, session: session)
        }
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
        let safeId = session.ensureUUID().uuidString

        if let context = modelContext {
            context.delete(session)
            try? context.save()
        }
        
        if let user = userSession {
            deleteChatAndMessagesInFirestore(userId: user.uid, chatId: safeId)
        }

        lastSyncedSessionSignatures.removeValue(forKey: safeId)
        restoredMessageChatIds.remove(safeId)
        
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
                    let safeId = session.ensureUUID().uuidString
                    deleteChatAndMessagesInFirestore(userId: user.uid, chatId: safeId)
                }
            }
            
            try context.delete(model: ChatSession.self)
            try context.save()
            lastSyncedSessionSignatures.removeAll()
            lastSyncedMessageSignatures.removeAll()
            restoredMessageChatIds.removeAll()
            
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
    
    func persistChanges() {
        saveContext()
    }

    private func deleteChatAndMessagesInFirestore(userId: String, chatId: String) {
        let chatRef = db.collection("users").document(userId).collection("chats").document(chatId)
        deleteMessagesBatch(in: chatRef) { [weak self] error in
            guard let error else { return }
            print("Firestore chat deletion failed (\(chatId)): \(error)")
            Task { @MainActor in
                self?.errorMessage = "Не удалось удалить чат из облака: \(error.localizedDescription)"
            }
        }
    }

    // Firestore doesn't cascade-delete subcollections. Remove message docs first, then delete chat doc.
    private func deleteMessagesBatch(in chatRef: DocumentReference, completion: @escaping (Error?) -> Void) {
        chatRef.collection("messages").limit(to: 200).getDocuments { snapshot, error in
            if let error {
                completion(error)
                return
            }
            guard let documents = snapshot?.documents, !documents.isEmpty else {
                chatRef.delete(completion: completion)
                return
            }

            let batch = self.db.batch()
            documents.forEach { batch.deleteDocument($0.reference) }
            batch.commit { error in
                if let error {
                    completion(error)
                    return
                }
                self.deleteMessagesBatch(in: chatRef, completion: completion)
            }
        }
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
                errorMessage = "Сбой авторизации: не удалось подтвердить запрос. Попробуйте еще раз."
                currentNonce = nil
                return
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
                let wasProLocally = self.isPro
                let wasMaxLocally = self.isMax
                
                // Устанавливаем текущее значение из базы (пока идет проверка времени)
                self.adminNote = note
                
                // Проверка времени через сеть (защита от смены даты на устройстве)
                Task {
                    let now = await self.fetchNetworkDate()
                    let isActiveNow = newPro || newMax
                    let wasActiveLocally = wasProLocally || wasMaxLocally
                    
                    // Автоматическая проверка срока действия подписки
                    if let expirationTimestamp = data["subscriptionExpirationDate"] as? Timestamp {
                        let expirationDate = expirationTimestamp.dateValue()
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "ru_RU")
                        formatter.dateStyle = .medium
                        
                        if now > expirationDate {
                            // Если админ вручную заново включил подписку (false -> true),
                            // автоматически продлеваем на месяц вместо мгновенного отката в false.
                            if isActiveNow {
                                if !wasActiveLocally {
                                    if let renewedDate = Calendar.current.date(byAdding: .month, value: 1, to: now) {
                                        self.updateSubscriptionDate(userId: userId, date: renewedDate)
                                        self.adminNote = "Активна до \(formatter.string(from: renewedDate))"
                                    } else {
                                        self.adminNote = "Активна до \(formatter.string(from: now))"
                                    }
                                } else {
                                    // Подписка действительно просрочена — отключаем автоматически.
                                    self.disableExpiredSubscription(userId: userId, dateStr: formatter.string(from: expirationDate))
                                    self.isPro = false
                                    self.isMax = false
                                    self.adminNote = "Истекла \(formatter.string(from: expirationDate))"
                                }
                            } else {
                                self.adminNote = "Истекла \(formatter.string(from: expirationDate))"
                            }
                        } else {
                            // Подписка активна — показываем дату
                            self.adminNote = "Активна до \(formatter.string(from: expirationDate))"
                        }
                    } else {
                        // Даты нет. Если подписка включена (админом) — значит это новая активация.
                        // Автоматически ставим дату истечения через 1 месяц.
                        if isActiveNow {
                            // Используем сетевое время для расчета даты окончания
                            let formatter = DateFormatter()
                            formatter.locale = Locale(identifier: "ru_RU")
                            formatter.dateStyle = .medium
                            if let newDate = Calendar.current.date(byAdding: .month, value: 1, to: now) {
                                self.updateSubscriptionDate(userId: userId, date: newDate)
                                self.adminNote = "Активна до \(formatter.string(from: newDate))"
                            } else {
                                self.adminNote = "Активна до \(formatter.string(from: now))"
                            }
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
                
                self.dailyRequestCount = count
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
        
        let usage = modelUsage[model] ?? 0
        let weeklyUsage = weeklyModelUsage[model] ?? 0
        
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
            
            var currentModelUsage: [String: Int] = [:]
            var currentWeeklyUsage: [String: Int] = [:]
            var newCount = 1
            
            if let data = doc.data() {
                let count = data["dailyRequestCount"] as? Int ?? 0
                currentModelUsage = data["modelUsage"] as? [String: Int] ?? [:]
                currentWeeklyUsage = data["weeklyModelUsage"] as? [String: Int] ?? [:]
                newCount = count + 1
            }
            
            currentModelUsage[model, default: 0] += 1
            currentWeeklyUsage[model, default: 0] += 1
            
            var dataToMerge: [String: Any] = [
                "dailyRequestCount": newCount,
                "modelUsage": currentModelUsage,
                "weeklyModelUsage": currentWeeklyUsage,
                "lastRequestDate": FieldValue.serverTimestamp()
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
        let safeId = session.ensureUUID().uuidString
        let signature = "\(session.title)|\(session.model)|\(session.lastModified.timeIntervalSince1970)"
        if lastSyncedSessionSignatures[safeId] == signature {
            return
        }
        
        let data: [String: Any] = [
            "id": safeId,
            "title": session.title,
            "model": session.model,
            "lastModified": Timestamp(date: session.lastModified)
        ]
        
        lastSyncedSessionSignatures[safeId] = signature
        db.collection("users").document(user.uid).collection("chats").document(safeId).setData(data, merge: true) { [weak self] error in
            if error != nil {
                self?.lastSyncedSessionSignatures.removeValue(forKey: safeId)
            }
        }
    }
    
    private func syncMessageToFirestore(_ message: Message, session: ChatSession) {
        guard let user = userSession else { return }
        let contentToStore: String
        if message.content.count > maxFirestoreContentChars {
            contentToStore = String(message.content.prefix(maxFirestoreContentChars)) + "\n\n[TRUNCATED]"
        } else {
            contentToStore = message.content
        }
        
        var data: [String: Any] = [
            "id": message.id.uuidString,
            "role": message.role.rawValue,
            "content": contentToStore,
            "type": message.type.rawValue,
            "createdAt": Timestamp(date: message.timestamp)
        ]
        
        // Optional: Skip large images to save bandwidth/storage costs
        if let imageData = message.imageData, imageData.count < 1_000_000 { // 1MB limit
             data["imageData"] = imageData
        }
        
        let safeSessionId = session.ensureUUID().uuidString
        let safeMessageId = message.id.uuidString
        let signature = "\(safeSessionId)|\(message.role.rawValue)|\(message.type.rawValue)|\(contentToStore.hashValue)|\(message.timestamp.timeIntervalSince1970)|\(data["imageData"] != nil)"
        if lastSyncedMessageSignatures[safeMessageId] == signature {
            return
        }
        lastSyncedMessageSignatures[safeMessageId] = signature
        
        db.collection("users").document(user.uid)
            .collection("chats").document(safeSessionId)
            .collection("messages").document(safeMessageId)
            .setData(data, merge: true) { [weak self] error in
                if let error = error {
                    self?.lastSyncedMessageSignatures.removeValue(forKey: safeMessageId)
                    print("Firestore message sync failed: \(error)")
                    Task { @MainActor in
                        self?.errorMessage = "Не удалось сохранить сообщение: \(error.localizedDescription)"
                    }
                }
            }
    }
    
    private func syncSubscriptionToFirestore() {
        guard let user = userSession else { return }
        db.collection("users").document(user.uid).setData([
            "isPro": isPro,
            "isMax": isMax
        ], merge: true)
    }

    private func parseMessageRole(_ rawRole: String?) -> MessageRole {
        switch rawRole?.lowercased() {
        case "assistant":
            return .assistant
        case "system":
            return .system
        default:
            return .user
        }
    }

    private func parseMessageType(_ rawType: String?) -> MessageType {
        switch rawType?.lowercased() {
        case "image":
            return .image
        default:
            return .text
        }
    }

    private func restoreMessagesFromFirestore(userId: String, chatId: String, session: ChatSession) {
        if restoredMessageChatIds.contains(chatId) {
            return
        }
        restoredMessageChatIds.insert(chatId)

        let messagesRef = db.collection("users").document(userId)
            .collection("chats").document(chatId)
            .collection("messages")
            .order(by: "createdAt")

        messagesRef.getDocuments { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error {
                self.restoredMessageChatIds.remove(chatId)
                print("Firestore messages restore failed (\(chatId)): \(error)")
                return
            }

            guard let documents = snapshot?.documents, !documents.isEmpty else { return }

            Task { @MainActor in
                var existingById: [UUID: Message] = [:]
                for message in session.messages {
                    existingById[message.id] = message
                }

                var didChange = false
                for document in documents {
                    let data = document.data()
                    let rawMessageId = (data["id"] as? String) ?? document.documentID
                    guard let messageId = UUID(uuidString: rawMessageId) else { continue }

                    let content = data["content"] as? String ?? ""
                    let role = self.parseMessageRole(data["role"] as? String)
                    let type = self.parseMessageType(data["type"] as? String)
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let imageData = data["imageData"] as? Data

                    if let existing = existingById[messageId] {
                        if existing.role != role {
                            existing.role = role
                            didChange = true
                        }
                        if existing.type != type {
                            existing.type = type
                            didChange = true
                        }
                        if existing.content != content {
                            existing.content = content
                            didChange = true
                        }
                        if existing.timestamp != createdAt {
                            existing.timestamp = createdAt
                            didChange = true
                        }
                        if existing.imageData != imageData {
                            existing.imageData = imageData
                            didChange = true
                        }
                        continue
                    }

                    let restored = Message(role: role, content: content, type: type, imageData: imageData)
                    restored.id = messageId
                    restored.timestamp = createdAt
                    session.messages.append(restored)
                    existingById[messageId] = restored
                    didChange = true
                }

                if didChange {
                    session.messages.sort { $0.timestamp < $1.timestamp }
                    if let latestMessageDate = session.messages.last?.timestamp, latestMessageDate > session.lastModified {
                        session.lastModified = latestMessageDate
                    }
                    self.saveContext()
                }
            }
        }
    }
    
    private func restoreHistory() {
        guard let user = userSession else { return }
        guard modelContext != nil else { return }

        let chatsRef = db.collection("users")
            .document(user.uid)
            .collection("chats")
            .order(by: "lastModified", descending: true)
            .limit(to: 100)
        chatsRef.getDocuments { [weak self] snapshot, error in
            guard let self = self else { return }

            if let error {
                print("Firestore restore failed: \(error)")
                return
            }

            guard let documents = snapshot?.documents, !documents.isEmpty else { return }

            Task { @MainActor in
                guard let context = self.modelContext else { return }
                let fallbackProject = self.currentProject ?? self.fetchFirstProject()

                let descriptor = FetchDescriptor<ChatSession>()
                let existingSessions = (try? context.fetch(descriptor)) ?? []
                var sessionsById: [UUID: ChatSession] = [:]
                for session in existingSessions {
                    if let uuid = session.uuid {
                        sessionsById[uuid] = session
                    }
                }

                var restoredPairs: [(session: ChatSession, chatId: String)] = []
                var didChange = false

                for document in documents {
                    let data = document.data()
                    let rawChatId = (data["id"] as? String) ?? document.documentID
                    guard let chatId = UUID(uuidString: rawChatId) else { continue }

                    let rawTitle = (data["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rawModel = (data["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = (rawTitle?.isEmpty == false) ? (rawTitle ?? "New Chat") : "New Chat"
                    let model = (rawModel?.isEmpty == false) ? (rawModel ?? "gemini-fast") : "gemini-fast"
                    let lastModified = (data["lastModified"] as? Timestamp)?.dateValue() ?? Date()

                    let session: ChatSession
                    if let existing = sessionsById[chatId] {
                        session = existing
                    } else {
                        let restored = ChatSession(title: title, model: model, project: fallbackProject)
                        restored.uuid = chatId
                        context.insert(restored)
                        sessionsById[chatId] = restored
                        session = restored
                        didChange = true
                    }

                    if session.title != title {
                        session.title = title
                        didChange = true
                    }
                    if session.model != model {
                        session.model = model
                        didChange = true
                    }
                    if session.lastModified != lastModified {
                        session.lastModified = lastModified
                        didChange = true
                    }
                    if session.project == nil, let fallbackProject {
                        session.project = fallbackProject
                        didChange = true
                    }

                    restoredPairs.append((session: session, chatId: chatId.uuidString))
                }

                if didChange {
                    self.saveContext()
                }

                let eagerPairs = restoredPairs
                    .sorted { $0.session.lastModified > $1.session.lastModified }
                    .prefix(self.eagerMessageRestoreLimit)

                for pair in eagerPairs {
                    self.restoreMessagesFromFirestore(userId: user.uid, chatId: pair.chatId, session: pair.session)
                }
            }
        }
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
