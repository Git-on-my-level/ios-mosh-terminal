# Ticket 006 — Terminal view + keyboard accessory row (local loopback)

## Goal
Create a terminal UI component with correct input ergonomics, independent of Mosh networking.

## Deliverables
- Terminal renderer integration (recommended: SwiftTerm) embedded in SwiftUI
- Keyboard accessory row with buttons:
  - Esc, Ctrl (sticky), Tab, `|`, `-`, `/`, `:`
- Input pipeline:
  - Regular text input
  - Modifier handling for Ctrl (sticky toggle)
  - Hardware keyboard support (as supported by the terminal component)
- Local loopback session for testing:
  - Typed characters are echoed back and rendered
  - Supports basic newlines and backspace

## Non-goals
- No SSH/Mosh networking
- No selection/scrollback UX

## Acceptance criteria
- Terminal renders text correctly and accepts input on device/simulator
- Accessory keys send the expected control characters
- Loopback mode is usable for smoke testing the terminal UI
