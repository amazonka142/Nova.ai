import SwiftUI
import Speech
import AVFoundation
import Combine

enum VoiceState {
    case idle
    case listening
    case processing
    case speaking
}

@MainActor
class VoiceChatViewModel: NSObject, ObservableObject, SFSpeechRecognizerDelegate, AVSpeechSynthesizerDelegate {
    // MARK: - Published Properties
    @Published var state: VoiceState = .idle
    @Published var transcript: String = ""
    @Published var audioLevel: CGFloat = 1.0 // Scale factor for visualizer
    @Published var errorMessage: String?
    @Published var isMuted: Bool = false
    
    // MARK: - Private Properties
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5
    
    // Reference to main ViewModel to handle logic & history
    weak var chatViewModel: ChatViewModel?
    
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        setupAudioSession()
    }
    
    // MARK: - Setup
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio Session Error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Public Controls
    
    func startSession() {
        requestPermissions { [weak self] authorized in
            guard authorized else { return }
            self?.startListening()
        }
    }
    
    func stopSession() {
        stopListening()
        stopSpeaking()
        state = .idle
        transcript = ""
    }
    
    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            stopListening()
            state = .idle
        } else {
            startListening()
        }
    }
    
    func interrupt() {
        if state == .speaking {
            stopSpeaking()
            startListening()
        }
    }
    
    // MARK: - Speech Recognition (Listening)
    
    private func startListening() {
        guard !isMuted else { return }
        
        errorMessage = nil
        // Reset
        stopSpeaking()
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
        }
        
        state = .listening
        transcript = ""
        
        // Configure Request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        // Configure Audio Input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install Tap for Audio & Visualizer
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Audio Engine Error: \(error.localizedDescription)"
            return
        }
        
        // Start Recognition Task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.transcript = result.bestTranscription.formattedString
                self.resetSilenceTimer()
            }
            
            if error != nil {
                self.stopListening()
            }
        }
    }
    
    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        silenceTimer?.invalidate()
        audioLevel = 1.0
    }
    
    // MARK: - Silence Detection & Processing
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.commitInput()
            }
        }
    }
    
    private func commitInput() {
        guard !transcript.isEmpty else { return }
        stopListening()
        state = .processing
        
        guard let chatVM = chatViewModel else {
            errorMessage = "Ошибка: Связь с чатом потеряна"
            state = .idle
            return
        }
        
        // Real AI Processing
        Task {
            do {
                let response = try await chatVM.processVoiceMessage(transcript)
                speak(text: response)
            } catch {
                errorMessage = error.localizedDescription
                speak(text: "Произошла ошибка. Попробуйте еще раз.")
            }
        }
    }
    
    // MARK: - Text to Speech (Speaking)
    
    private func speak(text: String) {
        state = .speaking
        transcript = text // Show AI response as subtitle
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = getBestVoice()
        utterance.rate = 0.5
        
        speechSynthesizer.speak(utterance)
        
        // Simulate visualizer for AI speaking
        simulateSpeakingVisualizer()
    }
    
    private func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    private func getBestVoice(language: String = "ru-RU") -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let langVoices = voices.filter { $0.language == language }
        
        if let premium = langVoices.first(where: { $0.quality == .premium }) {
            return premium
        }
        
        if let enhanced = langVoices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        
        return AVSpeechSynthesisVoice(language: language)
    }
    
    // Delegate: Finished speaking
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.startListening() // Loop back to listening
        }
    }
    
    // MARK: - Visualizer Logic
    
    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let step = max(1, frameLength / 50) // Sample subset for performance
        
        var sum: Float = 0
        var count: Int = 0
        
        for i in stride(from: 0, to: frameLength, by: step) {
            sum += abs(channelData[i])
            count += 1
        }
        
        let average = sum / Float(count)
        // Normalize and scale (1.0 to 2.5)
        let scale = 1.0 + CGFloat(min(average * 10, 1.5))
        
        DispatchQueue.main.async {
            self.audioLevel = scale
        }
    }
    
    private func simulateSpeakingVisualizer() {
        // Simple pulse animation when AI is speaking
        // In a real app, you might analyze the output buffer of the synthesizer
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            self.audioLevel = 1.3
        }
    }

    private func requestMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(completion)
        }
    }
    
    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.errorMessage = "Нет разрешения на распознавание речи."
                    completion(false)
                    return
                }
                self.requestMicrophonePermission { allowed in
                    DispatchQueue.main.async {
                        if !allowed {
                            self.errorMessage = "Нет доступа к микрофону."
                            completion(false)
                            return
                        }
                        completion(true)
                    }
                }
            }
        }
    }
}
