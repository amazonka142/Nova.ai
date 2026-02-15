import SwiftUI
import MarkdownUI
import Photos

struct ChatBubbleView: View {
    let message: Message
    let isTyping: Bool
    let onSpeak: (String) -> Void
    var onImageTap: ((UIImage) -> Void)? = nil
    var researchState: ResearchSessionData? = nil // Передаем состояние исследования
    var onStartResearch: (() -> Void)? = nil
    var onOpenReport: (() -> Void)? = nil
    var onShowResearchDetails: (() -> Void)? = nil
    var onPreviewHtml: ((String) -> Void)? = nil
    
    @AppStorage("appAccentColor") private var selectedAccentColor: AppAccentColor = .blue
    @AppStorage("appChatStyle") private var chatStyle: AppChatStyle = .bubble
    @State private var isLiked: Bool = false
    @State private var isDisliked: Bool = false
    @State private var isCopied: Bool = false
    @State private var cachedImage: UIImage?
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if message.role == .user {
                Spacer()
            } else if chatStyle != .minimal {
                // Avatar for AI
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                
                // --- RESEARCH BUBBLE ---
                if let researchData = researchState {
                    ResearchBubbleView(data: researchData, onStart: { onStartResearch?() }, onOpenReport: { onOpenReport?() }, onShowDetails: { onShowResearchDetails?() })
                }
                // -----------------------
                
                else {
                
                // Image Content
                if let imageData = message.imageData {
                    if let uiImage = cachedImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 250)
                            .cornerRadius(12)
                            .onTapGesture {
                                onImageTap?(uiImage)
                            }
                    } else {
                        Color.clear
                            .frame(width: 200, height: 200)
                            .onAppear {
                                // Decode image once
                                self.cachedImage = UIImage(data: imageData)
                            }
                    }
                }
                
                // Text Content
                if !message.content.isEmpty {
                    if chatStyle == .minimal {
                        Markdown(message.content)
                            .markdownTheme(themeForMessage)
                            .textSelection(.enabled)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 0)
                            .background(bubbleBackground)
                    } else {
                        Markdown(message.content)
                            .markdownTheme(themeForMessage)
                            .textSelection(.enabled)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 12)
                            .background(bubbleBackground)
                            .clipShape(RoundedCorner(radius: 16, corners: corners))
                    }
                }
                
                // Action Buttons (Only for AI and when NOT typing)
                if message.role == .assistant && !message.content.isEmpty && !isTyping {
                    HStack(spacing: 16) {
                        Button(action: {
                            UIPasteboard.general.string = message.content
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                            withAnimation { isCopied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { isCopied = false }
                            }
                        }) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                        }
                        
                        if let uiImage = cachedImage {
                            Button(action: {
                                Task {
                                    try? await PHPhotoLibrary.shared().performChanges {
                                        PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
                                    }
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.success)
                                }
                            }) {
                                Image(systemName: "arrow.down.to.line")
                                    .font(.caption)
                            }
                            
                            ShareLink(item: Image(uiImage: uiImage), preview: SharePreview(message.content.isEmpty ? "Image" : message.content, image: Image(uiImage: uiImage))) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.caption)
                            }
                        } else {
                            ShareLink(item: message.content) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.caption)
                            }
                        }
                        
                        Button(action: {
                            onSpeak(message.content)
                        }) {
                            Image(systemName: "speaker.wave.2")
                                .font(.caption)
                        }
                        
                        Button(action: { 
                            isLiked.toggle(); isDisliked = false 
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }) {
                            Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.caption)
                        }
                        
                        Button(action: { 
                            isDisliked.toggle(); isLiked = false 
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }) {
                            Image(systemName: isDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                    .padding(.leading, 4)
                    .transition(.opacity.animation(.easeInOut))
                }
                } // End else
            }
            
            if message.role == .assistant {
                Spacer()
            }
        }
        .padding(.horizontal)
    }
    
    private var themeForMessage: Theme {
        if message.role == .user {
            return chatStyle == .minimal ? .basic : .userBubble
        } else {
            return .aiBubble(onPreview: onPreviewHtml)
        }
    }
    
    private var bubbleBackground: some View {
        Group {
            if chatStyle == .minimal {
                Color.clear
            } else if message.role == .user {
                selectedAccentColor.color
            } else {
                Color(UIColor.secondarySystemBackground)
            }
        }
    }
    
    private var corners: UIRectCorner {
        if message.role == .user {
            return [.topLeft, .topRight, .bottomLeft]
        } else {
            return [.topLeft, .topRight, .bottomRight]
        }
    }
}

// Тема для сообщений пользователя (белый текст на цветном фоне)
extension Theme {
    static let userBubble = Theme.basic
        .text {
            ForegroundColor(.white)
        }
        .link {
            ForegroundColor(.white)
            UnderlineStyle(.single)
        }
}

extension Theme {
    static func aiBubble(onPreview: ((String) -> Void)? = nil) -> Theme {
        Theme.basic
            .codeBlock { configuration in
                VStack(spacing: 0) {
                    HStack {
                        Text(configuration.language ?? "code")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Artifact Preview Button
                        if (configuration.language == "html" || configuration.language == "html5"), let onPreview = onPreview {
                            Button(action: {
                                onPreview(configuration.content)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "eye.fill")
                                    Text("Предпросмотр")
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .padding(.trailing, 8)
                        }
                        
                        CodeCopyButton(content: configuration.content)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))
                    
                    Divider()
                    
                    configuration.label
                        .padding(12)
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.85))
                        }
                }
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
                .padding(.bottom, 12)
            }
            .table { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(.init(color: .secondary.opacity(0.2)))
                    .markdownTableBackgroundStyle(
                        .alternatingRows(Color.clear, Color.secondary.opacity(0.05))
                    )
            }
            .tableCell { configuration in
                configuration.label
                    .padding(6)
            }
    }
}

struct CodeCopyButton: View {
    let content: String
    @State private var isCopied = false
    
    var body: some View {
        Button(action: {
            UIPasteboard.general.string = content
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            withAnimation { isCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { isCopied = false }
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                Text(isCopied ? "Скопировано" : "Копировать")
            }
            .font(.caption)
            .foregroundColor(isCopied ? .green : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// Helper for rounded corners
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}
