# SttTool Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS menubar app that clones SuperWhisper — global push-to-talk dictation with local Whisper transcription and LLM-powered text cleanup modes.

**Architecture:** Service-oriented Swift app using SwiftUI for UI, AVAudioEngine for audio capture, WhisperKit for on-device transcription, and CGEvent for text injection. All services coordinated through a central TranscriptionCoordinator, state managed via an AppState singleton.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14+, WhisperKit (CoreML Whisper), AVAudioEngine, CGEvent, URLSession (LLM APIs)

---

## Phase 1: Project Scaffolding

### Task 1: Create Package.swift and project structure

**Files:**
- Create: `Package.swift`
- Create: `SttTool/SttTool.entitlements`

**Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SttTool",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SttTool", targets: ["SttTool"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "SttTool",
            dependencies: [
                "WhisperKit"
            ],
            path: "SttTool",
            exclude: ["SttTool.entitlements"],
            resources: [
                .copy("Resources/AppIcon.icns")
            ]
        )
    ]
)
```

**Step 2: Create entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.personal-information.addressbook</key>
    <false/>
</dict>
</plist>
```

**Step 3: Create directory structure and placeholder files**

```bash
mkdir -p SttTool/{App,Audio,Input,LLM,Models,Services,Views,Resources}
```

**Step 4: Create a placeholder AppIcon.icns**

Use a generic mic icon or create a simple one later. For now, copy any .icns or create an empty placeholder:

```bash
# We'll add a real icon later. For now, create an empty placeholder to satisfy SPM.
touch SttTool/Resources/AppIcon.icns
```

**Step 5: Verify project builds**

```bash
swift build 2>&1 | tail -5
```

Expected: Build will fail because no Swift source files exist yet. That's fine — next task adds them.

**Step 6: Commit**

```bash
git add Package.swift SttTool/SttTool.entitlements SttTool/Resources/
git commit -m "chore: scaffold project with Package.swift and directory structure"
```

---

### Task 2: Create app entry point and AppDelegate shell

**Files:**
- Create: `SttTool/App/SttToolApp.swift`
- Create: `SttTool/App/AppDelegate.swift`
- Create: `SttTool/App/AppState.swift`

**Step 1: Create AppState — centralized observable state**

```swift
// SttTool/App/AppState.swift
import Foundation
import SwiftUI

enum TranscriptionState: Equatable, CustomStringConvertible {
    case idle
    case loading
    case recording
    case transcribing
    case processing // LLM processing
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

    // MARK: - Settings (persisted)
    @AppStorage("selectedModel") var selectedModel: String = "openai_whisper-base"
    @AppStorage("language") var language: String = "en"
    @AppStorage("autoDetectLanguage") var autoDetectLanguage: Bool = false
    @AppStorage("activationMode") var activationMode: String = "pushToTalk" // or "toggle"
    @AppStorage("selectedMode") var selectedMode: String = "voice"
    @AppStorage("superModeEnabled") var superModeEnabled: Bool = false
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("customVocabularyJSON") var customVocabularyJSON: String = "[]"
    @AppStorage("customModesJSON") var customModesJSON: String = "[]"
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = 49 // Space
    @AppStorage("hotkeyModifiers") var hotkeyModifiers: Int = 524288 // Option

    // MARK: - Computed
    var modelDisplayName: String {
        switch selectedModel {
        case "openai_whisper-tiny", "openai_whisper-tiny.en":
            return "Nano"
        case "openai_whisper-base", "openai_whisper-base.en":
            return "Fast"
        case "openai_whisper-small", "openai_whisper-small.en":
            return "Pro"
        case "openai_whisper-large-v3":
            return "Ultra"
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
```

**Step 2: Create AppDelegate — menubar setup**

```swift
// SttTool/App/AppDelegate.swift
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var stateObservation: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menubar-only app
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        observeState()

        // Start model loading in background
        Task {
            await loadModel()
        }
    }

    // MARK: - Status Item
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemIcon()

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        let state = AppState.shared.transcriptionState

        let iconName: String
        let color: NSColor

        switch state {
        case .idle:
            iconName = "mic.fill"
            color = AppState.shared.isModelLoaded ? .secondaryLabelColor : .systemYellow
        case .loading:
            iconName = "mic.fill"
            color = .systemYellow
        case .recording:
            iconName = "mic.fill"
            color = .systemRed
        case .transcribing, .processing:
            iconName = "mic.fill"
            color = .systemBlue
        case .error:
            iconName = "mic.slash.fill"
            color = .systemOrange
        }

        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "SttTool") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let configured = image.withSymbolConfiguration(config) ?? image
            button.image = configured
            button.contentTintColor = color
        }
    }

    // MARK: - Popover
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                onOpenSettings: { [weak self] in self?.openSettings() },
                onQuit: { NSApp.terminate(nil) }
            )
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Settings Window
    func openSettings() {
        popover.performClose(nil)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "SttTool Settings"
        window.setContentSize(NSSize(width: 600, height: 500))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }

    // MARK: - State Observation
    private func observeState() {
        stateObservation = AppState.shared.$transcriptionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemIcon()
            }
    }

    // MARK: - Model Loading
    private func loadModel() async {
        AppState.shared.transcriptionState = .loading
        // TranscriptionService will be wired up in Task 6
        AppState.shared.transcriptionState = .idle
    }
}
```

**Step 3: Create SttToolApp entry point**

```swift
// SttTool/App/SttToolApp.swift
import SwiftUI

@main
struct SttToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            EmptyView()
        } label: {
            EmptyView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

**Step 4: Create placeholder views so it compiles**

```swift
// SttTool/Views/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("SttTool")
                .font(.headline)
            Text("Loading...")
                .foregroundStyle(.secondary)
            Divider()
            Button("Settings...") { onOpenSettings() }
            Button("Quit") { onQuit() }
        }
        .padding()
    }
}
```

```swift
// SttTool/Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Text("Settings — Coming Soon")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

**Step 5: Build and verify**

```bash
swift build 2>&1 | tail -5
```

Expected: Successful build (may take a while first time to fetch WhisperKit).

**Step 6: Test run**

```bash
swift run SttTool &
# Verify menubar icon appears, click it to see popover, then kill
kill %1
```

**Step 7: Commit**

```bash
git add SttTool/App/ SttTool/Views/MenuBarView.swift SttTool/Views/SettingsView.swift
git commit -m "feat: app entry point with menubar icon and popover shell"
```

---

## Phase 2: Core Services

### Task 3: Audio capture service

**Files:**
- Create: `SttTool/Services/AudioCaptureService.swift`
- Create: `SttTool/Models/AudioData.swift`

**Step 1: Create AudioData model**

```swift
// SttTool/Models/AudioData.swift
import Foundation

struct AudioData {
    let samples: [Float]
    let sampleRate: Double = 16000

    var duration: TimeInterval {
        Double(samples.count) / sampleRate
    }

    var isTooShort: Bool {
        duration < 0.5
    }

    var isTooLong: Bool {
        duration > 1800 // 30 minutes
    }
}
```

**Step 2: Create AudioCaptureService**

```swift
// SttTool/Services/AudioCaptureService.swift
import AVFoundation
import Foundation

actor AudioCaptureService {
    private var audioEngine: AVAudioEngine?
    private var audioSamples: [Float] = []
    private var isRecording = false

    private let targetSampleRate: Double = 16000

    func startRecording() throws {
        guard !isRecording else { return }

        audioSamples = []
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create target format: 16kHz mono Float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.formatError
        }

        // Create converter if needed
        let converter: AVAudioConverter?
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        } else {
            converter = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            Task {
                await self.processBuffer(buffer, converter: converter, targetFormat: targetFormat)
            }
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.isRecording = true
    }

    func stopRecording() -> AudioData? {
        guard isRecording else { return nil }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false

        let data = AudioData(samples: audioSamples)
        audioSamples = []
        return data
    }

    private func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        targetFormat: AVAudioFormat
    ) {
        if let converter = converter {
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil, let channelData = convertedBuffer.floatChannelData {
                let count = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
                audioSamples.append(contentsOf: samples)
            }
        } else {
            guard let channelData = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
            audioSamples.append(contentsOf: samples)
        }
    }
}

enum AudioError: LocalizedError {
    case formatError
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .formatError: return "Failed to create audio format"
        case .recordingFailed(let msg): return "Recording failed: \(msg)"
        }
    }
}
```

**Step 3: Build and verify**

```bash
swift build 2>&1 | tail -5
```

Expected: Successful build.

**Step 4: Commit**

```bash
git add SttTool/Services/AudioCaptureService.swift SttTool/Models/AudioData.swift
git commit -m "feat: audio capture service with AVAudioEngine and 16kHz conversion"
```

---

### Task 4: Transcription service (WhisperKit)

**Files:**
- Create: `SttTool/Services/TranscriptionService.swift`

**Step 1: Create TranscriptionService**

```swift
// SttTool/Services/TranscriptionService.swift
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

        // Inject custom vocabulary as prompt tokens
        if !customVocabulary.isEmpty {
            let vocabPrompt = customVocabulary.joined(separator: ", ")
            if let tokenizer = whisperKit.tokenizer {
                let tokens = tokenizer.encode(text: vocabPrompt)
                options.promptTokens = tokens.map { Int(truncatingIfNeeded: $0) }
            }
        }

        let results = try await whisperKit.transcribe(
            audioArray: audioData.samples,
            decodeOptions: options
        )

        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
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
```

**Step 2: Build and verify**

```bash
swift build 2>&1 | tail -5
```

Expected: Successful build.

**Step 3: Commit**

```bash
git add SttTool/Services/TranscriptionService.swift
git commit -m "feat: WhisperKit transcription service with model management"
```

---

### Task 5: Hotkey manager (CGEvent tap)

**Files:**
- Create: `SttTool/Services/HotkeyManager.swift`

**Step 1: Create HotkeyManager**

We use raw CGEvent tap (like local-whisper) rather than KeyboardShortcuts for precise push-to-talk control. This lets us swallow key events and detect key-down/key-up independently.

```swift
// SttTool/Services/HotkeyManager.swift
import Carbon
import CoreGraphics
import Foundation

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyCode: UInt16 = 49 // Space
    private var requiredModifiers: CGEventFlags = .maskAlternate // Option

    private var isKeyDown = false

    private init() {}

    func start() {
        loadSavedHotkey()

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Fallback to session event tap if HID tap fails
            guard let sessionTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: hotkeyCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                print("Failed to create event tap. Ensure Accessibility/Input Monitoring permission is granted.")
                return
            }
            setupRunLoop(with: sessionTap)
            return
        }
        setupRunLoop(with: tap)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func setHotkey(keyCode: UInt16, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.requiredModifiers = modifiers
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "hotkeyModifiers")
    }

    // MARK: - Private

    private func setupRunLoop(with tap: CFMachPort) {
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func loadSavedHotkey() {
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        let savedModifiers = UserDefaults.standard.integer(forKey: "hotkeyModifiers")

        if savedKeyCode != 0 {
            keyCode = UInt16(savedKeyCode)
        }
        if savedModifiers != 0 {
            requiredModifiers = CGEventFlags(rawValue: UInt64(savedModifiers))
        }
    }

    fileprivate func handleEvent(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Check if our hotkey modifiers are held (ignoring Fn and other noise)
        let relevantFlags = flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])
        let requiredRelevant = requiredModifiers.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])

        guard eventKeyCode == keyCode && relevantFlags == requiredRelevant else {
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown:
            if !isKeyDown {
                isKeyDown = true
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyDown?()
                }
            }
            return nil // Swallow the event

        case .keyUp:
            if isKeyDown {
                isKeyDown = false
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
            return nil // Swallow the event

        default:
            return Unmanaged.passRetained(event)
        }
    }
}

// C callback — bridges to instance method
private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable tap if it gets disabled (system can disable it under load)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passRetained(event)
    }

    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleEvent(proxy, type, event)
}
```

**Step 2: Build and verify**

```bash
swift build 2>&1 | tail -5
```

Expected: Successful build.

**Step 3: Commit**

```bash
git add SttTool/Services/HotkeyManager.swift
git commit -m "feat: global hotkey manager with CGEvent tap for push-to-talk"
```

---

### Task 6: Text injection service

**Files:**
- Create: `SttTool/Services/TextInjectionService.swift`

**Step 1: Create TextInjectionService**

```swift
// SttTool/Services/TextInjectionService.swift
import AppKit
import CoreGraphics
import Foundation

actor TextInjectionService {
    func injectText(_ text: String) async {
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Brief delay for clipboard to be ready
        try? await Task.sleep(for: .milliseconds(100))

        // Simulate Cmd+V
        simulatePaste()

        // Restore previous clipboard after a delay
        try? await Task.sleep(for: .milliseconds(500))
        pasteboard.clearContents()
        if let previous = previousContents {
            pasteboard.setString(previous, forType: .string)
        }
    }

    private func simulatePaste() {
        let vKeyCode: CGKeyCode = 9 // V key

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        usleep(5000) // 5ms between down and up
        keyUp.post(tap: .cghidEventTap)
    }
}
```

**Step 2: Build and verify**

```bash
swift build 2>&1 | tail -5
```

Expected: Successful build.

**Step 3: Commit**

```bash
git add SttTool/Services/TextInjectionService.swift
git commit -m "feat: text injection service using clipboard + simulated Cmd+V"
```

---

### Task 7: Permissions service

**Files:**
- Create: `SttTool/Services/PermissionsService.swift`

**Step 1: Create PermissionsService**

```swift
// SttTool/Services/PermissionsService.swift
import AVFoundation
import AppKit
import Foundation

@MainActor
final class PermissionsService: ObservableObject {
    @Published var microphoneGranted = false
    @Published var accessibilityGranted = false

    func checkPermissions() {
        checkMicrophone()
        checkAccessibility()
    }

    func checkMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.microphoneGranted = granted
                }
            }
        default:
            microphoneGranted = false
        }
    }

    func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // Check again after a short delay
        Task {
            try? await Task.sleep(for: .seconds(1))
            checkAccessibility()
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

**Step 2: Build and verify**

```bash
swift build 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add SttTool/Services/PermissionsService.swift
git commit -m "feat: permissions service for microphone and accessibility"
```

---

## Phase 3: Coordinator & Wiring

### Task 8: Transcription coordinator

**Files:**
- Create: `SttTool/Services/TranscriptionCoordinator.swift`

**Step 1: Create TranscriptionCoordinator**

```swift
// SttTool/Services/TranscriptionCoordinator.swift
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

        do {
            try audioService.startRecording()
            appState.transcriptionState = .recording
            appState.liveTranscriptionText = ""
        } catch {
            appState.showError("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func handleHotkeyReleased() {
        guard case .recording = appState.transcriptionState else { return }

        transcriptionTask = Task {
            do {
                guard let audioData = await audioService.stopRecording() else {
                    appState.transcriptionState = .idle
                    return
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
                if appState.selectedMode != "voice" {
                    appState.transcriptionState = .processing
                    // LLM processing will be wired in Task 12
                    // For now, just use raw transcription
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
```

**Step 2: Build and verify**

```bash
swift build 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add SttTool/Services/TranscriptionCoordinator.swift
git commit -m "feat: transcription coordinator orchestrating record-transcribe-inject pipeline"
```

---

### Task 9: Wire everything together in AppState and AppDelegate

**Files:**
- Modify: `SttTool/App/AppState.swift`
- Modify: `SttTool/App/AppDelegate.swift`

**Step 1: Add service instances to AppState**

Add these properties to `AppState`:

```swift
    // MARK: - Services
    let permissionsService = PermissionsService()
    let audioService = AudioCaptureService()
    let transcriptionService = TranscriptionService()
    let textInjectionService = TextInjectionService()
    lazy var coordinator: TranscriptionCoordinator = {
        TranscriptionCoordinator(
            appState: self,
            audioService: audioService,
            transcriptionService: transcriptionService,
            textInjectionService: textInjectionService,
            permissionsService: permissionsService
        )
    }()
```

**Step 2: Update AppDelegate to wire hotkey and model loading**

Update the `applicationDidFinishLaunching` method:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        observeState()

        // Check permissions
        AppState.shared.permissionsService.checkPermissions()

        // Wire hotkey to coordinator
        let coordinator = AppState.shared.coordinator
        HotkeyManager.shared.onKeyDown = {
            Task { @MainActor in
                coordinator.handleHotkeyPressed()
            }
        }
        HotkeyManager.shared.onKeyUp = {
            Task { @MainActor in
                coordinator.handleHotkeyReleased()
            }
        }
        HotkeyManager.shared.start()

        // Load model in background
        Task {
            await loadModel()
        }
    }
```

Update the `loadModel` method:

```swift
    private func loadModel() async {
        let state = AppState.shared
        state.transcriptionState = .loading

        do {
            try await state.transcriptionService.loadModel(state.selectedModel)
            state.isModelLoaded = true
            state.transcriptionState = .idle
        } catch {
            state.showError("Failed to load model: \(error.localizedDescription)")
            // Try fallback to base model
            do {
                try await state.transcriptionService.loadModel("openai_whisper-base")
                state.selectedModel = "openai_whisper-base"
                state.isModelLoaded = true
                state.transcriptionState = .idle
            } catch {
                state.showError("Failed to load any model")
            }
        }
    }
```

**Step 3: Build and verify**

```bash
swift build 2>&1 | tail -5
```

**Step 4: Test end-to-end**

```bash
swift run SttTool &
# Wait for model to download (first time ~150MB for base model)
# Hold Option+Space, speak, release
# Text should appear in the focused app
kill %1
```

**Step 5: Commit**

```bash
git add SttTool/App/AppState.swift SttTool/App/AppDelegate.swift
git commit -m "feat: wire services together - functional push-to-talk dictation"
```

---

## Phase 4: LLM Integration

### Task 10: LLM service protocol and mode definitions

**Files:**
- Create: `SttTool/LLM/LLMService.swift`
- Create: `SttTool/Models/TranscriptionMode.swift`

**Step 1: Create TranscriptionMode**

```swift
// SttTool/Models/TranscriptionMode.swift
import Foundation

struct TranscriptionMode: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let systemPrompt: String
    let isBuiltIn: Bool

    static let voice = TranscriptionMode(
        id: "voice",
        name: "Voice",
        systemPrompt: "",
        isBuiltIn: true
    )

    static let message = TranscriptionMode(
        id: "message",
        name: "Message",
        systemPrompt: """
        You are a text formatter. Take the following speech transcription and clean it up for a chat message. \
        Make it casual and conversational. Fix grammar, remove filler words (um, uh, like), and make it concise. \
        Do NOT add any preamble or explanation. Output ONLY the cleaned text.
        """,
        isBuiltIn: true
    )

    static let email = TranscriptionMode(
        id: "email",
        name: "Email",
        systemPrompt: """
        You are a text formatter. Take the following speech transcription and format it as a professional email. \
        Add appropriate greeting and closing. Fix grammar, remove filler words, and structure it clearly. \
        Do NOT add any preamble or explanation. Output ONLY the formatted email text.
        """,
        isBuiltIn: true
    )

    static let formal = TranscriptionMode(
        id: "formal",
        name: "Formal",
        systemPrompt: """
        You are a text formatter. Take the following speech transcription and rewrite it in a formal, professional tone. \
        Fix grammar, remove filler words, and use polished language. \
        Do NOT add any preamble or explanation. Output ONLY the formatted text.
        """,
        isBuiltIn: true
    )

    static let code = TranscriptionMode(
        id: "code",
        name: "Code",
        systemPrompt: """
        You are a text formatter for developers. Take the following speech transcription and clean it up, \
        preserving all technical terms, function names, variable names, and programming concepts exactly. \
        Fix grammar and remove filler words but keep technical accuracy. \
        Do NOT add any preamble or explanation. Output ONLY the cleaned text.
        """,
        isBuiltIn: true
    )

    static let allBuiltIn: [TranscriptionMode] = [voice, message, email, formal, code]
}
```

**Step 2: Create LLMService protocol and providers**

```swift
// SttTool/LLM/LLMService.swift
import Foundation

protocol LLMProvider {
    func processText(_ text: String, systemPrompt: String) async throws -> String
}

enum LLMProviderType: String, CaseIterable, Codable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
}
```

**Step 3: Build and verify**

```bash
swift build 2>&1 | tail -5
```

**Step 4: Commit**

```bash
git add SttTool/LLM/LLMService.swift SttTool/Models/TranscriptionMode.swift
git commit -m "feat: transcription mode definitions and LLM provider protocol"
```

---

### Task 11: OpenAI and Anthropic providers

**Files:**
- Create: `SttTool/LLM/OpenAIProvider.swift`
- Create: `SttTool/LLM/AnthropicProvider.swift`
- Create: `SttTool/Services/KeychainService.swift`

**Step 1: Create KeychainService for secure API key storage**

```swift
// SttTool/Services/KeychainService.swift
import Foundation
import Security

enum KeychainService {
    private static let serviceName = "com.stttool.apikeys"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

**Step 2: Create OpenAIProvider**

```swift
// SttTool/LLM/OpenAIProvider.swift
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
                ["role": "user", "content": text]
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
```

**Step 3: Create AnthropicProvider**

```swift
// SttTool/LLM/AnthropicProvider.swift
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
                ["role": "user", "content": text]
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
```

**Step 4: Build and verify**

```bash
swift build 2>&1 | tail -5
```

**Step 5: Commit**

```bash
git add SttTool/LLM/OpenAIProvider.swift SttTool/LLM/AnthropicProvider.swift SttTool/Services/KeychainService.swift
git commit -m "feat: OpenAI and Anthropic LLM providers with Keychain storage"
```

---

### Task 12: Mode manager and wire LLM into coordinator

**Files:**
- Create: `SttTool/LLM/ModeManager.swift`
- Modify: `SttTool/Services/TranscriptionCoordinator.swift`
- Modify: `SttTool/App/AppState.swift`

**Step 1: Create ModeManager**

```swift
// SttTool/LLM/ModeManager.swift
import AppKit
import Foundation

@MainActor
final class ModeManager: ObservableObject {
    @Published var allModes: [TranscriptionMode] = TranscriptionMode.allBuiltIn
    @Published var customModes: [TranscriptionMode] = []

    // Super Mode app-to-mode mappings
    private let superModeMappings: [String: String] = [
        "Slack": "message",
        "Discord": "message",
        "Messages": "message",
        "Telegram": "message",
        "WhatsApp": "message",
        "Mail": "email",
        "Outlook": "email",
        "Spark": "email",
        "Xcode": "code",
        "Visual Studio Code": "code",
        "Code": "code", // VS Code sometimes reports as "Code"
        "Terminal": "code",
        "iTerm2": "code",
        "Warp": "code",
    ]

    @AppStorage("llmProvider") var selectedProvider: String = "openai"
    @AppStorage("openaiModel") var openaiModel: String = "gpt-4o-mini"
    @AppStorage("anthropicModel") var anthropicModel: String = "claude-haiku-4-5-20251001"

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
        default:
            return nil
        }
    }

    // MARK: - Custom Modes
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
            AppState.shared.customModesJSON = json
        }
    }

    private func loadCustomModes() {
        if let data = AppState.shared.customModesJSON.data(using: .utf8),
           let modes = try? JSONDecoder().decode([TranscriptionMode].self, from: data) {
            customModes = modes
            allModes = TranscriptionMode.allBuiltIn + modes
        }
    }
}
```

**Step 2: Add ModeManager to AppState**

Add to AppState's properties:

```swift
    let modeManager = ModeManager()
```

**Step 3: Wire LLM processing into TranscriptionCoordinator**

In `handleHotkeyReleased()`, replace the LLM placeholder section:

```swift
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
                    // If no provider configured, just use raw transcription
                }
```

**Step 4: Build and verify**

```bash
swift build 2>&1 | tail -5
```

**Step 5: Commit**

```bash
git add SttTool/LLM/ModeManager.swift SttTool/Services/TranscriptionCoordinator.swift SttTool/App/AppState.swift
git commit -m "feat: LLM mode manager with Super Mode and provider integration"
```

---

## Phase 5: UI

### Task 13: Menubar popover view

**Files:**
- Modify: `SttTool/Views/MenuBarView.swift`

**Step 1: Build full MenuBarView**

```swift
// SttTool/Views/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject private var appState = AppState.shared
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with status
            headerSection
            Divider()

            // Mode selector
            modeSection
            Divider()

            // Recent transcriptions
            recentSection

            Divider()

            // Footer
            footerSection
        }
        .frame(width: 320)
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SttTool")
                        .font(.headline)
                    Text(appState.transcriptionState.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(appState.modelDisplayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
    }

    private var modeSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Mode")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Super", isOn: $appState.superModeEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            Picker("", selection: $appState.selectedMode) {
                ForEach(appState.modeManager.allModes) { mode in
                    Text(mode.name).tag(mode.id)
                }
            }
            .pickerStyle(.segmented)
            .disabled(appState.superModeEnabled)
        }
        .padding(12)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if appState.recentTranscriptions.isEmpty {
                Text("No transcriptions yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(appState.recentTranscriptions.prefix(5).enumerated()), id: \.offset) { _, text in
                            Text(text)
                                .font(.caption)
                                .lineLimit(2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Button("Settings...") { onOpenSettings() }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            Spacer()
            Button("Quit") { onQuit() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    // MARK: - Computed

    private var statusIcon: String {
        switch appState.transcriptionState {
        case .recording: return "mic.fill"
        case .error: return "mic.slash.fill"
        default: return "mic.fill"
        }
    }

    private var statusColor: Color {
        switch appState.transcriptionState {
        case .idle: return appState.isModelLoaded ? .green : .yellow
        case .loading: return .yellow
        case .recording: return .red
        case .transcribing, .processing: return .blue
        case .error: return .orange
        }
    }
}
```

**Step 2: Build and verify**

```bash
swift build 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add SttTool/Views/MenuBarView.swift
git commit -m "feat: menubar popover with mode selector and recent transcriptions"
```

---

### Task 14: Settings view (tabbed)

**Files:**
- Modify: `SttTool/Views/SettingsView.swift`

**Step 1: Build full SettingsView**

```swift
// SttTool/Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            ModelsSettingsTab()
                .tabItem { Label("Models", systemImage: "cpu") }
            ModesSettingsTab()
                .tabItem { Label("Modes", systemImage: "text.bubble") }
            APIKeysSettingsTab()
                .tabItem { Label("API Keys", systemImage: "key") }
            VocabularySettingsTab()
                .tabItem { Label("Vocabulary", systemImage: "textformat") }
            LanguageSettingsTab()
                .tabItem { Label("Language", systemImage: "globe") }
        }
        .frame(width: 550, height: 400)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
            Section("Activation") {
                Picker("Mode", selection: $appState.activationMode) {
                    Text("Push to Talk (hold hotkey)").tag("pushToTalk")
                    Text("Toggle (press to start/stop)").tag("toggle")
                }

                HStack {
                    Text("Hotkey:")
                    Text(hotkeyDescription)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Option + Space (default)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $appState.launchAtLogin)
            }

            Section("Permissions") {
                HStack {
                    Image(systemName: appState.permissionsService.microphoneGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appState.permissionsService.microphoneGranted ? .green : .red)
                    Text("Microphone")
                    Spacer()
                    if !appState.permissionsService.microphoneGranted {
                        Button("Grant") {
                            appState.permissionsService.openMicrophoneSettings()
                        }
                    }
                }
                HStack {
                    Image(systemName: appState.permissionsService.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appState.permissionsService.accessibilityGranted ? .green : .red)
                    Text("Accessibility")
                    Spacer()
                    if !appState.permissionsService.accessibilityGranted {
                        Button("Grant") {
                            appState.permissionsService.requestAccessibility()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeyDescription: String {
        var parts: [String] = []
        let mods = CGEventFlags(rawValue: UInt64(appState.hotkeyModifiers))
        if mods.contains(.maskControl) { parts.append("Ctrl") }
        if mods.contains(.maskAlternate) { parts.append("Option") }
        if mods.contains(.maskShift) { parts.append("Shift") }
        if mods.contains(.maskCommand) { parts.append("Cmd") }
        parts.append("Space") // Simplified for now
        return parts.joined(separator: " + ")
    }
}

// MARK: - Models Tab

struct ModelsSettingsTab: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
            Section("Whisper Model") {
                Picker("Active Model", selection: $appState.selectedModel) {
                    ForEach(TranscriptionService.ModelInfo.available, id: \.id) { model in
                        HStack {
                            Text(model.displayName)
                            Spacer()
                            Text(model.sizeDescription)
                                .foregroundStyle(.secondary)
                        }
                        .tag(model.id)
                    }
                }

                if appState.transcriptionState == .loading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading model...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Model Tiers") {
                VStack(alignment: .leading, spacing: 8) {
                    modelTierRow("Nano", "Tiny model, fastest, ~40MB", "bolt.fill")
                    modelTierRow("Fast", "Base model, balanced, ~150MB", "hare.fill")
                    modelTierRow("Pro", "Small model, accurate, ~500MB", "star.fill")
                    modelTierRow("Ultra", "Large-v3, best accuracy, ~1.5GB", "crown.fill")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func modelTierRow(_ tier: String, _ desc: String, _ icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
            VStack(alignment: .leading) {
                Text(tier).font(.headline)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Modes Tab

struct ModesSettingsTab: View {
    @ObservedObject private var appState = AppState.shared
    @State private var showAddMode = false
    @State private var newModeName = ""
    @State private var newModePrompt = ""

    var body: some View {
        Form {
            Section("Built-in Modes") {
                ForEach(TranscriptionMode.allBuiltIn) { mode in
                    HStack {
                        Text(mode.name)
                        Spacer()
                        if mode.id == "voice" {
                            Text("No LLM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Custom Modes") {
                ForEach(appState.modeManager.customModes) { mode in
                    HStack {
                        Text(mode.name)
                        Spacer()
                        Button(role: .destructive) {
                            appState.modeManager.removeCustomMode(id: mode.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Custom Mode...") {
                    showAddMode = true
                }
            }

            Section("Super Mode") {
                Toggle("Enable Super Mode", isOn: $appState.superModeEnabled)
                Text("Automatically selects the best mode based on the active app (e.g., Slack → Message, Mail → Email)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAddMode) {
            VStack(spacing: 16) {
                Text("New Custom Mode").font(.headline)
                TextField("Mode Name", text: $newModeName)
                    .textFieldStyle(.roundedBorder)
                Text("System Prompt:").frame(maxWidth: .infinity, alignment: .leading)
                TextEditor(text: $newModePrompt)
                    .frame(height: 150)
                    .border(.secondary.opacity(0.3))
                HStack {
                    Button("Cancel") { showAddMode = false }
                    Spacer()
                    Button("Add") {
                        if !newModeName.isEmpty && !newModePrompt.isEmpty {
                            appState.modeManager.addCustomMode(name: newModeName, systemPrompt: newModePrompt)
                            newModeName = ""
                            newModePrompt = ""
                            showAddMode = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 400)
        }
    }
}

// MARK: - API Keys Tab

struct APIKeysSettingsTab: View {
    @ObservedObject private var appState = AppState.shared
    @State private var openaiKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var showOpenAIKey = false
    @State private var showAnthropicKey = false

    var body: some View {
        Form {
            Section("LLM Provider") {
                Picker("Provider", selection: $appState.modeManager.selectedProvider) {
                    Text("OpenAI").tag("openai")
                    Text("Anthropic").tag("anthropic")
                }
            }

            Section("OpenAI") {
                HStack {
                    if showOpenAIKey {
                        TextField("API Key", text: $openaiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $openaiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showOpenAIKey ? "Hide" : "Show") {
                        showOpenAIKey.toggle()
                    }
                }
                TextField("Model", text: $appState.modeManager.openaiModel)
                    .textFieldStyle(.roundedBorder)
                Button("Save OpenAI Key") {
                    KeychainService.save(key: "openai_api_key", value: openaiKey)
                }
            }

            Section("Anthropic") {
                HStack {
                    if showAnthropicKey {
                        TextField("API Key", text: $anthropicKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $anthropicKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showAnthropicKey ? "Hide" : "Show") {
                        showAnthropicKey.toggle()
                    }
                }
                TextField("Model", text: $appState.modeManager.anthropicModel)
                    .textFieldStyle(.roundedBorder)
                Button("Save Anthropic Key") {
                    KeychainService.save(key: "anthropic_api_key", value: anthropicKey)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            openaiKey = KeychainService.get(key: "openai_api_key") ?? ""
            anthropicKey = KeychainService.get(key: "anthropic_api_key") ?? ""
        }
    }
}

// MARK: - Vocabulary Tab

struct VocabularySettingsTab: View {
    @ObservedObject private var appState = AppState.shared
    @State private var vocabulary: [String] = []
    @State private var newWord = ""

    var body: some View {
        Form {
            Section("Custom Vocabulary") {
                Text("Add names, abbreviations, and specialized terms to improve transcription accuracy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Add word or phrase...", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addWord() }
                    Button("Add") { addWord() }
                        .disabled(newWord.isEmpty)
                }

                List {
                    ForEach(vocabulary, id: \.self) { word in
                        Text(word)
                    }
                    .onDelete { indices in
                        vocabulary.remove(atOffsets: indices)
                        saveVocabulary()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadVocabulary() }
    }

    private func addWord() {
        guard !newWord.isEmpty else { return }
        vocabulary.append(newWord)
        newWord = ""
        saveVocabulary()
    }

    private func loadVocabulary() {
        if let data = appState.customVocabularyJSON.data(using: .utf8),
           let words = try? JSONDecoder().decode([String].self, from: data) {
            vocabulary = words
        }
    }

    private func saveVocabulary() {
        if let data = try? JSONEncoder().encode(vocabulary),
           let json = String(data: data, encoding: .utf8) {
            appState.customVocabularyJSON = json
        }
    }
}

// MARK: - Language Tab

struct LanguageSettingsTab: View {
    @ObservedObject private var appState = AppState.shared

    private let languages: [(code: String, name: String)] = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("ru", "Russian"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("tr", "Turkish"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("fi", "Finnish"),
        ("no", "Norwegian"),
        ("uk", "Ukrainian"),
        ("cs", "Czech"),
        ("el", "Greek"),
        ("he", "Hebrew"),
        ("hu", "Hungarian"),
        ("id", "Indonesian"),
        ("ms", "Malay"),
        ("ro", "Romanian"),
        ("th", "Thai"),
        ("vi", "Vietnamese"),
    ]

    var body: some View {
        Form {
            Section("Transcription Language") {
                Toggle("Auto-detect language", isOn: $appState.autoDetectLanguage)

                if !appState.autoDetectLanguage {
                    Picker("Language", selection: $appState.language) {
                        ForEach(languages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                }
            }

            Section("Info") {
                Text("Whisper supports 100+ languages. Auto-detect works well but specifying a language can improve accuracy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

**Step 2: Build and verify**

```bash
swift build 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add SttTool/Views/SettingsView.swift
git commit -m "feat: full settings UI with tabs for general, models, modes, API keys, vocabulary, language"
```

---

### Task 15: Transcription overlay

**Files:**
- Create: `SttTool/Views/TranscriptionOverlay.swift`
- Modify: `SttTool/App/AppDelegate.swift`

**Step 1: Create TranscriptionOverlay**

```swift
// SttTool/Views/TranscriptionOverlay.swift
import SwiftUI
import AppKit

struct TranscriptionOverlayView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !appState.liveTranscriptionText.isEmpty {
                Text(appState.liveTranscriptionText)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 300, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4)
    }

    private var dotColor: Color {
        switch appState.transcriptionState {
        case .recording: return .red
        case .transcribing: return .blue
        case .processing: return .purple
        default: return .gray
        }
    }

    private var statusText: String {
        switch appState.transcriptionState {
        case .recording: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .processing: return "Processing..."
        default: return ""
        }
    }
}

final class OverlayWindowController {
    private var window: NSWindow?

    func show() {
        if window != nil { return }

        let overlayView = TranscriptionOverlayView()
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = true

        // Position near mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: mouseLocation.x + 20,
            y: mouseLocation.y - 100
        ))

        window.orderFront(nil)
        self.window = window
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}
```

**Step 2: Wire overlay into AppDelegate**

Add to AppDelegate's properties:

```swift
    private let overlayController = OverlayWindowController()
```

Update `observeState()` to also show/hide the overlay:

```swift
    private func observeState() {
        stateObservation = AppState.shared.$transcriptionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateStatusItemIcon()
                switch state {
                case .recording, .transcribing, .processing:
                    self?.overlayController.show()
                default:
                    self?.overlayController.dismiss()
                }
            }
    }
```

**Step 3: Build and verify**

```bash
swift build 2>&1 | tail -5
```

**Step 4: Commit**

```bash
git add SttTool/Views/TranscriptionOverlay.swift SttTool/App/AppDelegate.swift
git commit -m "feat: floating transcription overlay near cursor during recording"
```

---

## Phase 6: Polish

### Task 16: Audio mute service (prevent feedback)

**Files:**
- Create: `SttTool/Services/AudioMuteService.swift`

**Step 1: Create AudioMuteService**

```swift
// SttTool/Services/AudioMuteService.swift
import CoreAudio
import Foundation

actor AudioMuteService {
    private var previousMuteState: UInt32 = 0
    private var isMutedByUs = false

    func muteOutput() {
        guard let deviceID = getDefaultOutputDevice() else { return }

        // Save current mute state
        previousMuteState = getMuteState(deviceID: deviceID)

        // Mute
        setMuteState(deviceID: deviceID, muted: 1)
        isMutedByUs = true
    }

    func restoreOutput() {
        guard isMutedByUs, let deviceID = getDefaultOutputDevice() else { return }

        setMuteState(deviceID: deviceID, muted: previousMuteState)
        isMutedByUs = false
    }

    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    private func getMuteState(deviceID: AudioDeviceID) -> UInt32 {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        return muted
    }

    private func setMuteState(deviceID: AudioDeviceID, muted: UInt32) {
        var value = muted
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
    }
}
```

**Step 2: Wire into AppState and Coordinator**

Add to AppState:

```swift
    let audioMuteService = AudioMuteService()
    @AppStorage("muteWhileRecording") var muteWhileRecording: Bool = false
```

Add muting to TranscriptionCoordinator's `handleHotkeyPressed()` (before `startRecording`):

```swift
        // Optionally mute system audio
        if appState.muteWhileRecording {
            await appState.audioMuteService.muteOutput()
        }
```

Add unmuting to `handleHotkeyReleased()` (right after `stopRecording`):

```swift
            // Restore audio
            if appState.muteWhileRecording {
                await appState.audioMuteService.restoreOutput()
            }
```

And to `cancel()`:

```swift
        if appState.muteWhileRecording {
            Task { await appState.audioMuteService.restoreOutput() }
        }
```

**Step 3: Build and verify**

```bash
swift build 2>&1 | tail -5
```

**Step 4: Commit**

```bash
git add SttTool/Services/AudioMuteService.swift SttTool/App/AppState.swift SttTool/Services/TranscriptionCoordinator.swift
git commit -m "feat: audio mute service to prevent feedback during recording"
```

---

### Task 17: Add .gitignore and final build verification

**Files:**
- Create: `.gitignore`

**Step 1: Create .gitignore**

```
.build/
.swiftpm/
Package.resolved
*.xcodeproj
*.xcworkspace
xcuserdata/
DerivedData/
.DS_Store
```

**Step 2: Full clean build**

```bash
swift package clean && swift build 2>&1 | tail -10
```

Expected: Successful build with no warnings ideally.

**Step 3: Test run end-to-end**

```bash
swift run SttTool
```

Manual test:
1. Verify menubar icon appears (mic icon, yellow while loading)
2. Wait for model to download/load (icon turns green)
3. Click icon, verify popover appears with mode selector
4. Open Settings, verify all tabs render
5. Hold Option+Space, speak a sentence, release
6. Verify text appears in the focused text field
7. Quit from menubar popover

**Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: add .gitignore and finalize project structure"
```

---

## Summary

| Phase | Tasks | What it delivers |
|-------|-------|-----------------|
| 1: Scaffolding | 1-2 | Building project with menubar icon |
| 2: Core Services | 3-7 | Audio capture, WhisperKit, hotkey, text injection, permissions |
| 3: Coordinator | 8-9 | Functional push-to-talk dictation end-to-end |
| 4: LLM Integration | 10-12 | Text cleanup modes with OpenAI/Anthropic |
| 5: UI | 13-15 | Full menubar popover, settings, overlay |
| 6: Polish | 16-17 | Audio muting, final verification |

After Task 9 you have a **working dictation tool**. Everything after that adds LLM modes and polish.
