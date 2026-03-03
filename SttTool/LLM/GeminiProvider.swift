import Foundation

struct GeminiProvider: LLMProvider {
    let model: String
    let apiKey: String

    init(model: String = "gemini-2.5-flash", apiKey: String? = nil) {
        self.model = model
        self.apiKey = apiKey ?? KeychainService.get(key: "gemini_api_key") ?? ""
    }

    func processText(_ text: String, systemPrompt: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMError.noAPIKey("Gemini API key not configured")
        }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": "[Transcription to format]:\n\(text)"]]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 2048
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError("Gemini API error: \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let resultText = parts.first?["text"] as? String else {
            throw LLMError.parseError("Failed to parse Gemini response")
        }

        return resultText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
