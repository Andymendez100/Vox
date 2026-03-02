import SwiftUI
import AppKit
import Combine

// MARK: - Overlay SwiftUI View

struct TranscriptionOverlayView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        HStack(spacing: 8) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                if !appState.liveTranscriptionText.isEmpty {
                    Text(appState.liveTranscriptionText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: 260, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .frame(maxWidth: 300)
    }

    // MARK: - Status Dot

    @ViewBuilder
    private var statusDot: some View {
        let color = dotColor
        ZStack {
            // Pulse ring (only while recording)
            if appState.transcriptionState == .recording {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .modifier(PulseModifier())
            }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 16, height: 16)
    }

    // MARK: - Helpers

    private var dotColor: Color {
        switch appState.transcriptionState {
        case .recording:
            return .red
        case .transcribing:
            return .blue
        case .processing:
            return .purple
        default:
            return .gray
        }
    }

    private var statusText: String {
        switch appState.transcriptionState {
        case .recording:
            return "Listening..."
        case .transcribing:
            return "Transcribing..."
        case .processing:
            return "Processing..."
        default:
            return ""
        }
    }
}

// MARK: - Pulse Animation Modifier

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.8 : 1.0)
            .opacity(isPulsing ? 0.0 : 0.6)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Overlay Window Controller

@MainActor
final class OverlayWindowController {
    private var window: NSWindow?
    private var stateObservation: AnyCancellable?

    func show() {
        // If already showing, just reposition
        if let window = window, window.isVisible {
            repositionWindow(window)
            return
        }

        let overlayView = TranscriptionOverlayView()
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false // SwiftUI handles shadows via .shadow modifier
        window.ignoresMouseEvents = true
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
        let offsetY: CGFloat = -100  // Below cursor (screen coords go up)

        var origin = NSPoint(
            x: mouseLocation.x + offsetX,
            y: mouseLocation.y + offsetY
        )

        // Ensure the window stays within the visible screen area
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let windowSize = window.frame.size

            // Clamp horizontally
            if origin.x + windowSize.width > visibleFrame.maxX {
                origin.x = mouseLocation.x - windowSize.width - offsetX
            }
            if origin.x < visibleFrame.minX {
                origin.x = visibleFrame.minX
            }

            // Clamp vertically
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
