# Ticket 012 — Settings (font size, theme, keep-awake) + apply to terminal

## Goal
Implement the small set of global settings and ensure they affect the terminal view.

## Deliverables
- Settings model stored in UserDefaults:
  - fontSize
  - themeMode (system/light/dark)
  - keepAwake (bool)
- Apply settings to:
  - Terminal font size
  - App appearance override (where applicable)
  - Idle timer disabled when keepAwake is enabled (only while terminal is visible)

## Non-goals
- Theme editor
- Per-host settings

## Acceptance criteria
- Settings persist across relaunch
- Font size changes are visible in terminal
- Keep-awake prevents screen dimming while terminal is active
