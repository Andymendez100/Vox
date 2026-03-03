import Foundation
import WhisperKit

struct TranscriptionOutput {
    let text: String
    let language: String
}

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

    private static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Vox/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func loadModel(_ modelName: String, progressCallback: ((Progress) -> Void)? = nil) async throws {
        // Download with progress reporting
        let modelFolder = try await WhisperKit.download(
            variant: modelName,
            downloadBase: Self.modelsDirectory,
            progressCallback: progressCallback
        )

        // Init from downloaded folder
        whisperKit = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: modelFolder.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false,
                useBackgroundDownloadSession: false
            )
        )
        isLoaded = true
    }

    func transcribe(
        audioData: AudioData,
        language: String? = nil,
        customVocabulary: [String] = [],
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> TranscriptionOutput {
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

        let callback: TranscriptionCallback = { progress in
            onProgress?(progress.text)
            return nil // continue transcription
        }

        let results = try await whisperKit.transcribe(
            audioArray: audioData.samples,
            decodeOptions: options,
            callback: callback
        ) as [TranscriptionResult]

        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedLanguage = results.first?.language ?? ""

        return TranscriptionOutput(text: text, language: detectedLanguage)
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
