# Build guide: macOS, Windows and Web

One codebase, three builds:

| Platform | Build it on | Command | You get | Checks MEGA accounts? |
|---|---|---|---|---|
| **macOS** | a Mac | `./build.sh` | `build/macos/Build/Products/Release/mega-checker-app.app` | ✅ via MEGAcmd |
| **Windows** | a Windows 10/11 PC | `build_windows.bat` | `build\windows\x64\runner\Release\mega-checker-app.exe` (+ its folder) | ✅ via MEGAcmd for Windows |
| **Web** | any computer | `./build_web.sh` | `build/web/` (upload to a static host) | ❌ manages the list only, see [why](#what-works-in-the-browser) |

> **Flutter can't cross-compile desktop apps.** Build the Windows app on
> Windows and the Mac app on a Mac. The web version can be built on either.

All three use the **same Supabase project and sign-in**, so a change made in
one shows up in the others after a reload (⟳). If you haven't set Supabase up
yet, follow [SUPABASE_SETUP.md](SUPABASE_SETUP.md) first (≈ 10 min, once).

---

## Contents

- [macOS](#macos)
- [Windows](#windows)
- [Web](#web)
  - [Keep it private (search engines and AI bots)](#web-keep-it-private)
- [Updating the app later](#updating-the-app-later)
- [Regenerating the icons](#regenerating-the-icons)

---

## macOS

### 1. Install the tools (once)

| Tool | Install |
|---|---|
| **Xcode** | App Store → *Xcode*, then in Terminal: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -runFirstLaunch` |
| **Homebrew** | <https://brew.sh> |
| **Flutter SDK 3.44+** | `brew install --cask flutter` |
| **CocoaPods** | `brew install cocoapods` |
| **MEGAcmd** | `brew install --cask megacmd`, then open **MEGAcmd** once |

```sh
flutter doctor          # "Xcode" and "Flutter" should be ✓
which mega-login        # → /opt/homebrew/bin/mega-login
```

### 2. Run it while developing

```sh
cd ~/Documents/Github/mega-checker-app
flutter pub get
./run.sh                # = flutter run -d macos  (r = hot reload, q = quit)
```

### 3. Build the app

```sh
./build.sh              # build only
./build.sh --install    # build, then copy to /Applications
```

Output: `build/macos/Build/Products/Release/mega-checker-app.app`, for Apple
Silicon (M1–M4). To share it as one file:

```sh
cd build/macos/Build/Products/Release
ditto -c -k --keepParent mega-checker-app.app mega-checker-app.zip
```

On **another** Mac, macOS blocks the app the first time (it isn't notarized):
try to open it, then **System Settings → Privacy & Security → Open Anyway**.
MEGAcmd must be installed on every Mac that runs the app.

**Scheduled checks** start the app from where it was when you saved the
schedule, so install it first (`./build.sh --install` → `/Applications`) and
set the schedule up from that copy. The schedule is a LaunchAgent in
`~/Library/LaunchAgents/com.megakeepalive.scheduled-check.plist`; the app
passes its command line to Dart through `macos/Runner/MainFlutterWindow.swift`.

Troubleshooting: [README.md](README.md#troubleshooting). Prebuilt downloads: the repo's **Releases** page.

---

## Windows

### 1. Install the tools (once)

| Tool | Why | Install |
|---|---|---|
| **Windows 10 or 11** (64-bit) | | |
| **Git for Windows** | Flutter needs it | <https://git-scm.com/download/win> |
| **Visual Studio 2022** (Community is free), *not* VS Code | compiles the Windows app | <https://visualstudio.microsoft.com/downloads/>. In the installer tick the **"Desktop development with C++"** workload |
| **Flutter SDK 3.44+** | the framework | Download the Windows zip from <https://docs.flutter.dev/get-started/install/windows/desktop>, extract it to `C:\src\flutter`, then add `C:\src\flutter\bin` to your **Path** (Start → *"Edit environment variables for your account"* → Path → New) |
| **Developer Mode** | Flutter plugins need symlinks | Start → *"Developer settings"* (or run `start ms-settings:developers`) → turn **Developer Mode** on |
| **MEGAcmd for Windows** | does the actual MEGA logins | <https://mega.io/cmd> → Windows installer. It installs to `%LOCALAPPDATA%\MEGAcmd`. Open **MEGAcmd** once after installing |

Open a **new** Command Prompt or PowerShell window (so the new Path is used)
and check:

```bat
flutter doctor
dir "%LOCALAPPDATA%\MEGAcmd\MEGAclient.exe"
```

The **Windows Version** and **Visual Studio – develop Windows apps** lines
should be ✓. Android / Chrome / Xcode lines don't matter.

### 2. Get the code

```bat
cd %USERPROFILE%\Documents
git clone https://github.com/medaminebt/mega-checker-app.git
cd mega-checker-app
flutter pub get
```

### 3. Run it while developing

```bat
flutter run -d windows
```

The first build takes a few minutes; later ones are fast. Press `r` for hot
reload and `q` to quit.

### 4. Build the app

```bat
build_windows.bat
```

(or by hand: `flutter build windows --release`)

You get:

```
build\windows\x64\runner\Release\
    mega-checker-app.exe       ← the app
    flutter_windows.dll        ← needed
    *_plugin.dll               ← needed
    data\                      ← needed
build\mega-checker-app-windows.zip   ← the same folder, zipped
```

On a Windows-on-ARM PC the folder is `build\windows\arm64\runner\Release\`.

> **Keep the whole folder together.** The `.exe` doesn't run on its own: it
> needs the DLLs and the `data` folder next to it. Copy or zip the entire
> `Release` folder.

**Install it:** unzip `mega-checker-app-windows.zip` somewhere permanent, e.g.
`C:\Users\<you>\Apps\mega-checker-app\`, then right-click
`mega-checker-app.exe` → **Show more options → Send to → Desktop (create
shortcut)**, or pin it to Start.

**First launch on another PC:** Windows SmartScreen may say *"Windows protected
your PC"* because the app isn't code-signed. Click **More info → Run anyway**.
MEGAcmd for Windows must be installed on that PC too.

### Windows notes

- **Settings** (Supabase URL/key, signed-in session, sort order) are stored per
  Windows user in `%APPDATA%\com.megakeepalive\mega-checker-app\`. Delete that
  folder to start over.
- **How checks run:** the app calls `MEGAclient.exe` in `%LOCALAPPDATA%\MEGAcmd`
  directly (`login`, `df`, `ls`, `logout`), which is what the `mega-*.bat`
  commands do. Calling it directly keeps passwords containing `& ^ % "` intact.
  If MEGAcmd is installed somewhere else, add that folder to your Path.
- **Window:** opens at 1440 × 880 (shrunk to fit smaller screens), minimum
  960 × 600; narrower windows scroll the table sideways.
- The Windows app **builds on GitHub Actions** (`windows-latest`, see
  `.github/workflows/release.yml`) but **hasn't been run on a real PC yet**.
  If a check fails, the most likely place is `lib/platform/native_io.dart`
  (MEGAcmd paths). Copy the error text.
- **No Windows PC to build on?** Download `mega-checker-app-windows-x64.zip`
  from the repo's **Releases** page instead.
- MEGAcmd may open its own server window the first time a check runs. Leave it
  open (or minimised) while checks run.
- **Scheduled checks** use Task Scheduler (`schtasks /Create /XML`, a task
  named *mega-checker-app scheduled check* that runs only while you're signed
  in). Set them up from the copy you'll keep: the task starts that exact
  `.exe`. The remembered master password is a DPAPI-encrypted file in
  `%APPDATA%\mega-checker-app\keys\`. Like the rest of the Windows build,
  this is written to Microsoft's documented formats but **not yet tried on a
  real PC**: if *Save schedule* reports an error, copy it.
- Optional, for a real installer: the [`msix`](https://pub.dev/packages/msix)
  package turns the build into an `.msix` installer
  (`flutter pub add --dev msix`, then `dart run msix:create`).

---

## Web

### What works in the browser

| Feature | Web |
|---|---|
| Sign in, see all accounts, last login, storage, stats | ✅ |
| Add / Paste list / edit / delete accounts, MEGA key, notes | ✅ |
| **Upload folder URL**: open the folder in a new tab and upload | ✅ |
| Sort (status, email, last login, storage), search | ✅ |
| Import CSV (file picker) / Export CSV (downloads the file) | ✅ |
| Two-step sign-in (2FA), master password, recovery key | ✅ (the master password is asked on every page load and never stored in the browser) |
| **Sign me out when I close the browser** (sign-in screen, or 🛡 Security) | ✅ web only |
| Rubbish Bin / versions sizes | ✅ shown |
| **Check all / Recheck failed / ▶ check one**, empty bin / delete versions | ❌ disabled |
| Scheduled checks | ❌ desktop only |

**Why no checks in the browser?** A check runs the MEGAcmd program on your
computer. Browsers can't start programs (that's a core security rule), so the
check buttons are disabled on the web, with a tooltip saying so. Run checks
from the Mac or Windows app; the results appear on the web after a reload (⟳).

### 1. Build

Works on macOS, Windows or Linux with Flutter 3.44+ (no Xcode or Visual
Studio needed):

```sh
./build_web.sh                    # macOS / Linux
```

```bat
flutter build web --release --no-web-resources-cdn   :: Windows
```

Output: `build/web/`. The folder is about 40 MB because it contains several
renderer variants, but a browser only downloads **≈ 10 MB** on the first visit
(then it's cached).

`--no-web-resources-cdn` bundles Flutter's renderer instead of loading it from
Google's CDN, so the app makes **no third-party requests**, only to your
Supabase project.

**Renderer:** the default build compiles the app to **JavaScript** (dart2js)
and draws with **CanvasKit** (Skia compiled to WebAssembly, `canvaskit.wasm`).
You can confirm it in `build/web/flutter_bootstrap.js`:
`"compileTarget":"dart2js","renderer":"canvaskit"`.

Optional: add `--wasm` for a faster WebAssembly build in Chrome, Edge and
Firefox (other browsers automatically fall back to the JavaScript build):
`./build_web.sh --wasm`. The app's code passes Flutter's WebAssembly dry run.

### 2. Try it locally

```sh
./build_web.sh --serve            # → http://localhost:8080
# or, while developing (hot reload):
flutter run -d chrome
```

### 3. Put it online

Upload the **contents** of `build/web/` to any static host. All of these have
a free plan:

| Host | How | Reads `web/_headers`? |
|---|---|---|
| **Cloudflare Pages** | dashboard → Workers & Pages → Create → Pages → **Upload assets** → drop the `build/web` folder | ✅ |
| **Netlify** | <https://app.netlify.com/drop> → drop the `build/web` folder | ✅ |
| **Vercel** | `npx vercel deploy build/web --prod` | ❌ use `vercel.json` below |
| **Firebase Hosting** | `firebase init hosting` (public dir `build/web`), then `firebase deploy` | ❌ use `firebase.json` below |
| Your own server (Nginx / Apache) | copy the files to the web root | ❌ use the config below |

- **Root vs sub-folder.** Host it at the root of a (sub)domain, e.g.
  `https://mega.example.com/`. For a sub-folder such as
  `https://example.com/mega/`, build with `./build_web.sh --base-href /mega/`.
  Note that `robots.txt` only works at a domain's root.
- **Supabase needs no changes.** It accepts requests from any website, and
  password sign-in needs no redirect URLs.
- **First visit in each browser:** paste the Supabase Project URL +
  publishable key, then sign in. They're saved in that browser only; nothing
  secret is built into the files you upload.
- Avoid **GitHub Pages** on a free account: the repository has to be public
  and you can't set response headers.

<a id="web-keep-it-private"></a>
### 4. Keep it private (search engines and AI bots)

Already built in. These files are copied into `build/web/` on every build:

| File | What it does |
|---|---|
| `robots.txt` | Disallows **all** crawlers, plus named groups for Google, Bing and other search engines, AI crawlers and assistants (GPTBot, ChatGPT-User, ClaudeBot, Claude-User, Google-Extended, PerplexityBot, CCBot, Bytespider, Applebot-Extended, Meta, Cohere, …) and link-preview bots |
| `llms.txt` | Tells LLMs and AI agents this is a private app that they must not read, index, summarise or train on |
| `index.html` | `<meta name="robots" content="noindex, nofollow, noarchive, nosnippet, noimageindex, noai, noimageai">`, plus `googlebot` / `bingbot` variants, and `referrer: no-referrer` so the MEGA links you open don't reveal your app's address |
| `_headers` | Sends `X-Robots-Tag: noindex, nofollow, …` on **every** file (Cloudflare Pages and Netlify). That's the strongest "don't index" signal |

For hosts that don't read `_headers`, add the same header yourself:

<details>
<summary>Vercel: <code>web/vercel.json</code> (copied into <code>build/web</code> on every build)</summary>

```json
{
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Robots-Tag", "value": "noindex, nofollow, noarchive, nosnippet, noimageindex, noai, noimageai" },
        { "key": "Referrer-Policy", "value": "no-referrer" }
      ]
    }
  ]
}
```
</details>

<details>
<summary>Firebase Hosting: <code>firebase.json</code></summary>

```json
{
  "hosting": {
    "public": "build/web",
    "headers": [
      {
        "source": "**",
        "headers": [
          { "key": "X-Robots-Tag", "value": "noindex, nofollow, noarchive, nosnippet, noimageindex, noai, noimageai" },
          { "key": "Referrer-Policy", "value": "no-referrer" }
        ]
      }
    ]
  }
}
```
</details>

<details>
<summary>Nginx / Apache</summary>

```nginx
# Nginx (inside the server { } block)
add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex, noai, noimageai" always;
add_header Referrer-Policy "no-referrer" always;
```

```apache
# Apache (.htaccess, needs mod_headers)
Header always set X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex, noai, noimageai"
Header always set Referrer-Policy "no-referrer"
```
</details>

**What actually keeps your data private.** `robots.txt`, `llms.txt` and the
noindex tags are *requests*: well-behaved search engines and AI companies
follow them, bad bots don't. Your accounts are protected by your **Supabase
sign-in + Row Level Security**. Anyone who finds the URL only sees the
"Connect to Supabase" screen and can't read anything. For an extra lock in
front of the whole site, put it behind **Cloudflare Access** (Zero Trust,
free for small teams) so even the sign-in page needs your email first. And
don't post the URL anywhere public.

### Web troubleshooting

| Symptom | Fix |
|---|---|
| Blank page when hosted in a sub-folder | Rebuild with `--base-href /folder-name/` (leading and trailing `/`). |
| Old version after uploading a new build | Hard-reload: **Ctrl+Shift+R** (Windows) / **⌘⇧R** (Mac). |
| *Can't reach Supabase…* | The free project may be paused (see [SUPABASE_USAGE.md](SUPABASE_USAGE.md#5-the-one-thing-to-watch-pausing)), or an ad/tracker blocker is blocking `*.supabase.co`. Allow it for your site. |
| Check buttons greyed out | Expected on the web; run checks from the desktop app. |
| *Unlocking…* takes ages (tens of seconds) | The page isn't on HTTPS. Browsers only give fast Web Crypto to `https://` pages and `localhost`; elsewhere the master-password math runs in slow JavaScript. Host over HTTPS (Cloudflare Pages, Netlify… do by default). |
| Asked for the master password on every visit | By design: the browser never stores it. The desktop apps can remember it (🛡 Security). |
| Signed out after closing the tab | *Sign me out when I close the browser* is on (sign-in screen or 🛡 Security). |
| Want to forget the saved URL/key in a browser | Header → server icon (*Supabase project settings*), or clear the site's data in the browser settings. |

---

## Updating the app later

1. `git pull` (or copy the new code), then `flutter pub get`.
2. If [SUPABASE_SETUP.md](SUPABASE_SETUP.md#updating-an-existing-project)
   mentions a database change, re-run `supabase/schema.sql` in the Supabase
   SQL Editor. It's safe to run again; it only adds what's missing.
3. Rebuild each platform you use (`./build.sh`, `build_windows.bat`,
   `./build_web.sh`) and replace the old app / re-upload `build/web/`.

## Regenerating the icons

Every icon (macOS app icon, Windows `.ico`, web favicon and PWA icons) is drawn
from the same glowing red "M" by one script. Run it on a Mac:

```sh
swift tool/generate_icons.swift
```

It writes `macos/Runner/Assets.xcassets/AppIcon.appiconset/`,
`windows/runner/resources/app_icon.ico`, `web/favicon.ico`,
`web/favicon.png` and `web/icons/`.
