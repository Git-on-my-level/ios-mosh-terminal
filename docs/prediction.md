# Prediction Model — Speculative Local Echo for iOS Mosh Terminal

This document describes the speculative local echo (prediction) implementation in the iOS Mosh Terminal app, explaining the model, safety guarantees, and architecture.

## Overview

The prediction system provides immediate visual feedback for user keystrokes by showing predicted characters before the server confirms them. This makes typing feel responsive even on high-latency connections while preserving security for password entry.

## Key Concepts

### Confirmed vs Predicted State

- **Confirmed State**: The terminal state after applying all server output. This is the authoritative state from the server and is rendered by SwiftTerm.
- **Predicted State**: A client-side overlay showing unconfirmed user keystrokes. Predictions are rendered on top of the confirmed state by `PredictionOverlayView`.

### Frames and Acknowledgments

The prediction engine tracks three monotonic counters:

- `local_frame_sent`: The last client state number sent to the server
- `local_frame_acked`: The last client state number transport-acked by the server
- `echoAck` ("late ack"): Server-provided acknowledgment indicating input has had time to be processed (delayed by ~50ms upstream)

Predictions are marked with an `expiration_frame = local_frame_sent + 1` and remain **Pending** until `echoAck >= expiration_frame`.

### Epochs (Security Mechanism)

Predictions are grouped into **epochs**:

- `prediction_epoch`: The epoch for newly created predictions (incremented when predictions become uncertain)
- `confirmed_epoch`: The last epoch that is allowed to be displayed

A prediction is **tentative** if `tentative_until_epoch > confirmed_epoch`.

**Security Impact**: In a password prompt, remote echo is disabled. Predictions cannot be confirmed as "correct echo", so `confirmed_epoch` does not advance and predictions remain tentative → **not displayed**.

This epoch-gating is the primary mechanism that prevents showing typed passwords.

## Architecture

### Components

1. **PredictionEngine**: Core prediction logic
   - Parses user keystrokes via `UTF8ByteParser`
   - Generates overlay cells and cursor predictions
   - Culls invalid/outdated predictions
   - Tracks epochs and network state

2. **TerminalPredictionCoordinator**: Connects UI and runtime
   - Observes user input and forwards to `PredictionEngine`
   - Observes server output and updates confirmed state
   - Observes echoAck and network metrics
   - Pushes render models to `PredictionOverlayView`

3. **PredictionOverlayView**: Renders predictions
   - Draws overlay cells on top of terminal
   - Draws predicted cursor
   - Underlines predictions when latency is high

### Prediction Modes

Users can select from four display modes via Settings:

- **Off**: Never show predictions
- **Adaptive**: Show predictions only when:
  - `srttTrigger` is true (latency > 30ms)
  - `glitchTrigger` is active (predictions pending too long)
- **Always**: Show all predictions when available
- **Experimental**: Show predictions even for uncertain states (use for debugging)

### Adaptive Triggers

The adaptive mode uses two triggers to determine when predictions help user experience:

1. **SRTT Trigger**: Activated when smoothed RTT exceeds 30ms
   - Deactivates when RTT falls below 20ms with no active predictions

2. **Glitch Trigger**: Activated when predictions remain pending for too long
   - `glitchThreshold`: 250ms (predictions older than this are likely "stuck")
   - `glitchRepairCount`: 10 (number of glitch events to trigger underline)
   - `glitchFlagThreshold`: 5000ms (very old predictions trigger strong underline)

### Supported Operations

The prediction engine handles these user inputs:

- **Printable characters**: Inserts characters at cursor position
- **Backspace**: Removes character before cursor, marks line as uncertain
- **Carriage Return**: Moves cursor to next line, marks state as uncertain
- **Left Arrow**: Moves cursor left, predicts position
- **Right Arrow**: Moves cursor right, predicts position

Unsupported inputs (escape sequences, multi-byte characters, full-screen apps) cause predictions to become tentative (not displayed).

## Performance Optimizations

### Sparse Storage

- `activeCellPositions`: Set of cell positions with active predictions
- `activeRowIndices`: Set of row indices containing active cells
- Culling only processes active rows, not all rows

### Bounded Culling

- `hasActivePredictions()` checks set emptiness instead of scanning
- Only evaluates validity for active cells
- O(active_cells) instead of O(rows * cols)

### Redraw Coalescing

- Overlay redraws throttled to max 60fps (16.67ms minimum interval)
- Pending redraws canceled when new updates arrive
- Prevents excessive display updates during rapid typing

## Safety Guarantees

1. **Password Security**: Predictions never shown when remote echo is disabled
2. **Epoch Gating**: Tentative predictions (unconfirmed epoch) never displayed
3. **Automatic Rollback**: Predictions removed when server contradicts them
4. **Conservative Behavior**: Stops predicting on uncertain input
5. **Memory Safety**: Weak references prevent retain cycles

## Testing

See unit tests in `MoshTerminalTests/`:

- `PredictionDisplayPreferenceTests`: Tests for all preference modes
- `PredictionEngineCullTests`: Tests for epoch gating and culling logic
- `PredictionEngineInputTests`: Tests for keystroke handling
- `PredictionSwiftTermIntegrationTests`: Integration tests with SwiftTerm

## Manual Testing

1. **Basic Typing**:
   - Type commands and verify predicted characters appear
   - Verify predictions disappear when confirmed

2. **Password Prompt**:
   - Run `sudo -k; sudo ls`
   - Type password and verify NO predictions appear

3. **High Latency**:
   - Use Network Link Conditioner or slow connection
   - Verify predictions appear and are underlined

4. **Rapid Typing**:
   - Type quickly and verify no performance degradation
   - Run `yes | head` and type simultaneously

5. **Resize/Scroll**:
   - Resize terminal window
   - Scroll in terminal history
   - Verify predictions reset correctly
