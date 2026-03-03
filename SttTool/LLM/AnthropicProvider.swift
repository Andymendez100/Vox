import Foundation

struct AnthropicProvider: LLMProvider {
    let model: String
    let apiKey: String

    init(model: String = "claude-haiku-4-5-20251001", apiKey: String? = nil) {
        self.model = model
        self.apiKey = apiKey ?? KeychainService.get(key: "anthropic_api_key") ?? ""
    }

    func processText(_ text: String, systemPrompt: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMError.noAPIKey("Anthropic API key not configured")
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": "[Transcription to format]:\n\(text)"]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError("Anthropic API error: \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let resultText = textBlock["text"] as? String else {
            throw LLMError.parseError("Failed to parse Anthropic response")
        }

        return resultText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LLMError: LocalizedError {
    case noAPIKey(String)
    case apiError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey(let msg): return msg
        case .apiError(let msg): return msg
        case .parseError(let msg): return msg
        }
    }
}
