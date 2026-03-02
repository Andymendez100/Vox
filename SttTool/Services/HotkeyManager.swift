import Carbon
import CoreGraphics
import Foundation

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    fileprivate var eventTap: CFMachPort?
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

    fileprivate func handleEvent(
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
