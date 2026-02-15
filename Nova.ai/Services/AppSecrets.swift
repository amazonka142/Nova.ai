import Foundation

enum AppSecrets {
    private static func sanitizedValue(for key: String) -> String? {
        if let envValue = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envValue.isEmpty {
            return envValue
        }

        guard let plistValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = plistValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let placeholderMarkers = ["REPLACE", "YOUR_", "<"]
        if placeholderMarkers.contains(where: { trimmed.uppercased().contains($0) }) {
            return nil
        }

        return trimmed
    }

    static var googleSearchAPIKey: String? {
        sanitizedValue(for: "GOOGLE_SEARCH_API_KEY")
    }

    static var googleSearchEngineID: String? {
        sanitizedValue(for: "GOOGLE_SEARCH_ENGINE_ID")
    }

    static var tavilyAPIKey: String? {
        sanitizedValue(for: "TAVILY_API_KEY")
    }
}
