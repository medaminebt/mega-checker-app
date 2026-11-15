# MEGA Keep-Alive (Flutter · macOS)

A macOS desktop app that keeps your MEGA accounts active. It logs in to each
account, reads its **storage** (used / total), and saves the **last login
time** in your own **Supabase** (PostgreSQL) database.

- **Supabase database** (Free plan): accounts, MEGA keys, last login and
  storage are stored there, protected by Row Level Security and your sign-in
- **Paste list**: paste many `email:password` lines at once (also `,` `;`
  tab or space)
- **Check all accounts** logs in one by one (10–25 s apart) through
  **MEGAcmd**; or check a single account with ▶
- **Last login + storage** per account, plus total storage across all accounts
- **MEGA key** field per account, typed in by hand
- Inline editing with **auto-save** (and a Retry if you're offline)
- **Import CSV** (bring in your old list) and **Export CSV** (a local backup)
- **shared_preferences** remembers your Supabase connection, sign-in session,
  sort order and the show/hide-passwords toggle
- **MEGA theme**: black canvas, MEGA Red actions, indigo accents, Lexend font

> **First time?** Set up Supabase first → **[SUPABASE_SETUP.md](SUPABASE_SETUP.md)**
> (about 10 minutes, once).

---

## Run it on your Mac

### 1. Install the tools (once)

| Tool | Why | Install |
|---|---|---|
| **Xcode** | builds macOS apps | App Store → *Xcode*. Then in Terminal: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -runFirstLaunch` |
| **Homebrew** | installs the rest | <https://brew.sh> |
| **Flutter SDK** (3.44+) | the framework | `brew install --cask flutter`, or follow <https://docs.flutter.dev/get-started/install/macos> |
| **CocoaPods** | native plugins (Supabase, shared_preferences) | `brew install cocoapods` |
| **MEGAcmd** | does the actual MEGA logins | `brew install --cask megacmd`, then open **MEGAcmd** once |

Check everything is in place:

```sh
flutter doctor          # the "Xcode" and "Flutter" lines should be ✓
which mega-login        # → /opt/homebrew/bin/mega-login
```

### 2. Get the code and dependencies

```sh
cd ~/Documents/Github/mega-checker-app
flutter pub get
```

### 3. Run it (development mode)

```sh
./run.sh                # same as: flutter run -d macos
```

The first build takes a few minutes (it runs `pod install`); later runs are
fast. While it runs, press `r` in the terminal for hot reload and `q` to quit.

> Use `./run.sh` or `flutter run -d macos`. A bare `flutter run` may try to
> launch on a connected iPhone/iPad.

### 4. First launch

1. **Connect to Supabase**: paste your Project URL + publishable key (see
   [SUPABASE_SETUP.md](SUPABASE_SETUP.md), step 5) → **Save & connect**.
2. **Sign in** with the Supabase user you created.
3. **Paste list** → paste your accounts → **Save**.
4. **Check all accounts**. Each row gets ✓ OK / ✗ Failed, the last-login
   timestamp and its storage.

---

## Build the Mac app (`.app`) for your MacBook Pro

```sh
./build.sh              # = flutter build macos --release
```

The app is created at:

```
build/macos/Build/Products/Release/mega-checker-app.app
```

It's built for **Apple Silicon** (M1–M4 MacBooks). Xcode 27's `lipo` breaks
Flutter 3.44's universal (Intel + Apple Silicon) release build, so
`macos/Runner/Configs/Release.xcconfig` excludes Intel (`EXCLUDED_ARCHS =
x86_64`). Delete that line if you ever need an Intel build and your
Flutter/Xcode combination supports it.

**Install it** in Applications (then open it from Launchpad or Spotlight like
any other app):

```sh
./build.sh --install    # builds, then copies it to /Applications
```

…or drag `mega-checker-app.app` from Finder into **Applications** yourself.

**Opening it the first time.** An app you built on the same Mac opens
normally. If you copy it to **another** Mac (AirDrop, USB, download), macOS
blocks it because it isn't notarized. Try to open it once, then go to
**System Settings → Privacy & Security** → **Open Anyway**. To send it as one
file:

```sh
cd build/macos/Build/Products/Release
ditto -c -k --keepParent mega-checker-app.app mega-checker-app.zip
```

MEGAcmd must be installed on any Mac that runs the app. The Supabase URL/key
are entered on the first launch of each Mac (nothing secret is built into the
app).

---

## Using the app

| Action | What it does |
|---|---|
| **Check all accounts** | Logs in to every account one by one through MEGAcmd (random 10–25 s pause between accounts). **Stop** halts after the current one. |
| ▶ on a row | Checks just that account. |
| **Add account** | One account: email, password, optional MEGA key and notes. |
| **Paste list** | Many accounts at once, one per line: `email:password`, `email,password`, `email;password`, `email<tab>password` or `email password`. Shows how many are new, already known, or skipped before saving. Optionally updates passwords of known emails. |
| **Import CSV** | Header row with `email,password` (optional `notes`, `mega_key`). Only adds emails that aren't in your list yet. Your old `email,password,notes` CSV works. |
| **Export CSV** | Saves a backup (`email,password,mega_key,notes,last_login_at,last_status,storage_used_bytes,storage_total_bytes`). Keep it private. |
| ⟳ | Reloads from Supabase. |
| Column headers | Click **STATUS**, **EMAIL** or **LAST LOGIN** to sort (asc → desc → off). Sort by last login to find accounts you haven't logged in to for a while. |
| Inline cells | Edit email, password, **MEGA key** or notes directly in the table. Changes save automatically; the footer shows *All changes saved* / *Not saved — Retry*. |
| **Show passwords & keys** | Reveals passwords and MEGA keys (remembered between launches). |

What each check stores in Supabase:

| Column | Meaning |
|---|---|
| `last_login_at` | time of the last **successful** login |
| `last_checked_at` | time of the last attempt |
| `last_status` / `last_error` | `ok` or `failed`, plus the reason |
| `storage_used_bytes` / `storage_total_bytes` | from `mega-df`, read right after logging in |

> MEGA never says whether the **email** or the **password** was wrong
> (anti-enumeration), so a failure reads "Wrong email or password".
> Accounts with 2FA enabled can't be checked (MEGAcmd would need the code).

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `CocoaPods not installed` during build | `brew install cocoapods`, then `./run.sh` again. |
| Build error about *macOS deployment target … 10.15* | Already fixed in this branch (target is 12.0). Run `flutter clean && flutter pub get`. |
| Release build: *does not contain architectures "arm64 x86_64"* | Xcode 27 `lipo` issue. Keep `EXCLUDED_ARCHS = x86_64` in `macos/Runner/Configs/Release.xcconfig` (already set). |
| *Table "mega_accounts" not found* | Run `supabase/schema.sql` in the Supabase SQL Editor ([setup step 2](SUPABASE_SETUP.md#2-create-the-table-run-the-sql-once)). |
| *Supabase rejected the publishable key* | Re-copy it from **Project Settings → API Keys**; use the header's server icon to fix it. |
| *Wrong email or password for your Supabase user* | That's the Supabase user, not MEGA. Check it in **Authentication → Users**, or reset its password there. |
| *This Supabase user is not confirmed yet* | Recreate the user with **Auto Confirm User** ticked, or confirm it in the dashboard. |
| *Can't reach Supabase…* | Check your internet; a free project may be **paused**. Open the dashboard → **Restore project**. |
| Every MEGA check fails *MEGAcmd not installed* | `brew install --cask megacmd`, open MEGAcmd once, restart the app. |
| Login OK but storage shows "—" | Run `mega-login you@x.com 'pw' && mega-df; mega-logout` in Terminal to see what MEGAcmd prints. |
| App won't open on another Mac | **System Settings → Privacy & Security → Open Anyway**. |
| Start over locally (forget URL/key/session) | `defaults delete com.megakeepalive.megaKeepalive` |

---

## Project layout

```
lib/
  main.dart                  app start, Supabase init, setup → sign-in → home
  app_theme.dart             MEGA design tokens + Material theme
  models.dart                Account, StorageInfo, LoginResult
  mega_service.dart          MEGAcmd: login → whoami → df (storage) → ls → logout
  accounts_repository.dart   Supabase table access + friendly error messages
  account_import.dart        "Paste list" parser + import merge plan
  csv_import.dart            CSV import / export (native macOS file dialogs)
  prefs.dart                 shared_preferences wrapper
  format.dart                bytes / date formatting
  screens/                   setup, sign-in, home (accounts table)
  widgets/                   account row, dialogs, badges, logo, form bits
supabase/schema.sql          table + Row Level Security (run once)
assets/fonts/                Lexend (SIL Open Font License)
```

## Tests

```sh
flutter test --exclude-tags live   # offline tests (in-memory database instead of Supabase)
flutter test --tags live           # live MEGAcmd check (network)
flutter test                       # everything
```

The `live` test talks to the real MEGA servers with a fake account and runs
`mega-logout` first, so don't run it while you're logged in to MEGAcmd
yourself.

## Notes

- **Check MEGA's Terms of Service** on automated access and multiple accounts.
  Policies change and this app can't verify them for you.
- Free Supabase projects pause after a week of inactivity; see
  [SUPABASE_SETUP.md](SUPABASE_SETUP.md#free-plan-what-to-know).
