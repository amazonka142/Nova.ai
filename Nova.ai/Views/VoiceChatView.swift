import SwiftUI

struct VoiceChatView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @StateObject private var viewModel = VoiceChatViewModel()
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var showSubtitles = true
    
    var body: some View {
        ZStack {
            // Background
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()
            
            VStack {
                // Top Bar (Status)
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.headline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 60)
                        .padding(.horizontal)
                        .transition(.opacity)
                } else {
                    Text(statusText)
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.top, 60)
                        .animation(.easeInOut, value: viewModel.state)
                }
                
                Spacer()
                
                // Visualizer
                ZStack {
                    // Outer Glow
                    Circle()
                        .fill(visualizerColor.opacity(0.2))
                        .frame(width: 200, height: 200)
                        .scaleEffect(viewModel.state == .processing ? 1.2 : viewModel.audioLevel * 1.2)
                        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: viewModel.audioLevel)
                    
                    // Core Circle
                    Circle()
                        .fill(visualizerColor)
                        .frame(width: 120, height: 120)
                        .scaleEffect(viewModel.state == .processing ? 1.0 : viewModel.audioLevel)
                        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: viewModel.audioLevel)
                        .overlay(
                            // Processing Indicator
                            Group {
                                if viewModel.state == .processing {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(1.5)
                                }
                            }
                        )
                }
                .onTapGesture {
                    if viewModel.state == .speaking {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        viewModel.interrupt()
                    }
                }
                
                Spacer()
                
                // Live Transcription / Subtitles
                if showSubtitles && !viewModel.transcript.isEmpty {
                    ScrollView {
                        Text(viewModel.transcript)
                            .font(.title3)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 30)
                    }
                    .frame(maxHeight: 200)
                    .scrollIndicators(.hidden)
                    .padding(.bottom, 40)
                    .transition(.opacity)
                    .id("transcript") // Force redraw on change
                }
                
                // Bottom Controls
                HStack(spacing: 40) {
                    // Mute / Pause
                    Button(action: {
                        viewModel.toggleMute()
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: viewModel.isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.title)
                                .foregroundColor(viewModel.isMuted ? .red : .primary)
                                .frame(width: 60, height: 60)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Circle())
                            
                            Text(viewModel.isMuted ? "Unmute" : "Mute")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Subtitles Toggle
                    Button(action: {
                        showSubtitles.toggle()
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: showSubtitles ? "captions.bubble.fill" : "captions.bubble")
                                .font(.title)
                                .foregroundColor(showSubtitles ? .primary : .secondary)
                                .frame(width: 60, height: 60)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Circle())
                            
                            Text(showSubtitles ? "Subs On" : "Subs Off")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Close
                    Button(action: {
                        viewModel.stopSession()
                        dismiss()
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.title)
                                .foregroundColor(.primary)
                                .frame(width: 60, height: 60)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Circle())
                            
                            Text("Close")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            viewModel.chatViewModel = chatViewModel
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }
    
    // MARK: - Helpers
    
    private var statusText: String {
        switch viewModel.state {
        case .idle: return viewModel.isMuted ? "Paused" : "Ready"
        case .listening: return "Listening..."
        case .processing: return "Thinking..."
        case .speaking: return "Nova is speaking"
        }
    }
    
    private var visualizerColor: Color {
        switch viewModel.state {
        case .idle: return .gray
        case .listening: return .black // Or white in dark mode via adaptive color
        case .processing: return .purple
        case .speaking: return .blue
        }
    }
}

#Preview {
    VoiceChatView(chatViewModel: ChatViewModel())
}