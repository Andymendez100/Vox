import Foundation

struct OpenAIProvider: LLMProvider {
    let model: String
    let apiKey: String

    init(model: String = "gpt-4o-mini", apiKey: String? = nil) {
        self.model = model
        self.apiKey = apiKey ?? KeychainService.get(key: "openai_api_key") ?? ""
    }

    func processText(_ text: String, systemPrompt: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMError.noAPIKey("OpenAI API key not configured")
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "[Transcription to format]:\n\(text)"]
            ],
            "temperature": 0.3,
            "max_tokens": 2048
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError("OpenAI API error: \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseError("Failed to parse OpenAI response")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
