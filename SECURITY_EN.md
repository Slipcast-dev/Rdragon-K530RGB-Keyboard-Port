[Русский](SECURITY.md) | **English**

# Security policy

## Reporting a vulnerability

Do not open a public issue containing vulnerability details. Report privately through
[Security → Report a vulnerability](https://github.com/Slipcast-dev/Rdragon-K530RGB-Keyboard-Port/security/advisories/new).

The maintainer aims to respond within 7 days.

## Scope

- `tools/k530menu/` and `tools/k530diag/` contain applications that write to the keyboard's HID interface. They change only the lighting mode, brightness, speed, and color.
- Builds are ad-hoc signed and are not notarized. Review the source and build it yourself if you do not trust the distributed archives.

## Materials that must not be committed

Passwords, tokens, private signing keys, certificates (`.p12`, `.pem`, `.mobileprovision`), and personal data. If you find any, report them through the link above.

The public `tools/k530menu/UpdatePublicKey.txt` is intended for distribution and is not a secret. The private release key is stored outside the repository. The application must not contain a token granting access to the private GitHub repository.
