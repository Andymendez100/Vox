import SwiftUI
import CoreGraphics

// MARK: - Main Settings View

struct SettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ModelsTab()
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }

            ModesTab()
                .tabItem {
                    Label("Modes", systemImage: "text.bubble")
                }

            APIKeysTab()
                .tabItem {
                    Label("API Keys", systemImage: "key")
                }

            VocabularyTab()
                .tabItem {
                    Label("Vocabulary", systemImage: "character.book.closed")
                }

            LanguageTab()
                .tabItem {
                    Label("Language", systemImage: "globe")
                }
        }
        .frame(width: 520, height: 440)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var permissions = AppState.shared.permissionsService
    @ObservedObject private var deviceManager = AppState.shared.audioDeviceManager
    @State private var isRecordingHotkey = false
    @State private var eventMonitor: Any?

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $appState.activationMode) {
                    Text("Push to Talk").tag("pushToTalk")
                    Text("Toggle").tag("toggle")
                }
                .pickerStyle(.segmented)

                LabeledContent("Hotkey") {
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
            } header: {
                Text("Activation")
            }

            Section("Audio Input") {
                Picker("Microphone", selection: $appState.selectedInputDeviceUID) {
                    Text("System Default").tag(AudioDeviceManager.systemDefaultUID)
                    ForEach(deviceManager.inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $appState.launchAtLogin)
            }

            Section("Permissions") {
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
        }
        .formStyle(.grouped)
        .onAppear {
            permissions.checkPermissions()
        }
        .onDisappear {
            // Clean up any active hotkey recording monitor
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
                    .font(.system(.body, design: .rounded))
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

// MARK: - Models Tab

struct ModelsTab: View {
    @ObservedObject private var appState = AppState.shared
    private let models = TranscriptionService.ModelInfo.available

    private let modelDescriptions: [String: String] = [
        "Tiny": "Fastest, lowest memory. Best for quick notes.",
        "Base": "Good balance of speed and accuracy. Recommended.",
        "Small": "Higher accuracy, moderate resource usage.",
        "Large V3": "Maximum accuracy, requires more memory and time.",
    ]

    var body: some View {
        Form {
            Section("Whisper Model") {
                Picker("Model", selection: $appState.selectedModel) {
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

                if appState.transcriptionState == .loading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading model...")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                if let desc = selectedModelDescription {
                    Text(desc)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var selectedModelDescription: String? {
        guard let model = models.first(where: { $0.id == appState.selectedModel }) else {
            return nil
        }
        return modelDescriptions[model.displayName]
    }
}

// MARK: - Modes Tab

struct ModesTab: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var modeManager = AppState.shared.modeManager

    @State private var newModeName = ""
    @State private var newModePrompt = ""
    @State private var showingAddMode = false

    var body: some View {
        Form {
            Section("Active Mode") {
                Picker("Mode", selection: $appState.selectedMode) {
                    ForEach(modeManager.allModes) { mode in
                        Text(mode.name).tag(mode.id)
                    }
                }
            }

            Section("Built-in Modes") {
                ForEach(TranscriptionMode.allBuiltIn) { mode in
                    BuiltInModeRow(mode: mode)
                }
            }

            Section("Custom Modes") {
                ForEach(modeManager.customModes) { mode in
                    HStack {
                        Text(mode.name)
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
                }

                if modeManager.customModes.isEmpty {
                    Text("No custom modes yet")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                if showingAddMode {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Mode name", text: $newModeName)
                        TextField("System prompt", text: $newModePrompt, axis: .vertical)
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
                    Button {
                        showingAddMode = true
                    } label: {
                        Label("Add Custom Mode", systemImage: "plus")
                    }
                }
            }

            Section {
                Toggle("Super Mode", isOn: $appState.superModeEnabled)
                Text("Automatically selects the best mode based on the active application.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Super Mode")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - API Keys Tab

struct APIKeysTab: View {
    @ObservedObject private var modeManager = AppState.shared.modeManager

    @State private var openaiKey = ""
    @State private var anthropicKey = ""
    @State private var showOpenAIKey = false
    @State private var showAnthropicKey = false
    @State private var savedIndicator: String?

    var body: some View {
        Form {
            Section("Provider") {
                Picker("LLM Provider", selection: $modeManager.selectedProvider) {
                    Text("OpenAI").tag("openai")
                    Text("Anthropic").tag("anthropic")
                }
                .pickerStyle(.segmented)
            }

            Section("OpenAI") {
                apiKeyField(
                    placeholder: "sk-...",
                    key: $openaiKey,
                    showKey: $showOpenAIKey
                )
                TextField("Model name", text: $modeManager.openaiModel)
                    .textFieldStyle(.roundedBorder)
                saveButton(provider: "OpenAI") {
                    KeychainService.save(key: "openai_api_key", value: openaiKey)
                }
                .disabled(openaiKey.isEmpty)
            }

            Section("Anthropic") {
                apiKeyField(
                    placeholder: "sk-ant-...",
                    key: $anthropicKey,
                    showKey: $showAnthropicKey
                )
                TextField("Model name", text: $modeManager.anthropicModel)
                    .textFieldStyle(.roundedBorder)
                saveButton(provider: "Anthropic") {
                    KeychainService.save(key: "anthropic_api_key", value: anthropicKey)
                }
                .disabled(anthropicKey.isEmpty)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            openaiKey = KeychainService.get(key: "openai_api_key") ?? ""
            anthropicKey = KeychainService.get(key: "anthropic_api_key") ?? ""
        }
    }

    private func apiKeyField(placeholder: String, key: Binding<String>, showKey: Binding<Bool>) -> some View {
        HStack {
            Group {
                if showKey.wrappedValue {
                    TextField(placeholder, text: key)
                } else {
                    SecureField(placeholder, text: key)
                }
            }
            .textFieldStyle(.roundedBorder)

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

// MARK: - Vocabulary Tab

struct VocabularyTab: View {
    @ObservedObject private var appState = AppState.shared
    @State private var newWord = ""
    @State private var words: [String] = []

    var body: some View {
        Form {
            Section {
                Text("Add specialized words, names, or technical terms to improve transcription accuracy.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Section("Words") {
                ForEach(words, id: \.self) { word in
                    HStack {
                        Text(word)
                            .font(.system(.body, design: .rounded))
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
                }

                if words.isEmpty {
                    Text("No custom vocabulary words")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

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
        }
        .formStyle(.grouped)
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

// MARK: - Language Tab

struct LanguageTab: View {
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
        Form {
            Section("Detection") {
                Toggle("Auto-detect language", isOn: $appState.autoDetectLanguage)
                Text("Whisper will identify the spoken language automatically. May slightly increase processing time.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Section("Language") {
                Picker("Language", selection: $appState.language) {
                    ForEach(languages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .disabled(appState.autoDetectLanguage)

                if appState.autoDetectLanguage {
                    Text("Language selection is disabled while auto-detect is on.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Built-in Mode Row

private struct BuiltInModeRow: View {
    let mode: TranscriptionMode

    var body: some View {
        HStack {
            Text(mode.name)
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
