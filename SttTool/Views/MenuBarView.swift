import SwiftUI

struct MenuBarView: View {
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var modeManager = AppState.shared.modeManager
    @State private var ringPulsing = false

    var body: some View {
        VStack(spacing: 10) {
            headerSection

            if appState.canUndo {
                undoBanner
            }

            if appState.transcriptionState == .loading {
                statusSection
                    .transition(.opacity)
            } else if case .error = appState.transcriptionState {
                statusSection
                    .transition(.opacity)
            }

            modeSection
            transcriptionsSection

            footerSection
        }
        .padding(12)
        .frame(width: 340)
        .background(.ultraThinMaterial)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appState.transcriptionState)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appState.canUndo)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(statusColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 28, height: 28)
                    .shadow(color: statusColor.opacity(0.5), radius: 6)
                    .scaleEffect(ringPulsing ? 1.15 : 1.0)
                    .opacity(ringPulsing ? 0.6 : 1.0)

                // Inner filled dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            .onChange(of: appState.transcriptionState) { _, newState in
                if newState == .recording {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        ringPulsing = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        ringPulsing = false
                    }
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Vox")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(appState.transcriptionState.description)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(appState.modelDisplayName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
        }
        .glassCard()
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

    // MARK: - Undo Banner

    private var undoBanner: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.orange)
                .frame(width: 2, height: 20)

            Text("Text injected")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                appState.coordinator.undoLastInjection()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10))
                    Text("Undo")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
        .glassCard()
        .transition(.move(edge: .top).combined(with: .opacity))
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
                .glassCard()
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
                .glassCard()
            }
        }
    }

    // MARK: - Mode Selector

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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

                Text("Super Mode")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("", isOn: $appState.superModeEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .tint(.accentColor)
            }
        }
        .glassCard()
    }

    private func modePill(_ mode: TranscriptionMode) -> some View {
        let isSelected = appState.selectedMode == mode.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
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
                        .fill(isSelected ? Color.accentColor : Color.white.opacity(0.06))
                )
                .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 6, x: 0, y: 0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Transcriptions

    private var transcriptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            if appState.recentTranscriptions.isEmpty {
                emptyState
            } else {
                transcriptionsList
            }
        }
        .frame(maxHeight: 200)
        .glassCard()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No transcriptions yet")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
            if appState.isModelLoaded {
                Text("Hold your hotkey to start")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var transcriptionsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(Array(appState.recentTranscriptions.enumerated()), id: \.element) { _, text in
                    TranscriptionRow(text: text)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 12) {
            Spacer()

            footerButton(icon: "gear", tooltip: "Settings") {
                onOpenSettings()
            }

            footerButton(icon: "power", tooltip: "Quit") {
                onQuit()
            }
        }
        .padding(.horizontal, 4)
    }

    private func footerButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        FooterButtonView(icon: icon, tooltip: tooltip, action: action)
    }
}

// MARK: - Footer Button with Hover Glow

private struct FooterButtonView: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(isHovered ? 0.25 : 0.1), lineWidth: 0.5)
                )
                .shadow(color: .white.opacity(isHovered ? 0.1 : 0), radius: 4, x: 0, y: 0)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }
}

// MARK: - Glass Card Modifier

private struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

extension View {
    fileprivate func glassCard() -> some View {
        modifier(GlassCard())
    }
}

// MARK: - Transcription Row

private struct TranscriptionRow: View {
    let text: String

    @State private var isHovered = false
    @State private var showCopied = false
    @State private var copyTask: Task<Void, Never>?

    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(isHovered ? AnyShapeStyle(Color.accentColor.opacity(0.6)) : AnyShapeStyle(.quaternary))
                    .frame(width: 2, height: 16)
                    .padding(.top, 2)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)

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
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
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
        copyTask?.cancel()
        copyTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                showCopied = false
            }
        }
    }
}
