# MEGA Keep-Alive — Flutter macOS app

A native macOS desktop app that keeps your own MEGA accounts active by logging in
to each one, and records the result back into your CSV.

**Your CSV is the database.** You import it, the app shows it in a table, you test
the logins one by one, and each account's `notes` column gets a timestamped result
(`login OK` / `login FAILED: …`) written straight back to the CSV.

There's **no master password and no encryption** — the CSV holds your accounts in
plain text. (See the security note at the bottom.)

It drives **MEGAcmd** (MEGA's official CLI) and uses no native Flutter plugins, so
it builds without CocoaPods.

---

## The CSV format

Three columns. Keep the header row exactly as shown:

```
email,password,notes
account1@gmail.com,Password1,
account2@gmail.com,Password2,backup account
```

- `notes` can start empty or hold your own text — the app **appends** to it, e.g.
  `backup account | [2026-06-04 20:06:52] login OK`.
- A password with a comma must be quoted: `"pa,ss"`.
- Editing in Excel / Numbers is fine (the app strips the hidden BOM they add).

`accounts_template.csv` in this folder is a starting point you can copy or edit.

---

## How to run the app

### Easiest — the built app (double-clickable)

```
build/macos/Build/Products/Release/mega_keepalive.app
```
Double-click it (first time: **right-click → Open → Open** to get past Gatekeeper).
Drag it to `/Applications` if you like.

### From source (dev mode)

```sh
cd /Users/medaminebentaieb/Documents/Github/mega-checker-app
./run.sh                 # always targets macOS
```

> ⚠️ **Use `./run.sh` or `flutter run -d macos`.** A bare `flutter run` targets your
> iPhone/iPad, which this macOS-only app doesn't support — that's what caused the
> earlier terminal error.

---

## Using it — the workflow you asked for

1. **Import CSV** — click it, pick your CSV. The accounts load into the table
   (Email · Password · Result · Notes). The app remembers this file and reloads it
   next launch. Passwords are hidden by default — toggle the 👁 icon to reveal them.
2. **Test all logins** — runs every account **one by one**:
   - success → the row turns green (**Logged in**) and `[date time] login OK` is
     appended to that account's notes,
   - failure → the row turns red with the reason, and
     `[date time] login FAILED: …` is appended to its notes.
   - There's a 10–25s gap between accounts (avoids looking like a burst).
   - **Stop** halts after the current account.
3. **Per-account test** — the ▶ button on any row tests just that one.
4. **Auto-save** — after every account, the table is written **back to your CSV**,
   so the notes are saved even if you stop early or the app closes.
5. **Export CSV** — save a copy of the current table (with all notes) to any
   location you choose.

So after a full run, your CSV looks like:

```
email,password,notes
account1@gmail.com,Password1,[2026-06-04 20:06:47] login OK
account2@gmail.com,Password2,backup account | [2026-06-04 20:06:52] login OK
account3@gmail.com,Password3,[2026-06-04 20:06:53] login FAILED: wrong email or password
```

> Note: MEGA never reveals whether the **email** or the **password** was wrong
> (anti-enumeration), so a failed login is logged as “wrong email or password.”

---

## Where the app keeps its bit of state

```
~/Library/Application Support/MEGAKeepAlive/config.json   # remembers the last CSV path
```

Everything else — your accounts and all results — lives in **your CSV file**.

---

## Rebuilding after code changes

```sh
flutter build macos --release      # → build/macos/Build/Products/Release/mega_keepalive.app
flutter test                       # CSV round-trip, table render, live MEGAcmd check
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Terminal error on `flutter run` (CocoaPods / iOS) | Use `./run.sh` or `flutter run -d macos`. |
| “No valid rows found” on import | Header row must be exactly `email,password,notes`. |
| App won’t open (“unidentified developer”) | Right-click → **Open** the first time. |
| Every login fails “MEGAcmd not installed” | `brew install --cask megacmd`, then reopen. |
| A real account shows red | Re-check that row's email/password; that account genuinely failed to log in. |

---

## Security note

There's **no encryption** now — your emails and passwords sit in the CSV in plain
text, and the app writes results back to it. That's the simple "database" model you
asked for. Keep the CSV somewhere private (and off shared drives / cloud sync if you
care). If you ever want it encrypted again with a master password, say the word.

- **Check MEGA's Terms of Service** on automated access and multiple accounts —
  policies change and I can't verify their current stance for you.
