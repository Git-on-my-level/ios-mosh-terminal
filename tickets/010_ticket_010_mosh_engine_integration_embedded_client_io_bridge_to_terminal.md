# Ticket 010 — Mosh engine integration (embedded client) + IO bridge to terminal

## Goal
Integrate a working Mosh client engine and bridge its input/output to the terminal view.

## Deliverables
- A `MoshEngine` abstraction with:
  - start(connectInfo, initialTerminalSize)
  - sendInput(bytes)
  - updateTerminalSize(cols, rows)
  - stop()
  - connection-state callbacks/events
- Integration approach (per Ticket 002 decision), e.g.:
  - Embed upstream mosh-client code and run it “headless” with pipes/FDs, or
  - Another compliant approach decided in Ticket 002
- Bridge:
  - Mosh output → feed into terminal emulator
  - Terminal input → send to Mosh engine
- Ensure secrets (session key) never hit logs

## Non-goals
- Reconnect logic beyond a single connect/disconnect
- Backgrounding behavior

## Acceptance criteria
- Can connect to a host via bootstrap info and obtain an interactive shell
- Basic typing works and output renders correctly
- Terminal resizes propagate (at least on rotation)
