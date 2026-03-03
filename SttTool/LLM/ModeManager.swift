import AppKit
import Foundation
import SwiftUI

@MainActor
final class ModeManager: ObservableObject {
    @Published var allModes: [TranscriptionMode] = TranscriptionMode.allBuiltIn
    @Published var customModes: [TranscriptionMode] = []

    private let superModeMappings: [String: String] = [
        "Slack": "message",
        "Discord": "message",
        "Messages": "message",
        "Telegram": "message",
        "WhatsApp": "message",
        "Google Chat": "message",
        "Safari": "message",
        "Google Chrome": "message",
        "Arc": "message",
        "Firefox": "message",
        "Brave Browser": "message",
        "Microsoft Edge": "message",
        "Mail": "email",
        "Outlook": "email",
        "Spark": "email",
        "Xcode": "code",
        "Visual Studio Code": "code",
        "Code": "code",
        "Terminal": "llm_optimize",
        "iTerm2": "llm_optimize",
        "Warp": "llm_optimize",
    ]

    @AppStorage("llmProvider") var selectedProvider: String = "openai"
    @AppStorage("openaiModel") var openaiModel: String = "gpt-4o-mini"
    @AppStorage("anthropicModel") var anthropicModel: String = "claude-haiku-4-5-20251001"
    @AppStorage("geminiModel") var geminiModel: String = "gemini-2.5-flash"

    private static let llmDisplayNames: [String: String] = [
        "gpt-5-nano": "GPT-5 Nano",
        "gpt-5-mini": "GPT-5 Mini",
        "gpt-5": "GPT-5",
        "gpt-5.2": "GPT-5.2",
        "gpt-4.1": "GPT-4.1",
        "gpt-4o-mini": "GPT-4o Mini",
        "gpt-4o": "GPT-4o",
        "claude-haiku-4-5-20251001": "Haiku 4.5",
        "claude-sonnet-4-6": "Sonnet 4.6",
        "claude-opus-4-6": "Opus 4.6",
        "claude-sonnet-4-5-20250929": "Sonnet 4.5",
        "gemini-3.1-pro-preview": "Gemini 3.1 Pro",
        "gemini-3-flash-preview": "Gemini 3 Flash",
        "gemini-3.1-flash-lite-preview": "Gemini 3.1 Flash Lite",
        "gemini-2.5-flash": "Gemini 2.5 Flash",
        "gemini-2.5-flash-lite": "Gemini 2.5 Flash Lite",
        "gemini-2.5-pro": "Gemini 2.5 Pro",
    ]

    var llmModelDisplayName: String {
        let model: String
        switch selectedProvider {
        case "openai": model = openaiModel
        case "anthropic": model = anthropicModel
        case "gemini": model = geminiModel
        default: return selectedProvider
        }
        return Self.llmDisplayNames[model] ?? model
    }

    init() {
        loadCustomModes()
    }

    func getMode(id: String) -> TranscriptionMode? {
        allModes.first { $0.id == id } ?? customModes.first { $0.id == id }
    }

    func resolveMode(selectedMode: String, superModeEnabled: Bool) -> TranscriptionMode? {
        if superModeEnabled {
            if let autoMode = detectModeForActiveApp() {
                return autoMode
            }
        }
        return getMode(id: selectedMode)
    }

    func detectModeForActiveApp() -> TranscriptionMode? {
        guard let appName = NSWorkspace.shared.frontmostApplication?.localizedName else {
            return nil
        }
        guard let modeId = superModeMappings[appName] else {
            return nil
        }
        return getMode(id: modeId)
    }

    func getProvider() -> LLMProvider? {
        switch selectedProvider {
        case "openai":
            let key = KeychainService.get(key: "openai_api_key")
            guard let key, !key.isEmpty else { return nil }
            return OpenAIProvider(model: openaiModel, apiKey: key)
        case "anthropic":
            let key = KeychainService.get(key: "anthropic_api_key")
            guard let key, !key.isEmpty else { return nil }
            return AnthropicProvider(model: anthropicModel, apiKey: key)
        case "gemini":
            let key = KeychainService.get(key: "gemini_api_key")
            guard let key, !key.isEmpty else { return nil }
            return GeminiProvider(model: geminiModel, apiKey: key)
        default:
            return nil
        }
    }

    func addCustomMode(name: String, systemPrompt: String) {
        let id = name.lowercased().replacingOccurrences(of: " ", with: "_")
        let mode = TranscriptionMode(id: id, name: name, systemPrompt: systemPrompt, isBuiltIn: false)
        customModes.append(mode)
        allModes.append(mode)
        saveCustomModes()
    }

    func removeCustomMode(id: String) {
        customModes.removeAll { $0.id == id }
        allModes.removeAll { $0.id == id && !$0.isBuiltIn }
        saveCustomModes()
    }

    private func saveCustomModes() {
        if let data = try? JSONEncoder().encode(customModes),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: "customModesJSON")
        }
    }

    private func loadCustomModes() {
        guard let json = UserDefaults.standard.string(forKey: "customModesJSON"),
              let data = json.data(using: .utf8),
              let modes = try? JSONDecoder().decode([TranscriptionMode].self, from: data) else {
            return
        }
        customModes = modes
        allModes = TranscriptionMode.allBuiltIn + modes
    }
}
