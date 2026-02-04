# UDP Timeout Regression Plan (Chunked Re-Integration)

## Goal
Find the smallest change (or smallest set of changes) between:

- **Good:** `225de97` (connects)
- **Bad:** `ab5ba0c` (UDP timeout)

…by starting from `225de97` on a new branch and re-applying the `ab5ba0c` feature **in coarse chunks**, running a deterministic Mosh handshake test after each chunk.

This is intentionally “binary-like” (large safe chunk → test → next large chunk → test), and we only split further once we hit the first failing chunk.

## Primary Pass/Fail Signal (Use This Every Step)
Use the repo’s end-to-end handshake test harness:

```bash
./scripts/e2e_mosh_test.sh
```

- **PASS:** test succeeds (`MoshE2EIntegrationTests/testMoshBootstrapAndHandshake`)
- **FAIL:** test fails/times out (treat as “UDP regression reproduced”)

This avoids relying on a specific external server/network while iterating.

After we identify the breaking chunk locally, do a quick manual check against the real Hetzner host to confirm.

## Setup (Once)
1. Ensure Docker is running (the harness uses Docker).
2. (Optional) pick a simulator explicitly:

```bash
DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro" ./scripts/e2e_mosh_test.sh
```

3. (Optional) keep the harness running between runs (the script auto-reuses it):

```bash
./scripts/mosh_harness.sh status
```

## Workflow
1. Create a new branch from the good commit:

```bash
git switch --create codex/udp-timeout-reintegration 225de97
```

2. Confirm baseline:

```bash
./scripts/e2e_mosh_test.sh
```

3. Apply the next chunk (see below), commit it, and re-run the test.
4. The **first chunk that fails** is where we focus. At that point, split that chunk into smaller chunks until the specific file(s)/hunk(s) causing the regression are isolated.

## How To Apply a Chunk (Recommended Commands)
Apply files from `ab5ba0c` onto the current branch:

```bash
git checkout ab5ba0c -- <path1> <path2> ...
git add <paths>
git commit -m "<chunk name>"
./scripts/e2e_mosh_test.sh
```

Tip: keep each chunk as a single commit so it’s easy to back out / bisect within the branch.

## Chunk Plan (Coarse First Pass)
These chunks match how `ab5ba0c` is structured: large “should be safe” additions first, then progressively more invasive wiring.

### Chunk 1: Add Prediction Feature Sources + Project Wiring (Should Be Inert)
Intent: compile/link the prediction code but do not change runtime connection behavior yet.

Apply:
- `MoshTerminal.xcodeproj/project.pbxproj`
- `MoshTerminal/Prediction/`
- `docs/prediction.md`
- `MoshTerminalTests/Prediction*.swift`
- `MoshTerminalTests/Prediction*/**` (any added prediction tests)

Expected: **PASS**. If this chunk alone breaks the UDP handshake, suspect **undefined behavior / memory-safety issues** that are sensitive to build layout (e.g., socket address bridging, pointer lifetime, etc.). In that case, jump to “If Chunk 1 Fails” below.

### Chunk 2: Settings Plumbing (Should Not Touch Networking)
Apply:
- `MoshTerminal/AppSettings.swift`
- `MoshTerminal/SettingsView.swift`

Expected: **PASS**.

### Chunk 3: UI Wiring (Prediction Coordinator Hookup)
Apply:
- `MoshTerminal/TerminalSessionController.swift`
- `MoshTerminal/TerminalView.swift`

Expected: **PASS**. If it fails here, suspect connection lifecycle issues (double-start, cancellation, main-thread blocking, etc.).

### Chunk 4: Engine/Runtime Wiring (Network Snapshot + Echo Ack)
Apply:
- `MoshTerminal/Services/MoshEngine.swift`
- `MoshTerminal/Services/NativeMoshEngine.swift`
- `MoshTerminal/Services/MoshRuntime.swift`
- `MoshTerminal/MoshClientCore/Util/TransportSender.swift`
- `MoshTerminal/Services/ConnectionManager.swift`
- `MoshTerminalTests/MoshRuntimeKeepaliveTests.swift`

Expected: **this is the most likely chunk to fail** if the regression is real protocol/runtime behavior rather than UI.

## If a Chunk Fails: How To Split Further (Fast)
Once you have the first failing chunk:
1. `git reset --hard HEAD~1` to get back to last-known-good on the reintegration branch.
2. Split the chunk by file groups and re-run `./scripts/e2e_mosh_test.sh` after each.

Suggested split order (most informative first):
1. `MoshTerminal/Services/MoshRuntime.swift` alone
2. `MoshTerminal/Services/NativeMoshEngine.swift` + `MoshTerminal/Services/MoshEngine.swift`
3. `MoshTerminal/Services/ConnectionManager.swift`
4. `MoshTerminal/TerminalSessionController.swift` + `MoshTerminal/TerminalView.swift`
5. `MoshTerminal.xcodeproj/project.pbxproj` + prediction sources/tests

If a single file causes failure, split within it by applying partial hunks (copy/paste the diff manually or use `git add -p` interactively).

## If Chunk 1 Fails (Prediction Sources Added But “Unused”)
This is a strong signal of **UB/build-layout sensitivity**, not a logical “prediction wiring” bug.

Recommended next steps (before involving an expert):
1. Run with Address Sanitizer / Thread Sanitizer in Xcode on the failing chunk.
2. Audit low-level networking/crypto for unsafe pointer casts and lifetime issues (e.g., `sockaddr_storage` rebinding, `withUnsafeBytes` usage, reuse-after-free patterns).
3. If you have a known “UB hardening” patch (e.g., safer sockaddr rebinding for `sendto`/`recvfrom`), apply it on top of the reintegration branch and re-test.

## What To Record Each Step (So We Don’t Re-Learn Things)
For each chunk commit, record:
- Commit hash
- `./scripts/e2e_mosh_test.sh` PASS/FAIL
- If FAIL, the most relevant portion of xcodebuild output (timeout/error line)

Optionally, for one failing case and one passing case (once the failing chunk is identified):
- Server-side UDP capture on the Docker harness container or on Hetzner (in/out) to confirm “server replies vs silence.”

