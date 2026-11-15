# Ideas & answers

Answers to questions about the app, plus a backlog of features worth
building next. Facts were checked on 15 Nov 2026 against the installed
**MEGAcmd 2.7.0** (`mega-help`, and MEGAcmd's source for `df` and `rm`), the
app's code, and the sources at the end.

**Update, 15 Nov 2026 (evening):** five backlog items are now built: **A1**
2FA sign-in, **A2** encrypted passwords and MEGA keys, **A3** sign out when
the browser closes, **B2** Rubbish Bin / versions sizes (with the **C1**
clean-up actions behind an *Are you sure?*), and **B7** scheduled checks.
They're marked ✅ below. In v1.1.0, 2FA became **optional**: you sign in
with just the password until you turn it on in 🛡 Security.

- [1. Do upload folder URLs work in the web version?](#1-do-upload-folder-urls-work-in-the-web-version)
  - [Can I make the file requests from the MEGA desktop app, and will the column fill itself?](#can-i-make-the-file-requests-from-the-mega-desktop-app-and-will-the-column-fill-itself)
- [2. Is the web version secure with the login?](#2-is-the-web-version-secure-with-the-login)
- [3. What else can MEGAcmd do?](#3-what-else-can-megacmd-do)
- [4. Idea backlog](#4-idea-backlog)
- [5. Does the web build use WebAssembly or CanvasKit?](#5-does-the-web-build-use-webassembly-or-canvaskit)

---

## 1. Do upload folder URLs work in the web version?

**Yes.** The *Upload folder* column and its ↗ button work the same in the
browser as in the desktop app:

- You can paste, edit and save the link. It's stored in Supabase, so a link
  added on the Mac shows up on the web, and the other way round.
- ↗ opens the link in a **new browser tab**. Because it opens on your click,
  popup blockers allow it.
- The tab is opened with `noopener,noreferrer`, and the page also sets
  `referrer: no-referrer`, so MEGA never learns your app's address.
- Only `http(s)` links are opened; anything else (e.g. `javascript:`) is
  refused.

### The catch: use the right kind of MEGA link

"Upload without logging in" only works with a **file request** link:

| Link type | Looks like | Upload without a MEGA login? | Visitor sees existing files? | How to create it |
|---|---|---|---|---|
| **File request** (formerly *MEGAdrop*) | `https://mega.nz/filerequest/…` | ✅ **yes** | ❌ no (write-only) | MEGA web app → *Shared items → File requests* |
| Folder link | `https://mega.nz/folder/…#key` | ❌ read-only: view and download | ✅ yes | right-click a folder → *Share link* |
| Writable folder link | `<handle>#<key>:<auth-key>` | only through MEGAcmd login with `--auth-key` | ✅ yes | `mega-export -a --writable /folder` |

**For this app, create a file request in each account and paste that link.**
Files uploaded through a file request are encrypted in your browser, and they
count against that account's storage. I couldn't confirm from MEGA's site
whether free accounts can create file requests; if *File requests* doesn't
appear in a free account's web app, that's the reason.

**Tip:** sort by **STORAGE** to put the emptiest account on top, then click
its ↗ to upload there.

### Can I make the file requests from the MEGA desktop app, and will the column fill itself?

**Short answer: no, and no.** Make them in the **MEGA web app**, then paste
each link into the app once.

- **Not from the MEGA desktop app.** MEGA documents file requests as a
  feature of the web app (*Shared items → File requests*, or right-click a
  folder → *Create file request*). The MEGA Desktop App for macOS (sync,
  backups, transfers, share links) has no file-request option.
- **Not from MEGAcmd either**, so this app can't create them for you: MEGAcmd
  2.7.0 has no file-request command (`mega-help -f` doesn't mention one). Its
  closest thing, `export -a --writable`, makes a *writable folder link*, which
  only works through a MEGAcmd login, not in a browser (see the table above).
- **The root itself can't be the target.** A file request belongs to a
  **folder**. Create one at the top of each account's Cloud Drive (say
  `/Uploads`), then make the file request on it. Uploads land in that folder
  and count against that account's storage.
- **The UPLOAD FOLDER column doesn't fill itself.** Nothing in MEGAcmd can
  read a file request's address, so the app has no way to fetch it. Copy the
  `https://mega.nz/filerequest/…` link from the web app and paste it into the
  account's **UPLOAD FOLDER** cell (it saves to Supabase, so every device and
  the web version see it). For a new account you can also put it in **Add
  account** or in an `upload_folder_url` column of a CSV import.
- Free accounts: I still couldn't confirm from MEGA's own pages whether they
  can create file requests. If the option is missing in an account's web app,
  that's the likely reason.

Per account, it takes about a minute: log in at mega.nz → create `/Uploads` →
*Create file request* on it → copy the link → paste it into the row.

---

## 2. Is the web version secure with the login?

**Short answer: yes, now with two-step sign-in and encrypted passwords,
provided you tick the checklist below.** The web version is as secure as the
desktop app: both need your Supabase password **and** a 6-digit code, and both
only ever send `enc1:…` ciphertext for passwords and MEGA keys.

### What protects your data

| Layer | What it does |
|---|---|
| **Supabase sign-in** | Every request needs your Supabase user's session. Without signing in, nothing can be read. |
| ✅ **Two-step sign-in (A1, optional)** | Turn it on in 🛡 Security → **Turn on 2FA**. From then on, after the password the app asks for a 6-digit code from an authenticator app (Supabase TOTP). A *restrictive* Row Level Security policy makes the database itself refuse sessions that skipped the code (`aal2`), and Supabase won't remove or add a factor without one. **Turn off 2FA** asks for a current code. |
| ✅ **Encrypted passwords and MEGA keys (A2)** | The app encrypts them with AES-256-GCM before saving. The key comes from your master password (PBKDF2-SHA256, 600 000 rounds), wrapped so a recovery key also opens it. Supabase stores ciphertext only; the master password never leaves the device, and on the web it's never stored. |
| ✅ **Sign out when the browser closes (A3)** | A checkbox on the sign-in screen (and in 🛡 Security) keeps the session in `sessionStorage`, which the browser clears when the tab or browser closes. |
| **Row Level Security** (`supabase/schema.sql`) | The database itself only returns rows whose `user_id` is the signed-in user. The anonymous role has **no access at all**, so the publishable key alone is useless. |
| **No secrets in the web files** | The Supabase URL and key are **not** built into `build/web/`; each browser asks for them on first visit. Someone who finds your web address learns nothing about your project. |
| **HTTPS everywhere** | Supabase only speaks HTTPS; Cloudflare Pages, Netlify, Vercel and Firebase serve your site over HTTPS. |
| **Brute-force limits** | Supabase limits password sign-ins to **150 attempts per 5 minutes per IP address**. |
| **Rendering** | Flutter draws the page on a canvas and never inserts your data as HTML, so cross-site scripting has very little to work with. |
| **Headers** (`web/_headers`) | `X-Frame-Options: DENY` stops other sites from framing your app (clickjacking); `no-referrer` hides your URL. |

**Hosting the web version adds no new way into your data.** The Supabase API
was already reachable from the internet for the desktop app; the web build
is just another client of it.

### Weak spots (honest list)

1. ~~No 2FA on the app's sign-in.~~ ✅ Fixed (A1), but it's optional: it
   only protects you once you **turn it on**. Keep the authenticator app
   safe; if you lose it, delete the factor in Supabase (*Authentication →
   Users*), sign in with the password and turn it on again.
2. ~~Passwords and MEGA keys stored as plain text.~~ ✅ Fixed (A2). What's
   left in clear text in the table: emails, notes, upload folder links,
   dates and storage figures.
3. **The browser remembers you** unless you tick *Sign me out when I close
   the browser* (A3). Even then, the master password is asked on every page
   load, so a remembered session alone doesn't reveal passwords.
4. **"Remember on this Mac / PC"** (needed for scheduled checks) keeps the
   data key in the macOS Keychain or a DPAPI-protected file. Programs running
   as your user on that computer could read it. Only tick it on your own
   computer; signing out forgets it.
5. **Lose the master password and the recovery key, and the stored passwords
   are gone.** By design: nobody, including you with full Supabase access, can
   decrypt them. *Lost both?* on the unlock screen erases them so you can
   start again.
6. **Open sign-ups.** If *Allow new users to sign up* is still on in
   Supabase, strangers can create users in your project. Row Level Security
   still keeps them out of **your** rows, but they could add their own rows
   and use your quota.
7. **Your web host and GitHub accounts.** Whoever controls them could replace
   the app's code with one that steals your sign-in. Protect both with 2FA.
8. **Exported CSVs** go to your Downloads folder with every password in clear
   text (the export decrypts them).
9. **Leaked-password checks** (rejecting known breached passwords) need
   Supabase Pro. On Free, picking a strong password is up to you.

### Checklist: do these now

- [ ] Supabase → **Authentication → Sign In / Providers** → **Allow new users
      to sign up: OFF** ([SUPABASE_SETUP.md step 4](SUPABASE_SETUP.md#4-turn-off-public-sign-ups-recommended)).
      For a web deployment this is a **must**, not a recommendation.
- [ ] Use a **long, random, unique** password for your Supabase app user
      (from a password manager).
- [ ] Re-run `supabase/schema.sql`, set a **master password** in the app
      and store the **recovery key** in your password manager. Then turn on
      **2FA** (🛡 Security → **Turn on 2FA**); it's optional, but for a web
      deployment it's strongly recommended.
- [ ] Update every copy of the app (other computers, the web deployment):
      older copies can't read the table once 2FA is on.
- [ ] Turn on **2FA** for your Supabase account, GitHub account and web-host
      account.
- [ ] Host only on **HTTPS** and don't post the URL anywhere public.
- [ ] Optional extra lock: put the site behind **Cloudflare Access**, so even
      the sign-in page requires your email first.
- [ ] Delete exported CSVs from Downloads once you've stored them safely.

---

## 3. What else can MEGAcmd do?

MEGAcmd 2.7.0 has about 70 commands. The app uses seven today: `login`,
`whoami`, `df`, `ls` and `logout` on every check, plus `rm` (empty the Rubbish
Bin, `rm -r -f "//bin/*"`) and `deleteversions -f --all` when you ask it to
free space.

### Ground rules for any MEGAcmd feature

- **Desktop only** (macOS and Windows). Browsers can't run MEGAcmd.
- **One account at a time.** In MEGAcmd's words, "you can only log into one
  entity at a time". Every feature runs inside the same log in → do things →
  log out loop. Long-running features (sync, WebDAV, big uploads) would need
  to **pause the keep-alive loop** while they run.
- **Transfer quota.** Downloads (`get`) from free accounts are limited by
  MEGA's transfer quota; uploads aren't.
- **MEGA's Terms of Service** apply to automation and multiple accounts.
  Check them before building anything that creates, deletes or moves lots of
  accounts.

### The commands, grouped

| Group | Commands | What they do | Useful for this app? |
|---|---|---|---|
| **Account & session** | `login` (incl. `--auth-code` for 2FA, or a saved session), `logout [--keep-session]`, `whoami -l`, `session`, `killsession [-a]`, `passwd`, `masterkey`, `userattr` | log in/out, show plan, storage per folder and **active sessions**, kill other sessions, change password, **export the Recovery Key** | ⭐⭐⭐ |
| **Storage info** | `df`, `du [--versions]`, `mount` | totals (incl. **Rubbish Bin** and **file versions**), size per folder, list root folders | ⭐⭐⭐ |
| **Browse & search** | `ls -lR`, `tree`, `find --pattern= --size= --mtime=`, `cat`, `attr`, `mediainfo`, `thumbnail`, `preview` | list, search, read files and their metadata | ⭐⭐ |
| **Organise** | `mkdir`, `mv`, `cp`, `rm`, `deleteversions` | manage files; **free space** by emptying the bin or deleting old versions | ⭐⭐⭐ |
| **Transfers** | `put`, `get`, `transfers`, `speedlimit` | upload or download files and folders, watch progress, limit bandwidth | ⭐⭐ |
| **Sharing** | `export` (public links, `--writable`), `import`, `share`, `users`, `invite`, `ipc`, `showpcr` | create links, **copy a link's contents into another account**, share folders between accounts, contacts | ⭐⭐ |
| **Sync & backup** | `sync`, `sync-ignore`, `sync-issues`, `sync-config`, `exclude`, `backup --period --num-backups` | keep a local folder mirrored, scheduled backups | ⭐ needs a permanent login |
| **Serve as a drive** | `webdav`, `ftp` | mount an account folder in Finder / Explorer (default `localhost:4443`) | ⭐ needs a permanent login |
| **Account lifecycle** | `signup`, `confirm`, `cancel`, `confirmcancel` | create, confirm or delete MEGA accounts | ⚠️ ToS-sensitive, don't automate |
| **Tool & settings** | `version`, `update`, `proxy`, `https`, `permissions`, `configure`, `log`, `debug`, `errorcode`, `psa` | MEGAcmd version and updates, proxy, logs, turning error codes into text | ⭐ diagnostics |

### What this could turn into

The best ones, roughly from easiest to hardest:

- **Auto-fill the MEGA key.** `masterkey` exports the account's Recovery Key
  right after login, so the MEGA key column could fill itself on the next
  check instead of being typed by hand.
- ✅ **See reclaimable space.** Built: the **BIN · VERSIONS** column shows
  the Rubbish Bin and old-versions sizes from the `df` output, and 🧹 offers
  *Empty Rubbish Bin* and *Delete old file versions*, each behind an *Are you
  sure?*.
- **Plan and sessions per account.** `whoami -l` shows the Pro level, storage
  per main folder and the active sessions. Add a *Plan* column and a
  *Log out other sessions* action (`killsession -a`), a quick security sweep
  across all accounts.
- **Check 2FA accounts.** `login --auth-code=123456` accepts the 6-digit
  code. If the app stored each account's 2FA secret, it could generate the
  code itself, though keeping that secret next to the password weakens what
  2FA protects.
- **Upload into the emptiest account.** Pick a local folder; the app chooses
  the account with the most free space and runs `put`, showing progress from
  `transfers`.
- **Find any file across all accounts.** Run `find` or `ls -lR` during each
  check, store the file list in Supabase, and search *"which account has
  `holiday-2024.zip`?"* from the app or the web.
- **Move files between accounts without downloading them.** `export -a` a
  folder in account A, then `import <link>` it into account B. MEGA copies it
  server-side.
- **Open an account like a drive.** `webdav /` serves the account at
  `http://127.0.0.1:4443/…`: Finder → *Connect to Server* or Windows →
  *Map network drive*. Only while that account stays logged in.

---

## 4. Idea backlog

**Value**: how much it helps day to day. **Effort**: S ≈ an afternoon, M ≈ a
day or two, L ≈ several days.

### A. Security

| # | Idea | How | Value | Effort | Notes |
|---|---|---|---|---|---|
| A1 | ✅ **2FA on the app sign-in** (done, optional) | Supabase TOTP 2FA (free, on by default) + Turn on / Turn off in 🛡 Security + a code prompt after the password once it's on + a `restrictive` RLS policy requiring `aal2` | ⭐⭐⭐ | M | Closes weak spot #1 on the web, once turned on |
| A2 | ✅ **Encrypt passwords and MEGA keys** with a master password (done) | encrypt in the app before saving; Supabase only ever stores ciphertext | ⭐⭐⭐ | M–L | Built with a recovery key, so a forgotten master password alone isn't fatal |
| A3 | ✅ "Sign out when the browser closes" option (web, done) | keep the session in `sessionStorage` instead of `localStorage` | ⭐⭐ | S | |
| A4 | Content-Security-Policy header | add to `web/_headers` (Flutter needs `wasm-unsafe-eval` and the Supabase domain) | ⭐ | S | |
| A5 | **Log out other sessions** per account | `whoami -l` → `killsession -a` | ⭐⭐ | S | Security sweep across all accounts |

### B. Better checks (reuses the login that already happens)

| # | Idea | How | Value | Effort | Notes |
|---|---|---|---|---|---|
| B1 | **Auto-fill MEGA key** | `masterkey <tempfile>` → read → delete the file → save if the field is empty | ⭐⭐⭐ | S | Only fills empty fields; never overwrites |
| B2 | ✅ **Rubbish Bin and versions size** columns (done) | parse the extra lines of the `df` output already captured | ⭐⭐⭐ | S | No extra MEGAcmd command needed |
| B3 | **Plan / Pro level** column | parse `whoami -l` | ⭐⭐ | S | |
| B4 | **2FA accounts** | `login --auth-code=` + stored TOTP secret | ⭐⭐ | M | See the trade-off above |
| B5 | Faster checks with saved sessions | `logout --keep-session`, then `login <session>` next time | ⭐ | M | Unverified whether a resumed session counts as fresh activity for MEGA |
| B6 | "Stale" badge | highlight accounts not logged in for more than N days (setting) | ⭐⭐ | S | Pure UI |
| B7 | ✅ **Scheduled checks** (done) | macOS `launchd` / Windows Task Scheduler start the app with `--scheduled-check`: it checks all, then quits | ⭐⭐⭐ | M | Weekly, monthly or on a date. Keeps MEGA accounts **and** the free Supabase project active without opening the app |

### C. Storage management

| # | Idea | How | Value | Effort | Notes |
|---|---|---|---|---|---|
| C1 | ✅ **Free space: empty bin / delete versions** (done, with B2) | `rm -r -f` on the Rubbish Bin, `deleteversions -f --all` | ⭐⭐⭐ | S–M | Destructive: confirm dialog, per account |
| C2 | **Upload into the emptiest account** | pick a folder → choose the account → `put -c` → progress via `transfers` | ⭐⭐⭐ | L | Pauses the keep-alive loop while uploading |
| C3 | **Global file search** | `find`/`ls -lR` during checks → new `mega_files` table → search box (works on web) | ⭐⭐ | L | Thousands of files ≈ a few MB in Supabase, still fine on Free |
| C4 | Folder overview per account | `du -h` on top-level folders | ⭐⭐ | S | |
| C5 | Move data between accounts | `export -a` in A → `import` in B | ⭐⭐ | M | Server-side copy; check quota impact first |
| C6 | Create upload links automatically | `export -a --writable /Uploads` → save to `upload_folder_url` | ⭐ | M | Writable folder link ≠ file request: browser uploading needs testing first |
| C7 | Back up an account to disk | `get /folder ~/Backups/...` | ⭐ | M | Downloads use transfer quota on free accounts |

### D. Power features (need one account to stay logged in)

| # | Idea | How | Value | Effort |
|---|---|---|---|---|
| D1 | Open an account as a drive | `webdav /` → open `http://127.0.0.1:4443/` in Finder / Explorer | ⭐⭐ | M |
| D2 | Continuous sync / scheduled backups | `sync`, `backup --period=…` | ⭐ | L |
| D3 | Bandwidth limit for uploads | `speedlimit -u` | ⭐ | S |

### E. Web version

| # | Idea | How | Value | Effort | Notes |
|---|---|---|---|---|---|
| E1 | Checks from the web | re-implement MEGA's login protocol (e.g. the `megajs` library) in a Supabase Edge Function | ⭐⭐ | L | MEGAcmd can't run there; Edge Function CPU limits and MEGA's ToS apply |
| E2 | "Last checked by desktop at …" banner | show the newest `last_checked_at` on the web | ⭐ | S | Tells you how fresh the data is |

### Suggested order (what's left)

1. **B1** auto-fill MEGA key: small, and useful on every check.
2. **A5** log out other sessions and **B6** "stale" badge: quick wins.
3. **C2** upload into the emptiest account.
4. **A4** Content-Security-Policy header for the web version.

---

## 5. Does the web build use WebAssembly or CanvasKit?

**CanvasKit, with the app compiled to JavaScript.** That's Flutter's default
for `flutter build web` without `--wasm`, which is how `build_web.sh` and the
release workflow build it. The built `build/web/flutter_bootstrap.js` says so:

```
"compileTarget":"dart2js", "renderer":"canvaskit", "mainJsPath":"main.dart.js"
```

The two words get mixed up because CanvasKit is itself WebAssembly: it's the
Skia graphics engine compiled to `canvaskit.wasm`. So the **drawing** runs as
WebAssembly, while **your app's Dart code** runs as JavaScript
(`main.dart.js`). `build/web/canvaskit/` also contains `skwasm*` files; they're
bundled by `--no-web-resources-cdn` but unused unless you build with `--wasm`.

| | Default (now) | `--wasm` |
|---|---|---|
| App code | JavaScript (dart2js) | WebAssembly (dart2wasm) |
| Renderer | CanvasKit | Skwasm |
| Browsers | all modern ones | Chrome, Edge, Firefox; others (e.g. Safari) automatically get the JavaScript + CanvasKit build |
| Speed | good | faster start-up and smoother scrolling |

The app passes Flutter's WebAssembly dry run (the build prints "Wasm dry run
succeeded"), so switching is one flag: `./build_web.sh --wasm`. Test it in
your browsers before deploying.

---

## Sources

- MEGAcmd 2.7.0 built-in help: `mega-help -f`, `mega-login --help`,
  `mega-export --help`, `mega-whoami --help`, `mega-killsession --help`,
  `mega-exec masterkey --help`, `mega-help --paths`, `mega-rm --help`,
  `mega-deleteversions --help`
- [MEGAcmd source, `megacmdexecuter.cpp`](https://github.com/meganz/MEGAcmd/blob/master/src/megacmdexecuter.cpp):
  the `df` output format (`Rubbish bin:` and `Total size taken up by file
  versions:` lines, 12-character size columns), `//bin` = Rubbish Bin, and
  `rm` expanding `*` itself
- [Supabase TOTP enrolment API](https://supabase.com/docs/reference/dart/auth-mfa-enroll)
  (`enroll`, `challengeAndVerify`, `getAuthenticatorAssuranceLevel`)
- Flutter 3.44 `flutter build web` output (`flutter_bootstrap.js` build config)
  and [Flutter's WebAssembly guide](https://docs.flutter.dev/platform-integration/web/wasm)
- `url_launcher_web` 2.4.3 source: links open with `window.open(url, target, 'noopener,noreferrer')`
- [Supabase Auth rate limits](https://supabase.com/docs/guides/auth/rate-limits): 150 password sign-ins per 5 min per IP
- [Supabase TOTP 2FA](https://supabase.com/docs/guides/auth/auth-mfa/totp): "free to use and is enabled on all Supabase projects by default"
- [Supabase MFA and RLS](https://supabase.com/docs/guides/auth/auth-mfa): `restrictive` policies requiring `aal2`
- [Supabase password security](https://supabase.com/docs/guides/auth/password-security): leaked-password protection is Pro and above
- [MEGA help: file requests](https://help.mega.io/files-folders/sharing/file-request): anyone can upload, including people without a MEGA account
