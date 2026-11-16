# Development Guide

## Architecture & repository boundaries

- `Sources/KKvoice`: SwiftUI settings window, menu-bar controller, audio source router (`AudioSourceRouter`), in-app driver installer (`DriverInstaller`), keyboard settings, button mappings, Vokie capture monitor, and orchestration.
- `Native/Helper`: Objective-C background process for Bluetooth discovery, Chromecast ATVV, remote buttons, keyboard event listening, and JSON-line IPC (`Native/Helper/SOURCE.md` records helper provenance).
- `Session`: deterministic capture state machine, shortcut relay, and physical-key coordination.
- `Audio`: CoreAudio output to the explicitly selected virtual device, Mac microphone fallback relay, PCM conversion, buffering, and session isolation.
- `SnapNote`: local MCP client, Keychain token store, action coordinator, and helper cancellation adapter.
- `Driver`: BlackHole-based `KKvoice Mic` HAL driver build script (`Driver/build-blackhole-driver.sh`), legacy local-dev patch script (`Driver/build-driver.sh`), and privileged installer.
- `*Tests` and `Tests/KKvoiceTests`: hardware-free regression tests.

Keep the remote protocol in the helper process and keep state transitions in the hardware-independent `Session` module. Do not move CoreAudio callbacks, BLE callbacks, or keychain access onto real-time audio or event-tap paths. Preserve third-party notices and do not commit credentials, personal notes, build products, local app bundles, or signing material.

The app sends JSON-line commands to `KKvoiceRemoteHelper`. Keep command ordering serialized. The helper does not attach remote session identifiers to all BLE events, so the coordinator must reject stale events and release capture idempotently.

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

`Scripts/build-helper.sh` compiles an arm64/x86_64 Objective-C helper with the macOS 12 deployment target. `Scripts/build-app.sh` runs that build, compiles the Swift package in release mode, copies the icon, helper, and (when built from BlackHole source) `KKvoiceMic.driver` into `dist/KKvoice.app`, and applies an ad-hoc signature. Do not treat this signature as suitable for notarized distribution or as stable TCC identity across signing changes.

## Audio driver

The app routes remote PCM (or fallback Mac microphone audio) to the selected virtual device's output side. The virtual device exposes that signal as an input to Vokie and other speech applications. KKvoice expects 48 kHz stereo packed Float32 output and sends 16 kHz mono remote PCM through its bounded buffer.

For releases, `Driver/build-blackhole-driver.sh` builds `KKvoiceMic.driver` directly from upstream [BlackHole](https://github.com/ExistentialAudio/BlackHole) source (GPLv3) with custom identifiers (`KKvoice Mic`, UID `KKvoiceMi2ch_UID`) and bundles it into `KKvoice.app/Contents/Resources/` for one-click in-app installation via `DriverInstaller`.

Legacy local-development script: `Driver/build-driver.sh` copies a locally installed `/Library/Audio/Plug-Ins/HAL/vRemoteDriver.driver` and binary-patches the copy to create `KKvoice Mic`. That script is for local development only and its output must **never** be redistributed in releases.

`Scripts/install-audio-driver.sh` stages a copy in `/tmp`, asks macOS for administrator authorization, installs the driver, and restarts Core Audio. This changes system-wide audio inventory and may require selecting the new input again in speech software. Do not remove the timestamped previous-driver backups without explicit reason.

## Permissions and privacy

- Bluetooth permission is required to pair and communicate with a remote.
- Input Monitoring is required for global physical keyboard shortcuts.
- Accessibility is used by the helper for supported system-level key behavior.
- SnapNote tokens are stored only in the user's Keychain. Tests use mock values.
- Remote audio is not written to disk. The app outputs the remote stream to the selected virtual device.
- Vokie capture monitoring uses CoreAudio process/device state; it does not read Vokie note content.

After changing bundle identifiers, signing, or helper packaging, previously granted macOS privacy permissions may need to be granted again in System Settings.

## SnapNote integration caveat

The implementation now exists in `KKvoiceApp.swift` and `SnapNote/`, but `SnapNote/INTEGRATION.md` describes the original planned contract and some statements there are stale. Treat source and tests as current behavior; review and update that document before relying on it as a specification. SnapNote note-focus and speech-software end-to-end behavior requires real-app testing.

## Hardware validation still needed

- Confirm the new `KKvoice Mic` input is selectable and receives continuous remote audio in Vokie.
- Verify Vokie cancel/stop detection and repeated keyboard wake/cancel cycles.
- Test supported remote models, sleep/wake, Bluetooth reconnect, and macOS permission recovery.
- Confirm login item and menu-bar lifecycle on a clean account.

Do not mark these scenarios verified based only on unit tests.
