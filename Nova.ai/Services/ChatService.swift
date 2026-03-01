import Foundation

// DTO for API communication that is Sendable
struct API_Message: Sendable, Encodable {
    let role: String
    let content: String
    let imageData: Data? // Added support for images
    
    enum CodingKeys: String, CodingKey {
        case role
        case content
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        
        if let imageData = imageData {
            // OpenAI Vision Format
            let base64String = imageData.base64EncodedString()
            let imageUrl = "data:image/jpeg;base64,\(base64String)"
            
            let contentItems: [ContentItem] = [
                .text(content),
                .imageUrl(ImageUrl(url: imageUrl))
            ]
            try container.encode(contentItems, forKey: .content)
        } else {
            try container.encode(content, forKey: .content)
        }
    }
}

// Helper enums for structured content
enum ContentItem: Encodable {
    case text(String)
    case imageUrl(ImageUrl)
    
    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageUrl(let imageUrl):
            try container.encode("image_url", forKey: .type)
            try container.encode(imageUrl, forKey: .imageUrl)
        }
    }
}

struct ImageUrl: Encodable {
    let url: String
}

protocol ChatServiceProtocol: Sendable {
    func sendMessage(_ messages: [API_Message], model: String) async throws -> String
    func streamMessage(_ messages: [API_Message], model: String) -> AsyncThrowingStream<String, Error>
}

final class PollinationsChatService: ChatServiceProtocol, Sendable {
    
    // Pollinations Text API Endpoint
    // Updated based on reference: https://gen.pollinations.ai/v1/chat/completions
    private let baseURL = URL(string: "https://gen.pollinations.ai/v1/chat/completions")!
    
    private func requireAPIKey() throws -> String {
        guard let apiKey = AppSecrets.pollinationsAPIKey else {
            throw URLError(.userAuthenticationRequired)
        }
        return apiKey
    }
    
    // ... sendMessage implementation ...
    
    func streamMessage(_ messages: [API_Message], model: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                var lastError: Error?
                // Цикл повторных попыток (до 3 раз)
                for attempt in 0..<3 {
                    do {
                        let apiKey = try requireAPIKey()
                        var request = URLRequest(url: baseURL)
                        request.httpMethod = "POST"
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                        request.timeoutInterval = 60 // Увеличенный таймаут для стриминга
                        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData // Игнорируем кэш соединения
                        
                        let hasImages = messages.contains { $0.imageData != nil }
                        let body: [String: Any]
                        
                        // Re-use logic for body construction, but add "stream": true
                        if hasImages {
                            // Vision Strategy
                            let isOpenAI = model.lowercased().contains("gpt") || model.lowercased().contains("openai")
                            
                            if !isOpenAI {
                                // Collapse for Gemini/Mistral (Goldfish Fix for Vision)
                                var promptBuilder = ""
                                let systemMsg = messages.first(where: { $0.role == "system" })?.content ?? "You are Nova."
                                promptBuilder += "System: \(systemMsg)\n\n"
                                for msg in messages where msg.role != "system" {
                                    promptBuilder += "\(msg.role == "user" ? "User" : "Nova"): \(msg.content)\n"
                                }
                                promptBuilder += "Nova:"
                                
                                let lastImage = messages.last(where: { $0.imageData != nil })?.imageData
                                let singleMessage = API_Message(role: "user", content: promptBuilder, imageData: lastImage)
                                
                                struct RequestBody: Encodable { let messages: [API_Message]; let model: String; let jsonMode: Bool; let stream: Bool }
                                let requestData = RequestBody(messages: [singleMessage], model: model, jsonMode: false, stream: true)
                                request.httpBody = try JSONEncoder().encode(requestData)
                            } else {
                                struct RequestBody: Encodable {
                                    let messages: [API_Message]
                                    let model: String
                                    let jsonMode: Bool
                                    let stream: Bool
                                }
                                let requestData = RequestBody(messages: messages, model: model, jsonMode: false, stream: true)
                                request.httpBody = try JSONEncoder().encode(requestData)
                            }
                        } else {
                            // Text Strategy (Goldfish Fix)
                            var promptBuilder = ""
                            let systemMsg = messages.first(where: { $0.role == "system" })?.content 
                                ?? "You are Nova. Be concise."
                            promptBuilder += "System: \(systemMsg)\n\n"
                            for msg in messages where msg.role != "system" {
                                promptBuilder += "\(msg.role == "user" ? "User" : "Nova"): \(msg.content)\n"
                            }
                            promptBuilder += "Nova:"
                            
                            body = [
                                "messages": [["role": "user", "content": promptBuilder]],
                                "model": model,
                                "jsonMode": false,
                                "stream": true
                            ]
                            request.httpBody = try JSONSerialization.data(withJSONObject: body)
                        }
                        
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        
                        guard let httpResponse = response as? HTTPURLResponse else {
                             throw URLError(.badServerResponse)
                        }
                        
                        if !(200...299).contains(httpResponse.statusCode) {
                            NSLog("Stream API Error Status: \(httpResponse.statusCode)")
                            // Попытка прочитать тело ошибки
                            var errorData = Data()
                            for try await byte in bytes { errorData.append(byte) }
                            let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                            NSLog("⚠️ API Error Body: \(errorStr)")
                             throw URLError(.badServerResponse)
                        }
                        
                        for try await line in bytes.lines {
                            let prefix = "data: "
                            if line.hasPrefix(prefix) {
                                let json = line.dropFirst(prefix.count)
                                if json == "[DONE]" { break }
                                
                                if let data = json.data(using: .utf8),
                                   let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                                   let content = chunk.choices.first?.delta.content {
                                    continuation.yield(content)
                                }
                            }
                        }
                        continuation.finish()
                        return // Успешное завершение, выходим из цикла
                        
                    } catch {
                        lastError = error
                        let nsError = error as NSError
                        // Повторяем только при потере соединения (-1005) или таймауте (-1001)
                        if nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorNetworkConnectionLost || nsError.code == NSURLErrorTimedOut) {
                            if attempt < 2 {
                                try? await Task.sleep(nanoseconds: 1_000_000_000) // Пауза 1 сек
                                continue
                            }
                        }
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish(throwing: lastError ?? URLError(.unknown))
            }
        }
    }
    
    // Helper for Streaming Response
    struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta
        }
        let choices: [Choice]
    }

    func sendMessage(_ messages: [API_Message], model: String) async throws -> String {
        let apiKey = try requireAPIKey()
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let hasImages = messages.contains { $0.imageData != nil }
        
        // Handle Request Body Construction
        if hasImages {
            // STRATEGY A: Structured Messages (Vision)
            let isOpenAI = model.lowercased().contains("gpt") || model.lowercased().contains("openai")
            
            if !isOpenAI {
                var promptBuilder = ""
                let systemMsg = messages.first(where: { $0.role == "system" })?.content ?? "You are Nova."
                promptBuilder += "System: \(systemMsg)\n\n"
                for msg in messages where msg.role != "system" {
                    promptBuilder += "\(msg.role == "user" ? "User" : "Nova"): \(msg.content)\n"
                }
                promptBuilder += "Nova:"
                
                let lastImage = messages.last(where: { $0.imageData != nil })?.imageData
                let singleMessage = API_Message(role: "user", content: promptBuilder, imageData: lastImage)
                
                struct RequestBody: Encodable { let messages: [API_Message]; let model: String; let jsonMode: Bool }
                let requestData = RequestBody(messages: [singleMessage], model: model, jsonMode: false)
                request.httpBody = try JSONEncoder().encode(requestData)
            } else {
                struct RequestBody: Encodable { let messages: [API_Message]; let model: String; let jsonMode: Bool }
                let requestData = RequestBody(messages: messages, model: model, jsonMode: false)
                request.httpBody = try JSONEncoder().encode(requestData)
            }
            
        } else {
            // STRATEGY B: Manual Prompt (Text Only) - The "Goldfish Fix"
            var promptBuilder = ""
            
            // 1. Add System Instruction
            let systemMsg = messages.first(where: { $0.role == "system" })?.content 
                ?? "You are Nova, a helpful AI assistant. Be concise. Do NOT greet the user in every message. Keep the conversation natural."
            
            promptBuilder += "System: \(systemMsg)\n\n"
            
            // 2. Append Conversation History
            for msg in messages where msg.role != "system" {
                let roleName = msg.role == "user" ? "User" : "Nova"
                promptBuilder += "\(roleName): \(msg.content)\n"
            }
            
            promptBuilder += "Nova:"
            
            let apiMessages = [
                ["role": "user", "content": promptBuilder]
            ]
            
            let body: [String: Any] = [
                "messages": apiMessages,
                "model": model,
                "jsonMode": false
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        // Retry Logic
        var lastError: Error?
        for _ in 0..<3 {
            do {
                // Execute Request
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    // Optional: Print error body for debugging
                    if let errorText = String(data: data, encoding: .utf8) {
                        print("API Error: \(errorText) (Status: \((response as? HTTPURLResponse)?.statusCode ?? 0))")
                    }
                    throw URLError(.badServerResponse)
                }
                
                // Structure for OpenAI-compatible response
                struct ChatCompletionResponse: Decodable {
                    struct Choice: Decodable {
                        struct Message: Decodable {
                            let content: String
                        }
                        let message: Message
                    }
                    let choices: [Choice]
                }
                
                // Try to decode as JSON first
                if let decodedResponse = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
                   let content = decodedResponse.choices.first?.message.content {
                    return content
                }
                
                // Fallback: Simple string decoding
                if let responseString = String(data: data, encoding: .utf8) {
                    return responseString
                }
                
                throw URLError(.cannotDecodeContentData)
                
            } catch {
                lastError = error
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorNetworkConnectionLost || nsError.code == NSURLErrorTimedOut) {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }
}
