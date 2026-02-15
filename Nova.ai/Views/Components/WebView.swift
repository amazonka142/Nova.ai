import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let htmlContent: String
    
    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = preferences
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor.systemBackground
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Wrap content in a basic HTML structure to ensure proper rendering and meta tags for mobile
        let fullHtml = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body { margin: 0; padding: 16px; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
            </style>
        </head>
        <body>
            \(htmlContent)
        </body>
        </html>
        """
        webView.loadHTMLString(fullHtml, baseURL: nil)
    }
}
