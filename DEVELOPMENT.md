# Development Guide

## Architecture & repository boundaries

- `Sources/KKvoice`: SwiftUI settings window (`macOS 13.0+`), menu-bar controller, audio source router (`AudioSourceRouter`), in-app driver installer & uninstaller (`DriverInstaller`), native GitHub Releases updater (`AppUpdater`), keyboard settings, button mappings, speech-app capture monitor (`InputApplicationAudioMonitor` for Vokie, Doubao IME, and WeChat IME), Quick Note orchestration (Apple Notes & SnapNote), and session coordination.
- `Native/Helper`: Objective-C background process for HID-gated Bluetooth discovery & zero-power passive standby (`remote_standby`), HID wake-on-keypress reconnect, Chromecast ATVV, remote buttons, Apple Notes automation (`appleNotesNewNote`), keyboard event listening, and JSON-line IPC (`Native/Helper/SOURCE.md` records helper provenance).
- `Session`: deterministic capture state machine (default `.hybrid` gesture supporting both tap-to-toggle and hold-to-talk), shortcut relay, and physical-key coordination.
- `Audio`: CoreAudio output to the selected virtual device (automatically unmuting and restoring full scalar volume on session start), physical audio input device fallback relay (`MacMicrophoneSource`), PCM conversion, buffering, and session isolation.
- `SnapNote`: local/LAN MCP client (supporting configurable endpoint URL & port), Keychain token store, action coordinator, and helper cancellation adapter.
- `Driver`: BlackHole-based `KKvoice Mic` HAL driver build script (`Driver/build-blackhole-driver.sh`) and privileged installer.
- `*Tests` and `Tests/KKvoiceTests`: hardware-free regression tests (33 XCTest unit tests in `Tests/KKvoiceTests` plus 5 standalone `*Tests/run.sh` suites).

Keep the remote protocol in the helper process and keep state transitions in the hardware-independent `Session` module. Do not move CoreAudio callbacks, BLE callbacks, or keychain access onto real-time audio or event-tap paths. Preserve third-party notices and do not commit credentials, personal notes, build products, local app bundles, or signing material.

The app sends JSON-line commands to `KKvoiceRemoteHelper`. Keep command ordering serialized. The helper does not attach remote session identifiers to all BLE events, so the coordinator must reject stale events and release capture idempotently.

## Bluetooth discovery, HID gate & zero-power standby

`KKvoiceRemoteHelper` combines a system-level `IOHIDManager` mount gate with bounded BLE discovery windows and kernel-driven passive wakeup:

- **System HID Mount Gate (`hidDevicePresent`)**: To prevent user-space `CBCentralManager` from opening an unbonded GATT connection while the remote is still in macOS Bluetooth Settings ("Nearby Devices") awaiting system SMP pairing, `KKvoiceRemoteHelper` only initiates BLE ATVV connections when the matching `IOHIDDevice` (`0x18D1:0x9450`) is mounted in `IOHIDManager` (`hidDevicePresent == YES`). In `AppModel`, the remote is reported as connected only when both the HID button channel (`isHIDReady`) and the BLE ATVV voice channel (`isVoiceReady`) are ready.
- **Bounded Discovery & Zero-Power Standby**: When `hidDevicePresent == YES` (or during a bounded probe window), the helper queries `retrievePeripheralsWithIdentifiers` (`lastChromecastPeripheralUUID`) and `retrieveConnectedPeripheralsWithServices` (`@[ATVVServiceUUID, @"1812", @"180A", @"180F", @"1800"]`) with strict `"Chromecast Remote"` name matching. When the remote is away, the helper stops `discoveryTimer` and `[central stopScan]`, emitting `{"type": "remote_standby"}` so the Mac consumes **zero background BLE scan power**.
- **Instant HID Wakeup**: As soon as the remote wakes up nearby (`HIDDeviceMatchedCallback` / `hid_connected` or any HID button report), the helper immediately connects the ATVV voice service on the main queue.
- `AppModel` persists `hasEverConnectedRemote` in `UserDefaults`: new Macs (`hasEverConnectedRemote == false`) display the first-time Bluetooth pairing bar (`同时长按「← + 🏠」3 秒`), while returning users away from their remote (`hasEverConnectedRemote == true`) see a calm offline standby state (`遥控器离线 · 当前使用其他收音设备 · 按遥控器任意键自动重连`).

## In-app updater (`AppUpdater`)

`Sources/KKvoice/AppUpdater.swift` implements a zero-dependency updater backed by `https://api.github.com/repos/intelKANG/KKvoice/releases/latest`:

- Compares release tags against `AppModel.appVersionString` via `SemanticVersion`.
- Supports automatic check on launch (delayed 3s, never interrupting active voice recording) and every 6 hours (`autoCheckUpdates`, default `true`), plus optional automatic download and installation (`autoInstallUpdates`, default `false`).
- Verifies downloaded archives before replacement: checks `CFBundleIdentifier == "local.kkvoice.app"`, runs `/usr/bin/codesign --verify --deep --strict`, validates matching Apple `TeamIdentifier` when the running bundle is team-signed, strips `com.apple.quarantine`, and swaps the app bundle via a detached relaunch script.

## Build workflow

Run all checks before packaging:

```sh
swift test
./SessionTests/run.sh
./AudioTests/run.sh
./NativeTests/run.sh
./KeyboardTests/run.sh
./SnapNoteTests/run.sh
./Scripts/build-app.sh
```

The main Swift package `KKvoice` targets **macOS 13.0+** (`Package.swift` `platforms: [.macOS(.v13)]`), while `Scripts/build-helper.sh` and `Driver/build-blackhole-driver.sh` compile universal (`arm64` + `x86_64`) binaries with `MACOSX_DEPLOYMENT_TARGET=12.0`.

`Scripts/build-app.sh` automatically runs `Driver/build-blackhole-driver.sh` when `.build/KKvoiceMic.driver` is not yet built, builds `KKvoiceRemoteHelper.app`, compiles the Swift package in release mode, copies the icon, helper, `KKvoiceMic.driver`, and `BlackHole-GPL-3.0.txt` into `dist/KKvoice.app`, and signs inside-out (`KKvoiceMic.driver` → `KKvoiceRemoteHelper.app` → `KKvoice.app`) using the dynamically detected local Apple signing identity (`CODESIGN_IDENTITY` override → `Developer ID Application` → `Apple Development` with `--options runtime`, falling back to `-` ad-hoc signing when no certificate is present).

## Audio driver & speech application compatibility

The app routes remote PCM (or fallback physical input device audio) to the `KKvoice Mic` (`KKvoiceMi2ch_UID`) virtual device's output side. The virtual device exposes that signal as an input to Doubao Input Method (`com.bytedance.inputmethod.doubaoime`), WeChat Input Method (`com.tencent.inputmethod.wetype`), Vokie (`com.vokie.desktop`), and other speech applications. KKvoice expects 48 kHz stereo packed Float32 output and sends 16 kHz mono remote PCM (or resampled fallback input PCM) through its bounded buffer, automatically unmuting and restoring full volume (`1.0`) when opening the output stream.

For builds and releases, `Driver/build-blackhole-driver.sh` compiles `KKvoiceMic.driver` directly from upstream [BlackHole](https://github.com/ExistentialAudio/BlackHole) `v0.6.1` source (GPLv3) with custom identifiers (`KKvoice Mic`, UID `KKvoiceMi2ch_UID`) and patches `kAudioDevicePropertyTransportType` from `kAudioDeviceTransportTypeVirtual` to `kAudioDeviceTransportTypeUSB` (`'usb '`) so `AVCaptureDevice`-based speech apps (such as Doubao Input Method) list `KKvoice Mic` as a selectable microphone. `DriverInstaller` provides one-click in-app installation, reinstallation, driver uninstallation (removing both `KKvoiceMic.driver` and any `.previous*` backups), and full app uninstallation.

See [docs/TECHNICAL_NOTES.md](docs/TECHNICAL_NOTES.md) for deep-dive engineering notes on the dual-mode voice gesture state machine, `kCGHIDEventTap` head-order guard, and Bluetooth HID pairing gate.

## Permissions and privacy

- **Bluetooth** permission is required to pair and communicate with a remote.
- **Input Monitoring** is required for global physical keyboard shortcuts and remote button events.
- **Accessibility** is used by the helper for supported system-level key behavior.
- **Microphone** permission is required only when using a physical audio input device (`其他收音设备`) as the automatic fallback source while the remote voice channel is not ready. **No microphone is ever captured while idle**; `AudioSourceRouter` / `MacMicrophoneSource` opens the selected input device only during an active keyboard-triggered recording session, streams directly to `KKvoice Mic` without writing to disk, and stops and zeroes buffers immediately when the session ends or is cancelled.
- **SnapNote tokens** are stored only in the user's Keychain (`SnapNoteTokenStore`). On launch, `SnapNoteTokenStore.exists()` checks item existence with `kSecUseAuthenticationUISkip` and `kSecReturnData: false` so startup never triggers a Keychain password prompt. Tests use mock values.
- Remote and fallback audio streams are never written to disk.
- Speech application capture monitoring (`InputApplicationAudioMonitor`) uses CoreAudio process/device state; it does not read note or dictation text content.

After changing bundle identifiers, signing, or helper packaging, previously granted macOS privacy permissions may need to be granted again in System Settings.

## Quick Note integration (Apple Notes & SnapNote)

The Quick Note page (`Sources/KKvoice/UI/SnapNoteView.swift`, `Sources/KKvoice/AppModel.swift`, `SnapNote/`) supports two providers (`QuickNoteProvider`):

1. **Apple Notes (`Apple 备忘录`, default)**: Requires no external setup; the helper activates `com.apple.Notes`, sends `⌘N`, types `#<tag>` (1–20 characters, defaulting to `"闪念"`), and inserts a newline so the note body is focused for immediate voice dictation.
2. **SnapNote (`闪念笔记`)**: Connects to the user-configured MCP endpoint and port (`snapNoteMCPEndpoint` / `snapNoteMCPPort`, defaulting to `http://127.0.0.1:31090/snapnote/data-source/mcp`), triggers the new-note shortcut, verifies the newly created note, and writes the custom tag (`snapNoteTagName`) with full helper cancellation acknowledgements (`cancel_snapnote_action` / `snapnote_action_cancelled`). `SnapNote/INTEGRATION.md` documents the security boundaries and protocol contract.

## Hardware validation checklist

- Confirm the bundled `KKvoice Mic` input is installable and uninstallable from inside the app, selectable in Doubao Input Method and Vokie, and receives continuous remote or fallback input device audio.
- Verify speech-app cancel/stop detection and repeated remote (tap/hold) and keyboard wake/cancel cycles.
- Test supported remote models, sleep/wake, Bluetooth reconnect, and macOS permission recovery.
- Confirm login item and menu-bar lifecycle on a clean account.

Do not mark these scenarios verified based only on unit tests.
