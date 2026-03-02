import Carbon
import CoreGraphics
import Foundation
import os.log

private let hotkeyLogger = Logger(subsystem: "com.voxapp.app", category: "HotkeyManager")

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    // Hotkey configuration
    private var keyCode: UInt16 = 54 // Right Command
    private var requiredModifiers: CGEventFlags = []
    private var useModifierOnly: Bool = true

    private var isKeyDown = false

    static let rightCommandKeyCode: UInt16 = 54
    static let leftCommandKeyCode: UInt16 = 55

    private init() {}

    func start() {
        stop()
        loadSavedHotkey()
        hotkeyLogger.notice("keyCode=\(self.keyCode), modifierOnly=\(self.useModifierOnly), modifiers=\(self.requiredModifiers.rawValue)")

        // Run the event tap on a dedicated background thread so the main
        // thread's busyness (model loading, transcription, SwiftUI) can never
        // block event processing and freeze the system.
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.startTapOnCurrentThread()
            // Keep the run loop alive
            CFRunLoopRun()
        }
        thread.name = "com.voxapp.hotkey-event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let rl = tapRunLoop {
            if let source = runLoopSource {
                CFRunLoopRemoveSource(rl, source, .commonModes)
            }
            CFRunLoopStop(rl)
        }
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
        isKeyDown = false
    }

    func setHotkey(keyCode: UInt16, modifiers: CGEventFlags, modifierOnly: Bool = false) {
        self.keyCode = keyCode
        self.requiredModifiers = modifiers
        self.useModifierOnly = modifierOnly
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "hotkeyModifiers")
        UserDefaults.standard.set(modifierOnly, forKey: "hotkeyModifierOnly")
    }

    // MARK: - Private

    private func startTapOnCurrentThread() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        // Use .listenOnly instead of .defaultTap. An active (default) tap
        // blocks ALL system input if the callback thread stalls for any reason
        // (priority inversion, memory pressure, OS scheduling). A listen-only
        // tap observes events without blocking — the system never waits for
        // our callback, so the app can never freeze the Mac.
        // Trade-off: we can't consume hotkey events, so they also reach other
        // apps. For modifier-only keys (Right Cmd) this is harmless.
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            hotkeyLogger.warning("cghidEventTap failed, trying cgSessionEventTap...")
            guard let sessionTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: hotkeyCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                hotkeyLogger.error("FAILED to create any event tap. Grant Accessibility permission and restart.")
                return
            }
            hotkeyLogger.notice("Using cgSessionEventTap (fallback)")
            installTap(sessionTap)
            return
        }
        hotkeyLogger.notice("Event tap created on dedicated thread (cghidEventTap)")
        installTap(tap)
    }

    private func installTap(_ tap: CFMachPort) {
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        let rl = CFRunLoopGetCurrent()!
        self.tapRunLoop = rl
        CFRunLoopAddSource(rl, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func loadSavedHotkey() {
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        let savedModifiers = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        let savedModifierOnly = UserDefaults.standard.bool(forKey: "hotkeyModifierOnly")

        if savedKeyCode != 0 {
            keyCode = UInt16(savedKeyCode)
            requiredModifiers = CGEventFlags(rawValue: UInt64(savedModifiers))
            useModifierOnly = savedModifierOnly
        }
    }

    fileprivate func handleEvent(
        _ proxy: CGEventTapProxy,
        _ type: CGEventType,
        _ event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if useModifierOnly {
            return handleModifierOnlyEvent(proxy, type, event)
        } else {
            return handleKeyComboEvent(proxy, type, event)
        }
    }

    private func handleModifierOnlyEvent(
        _ proxy: CGEventTapProxy,
        _ type: CGEventType,
        _ event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else {
            if isKeyDown && (type == .keyDown) {
                isKeyDown = false
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        guard eventKeyCode == keyCode else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags

        let isModifierPressed: Bool
        switch keyCode {
        case HotkeyManager.rightCommandKeyCode, HotkeyManager.leftCommandKeyCode:
            isModifierPressed = flags.contains(.maskCommand)
        case 56: // Left Shift
            isModifierPressed = flags.contains(.maskShift)
        case 58, 61: // Left/Right Option
            isModifierPressed = flags.contains(.maskAlternate)
        case 59, 62: // Left/Right Control
            isModifierPressed = flags.contains(.maskControl)
        default:
            isModifierPressed = false
        }

        if isModifierPressed && !isKeyDown {
            isKeyDown = true
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown?()
            }
            return nil
        } else if !isModifierPressed && isKeyDown {
            isKeyDown = false
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyComboEvent(
        _ proxy: CGEventTapProxy,
        _ type: CGEventType,
        _ event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let relevantFlags = flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])
        let requiredRelevant = requiredModifiers.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])

        guard eventKeyCode == keyCode && relevantFlags == requiredRelevant else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            if !isKeyDown {
                isKeyDown = true
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyDown?()
                }
            }
            return nil

        case .keyUp:
            if isKeyDown {
                isKeyDown = false
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = manager.eventTap {
                hotkeyLogger.warning("Event tap was disabled, re-enabling...")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleEvent(proxy, type, event)
}
