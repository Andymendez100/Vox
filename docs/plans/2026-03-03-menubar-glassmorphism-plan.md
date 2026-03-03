# Menubar Glassmorphism Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign `MenuBarView.swift` with glassmorphism floating glass cards, reorganized layout, and polished animations.

**Architecture:** Single-file rewrite of `SttTool/Views/MenuBarView.swift`. Also update popover size in `SttTool/App/AppDelegate.swift`. No new files needed — all glass card styling lives as a ViewModifier in the same file.

**Tech Stack:** SwiftUI, `.ultraThinMaterial`, AppKit (NSPasteboard, NSCursor)

---

### Task 1: GlassCard ViewModifier + Popover Shell

**Files:**
- Modify: `SttTool/Views/MenuBarView.swift` (full rewrite — keep `TranscriptionRow` struct)
- Modify: `SttTool/App/AppDelegate.swift:163` (popover contentSize)

**Step 1: Update popover size in AppDelegate**

In `AppDelegate.swift`, change the popover content size from 320x420 to 340x460:

```swift
popover.contentSize = NSSize(width: 340, height: 460)
```

**Step 2: Write the GlassCard modifier and new body shell**

Replace the `MenuBarView` body and divider with a new structure. Add a `GlassCard` ViewModifier at the bottom of the file (before `TranscriptionRow`):

```swift
// The GlassCard modifier
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
```

New body:

```swift
var body: some View {
    VStack(spacing: 10) {
        headerSection

        if appState.canUndo {
            undoBanner
        }

        if appState.transcriptionState == .loading {
            statusSection
        } else if case .error = appState.transcriptionState {
            statusSection
        }

        modeSection
        transcriptionsSection

        footerSection
    }
    .padding(12)
    .frame(width: 340)
    .background(.ultraThinMaterial)
}
```

Remove the old `divider` computed property entirely.

**Step 3: Build and verify it compiles**

Run: `cd /Users/andymendez/Documents/Personal/Code/Vox && swift build 2>&1 | tail -5`
Expected: Build succeeds (views will look broken until sections are updated, but it should compile).

**Step 4: Commit**

```bash
git add SttTool/Views/MenuBarView.swift SttTool/App/AppDelegate.swift
git commit -m "feat(ui): add GlassCard modifier and new popover shell"
```

---

### Task 2: Header Card with Glowing Status Ring

**Files:**
- Modify: `SttTool/Views/MenuBarView.swift` (headerSection, statusColor)

**Step 1: Add pulsing ring state and rewrite headerSection**

Add a `@State` property to `MenuBarView`:

```swift
@State private var ringPulsing = false
```

Replace `headerSection`:

```swift
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
        .animation(
            appState.transcriptionState == .recording
                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                : .default,
            value: ringPulsing
        )
        .onChange(of: appState.transcriptionState) { _, newState in
            ringPulsing = (newState == .recording)
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
```

Keep the existing `statusColor` computed property unchanged.

**Step 2: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Compiles successfully.

**Step 3: Commit**

```bash
git add SttTool/Views/MenuBarView.swift
git commit -m "feat(ui): glassmorphism header card with glowing status ring"
```

---

### Task 3: Undo Banner

**Files:**
- Modify: `SttTool/Views/MenuBarView.swift` (add undoBanner computed property)

**Step 1: Add the undoBanner**

Add a new computed property (the body already references it from Task 1):

```swift
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
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appState.canUndo)
}
```

**Step 2: Build and verify**

Run: `swift build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add SttTool/Views/MenuBarView.swift
git commit -m "feat(ui): glassmorphism undo banner with slide animation"
```

---

### Task 4: Status Section (Loading + Error) in Glass Cards

**Files:**
- Modify: `SttTool/Views/MenuBarView.swift` (statusSection)

**Step 1: Rewrite statusSection with glass card styling**

```swift
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
```

**Step 2: Build and verify**

Run: `swift build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add SttTool/Views/MenuBarView.swift
git commit -m "feat(ui): glassmorphism status/error cards"
```

---

### Task 5: Mode Selector Card with Glowing Pills

**Files:**
- Modify: `SttTool/Views/MenuBarView.swift` (modeSection, modePill)

**Step 1: Rewrite modeSection and modePill**

```swift
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
```

**Step 2: Build and verify**

Run: `swift build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add SttTool/Views/MenuBarView.swift
git commit -m "feat(ui): glassmorphism mode selector with glowing pills"
```

---

### Task 6: Recent Transcriptions Card with Accent Bars

**Files:**
- Modify: `SttTool/Views/MenuBarView.swift` (transcriptionsSection, emptyState, transcriptionsList, TranscriptionRow)

**Step 1: Rewrite transcriptionsSection**

```swift
private var transcriptionsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Recent")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.tertiary)

        if appState.recentTranscriptions.isEmpty {
            emptyState
        } else {
            transcriptionsList
        }
    }
    .frame(maxHeight: 200)
    .glassCard()
}
```

**Step 2: Rewrite emptyState** (minor — remove extra padding since card provides it)

```swift
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
    .padding(.vertical, 12)
}
```

**Step 3: Update transcriptionsList** (remove horizontal padding — card handles it)

```swift
private var transcriptionsList: some View {
    ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 2) {
            ForEach(Array(appState.recentTranscriptions.enumerated()), id: \.offset) { _, text in
                TranscriptionRow(text: text)
            }
        }
    }
}
```

**Step 4: Rewrite TranscriptionRow with accent bar**

```swift
private struct TranscriptionRow: View {
    let text: String

    @State private var isHovered = false
    @State private var showCopied = false

    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(isHovered ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.15))
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.15)) {
                showCopied = false
            }
        }
    }
}
```

**Step 5: Build and verify**

Run: `swift build 2>&1 | tail -5`

**Step 6: Commit**

```bash
git add SttTool/Views/MenuBarView.swift
git commit -m "feat(ui): glassmorphism recent transcriptions card with accent bars"
```

---

### Task 7: Icon-Only Glass Footer Buttons

**Files:**
- Modify: `SttTool/Views/MenuBarView.swift` (footerSection, footerButton)

**Step 1: Rewrite footer as icon-only glass circles**

```swift
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
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )
            .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(tooltip)
    .onHover { hovering in
        if hovering { NSCursor.pointingHand.push() }
        else { NSCursor.pop() }
    }
}
```

**Step 2: Build and verify**

Run: `swift build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add SttTool/Views/MenuBarView.swift
git commit -m "feat(ui): glassmorphism icon-only footer buttons"
```

---

### Task 8: Final Polish — Verify Full Build

**Step 1: Full clean build**

Run: `swift build -c release 2>&1 | tail -10`
Expected: Compiles with no errors or warnings related to MenuBarView.

**Step 2: Squash/clean commit if needed**

If all prior tasks committed cleanly, no action needed. Otherwise fix any issues and commit.
