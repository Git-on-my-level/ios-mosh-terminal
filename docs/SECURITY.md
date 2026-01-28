# Security

## Key storage
- Private keys are stored in the iOS Keychain as generic password items.
- Accessibility is set to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`:
  - Device-only: the keychain item does not sync to other devices.
  - Unlocked-only: the item is available only while the device is unlocked.

## Rationale and trade-offs
- This app does not promise background connectivity, so limiting access to the unlocked state is acceptable and more restrictive than "after first unlock."
- After a device reboot, keys are unavailable until the user unlocks the device.
- If the device is locked, reconnect attempts that require the private key will fail until the user unlocks it.

## Related posture
- No key material is logged.
- Host keys follow TOFU (trust-on-first-use) verification.
