# Supabase usage: will this app eat my Free plan?

**Short answer: no.** With **40 MEGA accounts** the app uses **well under 1 %
of every Free-plan limit**, even if you use it heavily. The only Free-plan rule
that can actually affect you is **pausing after 1 week without activity**, and
using the app at least once a week prevents it.

> Limits are from <https://supabase.com/pricing>, checked on 15 Nov 2026. Usage
> figures are estimates calculated from the exact requests the app makes (see
> [How the numbers were worked out](#how-the-numbers-were-worked-out)).

---

## 1. Comparison table: 40 MEGA accounts vs the Free plan

Two example months:

- **Typical**: app opened twice a day, **Check all accounts** once a day,
  about 100 edits a month, app open about 3 h a day.
- **Heavy**: desktop app open 24/7 plus a browser tab, **Check all** 3 times
  a day, opened or reloaded 10 times a day, about 300 edits.

| Resource | Free plan limit | 40 accounts, typical month | 40 accounts, heavy month | Share of the limit | OK? |
|---|---|---|---|---|---|
| **Database size** | 500 MB | ≈ 0.1 MB | ≈ 0.1 MB | ≈ 0.02 % | ✅ |
| **Egress** (data downloaded from Supabase) | 5 GB / month | ≈ 2.6 MB | ≈ 13 MB | 0.05 % – 0.26 % | ✅ |
| **Cached egress** | 5 GB / month | 0 | 0 | 0 % | ✅ not used |
| **API requests** | Unlimited | ≈ 1,450 | ≈ 5,600 | n/a | ✅ |
| **Monthly active users** | 50,000 | 1 (you) | 1 | 0.002 % | ✅ |
| **File storage** | 1 GB | 0 (CSV exports stay on your computer) | 0 | 0 % | ✅ not used |
| **Edge Function invocations** | 500,000 / month | 0 | 0 | 0 % | ✅ not used |
| **Realtime** messages / connections | 2 million / 200 | 0 / 0 | 0 / 0 | 0 % | ✅ not used |
| **Inactivity pause** | paused after 1 week with no activity | doesn't happen if you open the app weekly | doesn't happen | n/a | ⚠️ the one to watch |

**Verdict:** you could use the app like this for decades without getting near a
limit. To reach the 5 GB egress limit you'd need about **2,000× the typical
month**.

---

## 2. What the app actually sends to Supabase

| Action in the app | Supabase requests | Downloaded (egress) |
|---|---|---|
| Open the app / ⟳ reload | 1 read of your account rows | ≈ 0.6 KB per account + 0.7 KB of headers → **≈ 25 KB for 40 accounts** |
| Check one account (▶, **Check all**, **Recheck failed**) | 1 update per account | **≈ 0.7 KB**: the reply has no body, only headers |
| Edit a cell (email, password, MEGA key, upload folder URL, notes) | 1 update, 0.8 s after you stop typing | ≈ 0.7 KB |
| Add account / Paste list / Import CSV | 1 insert for the whole batch | ≈ 0.6 KB per new account |
| Delete an account | 1 delete | ≈ 0.7 KB |
| Sign in | 1 auth request (rare: the session is remembered) | ≈ 2 KB |
| Staying signed in | 1 token refresh about every hour **while the app is open** | ≈ 2 KB each |
| Export CSV | none: built from what's already on screen | 0 |
| Sort, search, show passwords, open upload folder | none: all done locally | 0 |

What **never** touches Supabase:

- **The MEGA logins themselves.** MEGAcmd talks straight to MEGA's servers.
- **The web app's files** (about 10 MB the first time a browser opens it).
  They come from your web host (Netlify, Cloudflare, …), not from Supabase.
- **Storage, Realtime, Edge Functions**: the app doesn't use them.

---

## 3. What if I add more accounts?

Typical month (as above), scaled up:

| MEGA accounts | Egress / month | % of 5 GB | Database size | % of 500 MB | One "Check all" takes about* |
|---|---|---|---|---|---|
| **40** | ≈ 2.6 MB | 0.05 % | ≈ 0.1 MB | 0.02 % | **17 min** |
| 100 | ≈ 6 MB | 0.1 % | ≈ 0.25 MB | 0.05 % | 45 min |
| 200 | ≈ 12 MB | 0.2 % | ≈ 0.5 MB | 0.1 % | 1 h 25 min |
| 1,000 | ≈ 60 MB | 1.2 % | ≈ 2.5 MB | 0.5 % | 7 h |
| 5,000 | ≈ 290 MB | 5.8 % | ≈ 12 MB | 2.5 % | 35 h (can't run daily) |

\* Each check is a MEGAcmd login (≈ 8 s) plus the random 10–25 s pause
between accounts.

**Supabase is never the bottleneck.** Long before Supabase limits matter, a
single "Check all" would take longer than a day.

---

## 4. Free vs Pro: do I ever need to pay?

| | **Free** | **Pro** |
|---|---|---|
| Price | $0 | from $25 / month (includes $10 compute credit) |
| Database size | 500 MB | 8 GB, then $0.125 / GB |
| Egress | 5 GB | 250 GB, then $0.09 / GB |
| Monthly active users | 50,000 | 100,000 |
| Paused when inactive | **yes, after 1 week** | never |
| Active projects | 2 | more allowed, each billed for its compute |
| **Needed for this app?** | **✅ yes, this is enough** | ❌ only if you want to never think about pausing |

**Recommendation: stay on Free.** The only thing Pro would change for this app
is that the project never pauses.

---

## 5. The one thing to watch: pausing

- Free projects are **paused after 1 week of inactivity**. Opening the app or
  running a check counts as activity, so weekly use is enough.
- If it does pause, the app shows *"Can't reach Supabase…"*. Open the
  Supabase dashboard → your project → **Restore project** (takes 1–2 min).
  **Your data is kept.**
- Tip: running **Check all accounts** once a week keeps both your MEGA
  accounts and your Supabase project active.

## 6. Check your real usage

Supabase dashboard → your organization → **Usage**. It shows database size,
egress and MAU for the current billing cycle. Expect egress in the **single
megabytes** per month and a database size dominated by Supabase's own system
tables (auth, storage, …), which exist in every project, even an empty one.

---

## How the numbers were worked out

- **Row size:** a realistic `mega_accounts` row (UUIDs, 27-character email,
  password, MEGA key, short note, upload folder link, timestamps, storage
  numbers) is **614 bytes** of JSON. With a 300-character note it's 875 bytes.
  40 rows ≈ 24.6 KB per full load.
- **Updates:** the app's updates don't ask for the row back, so Supabase
  replies *204 No Content*: only the response headers (≈ 0.7 KB).
- **Worst case on purpose:** the figures ignore compression. Supabase
  compresses responses for clients that accept it, so real egress is usually
  lower.
- **Typical month:** 60 loads × 25 KB + 1,200 check updates × 0.7 KB +
  100 edits × 0.7 KB + 90 token refreshes × 2 KB ≈ **2.6 MB**.
- **Heavy month:** 300 loads × 25 KB + 3,600 check updates × 0.7 KB +
  300 edits × 0.7 KB + 1,440 token refreshes × 2 KB (2 devices, open 24/7) ≈
  **13 MB**.
- **Database size:** 40 rows × ≈ 0.6 KB of data, stored by PostgreSQL in 8 KB
  pages plus two indexes (primary key, unique email) ≈ 0.1 MB. Updates leave
  old row versions that autovacuum cleans up, so it stays well under 0.5 MB.
  It grows with the **number of accounts**, not with how often you check them.

Sources: [Supabase pricing](https://supabase.com/pricing) (Free / Pro limits,
"Unlimited API requests", "Free projects are paused after 1 week of
inactivity").
