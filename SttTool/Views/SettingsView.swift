import SwiftUI
import CoreGraphics

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case models = "Models"
    case modes = "Modes"
    case apiKeys = "API Keys"
    case vocabulary = "Vocabulary"
    case language = "Language"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .models: return "cpu"
        case .modes: return "text.bubble"
        case .apiKeys: return "key"
        case .vocabulary: return "character.book.closed"
        case .language: return "globe"
        }
    }
}

// MARK: - Settings Glass Card Modifier

private struct SettingsGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
    fileprivate func settingsGlassCard() -> some View {
        modifier(SettingsGlassCard())
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Settings Row

private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, design: .rounded))
            Spacer()
            content()
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarItem(tab)
                }
                Spacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .frame(width: 140)

            Divider()
                .opacity(0.3)

            // Content area
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .general:
                        GeneralTabContent()
                    case .models:
                        ModelsTabContent()
                    case .modes:
                        ModesTabContent()
                    case .apiKeys:
                        APIKeysTabContent()
                    case .vocabulary:
                        VocabularyTabContent()
                    case .language:
                        LanguageTabContent()
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 520)
        .background(.ultraThinMaterial)
    }

    // MARK: - Sidebar Item

    private func sidebarItem(_ tab: SettingsTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .medium))
                Text(tab.rawValue)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Group {
                    if selectedTab == tab {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                            )
                            .shadow(color: Color.accentColor.opacity(0.2), radius: 6, x: 0, y: 0)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - General Tab Content

private struct GeneralTabContent: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var permissions = AppState.shared.permissionsService
    @ObservedObject private var deviceManager = AppState.shared.audioDeviceManager
    @State private var isRecordingHotkey = false
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Activation
            SectionHeader(title: "ACTIVATION")
            VStack(spacing: 12) {
                SettingsRow(label: "Mode") {
                    Picker("", selection: $appState.activationMode) {
                        Text("Push to Talk").tag("pushToTalk")
                        Text("Toggle").tag("toggle")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }

                SettingsRow(label: "Hotkey") {
                    Button {
                        startRecordingHotkey()
                    } label: {
                        HStack(spacing: 6) {
                            if isRecordingHotkey {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 6, height: 6)
                                Text("Press new hotkey...")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.orange)
                            } else {
                                Text(hotkeyDisplayString)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isRecordingHotkey ? Color.orange.opacity(0.1) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isRecordingHotkey ? Color.orange.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isRecordingHotkey)
                }
            }
            .settingsGlassCard()

            // Audio Input
            SectionHeader(title: "AUDIO INPUT")
            VStack(spacing: 12) {
                SettingsRow(label: "Microphone") {
                    Picker("", selection: $appState.selectedInputDeviceUID) {
                        Text("System Default").tag(AudioDeviceManager.systemDefaultUID)
                        ForEach(deviceManager.inputDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                    .onChange(of: appState.selectedInputDeviceUID) { _, newUID in
                        deviceManager.preferredInputUID = newUID
                        deviceManager.enforcePreferredInput()
                    }
                }

                SettingsRow(label: "Noise reduction") {
                    Toggle("", isOn: $appState.noiseReductionEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Text("Applies a noise gate to suppress low-level background noise during recording.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .settingsGlassCard()

            // Behavior
            SectionHeader(title: "BEHAVIOR")
            VStack(spacing: 12) {
                SettingsRow(label: "Sound feedback") {
                    Toggle("", isOn: $appState.soundFeedbackEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRow(label: "Copy to clipboard only (don't auto-paste)") {
                    Toggle("", isOn: $appState.copyOnlyMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .settingsGlassCard()

            // Startup
            SectionHeader(title: "STARTUP")
            VStack(spacing: 12) {
                SettingsRow(label: "Launch at Login") {
                    Toggle("", isOn: $appState.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .settingsGlassCard()

            // Permissions
            SectionHeader(title: "PERMISSIONS")
            VStack(spacing: 12) {
                permissionRow(
                    name: "Microphone",
                    granted: permissions.microphoneGranted,
                    onGrant: { permissions.checkMicrophone() },
                    onOpen: { permissions.openMicrophoneSettings() }
                )
                permissionRow(
                    name: "Accessibility",
                    granted: permissions.accessibilityGranted,
                    onGrant: { permissions.requestAccessibility() },
                    onOpen: { permissions.openAccessibilitySettings() }
                )
            }
            .settingsGlassCard()
        }
        .onAppear {
            permissions.checkPermissions()
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
            isRecordingHotkey = false
        }
    }

    private func permissionRow(name: String, granted: Bool, onGrant: @escaping () -> Void, onOpen: @escaping () -> Void) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(granted ? .green : .red)
                    .font(.system(size: 14))
                Text(name)
                    .font(.system(size: 13, design: .rounded))
            }
            Spacer()
            if granted {
                Text("Granted")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.green.opacity(0.8))
            } else {
                Button("Grant") { onGrant() }
                    .controlSize(.small)
                Button("Settings") { onOpen() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Hotkey Display

    private var hotkeyDisplayString: String {
        if appState.hotkeyModifierOnly {
            return modifierKeyName(UInt16(appState.hotkeyKeyCode))
        }

        var parts: [String] = []
        let flags = CGEventFlags(rawValue: UInt64(appState.hotkeyModifiers))

        if flags.contains(.maskControl) { parts.append("\u{2303}") }
        if flags.contains(.maskAlternate) { parts.append("\u{2325}") }
        if flags.contains(.maskShift) { parts.append("\u{21E7}") }
        if flags.contains(.maskCommand) { parts.append("\u{2318}") }

        parts.append(keyCodeName(UInt16(appState.hotkeyKeyCode)))
        return parts.joined()
    }

    private func modifierKeyName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 54: return "Right \u{2318}"
        case 55: return "Left \u{2318}"
        case 56: return "Left \u{21E7}"
        case 60: return "Right \u{21E7}"
        case 58: return "Left \u{2325}"
        case 61: return "Right \u{2325}"
        case 59: return "Left \u{2303}"
        case 62: return "Right \u{2303}"
        default: return "Key \(keyCode)"
        }
    }

    private func keyCodeName(_ keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 40: "K", 46: "M", 48: "Tab",
            49: "Space", 51: "Delete", 53: "Esc",
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            126: "\u{2191}", 125: "\u{2193}", 123: "\u{2190}", 124: "\u{2192}",
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }

    // MARK: - Hotkey Recording

    private func startRecordingHotkey() {
        guard !isRecordingHotkey else { return }
        isRecordingHotkey = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 60, 58, 61, 59, 62]
                guard modifierKeyCodes.contains(event.keyCode) else { return event }
                let hasModifier: Bool
                switch event.keyCode {
                case 54, 55: hasModifier = event.modifierFlags.contains(.command)
                case 56, 60: hasModifier = event.modifierFlags.contains(.shift)
                case 58, 61: hasModifier = event.modifierFlags.contains(.option)
                case 59, 62: hasModifier = event.modifierFlags.contains(.control)
                default: hasModifier = false
                }
                guard hasModifier else { return event }
                self.applyHotkey(
                    keyCode: event.keyCode,
                    modifiers: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)),
                    modifierOnly: true
                )
                return nil
            } else {
                let cgModifiers = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
                let hasModifiers = !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
                self.applyHotkey(
                    keyCode: event.keyCode,
                    modifiers: hasModifiers ? cgModifiers : [],
                    modifierOnly: false
                )
                return nil
            }
        }
    }

    private func applyHotkey(keyCode: UInt16, modifiers: CGEventFlags, modifierOnly: Bool) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecordingHotkey = false
        HotkeyManager.shared.setHotkey(keyCode: keyCode, modifiers: modifiers, modifierOnly: modifierOnly)
        HotkeyManager.shared.stop()
        HotkeyManager.shared.start()
        appState.hotkeyKeyCode = Int(keyCode)
        appState.hotkeyModifiers = Int(modifiers.rawValue)
        appState.hotkeyModifierOnly = modifierOnly
    }
}

// MARK: - Models Tab Content

private struct ModelsTabContent: View {
    @ObservedObject private var appState = AppState.shared
    private let models = TranscriptionService.ModelInfo.available

    private let modelDescriptions: [String: String] = [
        "Tiny": "Fastest, lowest memory. Best for quick notes.",
        "Base": "Good balance of speed and accuracy. Recommended.",
        "Small": "Higher accuracy, moderate resource usage.",
        "Large V3": "Maximum accuracy, requires more memory and time.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "WHISPER MODEL")
            VStack(spacing: 12) {
                SettingsRow(label: "Model") {
                    Picker("", selection: $appState.selectedModel) {
                        ForEach(models, id: \.id) { model in
                            HStack {
                                Text(model.displayName)
                                Spacer()
                                Text(model.sizeDescription)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                }

                if appState.transcriptionState == .loading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading model...")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                if let desc = selectedModelDescription {
                    Text(desc)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .settingsGlassCard()
        }
    }

    private var selectedModelDescription: String? {
        guard let model = models.first(where: { $0.id == appState.selectedModel }) else {
            return nil
        }
        return modelDescriptions[model.displayName]
    }
}

// MARK: - Modes Tab Content

private struct ModesTabContent: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var modeManager = AppState.shared.modeManager

    @State private var newModeName = ""
    @State private var newModePrompt = ""
    @State private var showingAddMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Active Mode
            SectionHeader(title: "ACTIVE MODE")
            VStack(spacing: 12) {
                SettingsRow(label: "Mode") {
                    Picker("", selection: $appState.selectedMode) {
                        ForEach(modeManager.allModes) { mode in
                            Text(mode.name).tag(mode.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
            .settingsGlassCard()

            // Built-in Modes
            SectionHeader(title: "BUILT-IN MODES")
            VStack(spacing: 8) {
                ForEach(TranscriptionMode.allBuiltIn) { mode in
                    BuiltInModeRow(mode: mode)
                    if mode.id != TranscriptionMode.allBuiltIn.last?.id {
                        Divider().opacity(0.3)
                    }
                }
            }
            .settingsGlassCard()

            // Custom Modes
            SectionHeader(title: "CUSTOM MODES")
            VStack(spacing: 8) {
                ForEach(modeManager.customModes) { mode in
                    HStack {
                        Text(mode.name)
                            .font(.system(size: 13, design: .rounded))
                        Spacer()
                        Button(role: .destructive) {
                            modeManager.removeCustomMode(id: mode.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    if mode.id != modeManager.customModes.last?.id {
                        Divider().opacity(0.3)
                    }
                }

                if modeManager.customModes.isEmpty {
                    Text("No custom modes yet")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                if showingAddMode {
                    Divider().opacity(0.3)
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Mode name", text: $newModeName)
                            .textFieldStyle(.roundedBorder)
                        TextField("System prompt", text: $newModePrompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...5)
                        HStack {
                            Button("Cancel") {
                                newModeName = ""
                                newModePrompt = ""
                                showingAddMode = false
                            }
                            Button("Add") {
                                guard !newModeName.isEmpty, !newModePrompt.isEmpty else { return }
                                modeManager.addCustomMode(name: newModeName, systemPrompt: newModePrompt)
                                newModeName = ""
                                newModePrompt = ""
                                showingAddMode = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newModeName.isEmpty || newModePrompt.isEmpty)
                        }
                    }
                } else {
                    Divider().opacity(0.3)
                    Button {
                        showingAddMode = true
                    } label: {
                        Label("Add Custom Mode", systemImage: "plus")
                            .font(.system(size: 13, design: .rounded))
                    }
                }
            }
            .settingsGlassCard()

            // Super Mode
            SectionHeader(title: "SUPER MODE")
            VStack(spacing: 12) {
                SettingsRow(label: "Super Mode") {
                    Toggle("", isOn: $appState.superModeEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Text("Automatically selects the best mode based on the active application.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .settingsGlassCard()
        }
    }
}

// MARK: - API Keys Tab Content

private struct APIKeysTabContent: View {
    @ObservedObject private var modeManager = AppState.shared.modeManager

    @State private var openaiKey = ""
    @State private var anthropicKey = ""
    @State private var geminiKey = ""
    @State private var showOpenAIKey = false
    @State private var showAnthropicKey = false
    @State private var showGeminiKey = false
    @State private var savedIndicator: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Provider
            SectionHeader(title: "PROVIDER")
            VStack(spacing: 12) {
                SettingsRow(label: "LLM Provider") {
                    Picker("", selection: $modeManager.selectedProvider) {
                        Text("OpenAI").tag("openai")
                        Text("Anthropic").tag("anthropic")
                        Text("Gemini").tag("gemini")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 280)
                }
            }
            .settingsGlassCard()

            // OpenAI
            SectionHeader(title: "OPENAI")
            VStack(spacing: 12) {
                apiKeyField(
                    placeholder: "sk-...",
                    key: $openaiKey,
                    showKey: $showOpenAIKey
                )
                SettingsRow(label: "Model") {
                    Picker("", selection: $modeManager.openaiModel) {
                        Text("gpt-5-nano").tag("gpt-5-nano")
                        Text("gpt-5-mini").tag("gpt-5-mini")
                        Text("gpt-5").tag("gpt-5")
                        Text("gpt-5.2").tag("gpt-5.2")
                        Text("gpt-4.1").tag("gpt-4.1")
                        Text("gpt-4o-mini").tag("gpt-4o-mini")
                        Text("gpt-4o").tag("gpt-4o")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                }
                saveButton(provider: "OpenAI") {
                    KeychainService.save(key: "openai_api_key", value: openaiKey)
                }
                .disabled(openaiKey.isEmpty)
            }
            .settingsGlassCard()

            // Anthropic
            SectionHeader(title: "ANTHROPIC")
            VStack(spacing: 12) {
                apiKeyField(
                    placeholder: "sk-ant-...",
                    key: $anthropicKey,
                    showKey: $showAnthropicKey
                )
                SettingsRow(label: "Model") {
                    Picker("", selection: $modeManager.anthropicModel) {
                        Text("claude-haiku-4-5").tag("claude-haiku-4-5-20251001")
                        Text("claude-sonnet-4-6").tag("claude-sonnet-4-6")
                        Text("claude-opus-4-6").tag("claude-opus-4-6")
                        Text("claude-sonnet-4-5").tag("claude-sonnet-4-5-20250929")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                }
                saveButton(provider: "Anthropic") {
                    KeychainService.save(key: "anthropic_api_key", value: anthropicKey)
                }
                .disabled(anthropicKey.isEmpty)
            }
            .settingsGlassCard()

            // Gemini
            SectionHeader(title: "GEMINI")
            VStack(spacing: 12) {
                apiKeyField(
                    placeholder: "AI...",
                    key: $geminiKey,
                    showKey: $showGeminiKey
                )
                SettingsRow(label: "Model") {
                    Picker("", selection: $modeManager.geminiModel) {
                        Text("gemini-3.1-pro-preview").tag("gemini-3.1-pro-preview")
                        Text("gemini-3-flash-preview").tag("gemini-3-flash-preview")
                        Text("gemini-3.1-flash-lite-preview").tag("gemini-3.1-flash-lite-preview")
                        Text("gemini-2.5-flash").tag("gemini-2.5-flash")
                        Text("gemini-2.5-flash-lite").tag("gemini-2.5-flash-lite")
                        Text("gemini-2.5-pro").tag("gemini-2.5-pro")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                }
                saveButton(provider: "Gemini") {
                    KeychainService.save(key: "gemini_api_key", value: geminiKey)
                }
                .disabled(geminiKey.isEmpty)
            }
            .settingsGlassCard()
        }
        .onAppear {
            openaiKey = KeychainService.get(key: "openai_api_key") ?? ""
            anthropicKey = KeychainService.get(key: "anthropic_api_key") ?? ""
            geminiKey = KeychainService.get(key: "gemini_api_key") ?? ""
        }
    }

    private func apiKeyField(placeholder: String, key: Binding<String>, showKey: Binding<Bool>) -> some View {
        HStack {
            Text("API Key")
                .font(.system(size: 13, design: .rounded))
            Spacer()
            Group {
                if showKey.wrappedValue {
                    TextField(placeholder, text: key)
                } else {
                    SecureField(placeholder, text: key)
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)

            Button {
                showKey.wrappedValue.toggle()
            } label: {
                Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func saveButton(provider: String, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button("Save Key") {
                action()
                showSaved(provider)
            }

            if savedIndicator == provider {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Saved")
                        .font(.system(size: 12, design: .rounded))
                }
                .foregroundStyle(.green)
                .transition(.opacity)
            }
        }
    }

    private func showSaved(_ provider: String) {
        withAnimation { savedIndicator = provider }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { savedIndicator = nil }
        }
    }
}

// MARK: - Vocabulary Tab Content

private struct VocabularyTabContent: View {
    @ObservedObject private var appState = AppState.shared
    @State private var newWord = ""
    @State private var words: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "CUSTOM VOCABULARY")
            VStack(spacing: 12) {
                Text("Add specialized words, names, or technical terms to improve transcription accuracy.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .settingsGlassCard()

            SectionHeader(title: "WORDS")
            VStack(spacing: 8) {
                ForEach(words, id: \.self) { word in
                    HStack {
                        Text(word)
                            .font(.system(size: 13, design: .rounded))
                        Spacer()
                        Button(role: .destructive) {
                            removeWord(word)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    if word != words.last {
                        Divider().opacity(0.3)
                    }
                }

                if words.isEmpty {
                    Text("No custom vocabulary words")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                Divider().opacity(0.3)

                HStack {
                    TextField("Add word or phrase", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addWord() }
                    Button {
                        addWord()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .settingsGlassCard()
        }
        .onAppear { loadWords() }
    }

    private func loadWords() {
        if let data = appState.customVocabularyJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            words = decoded
        }
    }

    private func saveWords() {
        if let data = try? JSONEncoder().encode(words),
           let json = String(data: data, encoding: .utf8) {
            appState.customVocabularyJSON = json
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !words.contains(trimmed) else { return }
        words.append(trimmed)
        newWord = ""
        saveWords()
    }

    private func removeWord(_ word: String) {
        words.removeAll { $0 == word }
        saveWords()
    }
}

// MARK: - Language Tab Content

private struct LanguageTabContent: View {
    @ObservedObject private var appState = AppState.shared

    private let languages: [(code: String, name: String)] = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("ro", "Romanian"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("fi", "Finnish"),
        ("no", "Norwegian"),
        ("ru", "Russian"),
        ("uk", "Ukrainian"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("th", "Thai"),
        ("vi", "Vietnamese"),
        ("id", "Indonesian"),
        ("ms", "Malay"),
        ("tr", "Turkish"),
        ("cs", "Czech"),
        ("hu", "Hungarian"),
        ("el", "Greek"),
        ("he", "Hebrew"),
        ("ca", "Catalan"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Detection
            SectionHeader(title: "DETECTION")
            VStack(spacing: 12) {
                SettingsRow(label: "Auto-detect language") {
                    Toggle("", isOn: $appState.autoDetectLanguage)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Text("Whisper will identify the spoken language automatically. May slightly increase processing time.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .settingsGlassCard()

            // Language
            SectionHeader(title: "LANGUAGE")
            VStack(spacing: 12) {
                SettingsRow(label: "Language") {
                    Picker("", selection: $appState.language) {
                        ForEach(languages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                    .disabled(appState.autoDetectLanguage)
                }

                if appState.autoDetectLanguage {
                    Text("Language selection is disabled while auto-detect is on.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .settingsGlassCard()
        }
    }
}

// MARK: - Built-in Mode Row

private struct BuiltInModeRow: View {
    let mode: TranscriptionMode

    var body: some View {
        HStack {
            Text(mode.name)
                .font(.system(size: 13, design: .rounded))
                .fontWeight(.medium)
            Spacer()
            if mode.systemPrompt.isEmpty {
                Text("Direct")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            } else {
                Text("LLM")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.blue.opacity(0.1)))
            }
        }
    }
}
