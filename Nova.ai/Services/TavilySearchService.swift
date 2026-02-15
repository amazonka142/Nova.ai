import Foundation

// Модель ответа от Tavily
struct TavilyResponse: Codable {
    let results: [TavilyResult]
}

struct TavilyResult: Codable {
    let title: String
    let url: String
    let content: String
    let score: Double?
}

enum TavilySearchServiceError: LocalizedError {
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Tavily search is not configured. Set TAVILY_API_KEY."
        }
    }
}

class TavilySearchService {
    static let shared = TavilySearchService()
    
    private init() {}

    // Функция поиска, возвращающая структурированные результаты
    func search(query: String) async throws -> [TavilyResult] {
        guard let apiKey = AppSecrets.tavilyAPIKey else {
            throw TavilySearchServiceError.missingConfiguration
        }

        guard let url = URL(string: "https://api.tavily.com/search") else { return [] }
        
        let body: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "search_depth": "advanced",
            "include_answer": false,
            "include_images": false,
            "include_raw_content": false,
            "max_results": 5
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
             throw URLError(.badServerResponse)
        }
        
        let decodedResponse = try JSONDecoder().decode(TavilyResponse.self, from: data)
        return decodedResponse.results
    }
}
