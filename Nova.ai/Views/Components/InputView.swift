import SwiftUI
import PhotosUI

struct InputView: View {

        @Binding var text: String

        // We remove the direct picker binding from here, as the parent will handle the menu sheet

        // But to keep it compiling for now, we can keep the binding unused or remove it.

        // Let's change the init to take an action for the plus button.

        var onMenuTap: () -> Void

        var attachmentData: Data?

        var onSend: () -> Void

        var isLoading: Bool 
        var isRecording: Bool = false
        var onVoiceToggle: (() -> Void)? = nil
        
        @Binding var activeTool: ChatViewModel.ChatTool
        @Binding var fileAttachment: ChatViewModel.AttachmentItem?

        @AppStorage("appAccentColor") private var selectedAccentColor: AppAccentColor = .blue
        @AppStorage("appLanguage") private var selectedLanguage: AppLanguage = .russian
        

        // Binding needed for the "X" button on attachment preview, so we keep a binding for clearing.

        @Binding var attachmentDataBinding: Data? 
        @State private var cachedPreviewImage: UIImage?

        

        var body: some View {

            VStack(alignment: .leading, spacing: 0) {

                // File Attachment Card
                if let file = fileAttachment {
                    HStack {
                        ZStack(alignment: .topTrailing) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.type)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(file.name)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                            .padding(10)
                            .frame(width: 100, height: 60, alignment: .leading)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                            
                            Button(action: { fileAttachment = nil }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.gray)
                                    .padding(6)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.scale.combined(with: .opacity))
                }

                // Attachment Preview

                if let data = attachmentData {

                    HStack {
                        // Используем кэшированное изображение или декодируем
                        if let uiImage = cachedPreviewImage ?? UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    Button(action: { attachmentDataBinding = nil }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                            .background(Color.white.clipShape(Circle()))
                                    }
                                    .offset(x: 4, y: -4),
                                    alignment: .topTrailing
                                )
                        }

                        Spacer()

                    }

                    .padding(.horizontal)

                    .padding(.bottom, 8)

                    .transition(.scale.combined(with: .opacity))
                    .onAppear {
                        if let data = attachmentData {
                            self.cachedPreviewImage = UIImage(data: data)
                        }
                    }
                    .onChange(of: attachmentData) { newData in
                        if let data = newData {
                            self.cachedPreviewImage = UIImage(data: data)
                        } else {
                            self.cachedPreviewImage = nil
                        }
                    }

                }

                // Active Tool Indicator (Chip)
                if activeTool != .none {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: activeTool.icon)
                                .font(.caption)
                            Text(activeTool.title)
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Button(action: {
                                withAnimation { activeTool = .none }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .padding(2)
                                    .background(Color.primary.opacity(0.1))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(activeTool.color.opacity(0.15))
                        .foregroundColor(activeTool.color)
                        .clipShape(Capsule())
                        .padding(.leading, 44) // Align with text field (36 button + 8 spacing)
                        
                        Spacer()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 4)
                }
                

                HStack(alignment: .bottom, spacing: 8) {

                    // Tools Menu Button (Replaces direct PhotosPicker)

                    Button(action: onMenuTap) {

                        Image(systemName: "plus")

                            .font(.system(size: 20, weight: .medium))

                            .foregroundColor(.secondary)

                            .frame(width: 36, height: 36)

                            .background(Color.secondary.opacity(0.1))

                            .clipShape(Circle())

                    }

                    .padding(.bottom, 2)

                    .disabled(isLoading)

                    // Voice Input Button
                    if text.isEmpty && !isLoading {
                        Button(action: { onVoiceToggle?() }) {
                            Image(systemName: isRecording ? "waveform.circle.fill" : "mic.circle")
                                .font(.system(size: 24))
                                .foregroundColor(isRecording ? .red : .secondary)
                                .symbolEffect(.pulse, isActive: isRecording)
                        }
                        .padding(.bottom, 6)
                        .padding(.trailing, 4)
                    }
                    

                    // Capsule Container

                HStack(alignment: .bottom, spacing: 4) {

                    TextField(selectedLanguage == .russian ? "Сообщение Nova..." : "Message Nova...", text: $text, axis: .vertical)

                        .padding(.horizontal, 12)

                        .padding(.vertical, 8)

                        .lineLimit(1...5)

                        .disabled(isLoading) // Disable text input while loading

                    

                    // Send / Stop Button inside the capsule

                    Button(action: onSend) {

                        Image(systemName: isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")

                            .font(.system(size: 28))

                            .foregroundColor(isLoading ? .red : ((text.isEmpty && attachmentData == nil && fileAttachment == nil) ? .gray.opacity(0.5) : selectedAccentColor.color))

                            .contentTransition(.symbolEffect(.replace))

                    }

                                        .disabled((text.isEmpty && attachmentData == nil && fileAttachment == nil && !isLoading)) // Active if loading OR has content

                    .padding(.trailing, 4)

                    .padding(.bottom, 4)

                }

                .background(Color.secondary.opacity(0.1))

                .clipShape(Capsule())

                // Add a border for better visibility in light mode

                .overlay(

                    Capsule()

                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)

                )

            }

            .padding(.horizontal)

            .padding(.top, 8)

            .padding(.bottom, 2) // Reduced from 10 to move closer to edge (safe area usually handles the rest)

            .background(.regularMaterial)

            .overlay(Divider(), alignment: .top)

        }

    }

}