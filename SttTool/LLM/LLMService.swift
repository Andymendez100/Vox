import Foundation

protocol LLMProvider {
    func processText(_ text: String, systemPrompt: String) async throws -> String
}

enum LLMProviderType: String, CaseIterable, Codable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case gemini = "Google Gemini"
}
