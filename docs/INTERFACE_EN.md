[Русский](INTERFACE_RU.md) | **English**

# K530 Lighting 0.4.0 interface

The application interface and built-in help support Russian and English; this is the English developer guide.

## Architecture

- `main.swift`: AppKit window, readable title, menu bar icon, context menu, and USB notifications.
- `LightingView.swift`: SwiftUI panel, consistently sized main buttons, compact ANSI 60% diagram, and pinned bottom status row. Long messages are truncated; tooltips expose their full text.
- `LightingSettings.swift`: draft settings, HEX validation, and conversion from UI speed 1–5 to protocol values 4–0.
- `LightingProfileStore.swift`: named local profiles in versioned JSON.
- `LightingProfilesView.swift`: selection, saving, and management of settings sets.
- `StatusMenuController.swift`: icon context menu and quick actions.
- `LightingController.swift`: panel state, profile drafts, launch at login, and serial HID service.
- `AppUpdater.swift`: background updates, authenticity checks, installation, and restart; see [the release guide](UPDATES_EN.md).
- `FaqWindowController.swift`: built-in help.

The target platform is macOS 11+, Intel and Apple Silicon. No external libraries are required. SwiftUI is embedded in AppKit through NSHostingView; see [Apple documentation](https://developer.apple.com/documentation/swiftui/nshostingview). The preview shows the overall color and does not simulate hardware animations.

## Localization

`AppLocalization.swift` stores the selected language in UserDefaults (`interfaceLanguage`): `ru` or `en`, with Russian as the default. `AppText` keeps both versions of messages so existing status can change language. SwiftUI observes the shared language object; native menus and open help refresh on the language-change notification. Lighting settings and saved user profile names are unchanged.

The RU/EN button sits beside the gear; both use the same style and measure 36 × 36. The bundle includes `FAQ_RU.md` and `FAQ_EN.md`, selected explicitly using the application language.

## Using the panel

1. Open the application or left-click its menu bar icon.
2. Connect the K530 over USB. Grant Input Monitoring permission and restart if necessary.
3. Select a settings set in “Profiles”. Change the effect, color, and levels; press Enter to confirm HEX input.
4. Save settings to the selected local profile. Saving does not write to the keyboard.
5. Click “Apply”, or press Command+Enter. A saved-to-keyboard confirmation appears only after writing and reading back the values.
6. “Restore Initial State” restores the first eight bytes of the hardware profiles captured by the first successful connection in the current session. A backup is saved to disk before the first write.

Sliders and the palette change the draft, rather than the device. Effects with their own palettes disable color selection. The gear menu provides device rereading, launch at login, updates, restart, help, and quit.

## Application profiles

The “Profiles” button is in the bottom action row beside “Restore Initial State” and “Apply”. Its popover uses a graphite background, cyan accents, custom buttons, and a text field. `preferredColorScheme(.dark)` gives the entire presentation a dark appearance, including when macOS uses a light theme.

A profile is a named set of mode, brightness, speed, and color settings. Sets are stored in `~/Library/Application Support/K530Lighting/profiles.json`; users can select, save, rename, create, and delete them. Separate profile drafts remain in memory when switching; only saved versions are written to disk. Save changes you need before quitting.

These are **local application profiles**, not a selector for the K530's active internal profile. Applying a set retains the previously verified write behavior: identical settings are written to all three hardware profiles. The active-hardware-profile selection command has not been recovered and is not used.

JSON read or validation errors are displayed to the user. A damaged file must not be silently replaced with defaults.

## Menu bar icon and Dock

Showing the main window sets `NSApplication.ActivationPolicy.regular`, so the application appears in the Dock. Closing that window with the red button, Command+W, or “Close Window” switches the policy to `accessory`: the Dock icon disappears while the application remains in the menu bar. Minimizing is not closing. Reopening the panel restores regular mode.

“Input Monitoring…” has been removed from the drop-down menus. The button opening system settings remains in the missing-permission section.

- Left-click opens the panel.
- Right-click opens the context menu: show/close the panel, choose a profile, quick lighting parameters, apply, updates, and quit.
- “Effect — apply” and “Brightness — apply” immediately write the changed settings and verify the result. Selecting a profile only loads it; use “Apply Selected Profile” to write it. Quick hardware changes do not automatically save the local profile to disk.

The icon remains available while the application process runs. After quitting, launch the `.app` from Finder or Applications again.

## Device communication

HID work runs on a serial queue. Each session is created and closed within one task on one thread, keeping its callback attached to the correct CFRunLoop. The UI does not wait for USB replies. If the device disconnects, a stale operation result cannot restore a false connected status.

## Building and installing

```sh
./tools/k530menu/build.sh universal
open tools/k530menu/.build/K530Lighting.app
```

To create an installation disk image and update files:

```sh
./tools/k530menu/package.sh
```

Output is saved in `dist/` at the repository root. Open the DMG, drag the `.app` to Applications, eject the image, and launch the installed copy. Alternatively, `./tools/k530menu/build.sh universal install` copies a local build to `~/Applications`.

macOS and Command Line Tools are required. The default module cache is `.build/ModuleCache`; override it with `SWIFT_MODULECACHE_PATH` if needed. Builds are ad-hoc signed; macOS may require Input Monitoring permission again after an update.

## Checks without hardware

Run the automated suites, including localization checks:

```sh
./tools/k530menu/test.sh
```



Building and unit tests do not replace hardware acceptance checks: USB reconnection, permissions, effects, lighting off, writes, restore, sleep/wake, and relaunch must be tested on a real K530. Visual layout must also be checked separately on supported macOS versions.
