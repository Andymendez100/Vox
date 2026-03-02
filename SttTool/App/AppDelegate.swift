import SwiftUI
import AppKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.stttool.app", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var stateObservation: AnyCancellable?
    private let overlayController = OverlayWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        observeState()

        // Check permissions
        let permissions = AppState.shared.permissionsService
        permissions.checkPermissions()
        logger.notice("Accessibility granted: \(permissions.accessibilityGranted)")
        logger.notice("Microphone granted: \(permissions.microphoneGranted)")

        // Request accessibility if not granted (shows system prompt dialog)
        if !permissions.accessibilityGranted {
            logger.notice("Requesting accessibility permission...")
            permissions.requestAccessibility()
        }

        // Wire hotkey to coordinator
        let coordinator = AppState.shared.coordinator
        HotkeyManager.shared.onKeyDown = {
            Task { @MainActor in
                logger.notice("Hotkey DOWN - starting recording")
                coordinator.handleHotkeyPressed()
            }
        }
        HotkeyManager.shared.onKeyUp = {
            Task { @MainActor in
                logger.notice("Hotkey UP - stopping recording")
                coordinator.handleHotkeyReleased()
            }
        }

        // Start hotkey manager (will retry after permission granted)
        if permissions.accessibilityGranted {
            HotkeyManager.shared.start()
            logger.notice("HotkeyManager started")
        } else {
            logger.notice("Deferring HotkeyManager start until accessibility is granted")
            Task {
                // Poll with backoff — no macOS notification exists for this
                var interval: Duration = .seconds(1)
                let maxInterval: Duration = .seconds(10)
                while !AXIsProcessTrusted() {
                    try? await Task.sleep(for: interval)
                    if interval < maxInterval { interval *= 2 }
                }
                permissions.accessibilityGranted = true
                logger.notice("Accessibility now granted! Starting HotkeyManager...")
                HotkeyManager.shared.start()
            }
        }

        // Load model in background
        Task {
            await self.loadModel()
        }

        // Open settings on launch
        openSettings()
    }

    // MARK: - Status Item
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
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
        let useColor: Bool

        switch state {
        case .idle where AppState.shared.isModelLoaded:
            iconName = "waveform"
            useColor = false
        case .idle, .loading:
            iconName = "waveform.badge.exclamationmark"
            useColor = false
        case .recording:
            iconName = "waveform.circle.fill"
            useColor = true
        case .transcribing, .processing:
            iconName = "waveform.circle"
            useColor = true
        case .error:
            iconName = "waveform.slash"
            useColor = false
        }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if useColor {
            // Non-template so the tint color actually shows
            let palette = NSImage.SymbolConfiguration(paletteColors: [
                state == .recording ? .systemRed : .systemBlue
            ])
            let combined = config.applying(palette)
            if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "SttTool")?
                .withSymbolConfiguration(combined) {
                image.isTemplate = false
                button.image = image
            }
        } else {
            // Template mode — system handles light/dark automatically
            if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "SttTool")?
                .withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
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

    // MARK: - Model Loading
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

    // MARK: - State Observation
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
}
