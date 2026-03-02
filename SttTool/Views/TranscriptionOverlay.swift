import SwiftUI
import AppKit
import Combine

// MARK: - Overlay SwiftUI View

struct TranscriptionOverlayView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var appearAnimation = false

    private var isRecording: Bool {
        appState.transcriptionState == .recording
    }

    var body: some View {
        HStack(spacing: 14) {
            // Animated recording indicator
            ZStack {
                if isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.2), lineWidth: 2)
                        .frame(width: 36, height: 36)
                        .scaleEffect(appearAnimation ? 1.6 : 1.0)
                        .opacity(appearAnimation ? 0 : 0.6)
                        .animation(
                            .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                            value: appearAnimation
                        )

                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 2)
                        .frame(width: 36, height: 36)
                        .scaleEffect(appearAnimation ? 1.3 : 1.0)
                        .opacity(appearAnimation ? 0 : 0.8)
                        .animation(
                            .easeOut(duration: 1.5).repeatForever(autoreverses: false).delay(0.3),
                            value: appearAnimation
                        )
                }

                Circle()
                    .fill(dotColor)
                    .frame(width: isRecording ? 16 : 10, height: isRecording ? 16 : 10)
                    .shadow(color: dotColor.opacity(0.5), radius: isRecording ? 6 : 0)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(statusText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                if !appState.liveTranscriptionText.isEmpty {
                    Text(appState.liveTranscriptionText)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 380, alignment: .leading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 24)
        .padding(.vertical, 14)
        .frame(width: 440)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        }
        .onAppear { appearAnimation = true }
        .onDisappear { appearAnimation = false }
    }

    // MARK: - Helpers

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

// MARK: - Draggable Overlay Window

private class DraggableWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Overlay Window Controller

@MainActor
final class OverlayWindowController {
    private var window: NSWindow?

    func show() {
        if let window = window, window.isVisible {
            repositionWindow(window)
            return
        }

        let overlayView = TranscriptionOverlayView()
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.setFrameSize(NSSize(width: 440, height: 80))

        // Ensure no opaque background behind the rounded pill
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        let window = DraggableWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 440, height: 80)),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = hostingView
        window.isReleasedWhenClosed = false

        repositionWindow(window)
        window.orderFront(nil)
        self.window = window
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }

    // MARK: - Positioning

    private func repositionWindow(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let offsetX: CGFloat = 20
        let offsetY: CGFloat = -100

        var origin = NSPoint(
            x: mouseLocation.x + offsetX,
            y: mouseLocation.y + offsetY
        )

        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let windowSize = window.frame.size

            if origin.x + windowSize.width > visibleFrame.maxX {
                origin.x = mouseLocation.x - windowSize.width - offsetX
            }
            if origin.x < visibleFrame.minX {
                origin.x = visibleFrame.minX
            }
            if origin.y < visibleFrame.minY {
                origin.y = visibleFrame.minY
            }
            if origin.y + windowSize.height > visibleFrame.maxY {
                origin.y = visibleFrame.maxY - windowSize.height
            }
        }

        window.setFrameOrigin(origin)
    }
}
