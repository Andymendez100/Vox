import SwiftUI
import AppKit
import Combine

// MARK: - Overlay SwiftUI View

struct TranscriptionOverlayView: View {
    @ObservedObject private var appState = AppState.shared

    private var isRecording: Bool {
        appState.transcriptionState == .recording
    }

    private var isLoading: Bool {
        appState.transcriptionState == .loading
    }

    var body: some View {
        Group {
            if isLoading {
                loadingBody
            } else if isRecording {
                recordingBody
            } else {
                nonRecordingBody
            }
        }
        .padding(.horizontal, 24)
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
    }

    // MARK: - Loading Layout

    private var loadingBody: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text("Loading \(appState.modelDisplayName) model...")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                if appState.modelLoadProgress > 0 {
                    Text("\(Int(appState.modelLoadProgress * 100))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if appState.modelLoadProgress > 0 {
                ProgressView(value: appState.modelLoadProgress)
                    .tint(.accentColor)
            }
        }
    }

    // MARK: - Recording Layout (centered waveform hero)

    private var recordingBody: some View {
        VStack(spacing: 8) {
            WaveformView(levels: appState.audioLevels)
                .frame(height: 40)

            HStack(spacing: 8) {
                Text(statusText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                if let startTime = appState.recordingStartTime {
                    RecordingTimerView(startTime: startTime)
                }

                if !appState.detectedLanguage.isEmpty {
                    Text(appState.detectedLanguage.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.blue.opacity(0.7))
                        )
                }
            }

            if !appState.liveTranscriptionText.isEmpty {
                Text(appState.liveTranscriptionText)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Non-recording Layout (dot + status)

    private var nonRecordingBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: dotColor.opacity(0.5), radius: 3)

                Text(statusText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }

            if !appState.liveTranscriptionText.isEmpty {
                Text(appState.liveTranscriptionText)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
        case .loading: return "Loading model..."
        case .recording: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .processing: return "Processing..."
        default: return ""
        }
    }
}

// MARK: - Waveform View

private struct WaveformView: View {
    let levels: [Float]

    private var displayLevels: [Float] {
        if levels.count >= 50 {
            return Array(levels.suffix(50))
        }
        return Array(repeating: 0, count: 50)
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<50, id: \.self) { index in
                WaveformBar(level: CGFloat(displayLevels[index]))
            }
        }
    }
}

private struct WaveformBar: View {
    let level: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let maxHeight = geometry.size.height
            let barHeight = max(2, maxHeight * level)

            RoundedRectangle(cornerRadius: 1)
                .fill(Color.red)
                .frame(width: geometry.size.width, height: barHeight)
                .opacity(0.4 + 0.6 * level)
                .position(x: geometry.size.width / 2, y: maxHeight / 2)
                .animation(.easeOut(duration: 0.1), value: level)
        }
    }
}

// MARK: - Recording Timer

private struct RecordingTimerView: View {
    let startTime: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            let nearingLimit = elapsed >= 270 // 4:30 — warn near 5-min cap

            Text(String(format: "%d:%02d", minutes, seconds))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(nearingLimit ? .orange : .secondary)
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
    private var cancellable: AnyCancellable?

    func show() {
        if let window = window, window.isVisible {
            repositionWindow(window)
            return
        }

        let overlayView = TranscriptionOverlayView()
        let hostingView = NSHostingView(rootView: overlayView)

        // Ensure no opaque background behind the rounded pill
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        let initialSize = hostingView.fittingSize

        let window = DraggableWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
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

        // Auto-resize window when content changes
        cancellable = AppState.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizeWindowToFit()
            }
    }

    func dismiss() {
        cancellable?.cancel()
        cancellable = nil
        window?.orderOut(nil)
        window = nil
    }

    // MARK: - Sizing

    private func resizeWindowToFit() {
        guard let window = window,
              let hostingView = window.contentView as? NSHostingView<TranscriptionOverlayView> else { return }
        let newSize = hostingView.fittingSize
        guard newSize.width > 0, newSize.height > 0 else { return }
        var frame = window.frame
        let heightDelta = newSize.height - frame.height
        frame.size = newSize
        frame.origin.y -= heightDelta
        window.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Positioning

    private func repositionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size

        // Top of the bottom quarter of screen, horizontally centered
        let origin = NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.minY + visibleFrame.height * 0.25
        )

        window.setFrameOrigin(origin)
    }
}
