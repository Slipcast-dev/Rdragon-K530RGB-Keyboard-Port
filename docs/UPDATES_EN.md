[Русский](UPDATES_RU.md) | **English**

# K530 Lighting automatic updates

## Access to releases

The repository is private. `AppUpdater` accesses the GitHub API and release assets through URLSession without authentication, so the current implementation cannot retrieve private releases. Install those updates manually from Releases using an account with access. A 404 response does not establish that no new private release exists.

An Ed25519 signature authenticates an archive but does not grant access to GitHub. Never embed the owner's access token in the `.app`. Automatic delivery would require a separately configured channel accessible to the client, or user authentication; the current code implements neither. Repository visibility is a separate decision for its owner.

## Behavior

`AppUpdater` checks the latest stable GitHub Release 30 seconds after launch, then every 6 hours. Network operations run in the background. A newer tag, such as `v0.4.0`, prompts with “Скачать” (Download) and “Позже” (Later). Later postpones the prompt for one day; a manual check ignores that postponement. Keyboard settings remain unchanged during the check.

After consent: verify the manifest signature → download with a percentage when the server reports its size → verify SHA-256 → extract → verify the bundle and code signature → install → launch the new version and quit the old process. Stages without a known percentage show an indeterminate indicator and operation text. Additional checks during a download are prevented.

If the trusted key is missing, an explanation is displayed and the release page is opened for manual installation. Unsigned updates are not installed automatically. There is no privilege elevation: the application folder must be writable by the user. Updates cannot be installed from App Translocation; move the application to Applications first.

## Architecture

`tools/k530menu/Sources/AppUpdater.swift` uses Foundation URLSession, Combine, AppKit, and CryptoKit, all system libraries. The interface observes `message`, `progress: Double?`, and `isBusy`; it calls `start()` once and `checkManually()` from the menu command. The archive's SHA-256 is included in an Ed25519-signed manifest. The public key is stored in the installed trusted build's resources; only the release machine needs the private key.

Installation does not change firmware or delete local profiles in Application Support. Normal quitting is blocked during downloading and installation; successful replacement permits the intentional quit used for restart. The old bundle is retained beside the application as a hidden `.K530Lighting-backup-UUID.app`. A failed move or launch command restores the old bundle. Success from `/usr/bin/open -n` confirms that macOS accepted the launch request, not that the new version cannot crash afterward. If it does crash, the backup `.app` can be launched manually. The user removes backup versions after verifying the update.

## Packaging the current 0.4.0 release

From the repository root:

```sh
./tools/k530menu/package.sh
```

The script runs a universal build, verifies the bundle signature, and creates `dist/K530Lighting-0.4.0-macOS-universal.dmg` containing the application and an Applications link. It also creates the update ZIP, `SHA256SUMS`, `update.json`, and `update.json.sig`. The manifest signature is checked with the public key from the built application. Missing or mismatched keys abort the release; existing final artifacts are not replaced with unsigned files.

By default, the private key is read from `~/Library/Application Support/K530Lighting/ReleaseKeys/update-signing.key`; override the path with `K530_UPDATE_PRIVATE_KEY`. `SWIFT_MODULECACHE_PATH` selects the Swift module cache. The private key is never included in archives. `dist/` and `.build/` are excluded from Git.

Packaging is local and does not publish the files: the manifest URL becomes usable only after the files are attached to the stable GitHub Release `v0.4.0`. Automatic updates need the ZIP; the DMG is for manual installation.

## Preparing signed releases

1. Generate the keys once on the release machine, placing the private key outside the repository:

   ```sh
   swiftc -module-cache-path /tmp/k530-sign-cache -framework CryptoKit tools/k530menu/Updates/SignUpdate.swift -o /tmp/k530-sign-update
   /tmp/k530-sign-update keygen /защищённый/путь/k530-update.key tools/k530menu/UpdatePublicKey.txt
   ```

   Replace `/защищённый/путь/` with your secure private-key directory.

2. Keep the private file, with mode `0600`, in secure storage and a protected backup. Never publish or commit it. Include the public `UpdatePublicKey.txt` in the trusted build's source and copy it into `Contents/Resources/UpdatePublicKey.txt`. Losing the private key requires manually distributing a new trusted build.
3. Build the application with increased `CFBundleShortVersionString` and numeric `CFBundleVersion` values. The manifest version must match the GitHub tag without `v`; the build number must strictly increase. Put `K530Lighting.app` at the root of the ZIP:

   ```sh
   ditto -c -k --sequesterRsrc --keepParent tools/k530menu/.build/K530Lighting.app K530Lighting-0.4.0-macOS-universal.zip
   shasum -a 256 K530Lighting-0.4.0-macOS-universal.zip
   ```

4. Create `update.json` with the real SHA-256 and the archive URL for the intended release:

   ```json
   {
     "version": "0.4.0",
     "build": 7,
     "archive": "https://github.com/Slipcast-dev/Rdragon-K530RGB-Keyboard-Port/releases/download/v0.4.0/K530Lighting-0.4.0-macOS-universal.zip",
     "sha256": "REPLACE_WITH_64_HEXADECIMAL_CHARACTERS",
     "minimumSystemVersion": "11.0"
   }
   ```

5. Sign the exact JSON bytes. Do not edit the JSON after signing:

   ```sh
   /tmp/k530-sign-update sign /защищённый/путь/k530-update.key update.json update.json.sig
   ```

6. Attach the ZIP, `update.json`, and `update.json.sig` to the same stable GitHub Release. A public key attached to a release is not a trust source: the client uses only the key already included in the installed application.

The archive must contain one universal application for both architectures; the updater does not select separate arm64/x86_64 assets. Downloads are limited to 250 MB. The application signature is checked using `codesign --verify --deep --strict`. Ad-hoc signing is accepted because a separate trusted Ed25519 signature authenticates the entire archive. Updating an ad-hoc-signed application may require granting Input Monitoring permission again. Developer ID signing and notarization are needed for a stable permission identity.

## Checks

```sh
swiftc -module-cache-path /tmp/k530-tests-cache -framework CryptoKit tools/k530menu/Sources/AppLocalization.swift tools/k530menu/Sources/AppUpdater.swift tools/k530menu/Tests/UpdaterTests.swift -o /tmp/k530-updater-tests
/tmp/k530-updater-tests
```

The test covers a valid signature, changed bytes, a foreign key, prohibited URLs, build-number rollback, SHA-256 format, and an incompatible macOS version. Before publication, separately test the complete cycle using two locally signed test releases: Later, downloading, network interruption, damaged ZIP, unwritable directory, successful replacement, restart, and renewed input permission. These integration scenarios do not automatically replace the user's working application.

Signature verification reference: [Apple CryptoKit](https://developer.apple.com/documentation/cryptokit/curve25519/signing/publickey/isvalidsignature(_:for:)). Guidance on trusted update signatures: [Sparkle documentation](https://sparkle-project.org/documentation/).

## Release-key storage

The public key already exists at `tools/k530menu/UpdatePublicKey.txt` and is included automatically by the build script. The default private-key path on the release machine is `~/Library/Application Support/K530Lighting/ReleaseKeys/update-signing.key`, with mode `0600`. Make a protected backup before moving release work to another computer. Do not run `keygen` again for an existing update chain.
