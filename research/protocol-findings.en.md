[Русский](protocol-findings.md) | **English**

# Redragon K530 USB HID protocol

Based on static analysis of the manufacturer's Windows software and subsequent checks on a K530 Draconic/Sonix `0C45:5004` (27 October 2026, Intel/macOS). Confirmed fields and historical analysis details are distinguished below. Other hardware revisions may differ.

Preserved evidence: [USB descriptors](device/k530-usb-descriptors.en.md), [first profile read](device/profiles-read-1.txt), and [visual color check by mode](device/color-scan-result.txt). These raw device records are preserved as captured, including their Russian annotations. The manufacturer's original binaries are not included.

The current implementation is in `tools/k530diag/Sources/k530diag/Protocol.swift`, `Session.swift`, and the application's HID service. Applying settings writes the first 8 bytes of each profile in one command: +0, +1, +2, and +4…+7 from the settings, and +3 rewritten with the value read from the keyboard. The local profile library does not switch the active hardware profile.

## How the code was obtained

The installer contains three embedded InstallShield files: `data1.cab` (521824 bytes, offset 741417), `data1.hdr` (23239 bytes, offset 1263281), and `data2.cab` (10648766 bytes, offset 1286563). Application files were in the `DefaultComponent` group and were extracted with `unshield` (commit feaa32f). This is the historical investigation method; these files are not needed to build the application.

## Transport

- HidServ.dll function table in the executable (VA 0x6E4FC8…): +4 hModule, followed by GetProcAddress entries in this order: Debug, Init, End, RequestGetDeviceCount, DeleteRequestFromUnitId, DeleteRequestFromHandle, RequestWrite, RequestWriteOne, RequestStatusWrite, RequestStatusGet, RequestAsyncRead, RequestStatusSetFeature.
- Packet transmission uses the function at VA `0x43FD90(buf, len, resp, resp_len, &status)`: it copies the command into a 64-byte buffer, zero-fills the remainder, sends it through `RequestWriteOne`, waits up to 1000 ms for a response, and retries up to 3 times on timeout or when response byte 3 differs from request byte 3. Response byte 7 of `0xFF`/`0xFE` means error/busy.
- The buffer is 64 bytes; byte 0 is `0x04`, Report ID 4 of the vendor collection `FF1C:0092` (interface 1 on the actual device, 63 data bytes). This agrees with the [captured descriptors](device/k530-usb-descriptors.en.md).

## Packet format (64 bytes)

| Byte | Meaning |
|---|---|
| 0 | `0x04` (Report ID) |
| 1–2 | Checksum: sum of bytes 3…63, 16-bit, low byte first |
| 3 | Command |
| 4 | Data length |
| 5–6 | Address, low byte first |
| 7 | Status: 0 in a request; `0xFF` or `0xFE` in a response means error |
| 8… | Data, up to 56 bytes |

## Commands found in the code

| Cmd | Function VA | Purpose |
|---|---|---|
| `0x01` | `0x440020` | Begin session, no data |
| `0x02` | `0x4400D0` | End session; 10 ms delay before transmission |
| `0x06` | `0x440FE0(data, len, addr)` | Write `len` bytes at `addr` |
| `0x05` | `0x4410B0(out, len, addr)` | **Read** `len` bytes from `addr`; response data begins at byte 8, up to 56 bytes |
| `0x17` | `0x440F00(data, len, idx)` | Block write; address = `profile*512 + idx*3`, where profile is the global at VA `0x6E0FA4`; called with len=54 for 8 blocks |

A typical write sequence is `01` → one or more `06`/`17` → `02`. Example (VA `0x418D21`): begin, write one byte `0x00` to `profile*42+15`, end.

## Profile layout and lighting (UI handler analysis)

A profile is a block at `profile*42`, where profile is the global variable at VA `0x6E0FA4`. Writes use `01 → 06 → 02`. The following fields were found in lighting button handlers (VA `0x41A930…0x41AD9E`, `0x41D040…0x41D439`, `0x41F2A0…0x41FECC`):

| Profile offset | Size | Meaning from the code | Confidence |
|---|---|---|---|
| +0 | 1 | **Lighting mode number**: 1–18 and 20; no 19. The `switch` uses the jump table at VA `0x41D054`, with 20 entries | High |
| +4 | 1 | Color flag: 0 selects the single color at +5…+7; nonzero means “Colourful.” The device has returned 255; the application writes 0 or 1 | High |
| +5…+7 | 3 | R, G, B color, using `COLORREF` byte order: R is the low byte | High |
| +1 | 1 | Brightness 0–4; 0 turns the lighting off | Confirmed by a person at the keyboard |
| +2 | 1 | Speed 0–4, displayed as 5–1 respectively in the application. Ordering inferred from the original slider | Requires separate visual hardware verification |
| +3 | 1 | 0 or 255 (VA `0x41F168`/`0x41F269`); purpose unknown | Low |
| +18 | 1 | 0 (VA `0x41FC8D…0x41FECC`); purpose unknown | Low |

Mode numbers and names (`Lang0409.ini`, `[MODE]`; names are machine translations from Chinese): 1 Go with the stream, 2 Clouds fly, 3 Winding paths, 4 The trial of light, 5 Breathing, 6 Normally on, 7 Pass without trace, 8 Ripple graff, 9 Fast run without trace, 10 Snow winter jasmine, 11 Flowers blooming, 12 Swift action, 13 Hurricane, 14 Accumulate, 15 Digital Times, 16 Both ways, 17 Surmount, 18 Fast and the Furious, 20 Coastal.

Changing a mode in the original program uses `01` → `06(data=[mode], len=1, addr=profile*42+0)` → `06(data=[flag], len=1, addr=profile*42+4)` → `02`. Example: mode 1, VA `0x41D062…0x41D0B2`.

Color example (VA `0x41A930`): three bytes `EB 63 1E` are written to `profile*42+5`, with flag +4 = 0.

## Reading profiles (original program loader, VA `0x42398C…0x4239CF`)

After checking the device (VA `0x440190`), the program performs `01 begin` → three `05` reads of **56 bytes** at addresses **0, 42, 84**, retaining the first 42 bytes of each → `02 end`. These are three 42-byte profiles. The loader uses +0 as the mode, +1/+2/+3 as numeric parameters, +4 as a flag (≠0 means “Colourful”), +5…+7 as the color (+5 is R), +15 (clamped to 3), +18, +19, and +24…+27 (a second color). This layout matches the addresses written by the UI handlers and supports the profile layout above.

Response validation (VA `0x43FD90`): response byte 3 equals the request command; byte 7 of `0xFF` or `0xFE` indicates an error. Response timeout is 1000 ms, with up to three attempts.

## Dangerous function: do not use

VA `0x441190` builds a packet containing `4, ?, ?, 0xEE, 0xEE` and sends it without waiting for a response (`0x43FF70`). It is called once by device-checking code (VA `0x43FCD3`). Its purpose is unknown: it may reset the device or enter a service mode. This command is absent from k530diag and must not be added without separate investigation.

## Still unknown

- The purposes of +3 and +18, the active hardware profile selection command, and the visual mapping of speed levels at +2.
- Which addresses are safe to write: writing to an incorrect address may corrupt keyboard profiles or macros.

## First read on the actual keyboard (27 October 2026)

`k530diag read-profile --send` was run; the result is in `research/device/profiles-read-1.txt`. The device responded to begin, three reads, and end without errors: **packet format, checksum, and addresses 0/42/84 were confirmed**. No writes were performed.

The first eight bytes match across all three profiles: `14 04 02 00 ff ff 00 00`. In the full block, profile 1 differs at +21, which is `02`.

| Offset | Value | Finding |
|---|---|---|
| +0 | 20 (0x14) | Mode 20 “Coastal,” in the known set 1–18, 20 |
| +1 | 4 | **Not** 21–25 as previously assumed: the original +1 hypothesis was wrong |
| +2 | 2 | Unknown at the time |
| +3 | 0 | Unknown |
| +4 | 255 | Not limited to 0/1: “Colourful” is tested as “≠ 0” |
| +5…+7 | `ff 00 00` | Red; when +4 is enabled, this color apparently is not used |
| +8 | 9 | Unknown |

This records the historical first-read state. A value alone does not confirm the visible effect or speed direction.

## First write (27 October 2026): command 0x06 and mode +0

`k530diag test-mode 6 --hold 10 --send` wrote +0 = 6 to all three profiles. Readback confirmed `[6, 6, 6]`; after 10 seconds, `[20, 20, 20]` was restored. According to the original experiment record, the full block matched the backup after restoration. One-off backup exports have been removed from the current tree; this is a historical record, not a new test. **Write acceptance and restoration were confirmed by readback.** Whether the visible lighting changed could not be established from the terminal; a person must check the keyboard.

## Brightness and color checked on the keyboard (27 October 2026)

Menu-bar application `tools/k530menu`, checked by a person at the keyboard:

- **Mode** (+0): works, confirmed.
- **Brightness** (+1, values 0–4): works, confirmed; maximum = 4.
- **Color** (+4 = 0, +5…+7 = R, G, B): write and readback are correct. **Mode 6 “Normally on” changes color**; mode 20 “Coastal” does not, because it uses its own palette. A later visual scan is preserved in [color-scan-result.txt](device/color-scan-result.txt): modes 1–3, 5–10, and 13–16 use the selected color; the others use their own palettes.
- For a preset color, the original program writes `+4 = 0` and `+5…+7`; for a custom color, only `+5…+7`; for “Colourful,” `+4 = 1` (VA `0x41F390`, `0x41F4F0`, `0x41F440`).
- The current application uses +2 for speed according to the original slider mapping (raw 0–4 ↔ UI 5–1). Separate visual hardware verification of the order has not been recorded. The application does not modify +3 or other unknown fields.

Build limitation: the application is ad-hoc signed. Input Monitoring permission is tied to the build and is lost after rebuilding.
