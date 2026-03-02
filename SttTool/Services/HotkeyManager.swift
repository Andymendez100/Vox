import Carbon
import CoreGraphics
import Foundation

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Hotkey configuration
    // For modifier-only hotkeys (e.g., Right Command), keyCode is the modifier key code
    // and useModifierOnly is true.
    // For key+modifier combos (e.g., Option+Space), keyCode is the key and
    // requiredModifiers is the modifier mask.
    private var keyCode: UInt16 = 54 // Right Command
    private var requiredModifiers: CGEventFlags = [] // No additional modifiers needed
    private var useModifierOnly: Bool = true // True = trigger on modifier key press/release

    private var isKeyDown = false

    // Right Command keycode
    static let rightCommandKeyCode: UInt16 = 54
    static let leftCommandKeyCode: UInt16 = 55

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

    func setHotkey(keyCode: UInt16, modifiers: CGEventFlags, modifierOnly: Bool = false) {
        self.keyCode = keyCode
        self.requiredModifiers = modifiers
        self.useModifierOnly = modifierOnly
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "hotkeyModifiers")
        UserDefaults.standard.set(modifierOnly, forKey: "hotkeyModifierOnly")
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
        let savedModifierOnly = UserDefaults.standard.bool(forKey: "hotkeyModifierOnly")

        if savedKeyCode != 0 {
            keyCode = UInt16(savedKeyCode)
            requiredModifiers = CGEventFlags(rawValue: UInt64(savedModifiers))
            useModifierOnly = savedModifierOnly
        }
        // else keep defaults (Right Command, modifier-only)
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

    // Handle modifier-only hotkeys (e.g., Right Command)
    private func handleModifierOnlyEvent(
        _ proxy: CGEventTapProxy,
        _ type: CGEventType,
        _ event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else {
            // If a regular key is pressed while our modifier is held, cancel
            if isKeyDown && (type == .keyDown) {
                isKeyDown = false
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
            return Unmanaged.passRetained(event)
        }

        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        guard eventKeyCode == keyCode else {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags

        // Check if our modifier is now pressed or released
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
            return nil // Swallow
        } else if !isModifierPressed && isKeyDown {
            isKeyDown = false
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
            return nil // Swallow
        }

        return Unmanaged.passRetained(event)
    }

    // Handle key+modifier combos (e.g., Option+Space)
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
            return Unmanaged.passRetained(event)
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
