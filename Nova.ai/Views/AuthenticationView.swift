import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct AuthenticationView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme
    
    @State private var displayedTitle = ""
    @State private var showContent = false
    
    @State private var showAppleSignInUnavailableAlert = false
    
    @State private var animateBlobs = false
    @State private var animateLogo = false
    
    var body: some View {
        ZStack {
            // Background - System Background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            // Animated Ambient Glow
            GeometryReader { proxy in
                ZStack {
                    // Blob 1 (Blue)
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 350, height: 350)
                        .blur(radius: 60)
                        .offset(x: animateBlobs ? -100 : 100, y: animateBlobs ? -150 : 0)
                        .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: animateBlobs)
                    
                    // Blob 2 (Purple)
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 300, height: 300)
                        .blur(radius: 60)
                        .offset(x: animateBlobs ? 120 : -120, y: animateBlobs ? 200 : -50)
                        .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: animateBlobs)
                    
                    // Blob 3 (Teal - New)
                    Circle()
                        .fill(Color.teal.opacity(0.15))
                        .frame(width: 250, height: 250)
                        .blur(radius: 50)
                        .offset(x: animateBlobs ? -50 : 50, y: animateBlobs ? 100 : 250)
                        .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: animateBlobs)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Logo / Title
                VStack(spacing: 15) {
                    ZStack {
                        // Glow behind logo
                        Circle()
                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 100, height: 100)
                            .blur(radius: 20)
                            .opacity(animateLogo ? 0.6 : 0.3)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 70))
                            .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .shadow(color: .purple.opacity(0.3), radius: 10, x: 0, y: 5)
                            .scaleEffect(animateLogo ? 1.05 : 1.0)
                            .rotationEffect(.degrees(animateLogo ? 5 : -5))
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                            animateLogo = true
                        }
                    }
                    
                    Text(displayedTitle)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .frame(height: 55) // Fixed height to prevent jumping
                    
                    Text("Твой второй пилот")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary.opacity(0.8))
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeIn(duration: 0.8).delay(0.5), value: showContent)
                }
                
                Spacer()
                
                // Features
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(icon: "bolt.fill", title: "Сверхскорость", subtitle: "Ответы быстрее мысли", color: .yellow)
                    FeatureRow(icon: "brain.head.profile.fill", title: "Безграничный IQ", subtitle: "Решает любые задачи", color: .purple)
                    FeatureRow(icon: "eye.fill", title: "Мультимодальность", subtitle: "Видит, слышит и рисует", color: .blue)
                }
                .padding(25)
                .background(
                    ZStack {
                        Color(UIColor.secondarySystemBackground).opacity(0.6)
                        // Gradient Border
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    }
                )
                .cornerRadius(24)
                .padding(.horizontal)
                .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 5)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.8), value: showContent)
                
                Spacer()
                
                // Apple Sign In (Disabled for IPA Distribution)
                Button(action: {
                    showAppleSignInUnavailableAlert = true
                }) {
                    HStack {
                        Image(systemName: "apple.logo")
                            .font(.title2)
                        Text("Войти через Apple")
                            .font(.system(size: 19, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 12)
                .opacity(showContent ? 1 : 0)
                .animation(.easeIn.delay(1.2), value: showContent)
                .alert("Функция недоступна", isPresented: $showAppleSignInUnavailableAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Эта функция будет доступна только в будущих версиях. Пожалуйста, войдите через Google.")
                }
                
                // Google Sign In
                Button(action: {
                    viewModel.signInWithGoogle()
                }) {
                    HStack(spacing: 12) {
                        Text("G")
                            .font(.title2)
                            .fontWeight(.heavy)
                            .foregroundStyle(
                                LinearGradient(colors: [.blue, .red, .yellow, .green], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                        
                        Text("Войти через Google")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .opacity(showContent ? 1 : 0)
                .animation(.easeIn.delay(1.3), value: showContent)
                
                // Guest Login Button
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.bottom, 20)
                } else {
                    Button(action: {
                        viewModel.signInAnonymously()
                    }) {
                        Text("Продолжить без регистрации")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 20)
                    .opacity(showContent ? 1 : 0)
                }
            }
        }
        .onAppear {
            animateBlobs = true
            startTypewriterAnimation()
        }
        .alert("Ошибка", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "Неизвестная ошибка")
        }
        .onOpenURL { url in
            GIDSignIn.sharedInstance.handle(url)
        }
    }
    
    private func startTypewriterAnimation() {
        let fullText = "Nova.ai"
        displayedTitle = ""
        showContent = false
        
        Task {
            // Initial delay
            try? await Task.sleep(nanoseconds: 200_000_000)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            
            for char in fullText {
                displayedTitle.append(char)
                generator.impactOccurred()
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            
            showContent = true
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}