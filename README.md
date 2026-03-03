# Vox

A native macOS menubar app for global push-to-talk dictation, powered by on-device AI transcription. Hold a hotkey, speak, and your words appear in any text field — no cloud required.

Built as a privacy-first alternative to SuperWhisper, Vox runs Whisper models locally via Apple's CoreML and optionally refines output through LLM-powered text modes.

## How It Works

```
Hold Hotkey → Speak → Release → Text Appears
     ↓           ↓         ↓           ↓
  Global     Audio via   WhisperKit   Paste into
  CGEvent    AVAudio     transcribes  active app
  tap        Engine      on-device    via Cmd+V
```

1. **Hold** the global hotkey (default: Right Command) from any app
2. **Speak** — a floating overlay shows live transcription and a waveform visualizer
3. **Release** — Whisper completes transcription, optional LLM cleanup runs, text is injected into the focused text field

## Features

**Core**
- Global push-to-talk hotkey that works system-wide, even when Vox is backgrounded
- On-device transcription via [WhisperKit](https://github.com/argmaxinc/WhisperKit) — no audio leaves your machine
- 100+ languages with auto-detection
- Multiple Whisper model tiers: Tiny (39MB) / Base (142MB) / Small (466MB) / Large V3 (1.5GB)

**Smart Modes**
- **Voice** — raw transcription
- **Message** — casual, chat-ready
- **Email** — formal with structure
- **Code** — preserves technical terms
- **Custom** — define your own prompt and LLM behavior
- **Super Mode** — auto-detects the active app and applies the right mode (Slack → Message, Mail → Email, Xcode → Code)

**UX Polish**
- Live waveform visualizer during recording
- Noise gate that skips silence and background noise
- Sound feedback on start, stop, complete, and error
- Undo last injection within 30 seconds
- Copy-only mode for transcribing without pasting
- Recording timer display
- Recent transcriptions in the menubar popover

## Architecture

```
SttTool/
├── App/
│   ├── SttToolApp.swift                # Entry point
│   ├── AppState.swift                  # Central @MainActor state
│   └── AppDelegate.swift               # Menubar lifecycle, hotkey wiring
├── Services/
│   ├── AudioCaptureService.swift       # AVAudioEngine, 16kHz PCM capture
│   ├── TranscriptionService.swift      # WhisperKit model management
│   ├── TranscriptionCoordinator.swift  # Orchestrates record → transcribe → inject
│   ├── HotkeyManager.swift            # CGEvent tap on background thread
│   ├── TextInjectionService.swift      # Clipboard + simulated Cmd+V
│   ├── AudioDeviceManager.swift        # Input device selection, Bluetooth handling
│   ├── AudioMuteService.swift          # Output muting during recording
│   ├── PermissionsService.swift        # Mic + Accessibility permission checks
│   ├── SoundFeedbackService.swift      # System sound feedback
│   └── KeychainService.swift           # Secure API key storage
├── LLM/
│   ├── LLMService.swift                # Provider protocol
│   ├── OpenAIProvider.swift            # GPT-4o-mini
│   ├── AnthropicProvider.swift         # Claude Haiku
│   └── ModeManager.swift              # Mode definitions, Super Mode logic
├── Models/
│   ├── TranscriptionMode.swift         # Built-in + custom modes
│   └── AudioData.swift                 # Audio buffer type
└── Views/
    ├── MenuBarView.swift               # Popover UI
    ├── SettingsView.swift              # Tabbed settings (6 tabs)
    └── TranscriptionOverlay.swift      # Floating overlay near cursor
```

**Key design decisions:**
- **Service-oriented** — each concern (audio, transcription, hotkey, injection) is an isolated service
- **Coordinator pattern** — `TranscriptionCoordinator` orchestrates the full record → transcribe → inject pipeline
- **Swift Concurrency** — services use actors for thread safety; the hotkey event tap runs on a dedicated background thread to prevent system-wide input lag
- **No external UI dependencies** — pure SwiftUI

## Technical Highlights

**Performance**
- Audio engine pre-warmed on launch to eliminate first-recording latency
- App Nap disabled for sub-100ms hotkey response after idle
- Memory-capped audio buffer (max 5 minutes / ~4.8MB)
- Hotkey debouncing (300ms) to prevent rapid-fire duplicates

**Robustness**
- Bluetooth reconnect handling — detects when a Bluetooth device switches the system input to HFP phone profile after sleep/wake and restores the built-in mic
- Graceful recovery from audio device changes, invalid formats, and HAL failures
- Event tap failure detection with automatic retry
- Clipboard contents preserved and restored after text injection

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI |
| Audio capture | AVAudioEngine (16kHz mono PCM) |
| Transcription | WhisperKit + CoreML |
| Global hotkey | CGEvent tap |
| Text injection | NSPasteboard + CGEvent |
| LLM integration | OpenAI / Anthropic REST APIs |
| Secrets | macOS Keychain |
| Audio devices | CoreAudio HAL |

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (recommended for Whisper performance) or Intel Mac
- Microphone access permission
- Accessibility permission (for text injection)

## Build

```bash
# Clone and build
git clone https://github.com/yourusername/Vox.git
cd Vox
swift build -c release

# Or build the .app bundle
./scripts/build-app.sh
```

## License

Copyright 2026. All rights reserved.
