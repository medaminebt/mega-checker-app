# Supabase setup (first time)

The app stores your MEGA accounts in **your own Supabase project** (a hosted
PostgreSQL database). The **Free plan** is enough. Setup takes about 10 minutes
and you only do it once.

You'll end up with:

| What | Where it's used |
|---|---|
| A table called `mega_accounts`, protected by Row Level Security | holds emails, passwords, MEGA keys, last login, storage |
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

- creates `mega_accounts` (email, password, mega_key, notes, last_login_at,
  last_checked_at, last_status, last_error, storage_used_bytes,
  storage_total_bytes, …),
- turns on **Row Level Security** so a signed-in user can only read and write
  **their own** rows,
- removes all access for anonymous requests (the publishable key alone can't
  read anything).

It's safe to run again if you're unsure whether it worked.

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

## 6. Connect the app

1. Start the app (see [README.md](README.md#run-it-on-your-mac)).
2. The first screen is **Connect to Supabase**. Paste the **Project URL** and
   **publishable key**, then click **Save & connect**. The app tests them and
   saves them on your Mac (shared_preferences), so you only do this once.
3. **Sign in** with the user from step 3.
4. Click **Paste list** and paste your MEGA accounts, one per line:

   ```
   first@gmail.com:Password1
   second@gmail.com,Password2
   third@outlook.com Password3
   ```

You're done. Open **Table Editor → mega_accounts** in Supabase any time to see
the raw data.

---

## Free plan: what to know

- **Limits**: 500 MB database, which is far more than this app will ever use.
- **Pausing**: free projects are **paused after ~1 week without activity**.
  Using the app counts as activity. If it does pause, the app shows *"Can't
  reach Supabase…"*. Open the Supabase dashboard and click **Restore project**
  (takes a minute or two). Your data is kept.
- **Backups**: the Free plan has no downloadable backups. Use **Export CSV** in
  the app now and then to keep your own copy (store it somewhere private: it
  contains passwords).

## Security notes

- Passwords and MEGA keys are stored **as plain text** in the table. They're
  protected by Row Level Security and your Supabase sign-in, and Supabase
  encrypts data at rest. But anyone who can open your Supabase dashboard
  (you) or who has the database password can read them. Protect your
  Supabase/GitHub login with **2FA**.
- If you'd like client-side encryption (a master password, so Supabase only
  ever sees ciphertext), that can be added later.

## Changing project / resetting the app

- **Switch project or fix a wrong key**: click the server icon in the app's
  header (*Supabase project settings*). The connect screen reopens with the
  current values filled in.
- **Wipe all local app settings** (URL, key, signed-in session, UI prefs):

  ```sh
  defaults delete com.megakeepalive.megaKeepalive
  ```
