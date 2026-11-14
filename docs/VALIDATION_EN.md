[Русский](VALIDATION_RU.md) | **English**

# Checks and compatibility

## Current release

**0.3.2, build 6**, November 14, 2026. All four `test.sh` suites passed; local Markdown links were checked without errors. Universal building and packaging were completed: the application signature, DMG, version/build, x86_64 + arm64, checksums, and agreement between the embedded FAQ and the then-current documentation were checked. GitHub file publication is checked separately.

The published 0.3.2 installers embed the Russian help from their release commit. Later bilingual repository documentation does not rebuild those artifacts or localize the shipped interface or help. The checks above describe the original build, not a new build of the translated documentation.

## Automated checks

From the repository root:

```sh
./tools/k530menu/test.sh
```

The four suites cover:

| Suite | Coverage |
|---|---|
| `LightingSettingsTests` | HEX, valid values, and speed conversion |
| `LightingProfileStoreTests` | Saving, independent sets, validation, and preservation of damaged files |
| `LightingControllerProfileTests` | Draft switching, saving, relaunch, profile creation, and deletion |
| `UpdaterTests` | Trusted signatures, tampering, URLs, build numbers, and installation rollback |

Tests do not send commands to the keyboard or download releases. `package.sh` separately verifies the application signature, DMG, and manifest signature against the build's public key. Before publication, checksums, version/build, and the architectures of a copy extracted from the DMG are checked.

## Recorded compatibility

- Lighting was previously checked by a person on a K530 Draconic/Sonix `0C45:5004`, Intel/macOS: mode, brightness, and color. Evidence is retained in [research/device](../research/device/).
- The executable contains x86_64 and arm64 and targets macOS 11+. Including arm64 does not replace execution on real Apple Silicon hardware.
- The visible order of speed levels needs a separate hardware check.
- Bluetooth, macros, key remapping, and firmware operations are not supported.

## Manual acceptance checks

Check the following on supported Macs before a release:

- Light/dark system appearance, readable panel and profiles popover, and display scaling.
- Dock appearance when opening the panel, disappearance after closing, and reopening from the menu bar.
- Command+W for the main window and help, left/right icon clicks, and quick settings.
- Permission grant/denial, USB reconnection, sleep/wake, applying settings, and restoring initial state.
- The complete update cycle between two signed releases accessible to the client: postponement, download, network failure, installation, and live restart.

Unit tests do not establish that these acceptance checks passed. UI automation, new hardware writes, and the complete network update cycle were not performed while preparing the current documentation. For a private GitHub repository, the current unauthenticated client cannot retrieve releases; see [the update guide](UPDATES_EN.md).
