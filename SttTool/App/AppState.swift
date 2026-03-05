import Foundation
import SwiftUI
import Combine

enum TranscriptionState: Equatable, CustomStringConvertible {
    case idle
    case loading
    case recording
    case transcribing
    case processing
    case error(String)

    var description: String {
        switch self {
        case .idle: return "Ready"
        case .loading: return "Loading model..."
        case .recording: return "Recording..."
        case .transcribing: return "Transcribing..."
        case .processing: return "Processing..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - UI State
    @Published var transcriptionState: TranscriptionState = .idle
    @Published var lastTranscription: String = ""
    @Published var recentTranscriptions: [String] = []
    @Published var errorMessage: String?
    @Published var isModelLoaded: Bool = false
    @Published var modelLoadProgress: Double = 0.0
    @Published var liveTranscriptionText: String = ""
    @Published var recordingStartTime: Date?
    @Published var lastInjectedText: String?
    @Published var canUndo: Bool = false
    @Published var detectedLanguage: String = ""
    @Published var audioLevels: [Float] = []
    private var smoothedLevels: [Float] = Array(repeating: 0, count: 50)

    // MARK: - Settings (persisted)
    @AppStorage("selectedModel") var selectedModel: String = "openai_whisper-base"
    @AppStorage("language") var language: String = "en"
    @AppStorage("autoDetectLanguage") var autoDetectLanguage: Bool = false
    @AppStorage("activationMode") var activationMode: String = "pushToTalk"
    @AppStorage("selectedMode") var selectedMode: String = "voice"
    @AppStorage("superModeEnabled") var superModeEnabled: Bool = false
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("customVocabularyJSON") var customVocabularyJSON: String = "[]"
    @AppStorage("customModesJSON") var customModesJSON: String = "[]"
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = 54 // Right Command
    @AppStorage("hotkeyModifiers") var hotkeyModifiers: Int = 0
    @AppStorage("hotkeyModifierOnly") var hotkeyModifierOnly: Bool = true
    @AppStorage("muteWhileRecording") var muteWhileRecording: Bool = false
    @AppStorage("selectedInputDeviceUID") var selectedInputDeviceUID: String = AudioDeviceManager.systemDefaultUID
    @AppStorage("soundFeedbackEnabled") var soundFeedbackEnabled: Bool = true
    @AppStorage("copyOnlyMode") var copyOnlyMode: Bool = false
    @AppStorage("noiseReductionEnabled") var noiseReductionEnabled: Bool = false

    // MARK: - Services
    let modeManager = ModeManager()
    let audioDeviceManager = AudioDeviceManager()
    let permissionsService = PermissionsService()
    let audioService = AudioCaptureService()
    let transcriptionService = TranscriptionService()
    let textInjectionService = TextInjectionService()
    let audioMuteService = AudioMuteService()
    lazy var coordinator: TranscriptionCoordinator = {
        TranscriptionCoordinator(
            appState: self,
            audioService: audioService,
            transcriptionService: transcriptionService,
            textInjectionService: textInjectionService,
            permissionsService: permissionsService
        )
    }()

    // MARK: - Computed
    var modelDisplayName: String {
        switch selectedModel {
        case "openai_whisper-tiny", "openai_whisper-tiny.en":
            return "Tiny"
        case "openai_whisper-base", "openai_whisper-base.en":
            return "Base"
        case "openai_whisper-small", "openai_whisper-small.en":
            return "Small"
        case "openai_whisper-large-v3":
            return "Large V3"
        default:
            return selectedModel
        }
    }

    // MARK: - Methods
    func addTranscription(_ text: String) {
        lastTranscription = text
        recentTranscriptions.insert(text, at: 0)
        if recentTranscriptions.count > 10 {
            recentTranscriptions.removeLast()
        }
    }

    func pushAudioLevel(_ level: Float) {
        // Shift left
        smoothedLevels.removeFirst()
        // Exponential smoothing
        let previous = smoothedLevels.last ?? 0
        let smoothed = previous * 0.15 + level * 0.85
        smoothedLevels.append(smoothed)
        audioLevels = smoothedLevels
    }

    func clearAudioLevels() {
        smoothedLevels = Array(repeating: 0, count: 50)
        audioLevels = []
    }

    func showError(_ message: String) {
        transcriptionState = .error(message)
        errorMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if case .error = transcriptionState {
                transcriptionState = .idle
                errorMessage = nil
            }
        }
    }

    private init() {}
}
