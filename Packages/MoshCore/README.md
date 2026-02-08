# MoshCore

This package hosts non-UI core logic shared by the MoshTerminal app.

## Modules
- `MoshClientCore`: Protocol framing, crypto/codecs, and transport state.
- `Prediction`: Prediction engine, overlay model, and SwiftTerm grid integration.

## Dependency Rules
- UI/app targets may depend on these modules.
- Core modules must not depend on app/UI code.
- `Prediction` may depend on `SwiftTerm` only; it should not reach into app services.
