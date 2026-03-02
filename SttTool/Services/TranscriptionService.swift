import Foundation
import WhisperKit

actor TranscriptionService {
    private var whisperKit: WhisperKit?
    private var isLoaded = false

    struct ModelInfo {
        let id: String
        let displayName: String
        let tier: String
        let sizeDescription: String

        static let available: [ModelInfo] = [
            ModelInfo(id: "openai_whisper-tiny", displayName: "Tiny", tier: "Nano", sizeDescription: "~40 MB"),
            ModelInfo(id: "openai_whisper-tiny.en", displayName: "Tiny (English)", tier: "Nano", sizeDescription: "~40 MB"),
            ModelInfo(id: "openai_whisper-base", displayName: "Base", tier: "Fast", sizeDescription: "~150 MB"),
            ModelInfo(id: "openai_whisper-base.en", displayName: "Base (English)", tier: "Fast", sizeDescription: "~150 MB"),
            ModelInfo(id: "openai_whisper-small", displayName: "Small", tier: "Pro", sizeDescription: "~500 MB"),
            ModelInfo(id: "openai_whisper-small.en", displayName: "Small (English)", tier: "Pro", sizeDescription: "~500 MB"),
            ModelInfo(id: "openai_whisper-large-v3", displayName: "Large V3", tier: "Ultra", sizeDescription: "~1.5 GB"),
        ]
    }

    func loadModel(_ modelName: String) async throws {
        whisperKit = try await WhisperKit(
            model: modelName,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: true,
            useBackgroundDownloadSession: false
        )
        isLoaded = true
    }

    func transcribe(
        audioData: AudioData,
        language: String? = nil,
        customVocabulary: [String] = []
    ) async throws -> String {
        guard let whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        var options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            temperature: 0.0,
            temperatureFallbackCount: 3,
            topK: 5,
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            clipTimestamps: []
        )

        if let language = language, !language.isEmpty {
            options.language = language
        }

        if !customVocabulary.isEmpty {
            let vocabPrompt = customVocabulary.joined(separator: ", ")
            if let tokenizer = whisperKit.tokenizer {
                let tokens = tokenizer.encode(text: vocabPrompt)
                options.promptTokens = tokens
            }
        }

        let result = try await whisperKit.transcribe(
            audioArray: audioData.samples,
            decodeOptions: options
        ) as [TranscriptionResult]

        let text = result.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    func unloadModel() {
        whisperKit = nil
        isLoaded = false
    }

    var modelLoaded: Bool {
        isLoaded
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Whisper model not loaded"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        }
    }
}
