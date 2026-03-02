import SwiftUI

struct MenuBarView: View {
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var modeManager = AppState.shared.modeManager

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().padding(.horizontal, 16)
            modeSelectorSection
            Divider().padding(.horizontal, 16)
            recentTranscriptionsSection
            Divider().padding(.horizontal, 16)
            footerSection
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            statusDot
            Text("SttTool")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            modelBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .shadow(color: statusColor.opacity(0.5), radius: 3, x: 0, y: 0)
    }

    private var statusColor: Color {
        switch appState.transcriptionState {
        case .idle:
            return appState.isModelLoaded ? .green : .yellow
        case .loading:
            return .yellow
        case .recording:
            return .red
        case .transcribing, .processing:
            return .blue
        case .error:
            return .orange
        }
    }

    private var modelBadge: some View {
        Text(appState.modelDisplayName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )
    }

    // MARK: - Mode Selector

    private var modeSelectorSection: some View {
        VStack(spacing: 10) {
            modesPicker
            superModeToggle
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var modesPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(modeManager.allModes) { mode in
                    modePill(mode)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func modePill(_ mode: TranscriptionMode) -> some View {
        let isSelected = appState.selectedMode == mode.id
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.selectedMode = mode.id
            }
        } label: {
            Text(mode.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }

    private var superModeToggle: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(appState.superModeEnabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))

            Text("Super Mode")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Toggle("", isOn: $appState.superModeEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }

    // MARK: - Recent Transcriptions

    private var recentTranscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if appState.recentTranscriptions.isEmpty {
                emptyTranscriptionsView
            } else {
                transcriptionsList
            }
        }
        .frame(maxHeight: 200)
        .padding(.vertical, 10)
    }

    private var emptyTranscriptionsView: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.system(size: 20))
                .foregroundStyle(.quaternary)
            Text("No transcriptions yet")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text(statusHint)
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var statusHint: String {
        switch appState.transcriptionState {
        case .idle where appState.isModelLoaded:
            return "Hold your hotkey to start"
        case .loading:
            return "Model is loading..."
        case .recording:
            return "Listening..."
        case .error(let msg):
            return msg
        default:
            return "Waiting for model..."
        }
    }

    private var transcriptionsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(Array(appState.recentTranscriptions.enumerated()), id: \.offset) { index, text in
                    TranscriptionRow(text: text, index: index)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button {
                onOpenSettings()
            } label: {
                Label("Settings", systemImage: "gear")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            Spacer()

            Text(appState.transcriptionState.description)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                onQuit()
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Transcription Row

private struct TranscriptionRow: View {
    let text: String
    let index: Int

    @State private var isHovered = false
    @State private var showCopied = false

    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showCopied {
                    Text("Copied")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if isHovered {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            showCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.15)) {
                showCopied = false
            }
        }
    }
}
