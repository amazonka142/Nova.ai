import Foundation

struct GoogleSearchResult: Decodable, Sendable {
    let items: [GoogleSearchItem]?
}

struct GoogleSearchItem: Decodable, Sendable {
    let title: String
    let link: String
    let snippet: String
}

enum GoogleSearchServiceError: LocalizedError {
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Google Search is not configured. Set GOOGLE_SEARCH_API_KEY and GOOGLE_SEARCH_ENGINE_ID."
        }
    }
}

struct GoogleSearchService {
    private let baseURL = "https://www.googleapis.com/customsearch/v1"
    
    func search(query: String) async throws -> String {
        guard let apiKey = AppSecrets.googleSearchAPIKey,
              let searchEngineId = AppSecrets.googleSearchEngineID else {
            throw GoogleSearchServiceError.missingConfiguration
        }

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw URLError(.badURL)
        }
        
        let urlString = "\(baseURL)?key=\(apiKey)&cx=\(searchEngineId)&q=\(encodedQuery)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        // Механизм повторных попыток (Retry Logic)
        var lastError: Error?
        for _ in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                
                if !(200...299).contains(httpResponse.statusCode) {
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("Google Search API Error: \(errorString)")
                    }
                    throw URLError(.badServerResponse)
                }
                
                let result = try JSONDecoder().decode(GoogleSearchResult.self, from: data)
                
                var output = ""
                if let items = result.items, !items.isEmpty {
                    for item in items.prefix(8) {
                        output += "Title: \(item.title)\n"
                        output += "URL: \(item.link)\n"
                        output += "Content: \(item.snippet)\n\n"
                    }
                } else {
                    output = "No results found."
                }
                return output
                
            } catch {
                lastError = error
                let nsError = error as NSError
                // Повторяем только при потере соединения (-1005) или таймауте (-1001)
                if nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorNetworkConnectionLost || nsError.code == NSURLErrorTimedOut) {
                    try? await Task.sleep(nanoseconds: 500_000_000) // Пауза 0.5 сек
                    continue
                }
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }
}
