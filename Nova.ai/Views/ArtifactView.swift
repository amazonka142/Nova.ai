import SwiftUI
import WebKit

struct ArtifactView: View {
    let htmlContent: String
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: Int = 0
    @State private var isCopied: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom Tab Picker
                Picker("Mode", selection: $selectedTab) {
                    Text("Предпросмотр").tag(0)
                    Text("Код").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                TabView(selection: $selectedTab) {
                    // Preview Tab
                    ArtifactWebView(htmlContent: htmlContent)
                        .tag(0)
                    
                    // Code Tab
                    ScrollView {
                        Text(htmlContent)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .tag(1)
                }
            }
            .navigationTitle("Артефакт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if selectedTab == 1 {
                            Button(action: {
                                UIPasteboard.general.string = htmlContent
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                                withAnimation { isCopied = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation { isCopied = false }
                                }
                            }) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            }
                        }
                        
                        ShareLink(item: htmlContent) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
}

struct ArtifactWebView: UIViewRepresentable {
    let htmlContent: String
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true // Разрешаем JS для интерактивности
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear // Адаптация под темную/светлую тему
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(htmlContent, baseURL: nil)
    }
}

#Preview {
    ArtifactView(htmlContent: "<h1>Hello World</h1><button>Click me</button>")
}
