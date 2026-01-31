import SwiftUI
import Photos

struct BubbleView: View {
    let message: Message
    var onSpeak: ((String) -> Void)? = nil
    @AppStorage("appAccentColor") private var selectedAccentColor: AppAccentColor = .blue
    @State private var cachedImage: UIImage?
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if message.role == .user {
                Spacer()
            } else {
                // Simple Avatar
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("AI")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    )
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Message Content
                if message.type == .text {
                    Text(.init(message.content)) // Enable Markdown parsing
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(backgroundView)
                        .foregroundColor(message.role == .user ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contextMenu {
                            if message.role == .user {
                                Button(action: { UIPasteboard.general.string = message.content }) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                            }
                        }
                } else if message.type == .image, let imageData = message.imageData {
                    VStack(alignment: .leading, spacing: 4) {
                        if let uiImage = cachedImage {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Color.clear
                                .frame(width: 200, height: 200)
                                .onAppear {
                                    self.cachedImage = UIImage(data: imageData)
                                }
                        }
                        
                        if !message.content.isEmpty && message.content != "Image Attachment" {
                            Text(message.content)
                                .font(.caption)
                                .foregroundColor(message.role == .user ? .white : .primary)
                                .padding(4)
                        }
                    }
                    .padding(4)
                    .background(backgroundView)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contextMenu {
                        Button(action: {
                            if let img = cachedImage {
                                Task {
                                    try? await PHPhotoLibrary.shared().performChanges {
                                        PHAssetChangeRequest.creationRequestForAsset(from: img)
                                    }
                                }
                            }
                        }) {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }
                    }
                } else {
                    Text("Image Placeholder")
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Action Buttons (AI Only)
                if message.role == .assistant {
                    HStack(spacing: 16) {
                        Button(action: {
                            UIPasteboard.general.string = message.content
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }) {
                            Image(systemName: "doc.on.doc")
                        }
                        
                        if let onSpeak = onSpeak, !message.content.isEmpty {
                            Button(action: { onSpeak(message.content) }) {
                                Image(systemName: "speaker.wave.2")
                            }
                        }
                        
                        if message.type == .image, let uiImage = cachedImage {
                            ShareLink(item: Image(uiImage: uiImage), preview: SharePreview(message.content, image: Image(uiImage: uiImage))) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        } else {
                            ShareLink(item: message.content) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Button(action: { setFeedback(.liked) }) {
                                Image(systemName: message.feedback == .liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                    .foregroundColor(message.feedback == .liked ? .green : .secondary)
                            }
                            
                            Button(action: { setFeedback(.disliked) }) {
                                Image(systemName: message.feedback == .disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                    .foregroundColor(message.feedback == .disliked ? .red : .secondary)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 4)
                }
            }
            
            if message.role == .assistant {
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
    
    // MARK: - Styles
    
    @ViewBuilder
    private var backgroundView: some View {
        if message.role == .user {
            selectedAccentColor.color
        } else {
            Color.secondary.opacity(0.1) // Standard light gray bubble
        }
    }
    
    private func setFeedback(_ status: FeedbackStatus) {
        message.feedback = (message.feedback == status) ? FeedbackStatus.none : status
        // Haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(status == .none ? .warning : .success)
    }
}
