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
        .frame(width: 550, height: 400)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var permissions = AppState.shared.permissionsService

    var body: some View {
        Form {
            Section("Activation") {
                Picker("Mode", selection: $appState.activationMode) {
                    Text("Push to Talk").tag("pushToTalk")
                    Text("Toggle").tag("toggle")
                }
                .pickerStyle(.segmented)

                LabeledContent("Hotkey") {
                    Text(hotkeyDisplayString)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $appState.launchAtLogin)
            }

            Section("Permissions") {
                HStack {
                    Label {
                        Text("Microphone")
                    } icon: {
                        Image(systemName: permissions.microphoneGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(permissions.microphoneGranted ? .green : .red)
                    }
                    Spacer()
                    if !permissions.microphoneGranted {
                        Button("Grant Access") {
                            permissions.checkMicrophone()
                        }
                        .controlSize(.small)
                        Button("Open Settings") {
                            permissions.openMicrophoneSettings()
                        }
                        .controlSize(.small)
                    } else {
                        Text("Granted")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Label {
                        Text("Accessibility")
                    } icon: {
                        Image(systemName: permissions.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(permissions.accessibilityGranted ? .green : .red)
                    }
                    Spacer()
                    if !permissions.accessibilityGranted {
                        Button("Grant Access") {
                            permissions.requestAccessibility()
                        }
                        .controlSize(.small)
                        Button("Open Settings") {
                            permissions.openAccessibilitySettings()
                        }
                        .controlSize(.small)
                    } else {
                        Text("Granted")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            permissions.checkPermissions()
        }
    }

    private var hotkeyDisplayString: String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: UInt64(appState.hotkeyModifiers))

        if flags.contains(.maskControl) { parts.append("\u{2303}") }
        if flags.contains(.maskAlternate) { parts.append("\u{2325}") }
        if flags.contains(.maskShift) { parts.append("\u{21E7}") }
        if flags.contains(.maskCommand) { parts.append("\u{2318}") }

        parts.append(keyCodeName(UInt16(appState.hotkeyKeyCode)))
        return parts.joined()
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
}

// MARK: - Models Tab

struct ModelsTab: View {
    @ObservedObject private var appState = AppState.shared
    private let models = TranscriptionService.ModelInfo.available

    private let tierInfo: [(tier: String, description: String, icon: String)] = [
        ("Nano", "Fastest, lowest memory usage. Best for quick notes.", "hare"),
        ("Fast", "Good balance of speed and accuracy. Recommended.", "bolt"),
        ("Pro", "Higher accuracy, moderate resource usage.", "star"),
        ("Ultra", "Maximum accuracy, requires more memory and time.", "sparkles"),
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
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Model Tiers") {
                ForEach(tierInfo, id: \.tier) { info in
                    HStack(spacing: 12) {
                        Image(systemName: info.icon)
                            .frame(width: 24)
                            .foregroundStyle(tierColor(info.tier))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.tier)
                                .fontWeight(.medium)
                            Text(info.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func tierColor(_ tier: String) -> Color {
        switch tier {
        case "Nano": return .green
        case "Fast": return .blue
        case "Pro": return .purple
        case "Ultra": return .orange
        default: return .primary
        }
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
                    HStack {
                        Text(mode.name)
                            .fontWeight(.medium)
                        Spacer()
                        if !mode.systemPrompt.isEmpty {
                            Text("LLM")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        } else {
                            Text("Direct")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.gray.opacity(0.15), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
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
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if modeManager.customModes.isEmpty {
                    Text("No custom modes yet")
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
                Text("Automatically selects the best mode based on the active application. For example, uses Message mode in Slack and Email mode in Mail.")
                    .font(.caption)
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
                HStack {
                    if showOpenAIKey {
                        TextField("sk-...", text: $openaiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-...", text: $openaiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showOpenAIKey.toggle()
                    } label: {
                        Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

                TextField("Model name", text: $modeManager.openaiModel)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Key") {
                        KeychainService.save(key: "openai_api_key", value: openaiKey)
                        showSaved("OpenAI")
                    }
                    .disabled(openaiKey.isEmpty)

                    if savedIndicator == "OpenAI" {
                        Text("Saved")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                }
            }

            Section("Anthropic") {
                HStack {
                    if showAnthropicKey {
                        TextField("sk-ant-...", text: $anthropicKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-ant-...", text: $anthropicKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showAnthropicKey.toggle()
                    } label: {
                        Image(systemName: showAnthropicKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

                TextField("Model name", text: $modeManager.anthropicModel)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Key") {
                        KeychainService.save(key: "anthropic_api_key", value: anthropicKey)
                        showSaved("Anthropic")
                    }
                    .disabled(anthropicKey.isEmpty)

                    if savedIndicator == "Anthropic" {
                        Text("Saved")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            openaiKey = KeychainService.get(key: "openai_api_key") ?? ""
            anthropicKey = KeychainService.get(key: "anthropic_api_key") ?? ""
        }
    }

    private func showSaved(_ provider: String) {
        withAnimation {
            savedIndicator = provider
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                savedIndicator = nil
            }
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
                Text("Add specialized words, names, or technical terms to improve transcription accuracy. These words are used as hints for the Whisper model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Words") {
                ForEach(words, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button(role: .destructive) {
                            removeWord(word)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if words.isEmpty {
                    Text("No custom vocabulary words")
                        .foregroundStyle(.tertiary)
                }

                HStack {
                    TextField("Add word or phrase", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addWord()
                        }
                    Button {
                        addWord()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadWords()
        }
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
                Text("When enabled, Whisper will attempt to identify the spoken language automatically. This may slightly increase processing time.")
                    .font(.caption)
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
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
