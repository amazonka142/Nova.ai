import SwiftUI
import FirebaseAuth
import UIKit

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showTools = false
    @State private var showMemorySheet = false
    @State private var previewImage: PreviewImage?
    @State private var selectedResearchId: IdentifiableUUID? // Для открытия шторки деталей
    @State private var selectedArtifact: ArtifactContent? // Для предпросмотра HTML
    @State private var messageBeingEdited: Message?
    @State private var editedRequestText = ""
    
    @AppStorage("appLanguage") private var selectedLanguage: AppLanguage = .russian
    
    var body: some View {
        VStack(spacing: 0) {
            subscriptionButton
            
            messagesList
            
            errorMessageView
            
            suggestionsView
            
            InputView(
                text: $viewModel.inputText,
                onMenuTap: { showTools = true },
                attachmentData: viewModel.pendingAttachmentData,
                onSend: viewModel.sendMessage,
                isLoading: viewModel.isLoading,
                isRecording: viewModel.isRecording,
                onVoiceToggle: viewModel.toggleVoiceInput,
                activeTool: $viewModel.activeTool,
                fileAttachment: $viewModel.pendingFileAttachment,
                attachmentDataBinding: $viewModel.pendingAttachmentData
            )
        }
        .navigationTitle(viewModel.currentSession.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.clear) // Transparent to show global gradient
        .animation(.easeInOut, value: viewModel.isPro)
        .animation(.easeInOut, value: viewModel.isMax)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.isSettingsPresented = true }) {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showTools) {
            ToolsMenuView(
                selectedTool: $viewModel.activeTool,
                selectedPhotoItem: $viewModel.selectedPhotoItem,
                isMax: viewModel.isMax,
                onUpgrade: { showTools = false; viewModel.showSubscription = true },
                onFileSelected: { url in viewModel.handleFileSelection(url: url) },
                onCameraCaptured: { image in viewModel.handleCameraImage(image) }
            )
            .presentationDetents([.fraction(0.45), .large])
            .presentationDragIndicator(.hidden) // We made our own handle
        }
        .sheet(isPresented: $viewModel.showSubscription) {
            SubscriptionView(viewModel: viewModel)
        }
        .alert(selectedLanguage == .russian ? "Доступна новая версия" : "New version available", isPresented: isUpdateAvailable, presenting: viewModel.appUpdate) { update in
            Button(selectedLanguage == .russian ? "Скачать обновление" : "Download Update") {
                if let url = viewModel.validatedUpdateURL(from: update.downloadURL) {
                    UIApplication.shared.open(url)
                }
            }
            Button(selectedLanguage == .russian ? "Позже" : "Later", role: .cancel) {
                viewModel.appUpdate = nil
            }
        } message: { update in
            Text("Nova.ai v\(update.version)\n\n" + (selectedLanguage == .russian ? "Что нового:\n" : "What's new:\n") + update.changelog)
        }
        .sheet(isPresented: $showMemorySheet) {
            NavigationStack {
                MemoryView()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedArtifact) { artifact in
            ArtifactView(htmlContent: artifact.html)
        }
        .sheet(item: $messageBeingEdited) { message in
            EditRequestSheet(
                text: $editedRequestText,
                selectedLanguage: selectedLanguage,
                onCancel: {
                    messageBeingEdited = nil
                    editedRequestText = ""
                },
                onSave: {
                    viewModel.editUserMessage(message, newContent: editedRequestText)
                    messageBeingEdited = nil
                    editedRequestText = ""
                }
            )
        }
        .fullScreenCover(item: $previewImage) { item in
            PreviewImageViewer(image: item.image)
        }
        .fullScreenCover(item: $viewModel.selectedReport) { report in
            ResearchReportView(report: report)
        }
        .sheet(item: $selectedResearchId) { identifiableId in
            if let data = viewModel.researchStates[identifiableId.id] {
                ResearchProgressSheet(data: data)
            }
        }
    }
    
    @ViewBuilder
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.currentSession.messages) { message in
                        if message.role == .system {
                            // System Notification Style
                            Text(message.content)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 12)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                                .id(message.id)
                                .onTapGesture {
                                    if message.content.contains("💾 Запомнил") {
                                        showMemorySheet = true
                                    }
                                }
                        } else {
                            ChatBubbleView(
                                message: message,
                                isTyping: viewModel.isLoading && message.id == viewModel.currentSession.messages.last?.id,
                                onSpeak: viewModel.speakMessage,
                                onImageTap: { image in previewImage = PreviewImage(image: image) },
                                researchState: viewModel.researchStates[message.id],
                                onStartResearch: { viewModel.startDeepResearch(for: message.id) },
                                onOpenReport: {
                                    if let report = viewModel.researchStates[message.id]?.report {
                                        viewModel.selectedReport = report
                                    }
                                },
                                onShowResearchDetails: { selectedResearchId = IdentifiableUUID(id: message.id) },
                                onPreviewHtml: { html in
                                    selectedArtifact = ArtifactContent(html: html)
                                },
                                onEditRequest: { message in
                                    guard !viewModel.isLoading else { return }
                                    editedRequestText = message.content
                                    messageBeingEdited = message
                                },
                                onRegenerate: { message in
                                    viewModel.regenerateAssistantResponse(for: message)
                                }
                            )
                            .id(message.id)
                        }
                    }
                    
                    if viewModel.isLoading {
                        HStack {
                            TypingIndicatorView()
                            Spacer()
                        }
                        .padding(.horizontal)
                        .transition(.opacity)
                    }
                }
                .padding(.vertical)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.currentSession.messages.map(\.id)) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isLoading) { _, loading in
                if loading { scrollToBottom(proxy: proxy) }
            }
        }
    }
    
    @ViewBuilder
    private var errorMessageView: some View {
        if let error = viewModel.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(error)
            }
            .foregroundColor(.red)
            .font(.caption)
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }
    
    @ViewBuilder
    private var suggestionsView: some View {
        // Smart Suggestions
        if !viewModel.smartSuggestions.isEmpty && !viewModel.isLoading {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.smartSuggestions, id: \.self) { suggestion in
                        Button(action: {
                            viewModel.inputText = suggestion
                            viewModel.sendMessage()
                        }) {
                            Text(suggestion)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(16)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    
    @ViewBuilder
    private var subscriptionButton: some View {
        if !viewModel.isPro && !viewModel.isMax {
            Button(action: {
                if viewModel.userSession?.isAnonymous == true {
                    viewModel.showAuthRequest = true
                } else {
                    viewModel.showSubscription = true
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    
                    let isAnonymous = viewModel.userSession?.isAnonymous == true
                    let text: String = {
                        if isAnonymous {
                            return selectedLanguage == .russian ? "Войти" : "Sign In"
                        } else {
                            return selectedLanguage == .russian ? "Обновить" : "Upgrade"
                        }
                    }()
                    
                    Text(text)
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)))
                .foregroundColor(.white)
                .shadow(radius: 4)
            }
            .padding(.top, 24)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    private var isUpdateAvailable: Binding<Bool> {
        Binding(
            get: { viewModel.appUpdate != nil },
            set: { if !$0 { viewModel.appUpdate = nil } }
        )
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastId = viewModel.currentSession.messages.last?.id else { return }
        
        // Small delay to allow View to render the new bubble height
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

struct IdentifiableUUID: Identifiable {
    let id: UUID
}

struct ArtifactContent: Identifiable {
    let id = UUID()
    let html: String
}

struct PreviewImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct EditRequestSheet: View {
    @Binding var text: String
    let selectedLanguage: AppLanguage
    let onCancel: () -> Void
    let onSave: () -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(selectedLanguage == .russian ? "Измените запрос. Ответы после него будут сгенерированы заново." : "Edit the request. Answers after it will be regenerated.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                TextEditor(text: $text)
                    .frame(minHeight: 220)
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 12)
            .navigationTitle(selectedLanguage == .russian ? "Исправить запрос" : "Edit Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectedLanguage == .russian ? "Отмена" : "Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedLanguage == .russian ? "Отправить" : "Send", action: onSave)
                        .disabled(trimmedText.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct PreviewImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ZoomableImageView(image: image)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            imageView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
        
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let zoomScale = scrollView.zoomScale > 1 ? 1 : 3
            scrollView.setZoomScale(CGFloat(zoomScale), animated: true)
        }
    }
}
