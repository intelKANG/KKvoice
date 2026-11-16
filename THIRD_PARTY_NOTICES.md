# Third-party sources and notices

## 1. BlackHole (`KKvoiceMic.driver`)

The bundled `KKvoice Mic` virtual audio HAL driver (`KKvoice.app/Contents/Resources/KKvoiceMic.driver`) is built directly from upstream [ExistentialAudio/BlackHole](https://github.com/ExistentialAudio/BlackHole) source code:

- **Upstream repository**: <https://github.com/ExistentialAudio/BlackHole>
- **Pinned upstream version / tag**: `v0.6.1`
- **License**: GNU General Public License v3.0 (`GPL-3.0`), included at `Driver/LICENSES/BlackHole-GPL-3.0.txt`, `KKvoice.app/Contents/Resources/BlackHole-GPL-3.0.txt`, and `KKvoice.app/Contents/Resources/KKvoiceMic.driver/Contents/Resources/LICENSE`.
- **Build-time customization defines (`GCC_PREPROCESSOR_DEFINITIONS`)**:
  - `DEBUG=0`
  - `kNumber_Of_Channels=2`
  - `kSampleRates=48000`
  - `kPlugIn_BundleID="local.kkvoice.mic.driver"`
  - `kDriver_Name="KKvoiceMi"` (produces device UID `KKvoiceMi2ch_UID` and model UID `KKvoiceMi2ch_ModelUID`)
  - `kDevice_Name="KKvoice Mic"`
  - `kDevice2_Name="KKvoice Mic 2"`
- **Info.plist customizations**:
  - `CFBundleIdentifier = local.kkvoice.mic.driver`
  - `CFBundleName = KKvoice Mic`
  - `CFPlugInFactories` / `CFPlugInTypes` factory UUID = `813EAA21-8D32-4A84-86D7-5C8C68D8F078` (`BlackHole_Create`)
- **Corresponding source**: The complete corresponding source code for `KKvoiceMic.driver` consists of the unmodified upstream `ExistentialAudio/BlackHole` source tree at tag `v0.6.1` together with our build script `Driver/build-blackhole-driver.sh` in this repository.

> **Note on `Driver/build-driver.sh` (local development only)**: The legacy script `Driver/build-driver.sh` binary-patches a locally installed `vRemoteDriver.driver` for local development convenience only. Its output is **never** bundled into `KKvoice.app` or redistributed in releases.

---

## 2. Native helper (`KKvoiceRemoteHelper`)

KKvoice includes a native helper copied from the user's existing Chromecast Voice Remote Vokie plugin working copy and subsequently modified. Its snapshot provenance and original Git commit are recorded in `Native/Helper/SOURCE.md`. The plugin credits [vRemoter](https://github.com/VincentKingHsu/vRemoter) for public Chromecast Voice Remote and ATVV protocol research, as well as [fanxeon/mi-ao](https://github.com/fanxeon/mi-ao) and [b0o/ATVVoice](https://github.com/b0o/ATVVoice). No affiliation is implied.
