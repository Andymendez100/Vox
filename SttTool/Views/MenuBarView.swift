import SwiftUI

struct MenuBarView: View {
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var modeManager = AppState.shared.modeManager

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            divider
            statusSection
            divider
            modeSection
            divider
            transcriptionsSection
            divider
            footerSection
        }
        .frame(width: 320)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Vox")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(appState.transcriptionState.description)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if appState.canUndo {
                Button {
                    appState.coordinator.undoLastInjection()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                        Text("Undo")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }

            Text(appState.modelDisplayName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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

    // MARK: - Status

    private var statusSection: some View {
        Group {
            if appState.transcriptionState == .loading {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading model...")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if appState.modelLoadProgress > 0 {
                            Text("\(Int(appState.modelLoadProgress * 100))%")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if appState.modelLoadProgress > 0 {
                        ProgressView(value: appState.modelLoadProgress)
                            .tint(.accentColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else if case .error(let msg) = appState.transcriptionState {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text(msg)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Mode Selector

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MODE")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .tracking(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(modeManager.allModes) { mode in
                        modePill(mode)
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(appState.superModeEnabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))

                Text("Auto-select mode")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("", isOn: $appState.superModeEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func modePill(_ mode: TranscriptionMode) -> some View {
        let isSelected = appState.selectedMode == mode.id
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.selectedMode = mode.id
            }
        } label: {
            Text(mode.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Transcriptions

    private var transcriptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
                .padding(.horizontal, 16)

            if appState.recentTranscriptions.isEmpty {
                emptyState
            } else {
                transcriptionsList
            }
        }
        .frame(maxHeight: 200)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.quaternary)
            Text("No transcriptions yet")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.tertiary)
            if appState.isModelLoaded {
                Text("Hold your hotkey to start")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var transcriptionsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(Array(appState.recentTranscriptions.enumerated()), id: \.offset) { _, text in
                    TranscriptionRow(text: text)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 0) {
            footerButton(icon: "gear", label: "Settings") {
                onOpenSettings()
            }

            Spacer()

            footerButton(icon: "power", label: "Quit") {
                onQuit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func footerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.001))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }
}

// MARK: - Transcription Row

private struct TranscriptionRow: View {
    let text: String

    @State private var isHovered = false
    @State private var showCopied = false

    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(text)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showCopied {
                    Text("Copied")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
