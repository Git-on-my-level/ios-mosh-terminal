# E2E Mosh Integration Test

This doc explains how to run the end-to-end Mosh integration test locally. The test spins up a local Docker harness that runs `sshd` and `mosh-server`, then the iOS test boots Mosh via SSH and performs the UDP handshake.

## Prerequisites
- Docker (running)
- OpenSSH tools: `ssh-keygen`, `ssh-keyscan`
- Xcode + iOS Simulator runtime
- Optional: `mosh` client (only needed for manual CLI testing)

## Quick start
Run the one-shot test script (recommended):

```bash
./scripts/e2e_mosh_test.sh
```

This will:
1. Start the Docker harness (if not already running).
2. Export the required `MOSH_*` env vars for the test.
3. Run the `MoshE2EIntegrationTests/testMoshBootstrapAndHandshake` test on the simulator.
4. Stop the harness automatically when the test completes.

## Example output
You should see output similar to:

```
Mosh harness started.
Connection env: /tmp/mosh-harness.XXXXXX/connection.env
Test Suite 'MoshE2EIntegrationTests' started
Test Case '-[MoshE2EIntegrationTests testMoshBootstrapAndHandshake]' passed (X.XXX seconds)
```

## Configuration
You can customize the simulator destination and timeout:

```bash
DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro" ./scripts/e2e_mosh_test.sh
MOSH_E2E_TIMEOUT=30 ./scripts/e2e_mosh_test.sh
```

The harness script also supports overrides:

```bash
MOSH_HARNESS_HOST=127.0.0.1 MOSH_HARNESS_UDP_RANGE=60000-61000 ./scripts/mosh_harness.sh start
```

## What the test uses
The test reads the following environment variables from the harness:
- `MOSH_HOST`
- `MOSH_SSH_PORT`
- `MOSH_USER`
- `MOSH_KEY_PATH`
- `MOSH_KNOWN_HOSTS_PATH` (currently unused by the test)
- `MOSH_UDP_PORT_RANGE`

## Ephemeral keys and storage
The harness generates a fresh SSH keypair for each run using `mktemp` and `ssh-keygen`.
- The private key is stored only in the temporary harness directory.
- The path is exposed via `MOSH_KEY_PATH`.
- When the harness stops, the entire temp directory is removed.

The test also uses a temporary JSON store for TOFU host keys and deletes it after the run.
No SSH keys or host keys are persisted in the repo or Keychain.

## Troubleshooting
- `Missing MOSH_* env vars`: Run `./scripts/e2e_mosh_test.sh` (it sets them for the test).
- `Missing required command: docker` or `ssh-keygen`: Install Docker or OpenSSH tools.
- `Harness already running`: Stop it with `./scripts/mosh_harness.sh stop`.
- `Mosh handshake failed`: Check that Docker is running and the UDP port range is free.
- `mosh-server was not found`: Ensure the harness container built correctly (try `./scripts/mosh_harness.sh stop` then `start`).
- Simulator build failures: confirm Xcode CLI setup and run `./scripts/build_sim.sh` to validate basics first.
