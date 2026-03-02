import AppKit
import CoreGraphics
import Foundation

actor TextInjectionService {
    func injectText(_ text: String) async {
        // Save current clipboard
        let previousContents = await MainActor.run {
            NSPasteboard.general.string(forType: .string)
        }

        // Set new text
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }

        // Brief delay for clipboard to be ready
        try? await Task.sleep(for: .milliseconds(100))

        // Simulate Cmd+V
        simulatePaste()

        // Restore previous clipboard after a delay
        try? await Task.sleep(for: .milliseconds(500))
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let previous = previousContents {
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    func copyToClipboard(_ text: String) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    func undoLastInjection() async {
        simulateUndo()
    }

    private func simulatePaste() {
        let vKeyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        usleep(5000)
        keyUp.post(tap: .cghidEventTap)
    }

    private func simulateUndo() {
        let zKeyCode: CGKeyCode = 6

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: zKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: zKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        usleep(5000)
        keyUp.post(tap: .cghidEventTap)
    }
}
