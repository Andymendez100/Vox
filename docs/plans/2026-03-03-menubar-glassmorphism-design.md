# Menubar Popover Glassmorphism Redesign

## Overview

Redesign the MenuBarView popover with a glassmorphism aesthetic — frosted glass cards, subtle glows, translucent layers. Same features as current, reorganized into floating glass cards for stronger visual hierarchy.

Follows system light/dark appearance.

## Decisions

- **Aesthetic**: Glassmorphism (frosted glass cards on blurred background)
- **Layout**: Floating glass cards approach — each section is a discrete translucent panel
- **Theme**: Follows system appearance (light/dark)
- **Content**: Same features, reorganized. Undo moved to contextual banner. Footer becomes icon-only glass circles. MODE label removed.

## Popover Shell

- Width: 340px (up from 320)
- Background: `.ultraThinMaterial`
- Cards inset with 12px horizontal margin, 10px vertical gap between cards

## Glass Card Component

Reusable modifier applied to every section:
- Background: `.ultraThinMaterial` + `RoundedRectangle(cornerRadius: 12, style: .continuous)`
- Border: `white.opacity(0.12)` stroke, 0.5pt
- Shadow: `black.opacity(0.08)`, radius 8, y offset 2
- Inner padding: 14px horizontal, 12px vertical

## Header Card

- Status indicator: 28px ring (Circle stroke in status color) with glow (`.shadow(color: statusColor.opacity(0.5), radius: 6)`), inner 8px filled dot. Pulses when recording.
- "Vox" + status text left-aligned
- Model badge right-aligned, capsule with `.ultraThinMaterial` fill

## Undo Banner (Conditional)

- Only visible when `canUndo == true`
- Separate glass card with 2px orange vertical accent bar on left
- "Text injected" label + capsule Undo button right-aligned
- Transition: `.move(edge: .top).combined(with: .opacity)` with spring

## Mode Selector Card

- No "MODE" label — pills are self-explanatory
- Selected pill: glass-highlighted with soft glow (`accentColor.opacity(0.3)` shadow)
- Unselected pills: `white.opacity(0.06)` fill
- Super Mode row: sparkle icon + label + toggle, inline

## Recent Transcriptions Card

- "Recent" label inside the card at top
- Each row: 2px left accent bar (`.quaternary`), brightens on hover
- Hover: glass highlight behind row, copy icon appears
- Empty state: centered waveform icon + text inside card
- Max height ~200px with scroll

## Footer

- No card — floats on popover background
- Two icon-only circular glass buttons (30px): gear (settings), power (quit)
- `.ultraThinMaterial` fill, hover glow effect
- Right-aligned with 12px gap
- Tooltips for accessibility

## Animations

- Card state changes: `.spring(response: 0.3, dampingFraction: 0.8)`
- Mode pill selection: `.easeInOut(duration: 0.2)`
- Undo banner: spring slide in/out
- Status ring pulse: repeating ease-in-out when recording
- Hover effects: `.easeInOut(duration: 0.15)`
