# Contributing to HopTalk

Thanks for taking time to improve HopTalk. This project includes Flutter app code and a BLE/LoRa protocol that is also implemented by a separate ESP32 firmware project. Keep changes focused, explain compatibility effects, and never commit private keys or account credentials.

## Contents

- [Before you start](#before-you-start)
- [App architecture](#app-architecture)
- [Working with the mesh controller](#working-with-the-mesh-controller)
- [Cross-project protocol compatibility](#cross-project-protocol-compatibility)
- [Security-sensitive areas](#security-sensitive-areas)
- [Storage and data models](#storage-and-data-models)
- [Make and check a change](#make-and-check-a-change)
- [Testing on hardware](#testing-on-hardware)
- [Pull request checklist](#pull-request-checklist)
- [Documentation](#documentation)
- [License](#license)

## Before you start

- Read the relevant feature code and check existing issues or pull requests for related work. The README explains how routing, encryption, storage, and the BLE/LoRa path work.
- For a bug fix or documentation update, you can prepare a focused pull request.
- For a new feature, data format change, BLE command change, or LoRa packet change, open an issue or discuss the plan first. Protocol work can require matching changes in the app and the separate [HopTalk ESP32 firmware](https://github.com/nuhanchowdhurylinkdin-a11y/HopTalk-esp32).
- Use an Android phone for end-to-end mesh checks. `nearby_connections` is an Android-only plugin in the current app setup.

## App architecture

- The app is organized by feature under `lib/features/`; keep UI, GetX controller/state, model, and service responsibilities in their existing areas.
- `lib/main.dart` initializes SharedPreferences and Hive, registers adapters, starts `ChatStorageService`, and selects the initial route.
- GetX bindings and routes live in `lib/core/utils/bindings/` and `lib/routes/`.
- `MeshNetworkController` owns shared mesh state and lives for the whole app session (it is registered as permanent). Keep long-running mesh work there, not in screen widgets or per-screen controllers.
- `ChatStorageService` owns paged local conversation storage. `CryptoService` handles peer encryption, `Esp32BleService` handles BLE transport, and `LoRaCodec` owns binary packet encoding and decoding.
- Keep persistence changes consistent with Hive models and generated adapters (see [Storage and data models](#storage-and-data-models)).

## Working with the mesh controller

`MeshNetworkController` is split into Dart `part` files. They are all part of one library and share its private members.

| File | Responsibility |
| --- | --- |
| `mesh_network_controller.dart` | Fields, reactive state, `initMeshNetwork`, `updateLocalProfile`, lifecycle, `_resetState`, `_log`. |
| `permissions_extension.dart` | Android permission checks and requests, GPS check, profile thumbnail helper. |
| `connections_extension.dart` | Advertising, discovery, connect/retry logic, endpoint names, blocking, ID helpers (`_shortId`, `_sameUser`, `_isBlockedUser`). |
| `messaging_extension.dart` | Incoming payload handling, delivery, decryption, receipts, profiles, sending, forwarding, duplicate cache. |
| `routing_extension.dart` | Routing table, route updates, gateway selection. |
| `contacts_extension.dart` | QR payload creation and parsing, saving and loading QR contacts. |
| `esp32_extension.dart` | ESP32 connection state, user ID list sync, LoRa send and receive, ID prefix expansion. |

Rules to follow when editing these files:

- Keep each `part` and `part of` declaration paired. `part` files cannot contain their own imports; add imports to `mesh_network_controller.dart`.
- Method names must be unique across all extensions and the class, otherwise the library will not compile. Check before adding a helper.
- Inside an extension, static members of the class need the class name (for example `MeshNetworkController.keyChangedError`).
- Add new shared fields to the class, not to an extension, because extensions cannot declare fields.
- Never block the UI isolate. Long work belongs in `async` methods, and fire-and-forget calls should use `unawaited` and handle their own errors.
- Treat every packet received from a peer as untrusted: check types, lengths, and formats before using a value, and never let one bad packet stop the processing of others.
- Log through `_log` (debug builds only). Do not log keys, message text, or full user IDs unless it is needed to fix a specific problem and is removed afterwards.

## Cross-project protocol compatibility

The current app and ESP32 firmware share these contracts:

- BLE service `BE28A6AE-FE7A-4394-8858-F48BD1D62026`, RX `4AF882CE-9582-4515-BEAB-1941400E169B` (phone writes), and TX `718CEFEA-4CE7-4A32-BC46-8C24BC97BD7E` (board notifies).
- A full user-ID snapshot begins with byte `0xF0`, sends each ID as its own write containing a 16-character ASCII hex prefix, then commits with `0xF1`. Incremental updates use `0xA1` to add or `0xA2` to remove followed by the prefix. Prefixes are lowercase hex and are taken from every user in the routing table, including the phone's own ID.
- Every BLE write must fit in `MTU - 3` bytes. The app requests an MTU of 247 after connecting.
- The LoRa frame has a 25-byte header and a maximum total size of 200 bytes:

  | Bytes | Content |
  | --- | --- |
  | 0 | Type: `0x01` message, `0x02` seen receipt |
  | 1 to 8 | Message ID |
  | 9 to 16 | Sender ID prefix |
  | 17 to 24 | Receiver ID prefix |
  | 25 to end | Encrypted body: nonce (12) + ciphertext + tag (16) |

- The phone encrypts message content. Firmware uses visible packet metadata and receiver ID for filtering and forwarding; it does not decrypt message content.
- The QR contact payload has a `v` field (currently `1`). Change `v` when the payload format changes incompatibly, and keep rejecting unknown versions.
- The JSON packets sent over Nearby Connections (`HANDSHAKE`, `ROUTING_UPDATE`, `PROFILE`, chat message, `SEEN`) are an app-to-app contract. Old and new app versions may meet in the same mesh, so unknown fields must be ignored and unknown types must not crash the receiver.

If you change any of these values or layouts, update both implementations and their documentation, add or adjust codec tests, and describe how old and new app/firmware versions behave together. Do not assume every user will update both devices at the same time. A new packet type should use an unused value and be ignored safely by older firmware and apps.

Over LoRa, airtime is limited and frames can be lost. Before adding anything that sends more LoRa traffic (for example acknowledgements or retries), explain the extra airtime and what happens when the extra frame is lost.

## Security-sensitive areas

Changes to these areas need extra care and a clear explanation in the pull request:

- `CryptoService` (key agreement, key derivation, AES-GCM usage, nonce handling).
- QR creation, parsing, key pinning, and the `KEY_CHANGED` flow in `contacts_extension.dart` and `ChatStorageService`.
- Profile acceptance rules in `_handleProfile` (including the rule that a different key for a known user is ignored).
- Parsing and validation of incoming packets, routing updates, and BLE data.
- Anything that persists keys, user IDs, or message content.

Do not weaken validation to make a test pass, and do not store private keys outside secure storage. Report suspected vulnerabilities privately to the maintainer instead of opening a public issue with details.

## Storage and data models

- Chat messages are stored in encrypted Hive boxes. `ChatMessage` (Hive type 1) and other annotated models use generated adapters. If you change an annotated model, regenerate its adapter and include the generated file:

  ```sh
  dart run build_runner build --delete-conflicting-outputs
  ```

- Never reuse or renumber an existing `@HiveField` index. New fields need a new index and a `defaultValue`, so existing user data still loads.
- The conversation list is a map-based Hive record per peer. When adding keys to it, keep reading code tolerant of records that do not have the new key.
- `ChatStorageService` currently deletes and recreates a Hive box that cannot be opened. Do not add code paths that delete user data without a clear reason, and describe any change to this behavior.
- Keys that must not leave the device (X25519 private key, Hive cipher key) belong in `flutter_secure_storage` only.
- State that is only kept in memory today (routing table, mesh-learned profiles, block list, duplicate cache) is listed in the README. If you start persisting any of it, update the README and think about stale or malicious data.

## Make and check a change

1. Fork the repository and create a branch with a clear name, such as `fix/qr-validation`, `feature/chat-search`, or `docs/android-setup`.
2. Make the smallest complete change that solves the problem. Keep unrelated formatting and generated files out of the pull request.
3. Run the checks that fit the change:

   ```sh
   flutter pub get
   flutter analyze
   flutter test
   ```

4. For app changes involving Nearby Connections, BLE, permissions, or LoRa, check on Android hardware when possible. For firmware changes, run its PlatformIO build and include hardware details if tested.

Tests that need no hardware are welcome, especially for:

- `LoRaCodec`: encode then decode returns the same fields, oversized and malformed frames are rejected, both frame types work.
- QR payload parsing: valid payloads, wrong version, bad key length, bad ID.
- Routing update processing: new routes, shorter routes, hop limit, removal of stale routes.
- Encryption: round trip, wrong key fails, tampered ciphertext fails.

## Testing on hardware

For changes that touch the ESP32 path, check what applies and report the results:

- Connect and disconnect the ESP32 repeatedly. It should reconnect reliably, and the service must be found after the firmware's UUIDs change.
- After connecting, the firmware should report the user ID list (snapshot), and later routing changes should arrive as add and remove updates.
- Send a message from a phone to a contact that is outside Nearby range, through the gateway, and read it on the other side.
- Send a message that is exactly at, and one that is over, the 147-byte text limit.
- Check the behavior when the receiving phone does not know the sender, and when the gateway phone is not the sender.
- Check that opening the chat produces a seen receipt that reaches the sender over LoRa.
- Note the board model, radio module, frequency, spreading factor, bandwidth, and distance used.

In debug builds, the chat screen has a "Force LoRa" toggle that sends over LoRa even when a mesh route exists. This is useful when testing with two phones that are close together.

## Pull request checklist

Include:

- What changed and why.
- The commands or checks you ran and their results.
- Screenshots for visible UI changes, if helpful.
- Android device/OS and hardware details for device-specific checks.
- Any effect on BLE/LoRa compatibility, QR payload version, storage format, or existing user data.
- Any change to what is encrypted, what is visible over the air, or what is stored on the device.
- Clear note when hardware testing was not possible.

Do not include passwords, private keys, personally identifying test data, or unrelated binary files. Submit work through a branch and pull request rather than pushing directly to the main branch.

## Documentation

The README describes the behavior of routing, storage, encryption, and the BLE/LoRa protocol. If your change alters any of that, update the README in the same pull request, including its tables and diagrams. Protocol changes also need matching documentation in the firmware repository.

## License

By submitting a contribution, you confirm that you have the right to share it under this repository's GNU General Public License version 3. The app repository's license is `GPL-3.0-only`; third-party dependencies and assets retain their own licenses. When adding a dependency, check that its license is compatible with GPL-3.0-only and note it in the pull request.