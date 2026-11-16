# Development Guide

## Architecture & repository boundaries

- `Sources/KKvoice`: SwiftUI settings window (`macOS 13.0+`), menu-bar controller, audio source router (`AudioSourceRouter`), in-app driver installer (`DriverInstaller`), native GitHub Releases updater (`AppUpdater`), keyboard settings, button mappings, Vokie capture monitor, and orchestration.
- `Native/Helper`: Objective-C background process for bounded Bluetooth discovery & zero-power passive standby (`remote_standby`), HID wake-on-keypress reconnect, Chromecast ATVV, remote buttons, keyboard event listening, and JSON-line IPC (`Native/Helper/SOURCE.md` records helper provenance).
- `Session`: deterministic capture state machine, shortcut relay, and physical-key coordination.
- `Audio`: CoreAudio output to the explicitly selected virtual device, Mac microphone fallback relay, PCM conversion, buffering, and session isolation.
- `SnapNote`: local MCP client, Keychain token store, action coordinator, and helper cancellation adapter.
- `Driver`: BlackHole-based `KKvoice Mic` HAL driver build script (`Driver/build-blackhole-driver.sh`), legacy local-dev patch script (`Driver/build-driver.sh`), and privileged installer.
- `*Tests` and `Tests/KKvoiceTests`: hardware-free regression tests (33 XCTest unit tests in `Tests/KKvoiceTests` plus 5 standalone `*Tests/run.sh` suites).

Keep the remote protocol in the helper process and keep state transitions in the hardware-independent `Session` module. Do not move CoreAudio callbacks, BLE callbacks, or keychain access onto real-time audio or event-tap paths. Preserve third-party notices and do not commit credentials, personal notes, build products, local app bundles, or signing material.

The app sends JSON-line commands to `KKvoiceRemoteHelper`. Keep command ordering serialized. The helper does not attach remote session identifiers to all BLE events, so the coordinator must reject stale events and release capture idempotently.

## Bluetooth discovery & zero-power standby

`KKvoiceRemoteHelper` uses bounded active BLE discovery windows combined with kernel-driven `IOHIDManager` passive wakeup:

- On first-time pairing (`60s`), startup when a known remote exists (`15s`), HID wakeup (`10s`), disconnect (`6s`), or manual UI scan (`{"type": "scan_remote", "duration": 60}`), the helper polls `retrievePeripheralsWithIdentifiers` (using the persisted `lastChromecastPeripheralUUID`) and `retrieveConnectedPeripheralsWithServices` (`@[ATVVServiceUUID, @"1812", @"180A", @"180F", @"1800"]`) every `2.0s`, and runs unfiltered BLE advertisement scanning `scanForPeripheralsWithServices:nil` (`CBCentralManagerScanOptionAllowDuplicatesKey: @NO`) with strict `"Chromecast Remote"` name matching so 31-byte pairing advertisements are captured immediately without matching unrelated ATVV remotes.
- If the window expires without finding the remote, the helper stops `discoveryTimer` and calls `[central stopScan]`, emitting `{"type": "remote_standby"}` so the Mac consumes **zero background BLE scan power** when away from the remote.
- As soon as the remote wakes up nearby (matching `HIDDeviceMatchedCallback` / `hid_connected` or delivering any HID button report while `peripheral == nil`), the helper immediately reconnects the known peripheral or opens a `10.0s` discovery window on the main queue.
- `AppModel` persists `hasEverConnectedRemote` in `UserDefaults`: new Macs (`hasEverConnectedRemote == false`) display the first-time Bluetooth pairing bar (`同时长按「← + 🏠」3 秒`), while returning users away from their remote (`hasEverConnectedRemote == true`) see a calm offline standby state (`遥控器离线 · 当前使用 Mac 麦克风 · 按遥控器任意键自动重连`).

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

## Audio driver

The app routes remote PCM (or fallback Mac microphone audio) to the `KKvoice Mic` (`KKvoiceMi2ch_UID`) virtual device's output side. The virtual device exposes that signal as an input to Vokie and other speech applications. KKvoice expects 48 kHz stereo packed Float32 output and sends 16 kHz mono remote PCM (or resampled Mac microphone PCM) through its bounded buffer.

For builds and releases, `Driver/build-blackhole-driver.sh` compiles `KKvoiceMic.driver` directly from upstream [BlackHole](https://github.com/ExistentialAudio/BlackHole) `v0.6.1` source (GPLv3) with custom identifiers (`KKvoice Mic`, UID `KKvoiceMi2ch_UID`) and bundles it into `KKvoice.app/Contents/Resources/` for automatic launch detection and one-click in-app installation via `DriverInstaller`.

Legacy local-development script: `Driver/build-driver.sh` copies a locally installed `/Library/Audio/Plug-Ins/HAL/vRemoteDriver.driver` and binary-patches the copy to create `KKvoice Mic`. That script is for historical local development only and its output must **never** be bundled or redistributed in releases.

`Scripts/install-audio-driver.sh` is an optional CLI installer that stages a copy in `/tmp`, asks macOS for administrator authorization, installs the driver, and restarts Core Audio. Do not remove the timestamped previous-driver backups without explicit reason.

## Permissions and privacy

- **Bluetooth** permission is required to pair and communicate with a remote.
- **Input Monitoring** is required for global physical keyboard shortcuts and remote button events.
- **Accessibility** is used by the helper for supported system-level key behavior.
- **Microphone** permission is required only when using a physical Mac microphone as the automatic fallback source while the remote voice channel is not ready. **No microphone is ever captured while idle**; `AudioSourceRouter` / `MacMicrophoneSource` opens the selected Mac microphone only during an active keyboard-triggered recording session, streams directly to `KKvoice Mic` without writing to disk, and stops and zeroes buffers immediately when the session ends or is cancelled.
- **SnapNote tokens** are stored only in the user's Keychain (`SnapNoteTokenStore`). On launch, `SnapNoteTokenStore.exists()` checks item existence with `kSecUseAuthenticationUISkip` and `kSecReturnData: false` so startup never triggers a Keychain password prompt. Tests use mock values.
- Remote and fallback audio streams are never written to disk.
- Vokie capture monitoring uses CoreAudio process/device state; it does not read Vokie note content.

After changing bundle identifiers, signing, or helper packaging, previously granted macOS privacy permissions may need to be granted again in System Settings.

## SnapNote integration

The current implementation lives in `Sources/KKvoice/KKvoiceApp.swift`, `Sources/KKvoice/AppModel.swift`, `Sources/KKvoice/UI/SnapNoteView.swift`, and `SnapNote/` (with tests in `SnapNoteTests/`). It supports user-customizable tag names (`snapNoteTagName`, 1–20 characters, defaulting to `"闪念"`) and full helper cancellation acknowledgements (`cancel_snapnote_action` / `snapnote_action_cancelled`). `SnapNote/INTEGRATION.md` documents the security boundaries and protocol contract.

## Hardware validation checklist

- Confirm the bundled `KKvoice Mic` input is installable from inside the app, selectable, and receives continuous remote or fallback Mac microphone audio in Vokie.
- Verify Vokie cancel/stop detection and repeated keyboard wake/cancel cycles.
- Test supported remote models, sleep/wake, Bluetooth reconnect, and macOS permission recovery.
- Confirm login item and menu-bar lifecycle on a clean account.

Do not mark these scenarios verified based only on unit tests.
