# iOS Mosh Client — Agent Implementation Pack

This zip contains the planning documents to guide coding agents implementing a minimal, Mosh-first iOS terminal app.

## How to use
1. Read `CONSTITUTION.md` (binding design principles).
2. Read `SPEC_V1.md` (v1 requirements + explicit non-goals).
3. Implement tickets in `tickets/` strictly in numeric order.

## Process rules for agents
- If a ticket conflicts with the constitution or spec, stop and amend the ticket (do **not** “just implement both”).
- Do not add features that are not in the spec.
- Keep changes small and reviewable: each ticket should land as a coherent PR/commit.

## Agent Setup
- Xcode must be installed (same major version across machines recommended).
- After install, run: `sudo xcodebuild -runFirstLaunch`
- iOS Simulator runtime must be installed via Xcode → Settings → Platforms.
- Ensure developer tools path is correct: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- Build via CLI: `./scripts/build_sim.sh`
