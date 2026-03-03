import Foundation

@MainActor
final class TranscriptionCoordinator {
    private let appState: AppState
    private let audioService: AudioCaptureService
    private let transcriptionService: TranscriptionService
    private let textInjectionService: TextInjectionService
    private let permissionsService: PermissionsService
    private var transcriptionTask: Task<Void, Never>?
    private var undoTimer: Task<Void, Never>?

    // Hotkey debounce
    private var lastHotkeyPressTime: Date?
    private let debounceInterval: TimeInterval = 0.3

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
        // Debounce rapid presses
        let now = Date()
        if let last = lastHotkeyPressTime, now.timeIntervalSince(last) < debounceInterval {
            return
        }
        lastHotkeyPressTime = now

        guard appState.isModelLoaded else {
            appState.showError("Model not loaded yet")
            return
        }

        // Only check cached permission state — never trigger system dialogs
        // from the hotkey handler. Permissions are requested at startup and
        // in Settings; showing a modal dialog here can race with the event
        // tap and confuse the user.
        guard permissionsService.microphoneGranted else {
            appState.showError("Microphone permission required — check System Settings")
            return
        }
        guard permissionsService.accessibilityGranted else {
            appState.showError("Accessibility permission required — check System Settings")
            return
        }

        // If already recording (toggle mode), treat as release
        if case .recording = appState.transcriptionState {
            handleHotkeyReleased()
            return
        }

        // Clear undo state on new recording
        appState.canUndo = false
        appState.lastInjectedText = nil
        undoTimer?.cancel()

        // Set UI state immediately for instant visual feedback
        appState.clearAudioLevels()
        appState.transcriptionState = .recording
        appState.recordingStartTime = Date()
        appState.liveTranscriptionText = ""
        appState.detectedLanguage = ""
        SoundFeedbackService.shared.playStartRecording()

        // Start the audio engine asynchronously (actor-isolated)
        Task { @MainActor in
            do {
                if appState.muteWhileRecording {
                    await appState.audioMuteService.muteOutput()
                }
                // Device selection is handled by AudioDeviceManager which
                // enforces the system default at startup and on device changes.
                let levelCallback: @Sendable (Float) -> Void = { [weak appState] level in
                    Task { @MainActor in
                        appState?.pushAudioLevel(level)
                    }
                }
                try await audioService.startRecording(
                    noiseReductionEnabled: appState.noiseReductionEnabled,
                    onAudioLevel: levelCallback
                )
            } catch {
                // Revert UI state if engine failed to start
                appState.transcriptionState = .idle
                appState.recordingStartTime = nil
                SoundFeedbackService.shared.playError()
                appState.showError("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }

    func handleHotkeyReleased() {
        guard case .recording = appState.transcriptionState else { return }

        appState.recordingStartTime = nil
        appState.clearAudioLevels()
        SoundFeedbackService.shared.playStopRecording()

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

                // Transcribe with live preview callback
                let language = appState.autoDetectLanguage ? nil : appState.language
                let result = try await transcriptionService.transcribe(
                    audioData: audioData,
                    language: language,
                    customVocabulary: vocabulary,
                    onProgress: { [weak appState] text in
                        Task { @MainActor in
                            appState?.liveTranscriptionText = text
                        }
                    }
                )

                var text = result.text

                // Update detected language
                if appState.autoDetectLanguage {
                    appState.detectedLanguage = result.language
                }

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

                // Inject or copy text
                if appState.copyOnlyMode {
                    await textInjectionService.copyToClipboard(text)
                } else {
                    await textInjectionService.injectText(text)
                }

                // Save to recent
                appState.addTranscription(text)

                // Set undo state
                appState.lastInjectedText = text
                appState.canUndo = true
                undoTimer?.cancel()
                undoTimer = Task {
                    try? await Task.sleep(for: .seconds(30))
                    appState.canUndo = false
                    appState.lastInjectedText = nil
                }

                SoundFeedbackService.shared.playComplete()
                appState.transcriptionState = .idle

            } catch {
                SoundFeedbackService.shared.playError()
                appState.showError(error.localizedDescription)
            }
        }
    }

    func undoLastInjection() {
        guard appState.canUndo else { return }
        appState.canUndo = false
        appState.lastInjectedText = nil
        undoTimer?.cancel()
        Task {
            await textInjectionService.undoLastInjection()
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
        appState.recordingStartTime = nil
        appState.liveTranscriptionText = ""
        appState.clearAudioLevels()
    }

    private func parseCustomVocabulary() -> [String] {
        guard let data = appState.customVocabularyJSON.data(using: .utf8),
              let words = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return words
    }
}
