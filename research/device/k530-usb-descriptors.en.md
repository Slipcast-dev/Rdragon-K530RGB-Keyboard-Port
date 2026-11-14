[Русский](k530-usb-descriptors.md) | **English**

# Actual K530 descriptors (USB cable)

Captured on 27 October 2026 on macOS 13 (Darwin 22.6, Intel MacBook), using `ioreg`. No serial numbers are included.

## Device

| Field | Value |
|---|---|
| Product / Manufacturer | `Draconic` / `SONiX` |
| VID:PID | `0C45:5004`, matching the candidates from HidServ.dll |
| bcdDevice | `0x0112` (1.12) |
| USB | 2.0 Full Speed (12 Mbps), 64-byte EP0, 400 mA power consumption |
| HID interfaces | 2 |

## Interface 0: boot keyboard and 64-byte Feature report

Max in/out/feature = 8 / 1 / 64. No Report IDs are used.

```
05 01 09 06 a1 01 05 07 19 e0 29 e7 15 00 25 01 75 01 95 08 81 02 95 01 75 08 81 01
95 05 75 01 05 08 19 01 29 05 91 02 95 01 75 03 91 01 95 06 75 08 15 00 26 ff 00
05 07 19 00 2a ff 00 81 00 05 0c 09 00 15 80 25 7f 95 40 75 08 b1 02 c0
```

Key detail: **a 64-byte Feature report without an ID** (Consumer Usage Page 0x0C, Usage 0). Historically considered a possible command channel. The current lighting application does not use it, and its purpose is unconfirmed.

## Interface 1: NKRO, multimedia, and service channel

Max in/out/feature = 64 / 64 / 1.

| Report ID | Purpose | Type |
|---|---|---|
| 1 | NKRO keyboard, 120-bit bitmap = 15 bytes | Input |
| 2 | System Control (Generic Desktop 0x80) | Input |
| 3 | Consumer (16 bits) | Input |
| 4 | **Vendor `FF1C:0092`**, 63 bytes | Input + Output |
| 5 | Mouse: buttons, 16-bit X/Y, wheel | Input |

The **ID 4 report, 63 bytes in both directions**, matches the `FF1C:0092` candidate from HidServ.dll. In the subsequent [first profile read](profiles-read-1.txt), this channel accepted begin/read/end. The current application uses it for lighting commands. Raw evidence retains its original Russian annotations.

```
05 01 09 06 a1 01 85 01 05 07 19 04 29 70 15 00 25 01 75 01 95 78 81 02 c0
05 01 09 80 a1 01 85 02 05 01 19 81 29 83 15 00 25 01 95 03 75 01 81 02 95 01 75 05 81 01 c0
05 0c 09 01 a1 01 85 03 15 00 26 ff 1f 19 00 2a ff 1f 75 10 95 01 81 00 c0
06 1c ff 09 92 a1 01 85 04 19 00 2a ff 00 15 00 26 ff 00 75 08 95 3f 91 00 19 00 29 ff 81 00 c0
05 01 09 02 a1 01 85 05 09 01 a1 00 05 09 19 01 29 05 15 00 25 01 95 05 75 01 81 02 95 01 75 03 81 01
05 01 09 30 09 31 16 00 80 26 ff 7f 75 10 95 02 81 06 09 38 15 81 25 7f 75 08 95 01 81 06
05 0c 0a 38 02 15 81 25 7f 75 08 95 01 81 06 c0 c0
```

Report sizes were confirmed by `k530diag descriptors`: Input ID 4 = 63 bytes, Output ID 4 = 63 bytes. The actual on-wire length requires clarification through live traffic.

## Confirmed and unconfirmed findings

- Confirmed: VID/PID, the `FF1C:0092` usage pair, the 64-byte Feature report, and vendor report ID 4.
- Subsequent reads and writes through Report ID 4 are described in the [protocol documentation](../protocol-findings.en.md). The Feature channel on interface 0 remains unconfirmed and is not used by the application.
- The `FFFF:0001` and `000C:0001` candidates from HidServ.dll do not appear as separate collections on this device. `0C:01` exists as Consumer; `FFFF:0001` is absent from the descriptors. The filter may support multiple revisions.
