# Legal Notes

## Clean-room stance
- The Mosh protocol client for this project is a clean-room implementation.
- No GPL-licensed Mosh client source code is copied, linked, or embedded.
- Only protocol behavior and publicly available documentation are referenced.

## Mosh client core third-party components
- OCB v3 Reference Code (Optimized C)
  - Used by: `MoshTerminal/MoshClientCore/Crypto/OCB/ocb.c`
  - License: ISC-style (see `LICENSE-THIRD-PARTY-OCB.txt`)
  - In-app notice: `MoshTerminal/Licenses.swift`
- zlib compression library
  - Used by: `MoshTerminal/MoshClientCore/Util/ZlibCodec.swift` (system zlib on Apple platforms)
  - License: zlib (see `LICENSE-THIRD-PARTY-ZLIB.txt`)
  - In-app notice: `MoshTerminal/Licenses.swift`

## Notices location
- Repo license texts: `LICENSE-THIRD-PARTY-OCB.txt`, `LICENSE-THIRD-PARTY-ZLIB.txt`
- In-app license screen: `MoshTerminal/Licenses.swift`

## Privacy check
- Session keys and decrypted payloads are kept in-memory only and are not logged.
- Avoid storing secrets in global state to prevent crash report enrichment.
