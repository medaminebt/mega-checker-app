# MEGA Keep-Alive (Flutter · macOS)

A native macOS desktop app that keeps your own MEGA accounts active by logging in
to each one and recording the result back into your CSV.

**Your CSV is the database** — import it, test the logins one by one, and each
account's `notes` column gets a timestamped `login OK` / `login FAILED: …` written
back to the file. No master password, no encryption.

- **Import CSV** → accounts table (native file dialog, no plugins)
- **Test all logins** one by one, with live green/red per-row results
- **Notes written back** to the CSV after every account (auto-save) + **Export CSV**
- Drives **MEGAcmd** under the hood · **indigo** UI · builds **without CocoaPods**

## Quick start

```sh
./run.sh                    # run from source (always targets macOS)
# or double-click the built app:
#   build/macos/Build/Products/Release/mega_keepalive.app
```

Click **Import CSV** (format: `email,password,notes`) → **Test all logins**.

👉 **Full usage & troubleshooting: [`run_instructions.md`](run_instructions.md).**

## Source layout (`lib/`)

| File | Purpose |
|---|---|
| `main.dart` | UI: import, table, test-all/per-row, notes, export |
| `csv_import.dart` | native `osascript` open/save dialogs + CSV read/write |
| `mega_service.dart` | MEGAcmd login/logout + result classification |
| `models.dart` | `Account` (mutable notes) + login result types |
| `paths.dart` | remembers the last CSV path |

## Tests

```sh
flutter test    # CSV parse/export round-trip, table render, live MEGAcmd check
```

## Security note

No encryption — accounts live in the CSV in plain text. Keep it private. Ask if you
want master-password encryption back.
