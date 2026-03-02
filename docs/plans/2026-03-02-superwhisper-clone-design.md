# SttTool — SuperWhisper Clone Design

## Overview

A native macOS menubar app that provides global push-to-talk speech-to-text dictation with local Whisper transcription and optional LLM-powered text cleanup. Functions as a full replacement for SuperWhisper.

## Scope

### In Scope
- Global hotkey push-to-talk dictation (default: Option+Space)
- Local Whisper transcription via WhisperKit (Nano/Fast/Pro/Ultra model tiers)
- Live streaming transcription overlay
- LLM-powered text cleanup modes (Voice, Message, Email, Formal, Code, Custom)
- Super Mode — auto-select mode based on active app
- Auto-paste transcribed text into the active application
- Custom vocabulary for names/terms
- 100+ language support
- Settings UI: API keys, model management, hotkey config, mode editor
- Menubar app with popover for quick controls

### Out of Scope
- File/video transcription
- Meeting notes/recording
- iOS/mobile support

## Architecture

### App Type
Native macOS menubar app. Swift + SwiftUI. Minimum deployment: macOS 14 (Sonoma).

### Core Flow
1. User holds global hotkey (Option+Space)
2. Audio captured from microphone via AVAudioEngine
3. Live streaming transcription shown in floating overlay
4. On hotkey release, final transcription completes
5. If an LLM mode is active, text is sent to the configured LLM for cleanup/formatting
6. Final text is injected into the active app via Accessibility API (clipboard + Cmd+V)

### Key Dependencies
- **WhisperKit** (argmaxinc/WhisperKit) — on-device Whisper inference via CoreML/Neural Engine
- **KeyboardShortcuts** (sindresorhus/KeyboardShortcuts) — global hotkey registration
- macOS Accessibility framework — text injection via CGEvent
- AVAudioEngine — microphone capture
- URLSession — LLM API calls (OpenAI, Anthropic)

## Project Structure

```
SttTool/
├── SttToolApp.swift                 # App entry point, menubar setup, app delegate
├── Audio/
│   ├── AudioRecorder.swift          # AVAudioEngine mic capture, buffering
│   └── TranscriptionEngine.swift    # WhisperKit wrapper, model management, streaming
├── Input/
│   ├── HotkeyManager.swift          # Global hotkey registration (push-to-talk + toggle)
│   └── TextInjector.swift           # Accessibility paste into active app
├── LLM/
│   ├── LLMService.swift             # Protocol for LLM providers
│   ├── OpenAIProvider.swift         # OpenAI API integration
│   ├── AnthropicProvider.swift      # Anthropic API integration
│   └── ModeManager.swift            # Predefined + custom modes, Super Mode logic
├── Models/
│   ├── AppSettings.swift            # User preferences, persisted via UserDefaults/@AppStorage
│   ├── TranscriptionMode.swift      # Mode definitions (system prompts, formatting)
│   └── CustomVocabulary.swift       # Custom terms/names list
├── Views/
│   ├── MenuBarView.swift            # Menubar popover: mode picker, recent transcriptions
│   ├── SettingsView.swift           # Settings window (tabbed)
│   ├── TranscriptionOverlay.swift   # Floating window showing live transcription near cursor
│   └── ModelManagerView.swift       # Download/manage Whisper model tiers
└── Resources/
    └── Assets.xcassets              # App icon, menubar icons
```

## Component Details

### 1. Audio Recording (AudioRecorder)
- Uses AVAudioEngine with the system default input device
- Captures audio as float32 PCM at 16kHz (Whisper's native sample rate)
- Buffers audio in memory while hotkey is held — no temp files
- Passes audio buffer to TranscriptionEngine on hotkey release
- Visual indicator: menubar icon changes color (red dot) while recording
- Handles audio session interruptions gracefully

### 2. Transcription Engine (TranscriptionEngine)
- Wraps WhisperKit for on-device inference
- **Model tiers** (stored in ~/Library/Application Support/SttTool/Models/):
  - Nano → whisper-tiny (~40MB) — fastest, good for short commands
  - Fast → whisper-base (~150MB) — balanced speed/accuracy
  - Pro → whisper-small (~500MB) — high accuracy
  - Ultra → whisper-large-v3 (~1.5GB) — best accuracy
- Downloads models on demand via WhisperKit's model hub
- Supports streaming transcription via AudioStreamTranscriber for live preview
- Language: auto-detect or user-selected, 100+ languages
- Custom vocabulary: injected via WhisperKit's initial prompt feature
- Uses Voice Activity Detection (VAD) to skip silence

### 3. Hotkey Manager (HotkeyManager)
- Uses KeyboardShortcuts package for system-wide hotkey capture
- Default shortcut: Option+Space
- **Push-to-talk** (default): hold to record, release to transcribe
- **Toggle mode** (configurable): press to start, press again to stop
- User-configurable shortcut via Settings
- Shows recording state in menubar icon

### 4. Text Injector (TextInjector)
- Injects transcribed text into the currently focused application
- Strategy:
  1. Save current clipboard contents
  2. Copy transcription to clipboard (NSPasteboard)
  3. Simulate Cmd+V via CGEvent to paste
  4. Restore previous clipboard contents after brief delay
- Requires Accessibility permission (AXIsProcessTrusted)
- Prompts user to grant Accessibility access on first launch
- Handles edge cases: no focused text field, clipboard restoration timing

### 5. LLM Modes (LLMService + ModeManager)

**Predefined modes** (each has a system prompt):
- **Voice** — raw transcription, no LLM processing
- **Message** — casual tone, cleaned up for chat apps
- **Email** — formal structure, greeting/closing
- **Formal** — professional, polished language
- **Code** — preserves technical terms, formats for developer context

**Custom modes**: user defines name + system prompt + formatting instructions

**Super Mode**: reads the frontmost app name (via NSWorkspace) and auto-selects:
- Slack/Discord/Messages → Message mode
- Mail/Outlook → Email mode
- Xcode/VS Code/Terminal → Code mode
- Default → user's preferred mode

**LLM Providers**:
- OpenAI (GPT-4o-mini default, configurable)
- Anthropic (Claude Haiku default, configurable)
- User provides their own API keys in Settings
- Streaming responses for fast output

### 6. Settings & UI

**Menubar icon**: SF Symbol microphone, color changes when recording (gray → red)

**Menubar popover** (click menubar icon):
- Current mode selector (dropdown)
- Recent transcriptions list (last 10)
- Quick toggle: Super Mode on/off
- Model selector
- "Settings..." button
- "Quit" button

**Settings window** (Cmd+, or via popover):
- **General tab**: hotkey config, activation mode (push-to-talk vs toggle), launch at login
- **Models tab**: download/delete Whisper models, select active model, show sizes
- **Modes tab**: enable/disable modes, edit custom modes, Super Mode app mappings
- **API Keys tab**: enter/manage OpenAI and Anthropic keys (stored in Keychain)
- **Vocabulary tab**: add/remove custom terms and names
- **Language tab**: select transcription language or auto-detect

**Transcription overlay**: small floating window near cursor showing live text as user speaks. Dismisses automatically after paste. Minimal, translucent design.

## Data Storage
- **User preferences**: UserDefaults / @AppStorage
- **API keys**: macOS Keychain (via Security framework)
- **Whisper models**: ~/Library/Application Support/SttTool/Models/
- **Custom modes**: JSON file in ~/Library/Application Support/SttTool/modes.json
- **Custom vocabulary**: JSON file in ~/Library/Application Support/SttTool/vocabulary.json
- **Recent transcriptions**: in-memory (not persisted across launches)

## Permissions Required
- **Microphone access** (Privacy & Security → Microphone)
- **Accessibility** (Privacy & Security → Accessibility) — for text injection
- **Input Monitoring** (Privacy & Security → Input Monitoring) — for global hotkey

## Technology Choices

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| UI framework | SwiftUI | Modern, declarative, good for menubar apps |
| Audio capture | AVAudioEngine | Native, low-latency, handles device changes |
| Speech-to-text | WhisperKit | Apple Silicon optimized, CoreML, Swift-native |
| Global hotkeys | KeyboardShortcuts | Battle-tested, handles edge cases |
| Text injection | CGEvent + NSPasteboard | Standard macOS approach, works in all apps |
| LLM calls | URLSession | Native, no extra dependencies |
| Key storage | Keychain | Secure, standard macOS practice |
| Package manager | Swift Package Manager | Native to Xcode, simplest for Swift |
