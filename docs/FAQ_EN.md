[Русский](FAQ_RU.md) | **English**

# Frequently asked questions

The application interface is currently in Russian. English action names below are explanations; the Russian labels identify the buttons you will see.

## What is this application?

K530 Lighting 0.3.2 is a macOS menu bar application for controlling Redragon K530 RGB lighting (USB `0C45:5004`). It is unofficial and is not affiliated with Redragon. It does not modify firmware, macros, or key mappings.

## What do I need?

- A Mac running macOS 11 or later.
- A K530 RGB connected with a USB cable. Bluetooth control is not supported.
- Input Monitoring permission for the installed copy of the application.

## How do I install it?

1. Open `dist/K530Lighting-0.3.2-macOS-universal.dmg` or the downloaded disk image for that release.
2. Quit the running copy: right-click the menu bar icon and choose “Завершить K530 Lighting” (Quit K530 Lighting).
3. Drag `K530Lighting.app` to Applications, eject the disk image, and launch the installed copy from Applications.
4. The build is ad-hoc signed and is not notarized. On first launch, use macOS's normal Open action for an application you trust; do not disable system protections.

For ZIP distributions, extract the archive and move the `.app` to Applications. Do not run multiple copies from different folders at the same time.

## The application opens, but the keyboard does not connect

If the panel says “Нужен доступ к клавиатуре” (Keyboard access required), use the permission section:

1. Click “Открыть настройки” (Open Settings), then go to Privacy & Security → Input Monitoring.
2. Enable K530Lighting. If an entry from an older build remains, remove it and add the current `.app` using “+”.
3. “Показать эту .app” (Show this .app) selects the running copy in Finder. Add that copy, rather than an older copy in Downloads.
4. Click “Перезапустить” (Restart), or fully quit and reopen the application.

Permission may need to be granted again after an ad-hoc rebuild. The application cannot grant itself permission. If the system link does not open the correct section, navigate there manually.

## Where is the window, and how does the icon work?

Left-clicking the icon opens the panel. Right-clicking opens a menu for showing or closing the panel, profiles, quick settings, updates, and quitting. The application appears in the Dock while its main window is open. Closing the main window with the red button, Command+W, or “Закрыть окно” (Close Window) removes its Dock icon; the process continues running in the menu bar. Reopening the panel restores the Dock icon. After choosing “Завершить K530 Lighting”, launch the application from Finder or Applications again: a terminated process has no menu bar icon.

## How do I control lighting?

Choose an effect, color, brightness, and speed, then click “Применить” (Apply), or press Command+Enter. Panel sliders change a local draft; moving them does not write to the device. Context menu commands marked “— применить” (apply) immediately write the selected effect or brightness. A saved status appears only after the values read back from the keyboard have been checked.

Brightness has levels 0–4, where 0 turns lighting off. Speed is displayed as 1–5. “Вернуть исходное” (Restore Initial State) restores the state captured by the first successful read in the current session. The automatic backup is stored in `~/Library/Application Support/K530Lighting`.

## How do I save different profiles?

Click “Профили” (Profiles) in the bottom action row beside “Вернуть исходное” and “Применить”. Select a set, edit its settings, and save it. You can create, rename, and delete local sets. Separate unsaved drafts survive switching between profiles until the application quits; use the save button to retain them between launches.

Profiles are stored on this Mac in `~/Library/Application Support/K530Lighting/profiles.json`. Selecting a set loads it into the panel; “Применить” sends its settings to the keyboard. These are application profiles: they do not select the keyboard's active internal profile. Applying a set writes identical settings to all three hardware profiles, as before.

## Why does the color not change?

Modes 1–3, 5–10, and 13–16 use the selected color. Modes 4, 11, 12, 17, 18, and 20 have their own palettes: color selection is disabled with an explanation. The preview shows the overall color, rather than the exact hardware animation.

## The keyboard is not found even though permission is enabled

Check the USB cable, port, and connection mode. In `system_profiler SPUSBDataType`, the device may be named Draconic; the expected identifiers are `0x0c45:0x5004`. A different hardware revision may need different support. Choose “Перечитать устройство” (Read Device Again) in the settings menu.

## How do updates work?

The repository is currently private. The application accesses GitHub without authentication and cannot retrieve private releases. Download updates manually from Releases while signed in to an account with access. The application contains no access tokens. A signed archive does not itself grant access to private files.

The automatic cycle described below is available when the release is accessible to the client at the configured HTTPS URLs.

The latest stable release is checked 30 seconds after launch and every 6 hours. A manual check is also available. “Скачать” (Download) starts authenticity verification, downloading, installation, and restart; “Позже” (Later) postpones the prompt for one day. The bottom status row shows the current stage, and a separate indicator shows download progress.

Only archives with a valid signature and checksum are installed automatically. The application folder must be writable by the user. If installation in the system Applications folder is unavailable, use `~/Applications`; the updater does not automatically request administrator privileges. See [the update guide](UPDATES_EN.md).

## Does it work on Apple Silicon?

The application is built for Intel and Apple Silicon. Historical hardware lighting checks were performed on Intel; a complete hardware test matrix for both architectures is still needed. Including an arm64 binary does not by itself confirm execution on Apple Silicon.

## How do I uninstall it?

Disable launch at login, choose “Завершить K530 Lighting”, and delete the `.app`. Optionally remove its Input Monitoring entry. Local profiles and backups are stored in `~/Library/Application Support/K530Lighting`; save anything you need before deleting it. On the release machine, the `ReleaseKeys` folder contains the private update-signing key. Losing that key interrupts the existing signed update chain.

## Where should I report problems?

Open an issue in the repository. Include the application and macOS versions, Mac model, USB identifiers, and full status text. Hover over a truncated status message to see its full text.
