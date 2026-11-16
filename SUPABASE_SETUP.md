# Supabase setup (first time)

The app stores your MEGA accounts in **your own Supabase project** (a hosted
PostgreSQL database). The **Free plan** is enough. Setup takes about 10 minutes
and you only do it once.

You'll end up with:

| What | Where it's used |
|---|---|
| A table called `mega_accounts`, protected by Row Level Security | holds emails, encrypted passwords and MEGA keys, last login, storage |
| A table called `mega_vault` | your encrypted data key (needs your master password to be useful) |
| One Supabase **user** (an email + password you choose) | you sign in to the app with it |
| The **Project URL** + **publishable key** | pasted into the app once |

> You do **not** need the database password in the app. Keep it in your
> password manager. (Your local `.env.supabase` is now git-ignored so it can't
> be committed by accident.)

---

## 1. Create the project (skip if you already have one)

1. Go to <https://supabase.com> → **Start your project** → sign in (GitHub
   sign-in is easiest).
2. **New project**:
   - **Organization**: your personal one (Free plan).
   - **Name**: e.g. `mega-keepalive`.
   - **Database password**: click *Generate*, then save it in your password
     manager. The app never asks for it.
   - **Region**: the one closest to you (e.g. *Central EU (Frankfurt)*).
3. Click **Create new project** and wait 1–2 minutes until it's ready.

## 2. Create the table (run the SQL once)

1. In the left sidebar open **SQL Editor** → **New query**.
2. Open [`supabase/schema.sql`](supabase/schema.sql) from this repo, copy
   **everything**, paste it into the editor.
3. Click **Run** (or ⌘↵). You should see *"Success. No rows returned"*.
4. Check it worked: **Table Editor** → you should see `mega_accounts` with an
   **RLS enabled** label.

What the script does:

- creates `mega_accounts` (email, password, mega_key, notes,
  upload_folder_url, last_login_at, last_checked_at, last_status, last_error,
  storage_used_bytes, storage_total_bytes, storage_rubbish_bytes,
  storage_versions_bytes, …),
- creates `mega_vault`, one row per user holding the **encrypted** key that
  protects your MEGA passwords (see [Security notes](#security-notes)),
- turns on **Row Level Security** so a signed-in user can only read and write
  **their own** rows,
- adds a **2FA rule** (a *restrictive* policy): 2FA is optional, but once
  you've turned it on, both tables answer only sessions that also passed the
  6-digit code (`aal2`), so your Supabase password alone gets nothing,
- removes all access for anonymous requests (the publishable key alone can't
  read anything).

It's safe to run again if you're unsure whether it worked.

### Updating an existing project

When a new version of the app adds a column, open the **SQL Editor**, paste
the whole [`supabase/schema.sql`](supabase/schema.sql) again and click
**Run**. It keeps your data and only adds what's missing.

| App version | Database change |
|---|---|
| Upload folder URL | adds `upload_folder_url` (text, default empty) |
| 2FA, master password, bin / versions, scheduled checks (v1.1) | adds `mega_vault`, the 2FA policies, `storage_rubbish_bytes` and `storage_versions_bytes` |
| Pinned accounts (v1.2) | adds `pinned_at` (timestamp, empty = not pinned) |

**Coming from v1.0 you need the update:** after sign-in the app opens your
encryption settings, and stops with *Table "mega_vault" not found* until
you've re-run the script. Your accounts are untouched; their passwords are
encrypted the first time you unlock.

**Coming from v1.1:** everything works without the update except 📌 pins,
which say *missing a column* until you re-run the script.

> Once you turn on 2FA in the new app, **older copies of the app** (on
> another computer, or an old web deployment) see an empty list, because
> they can't pass the 2FA rule. Update every copy.

## 3. Create your app user

1. Sidebar → **Authentication** → **Users** → **Add user** → **Create new user**.
2. Enter **your email** and a **strong password** (this is the password you'll
   type into the app; it's unrelated to MEGA).
3. Tick **Auto Confirm User**, then **Create user**.

## 4. Turn off public sign-ups (recommended)

So nobody else can create a user in your project:

**Authentication** → **Sign In / Providers** → under *User Signups*, switch
**Allow new users to sign up** **off** → **Save**.

(Even if someone did sign up, Row Level Security keeps them out of your rows.
This just closes the door completely.)

## 5. Copy the two values the app needs

1. **Project URL** looks like `https://abcdefghijkl.supabase.co`. Find it under
   **Project Settings → Data API** (it's also on the project's home page and in
   the **Connect** dialog).
2. **Publishable key** starts with `sb_publishable_`. Find it under
   **Project Settings → API Keys**.

> ⚠️ Never use a **secret** key (`sb_secret_…`) or the legacy
> **service_role** key in the app. They bypass all security. The app refuses
> them anyway.

## 6. Check that 2FA is allowed (it is by default)

**Authentication → Multi-Factor** (on some dashboards: *Sign In / Providers
→ Multi-Factor*) → **TOTP (App Authenticator)** should be **Enabled**. It's
free on every plan. 2FA is optional in the app; this only matters if you
turn it on (🛡 **Security → Turn on 2FA**).

## 7. Connect the app

1. Start the app (see [README.md](README.md#quick-start)).
2. The first screen is **Connect to Supabase**. Paste the **Project URL** and
   **publishable key**, then click **Save & connect**. The app tests them and
   saves them on this computer (or in this browser, for the web version), so
   you only do this once per device.
3. **Sign in** with the user from step 3.
4. **Set a master password** and **save the recovery key** it shows (password
   manager, or on paper). The master password encrypts your MEGA passwords
   and keys on your device; Supabase never sees it. On a Mac or PC you can
   tick **Remember on this Mac / PC** so the app opens without it (scheduled
   checks need this).
5. Click **Paste list** and paste your MEGA accounts, one per line:

   ```
   first@gmail.com:Password1
   second@gmail.com,Password2
   third@outlook.com Password3
   ```
6. **Optional, recommended:** 🛡 in the header → **Turn on 2FA** → scan the
   QR code with an authenticator app on your phone and type the 6-digit code.
   From then on every sign-in asks for a code after your password (see
   [Security notes](#security-notes)).

You're done. Open **Table Editor → mega_accounts** in Supabase any time to see
the raw data.

---

## Free plan: what to know

- **Limits**: 500 MB database and 5 GB egress a month, far more than this app
  will ever use (about 0.1 MB and 3 MB a month with 40 accounts). Full
  breakdown: [SUPABASE_USAGE.md](SUPABASE_USAGE.md).
- **Pausing**: free projects are **paused after ~1 week without activity**.
  Using the app counts as activity. If it does pause, the app shows *"Can't
  reach Supabase…"*. Open the Supabase dashboard and click **Restore project**
  (takes a minute or two). Your data is kept.
- **Backups**: the Free plan has no downloadable backups. Use **Export CSV** in
  the app now and then to keep your own copy (store it somewhere private: it
  contains passwords).

## Security notes

- **Passwords and MEGA keys are encrypted in the app** before they're saved
  (AES-256-GCM). The key comes from your **master password** (PBKDF2-SHA256,
  600 000 rounds) and never leaves your device. The table only holds
  `enc1:…` text, so someone who gets into your Supabase dashboard or database
  sees emails, notes and dates, but **not** the passwords or keys.
- **Recovery key:** the data key is also encrypted with a random recovery key
  shown once when you set the master password. Keep it safe. If you lose both
  the master password and the recovery key, nobody can decrypt the stored
  passwords; the unlock screen's **Lost both?** erases them so you can start
  again (emails, notes and history stay).
- **2FA (optional, recommended):** 🛡 **Security → Turn on 2FA**, scan the
  QR code with an authenticator app (Google Authenticator, Microsoft
  Authenticator, 1Password, Bitwarden…) and type the 6-digit code. From then
  on every sign-in asks for a code after the password, a stolen Supabase
  password isn't enough, and the database itself refuses sessions without
  the code. **Turn off 2FA** asks for a current code. Lost the phone? Delete
  the factor in **Authentication → Users → your user**, then sign in with
  just your password and turn it on again.
- **Remember on this Mac / PC** keeps the data key in the macOS Keychain or a
  DPAPI-encrypted file on Windows. Anything running as your user account on
  that computer could read it, so only tick it on your own computer. Signing
  out forgets it.
- Still protect your **Supabase and GitHub logins with 2FA**, and keep
  exported CSV files private: they contain the passwords in clear text.

## Changing project / resetting the app

- **Switch project or fix a wrong key**: click the server icon in the app's
  header (*Supabase project settings*). The connect screen reopens with the
  current values filled in.
- **Wipe all local app settings** (URL, key, signed-in session, UI prefs):

  ```sh
  defaults delete com.megakeepalive.megaKeepalive    # macOS
  ```

  Windows: delete the folder `%APPDATA%\com.megakeepalive\mega-checker-app\`.
  Web: clear the site's data in your browser's settings.
- **Forget a remembered master password by hand**: macOS
  `security delete-generic-password -s mega-checker-app` (repeat until it says
  *could not be found*); Windows: delete `%APPDATA%\mega-checker-app\keys\`.
  The scheduled-check log and lock files live next to it
  (`~/Library/Application Support/mega-checker-app/` on macOS).
