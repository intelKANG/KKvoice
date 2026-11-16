# KKvoice

KKvoice is a native macOS companion for supported Chromecast voice remotes. It relays the remote microphone to a selectable virtual audio input, lets a physical keyboard shortcut wake the remote, and maps remote buttons to macOS actions. It also includes an optional SnapNote integration.

This repository is the complete application source and build guide. Runtime credentials are kept in the macOS Keychain and are not part of the project.

## Requirements

- macOS 12 or later; macOS 13 or later for the built-in login item setting.
- Xcode Command Line Tools with Swift, Clang, and Apple SDKs.
- A supported Chromecast voice remote paired with the Mac.
- A compatible virtual audio device with 48 kHz, stereo, Float32 output. KKvoice can use `KKvoice Mic` or existing BlackHole-compatible devices.
- The helper needs Bluetooth, Accessibility, and Input Monitoring permissions for the relevant features.

## Build and run

```sh
swift test
./SessionTests/run.sh
./AudioTests/run.sh
./NativeTests/run.sh
./KeyboardTests/run.sh
./SnapNoteTests/run.sh
./Scripts/build-app.sh
open dist/KKvoice.app
```

`build-app.sh` compiles the universal helper and release Swift app, bundles the app icon and helper, then ad-hoc signs the local app. This is a local development build, not a Developer ID or notarized release.

## KKvoice Mic virtual driver

The app can use an existing compatible virtual device. To build the optional `KKvoice Mic` HAL driver, `Driver/build-driver.sh` currently requires the vRemoter-derived driver to be installed at:

```text
/Library/Audio/Plug-Ins/HAL/vRemoteDriver.driver
```

It copies that driver into `.build/KKvoiceMic.driver`, assigns separate bundle/factory/device identifiers, and patches the display name. It does not modify the installed vRemote driver. After inspecting the local build, install with:

```sh
./Scripts/install-audio-driver.sh
```

macOS prompts for administrator authorization and restarts Core Audio. The installer preserves any prior KKvoice Mic driver as a timestamped backup. Choose `KKvoice Mic` again in Vokie or another input app after installation. The binary-patching method depends on a local vRemote driver binary and is not a clean-room source build; public redistribution requires reviewing the upstream licenses and notices in `THIRD_PARTY_NOTICES.md`.

## Architecture

- `Sources/KKvoice`: AppKit settings window, menu-bar item, keyboard settings, button mappings, Vokie capture monitor, and orchestration.
- `Native/Helper`: Objective-C background process for Bluetooth discovery, Chromecast ATVV, remote buttons, keyboard event listening, and JSON-line IPC.
- `Session`: deterministic capture state machine, shortcut relay, and physical-key coordination.
- `Audio`: CoreAudio output to the explicitly selected virtual device, PCM conversion, buffering, and session isolation.
- `SnapNote`: local MCP client, Keychain token store, action coordinator, and helper cancellation adapter.
- `Driver`: optional locally built KKvoice Mic driver and privileged installer.
- `*Tests` and `Tests/KKvoiceTests`: hardware-free regression tests.

Read `DEVELOPMENT.md` before changing architecture, the helper protocol, driver identifiers, permissions, or the SnapNote action flow. `Native/Helper/SOURCE.md` records helper provenance. Preserve third-party notices and do not commit credentials, personal notes, build products, local app bundles, or signing material.

## Acknowledgements

- [BlackHole](https://github.com/ExistentialAudio/BlackHole) provides the basis for the virtual audio driver.
- [vRemoter](https://github.com/VincentKingHsu/vRemoter) informed the remote and audio-driver compatibility work.

See `THIRD_PARTY_NOTICES.md` for source provenance and license notes.
