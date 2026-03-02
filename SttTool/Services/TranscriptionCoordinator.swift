import Foundation

@MainActor
final class TranscriptionCoordinator {
    private let appState: AppState
    private let audioService: AudioCaptureService
    private let transcriptionService: TranscriptionService
    private let textInjectionService: TextInjectionService
    private let permissionsService: PermissionsService
    private var transcriptionTask: Task<Void, Never>?

    init(
        appState: AppState,
        audioService: AudioCaptureService,
        transcriptionService: TranscriptionService,
        textInjectionService: TextInjectionService,
        permissionsService: PermissionsService
    ) {
        self.appState = appState
        self.audioService = audioService
        self.transcriptionService = transcriptionService
        self.textInjectionService = textInjectionService
        self.permissionsService = permissionsService
    }

    func handleHotkeyPressed() {
        guard appState.isModelLoaded else {
            appState.showError("Model not loaded yet")
            return
        }

        permissionsService.checkPermissions()
        guard permissionsService.microphoneGranted else {
            appState.showError("Microphone permission required")
            return
        }
        guard permissionsService.accessibilityGranted else {
            appState.showError("Accessibility permission required")
            permissionsService.requestAccessibility()
            return
        }

        // If already recording (toggle mode), treat as release
        if case .recording = appState.transcriptionState {
            handleHotkeyReleased()
            return
        }

        // startRecording() is actor-isolated and throws, so we need try await.
        // Since this method is synchronous, wrap in a Task.
        Task { @MainActor in
            do {
                if appState.muteWhileRecording {
                    await appState.audioMuteService.muteOutput()
                }
                let deviceID = appState.audioDeviceManager.resolveDeviceID(forUID: appState.selectedInputDeviceUID)
                try await audioService.startRecording(inputDeviceID: deviceID)
                appState.transcriptionState = .recording
                appState.liveTranscriptionText = ""
            } catch {
                appState.showError("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }

    func handleHotkeyReleased() {
        guard case .recording = appState.transcriptionState else { return }

        transcriptionTask = Task { @MainActor in
            do {
                guard let audioData = await audioService.stopRecording() else {
                    appState.transcriptionState = .idle
                    return
                }

                if appState.muteWhileRecording {
                    await appState.audioMuteService.restoreOutput()
                }

                if audioData.isTooShort {
                    appState.transcriptionState = .idle
                    return
                }

                appState.transcriptionState = .transcribing

                // Get custom vocabulary
                let vocabulary = parseCustomVocabulary()

                // Transcribe
                let language = appState.autoDetectLanguage ? nil : appState.language
                var text = try await transcriptionService.transcribe(
                    audioData: audioData,
                    language: language,
                    customVocabulary: vocabulary
                )

                guard !text.isEmpty else {
                    appState.transcriptionState = .idle
                    return
                }

                // LLM processing if mode is not "voice"
                let mode = appState.modeManager.resolveMode(
                    selectedMode: appState.selectedMode,
                    superModeEnabled: appState.superModeEnabled
                )

                if let mode, mode.id != "voice", !mode.systemPrompt.isEmpty {
                    appState.transcriptionState = .processing
                    if let provider = appState.modeManager.getProvider() {
                        do {
                            text = try await provider.processText(text, systemPrompt: mode.systemPrompt)
                        } catch {
                            // If LLM fails, fall back to raw transcription
                            print("LLM processing failed, using raw transcription: \(error)")
                        }
                    }
                }

                // Inject text
                await textInjectionService.injectText(text)

                // Save to recent
                appState.addTranscription(text)
                appState.transcriptionState = .idle

            } catch {
                appState.showError(error.localizedDescription)
            }
        }
    }

    func cancel() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        Task {
            _ = await audioService.stopRecording()
        }
        if appState.muteWhileRecording {
            Task { await appState.audioMuteService.restoreOutput() }
        }
        appState.transcriptionState = .idle
        appState.liveTranscriptionText = ""
    }

    private func parseCustomVocabulary() -> [String] {
        guard let data = appState.customVocabularyJSON.data(using: .utf8),
              let words = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return words
    }
}
