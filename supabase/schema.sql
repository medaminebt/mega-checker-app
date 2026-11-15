-- =============================================================================
-- MEGA Keep-Alive — Supabase schema
--
-- Run ONCE: Supabase dashboard → your project → SQL Editor → "New query" →
-- paste this whole file → "Run". It is safe to run again (idempotent), and
-- running it again is also how an existing project gets new columns and
-- tables (this version adds: storage_rubbish_bytes, storage_versions_bytes,
-- the mega_vault table and the 2FA policies).
-- =============================================================================

-- One row per MEGA account, owned by the Supabase user who created it.
create table if not exists public.mega_accounts (
  id                  uuid        primary key default gen_random_uuid(),
  user_id             uuid        not null default auth.uid()
                                  references auth.users (id) on delete cascade,
  email               text        not null,
  password            text        not null default '',
  mega_key            text        not null default '',  -- MEGA recovery key (typed in by hand)
  notes               text        not null default '',
  upload_folder_url   text        not null default '',  -- MEGA upload folder link
  last_login_at       timestamptz,                       -- last SUCCESSFUL login
  last_checked_at     timestamptz,                       -- last attempt (ok or not)
  last_status         text        check (last_status in ('ok', 'failed')),
  last_error          text,
  storage_used_bytes  bigint,                            -- from `mega-df` on last success
  storage_total_bytes bigint,
  storage_rubbish_bytes  bigint,                         -- Rubbish Bin size (mega-df)
  storage_versions_bytes bigint,                         -- old file versions size (mega-df)
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint mega_accounts_user_email_key unique (user_id, email)
);

-- Columns added after the first release (no-ops on a fresh table).
alter table public.mega_accounts
  add column if not exists upload_folder_url      text not null default '',
  add column if not exists storage_rubbish_bytes  bigint,
  add column if not exists storage_versions_bytes bigint;

-- password and mega_key hold "enc1:…" ciphertext once you set a master
-- password in the app (see public.mega_vault below). Supabase never sees
-- them in clear text after that.
comment on column public.mega_accounts.password is
  'MEGA password, encrypted in the app (enc1:...) once a master password is set.';
comment on column public.mega_accounts.mega_key is
  'MEGA recovery key, encrypted in the app (enc1:...) once a master password is set.';

comment on table public.mega_accounts is
  'MEGA accounts checked by the MEGA Keep-Alive desktop app.';

-- Keep updated_at current on every change.
create or replace function public.mega_accounts_touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists mega_accounts_touch_updated_at on public.mega_accounts;
create trigger mega_accounts_touch_updated_at
  before update on public.mega_accounts
  for each row execute function public.mega_accounts_touch_updated_at();

-- -----------------------------------------------------------------------------
-- Security: Row Level Security — a signed-in user only ever sees their rows.
-- The publishable key alone (no sign-in = "anon" role) gets no access at all.
-- -----------------------------------------------------------------------------
alter table public.mega_accounts enable row level security;

drop policy if exists "Owner can read"   on public.mega_accounts;
drop policy if exists "Owner can insert" on public.mega_accounts;
drop policy if exists "Owner can update" on public.mega_accounts;
drop policy if exists "Owner can delete" on public.mega_accounts;

create policy "Owner can read" on public.mega_accounts
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Owner can insert" on public.mega_accounts
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Owner can update" on public.mega_accounts
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Owner can delete" on public.mega_accounts
  for delete to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.mega_accounts from anon;
grant select, insert, update, delete on table public.mega_accounts to authenticated;

-- -----------------------------------------------------------------------------
-- Master password ("vault"): one row per user. It holds the random data key
-- that encrypts passwords and MEGA keys, itself encrypted twice: with a key
-- derived from your master password (PBKDF2-SHA256) and with your recovery
-- key. Nothing in this row can decrypt anything without one of those two,
-- and the app never sends either of them to Supabase.
-- -----------------------------------------------------------------------------
create table if not exists public.mega_vault (
  user_id              uuid        primary key default auth.uid()
                                   references auth.users (id) on delete cascade,
  kdf                  text        not null default 'pbkdf2-sha256',
  kdf_iterations       integer     not null check (kdf_iterations >= 100000),
  kdf_salt             text        not null,  -- base64
  wrapped_key          text        not null,  -- data key, encrypted with the master password
  recovery_wrapped_key text,                  -- data key, encrypted with the recovery key
  key_check            text        not null,  -- known text encrypted with the data key
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

comment on table public.mega_vault is
  'Encrypted data key for the MEGA Keep-Alive app (client-side encryption).';

drop trigger if exists mega_vault_touch_updated_at on public.mega_vault;
create trigger mega_vault_touch_updated_at
  before update on public.mega_vault
  for each row execute function public.mega_accounts_touch_updated_at();

alter table public.mega_vault enable row level security;

drop policy if exists "Owner can read"   on public.mega_vault;
drop policy if exists "Owner can insert" on public.mega_vault;
drop policy if exists "Owner can update" on public.mega_vault;
drop policy if exists "Owner can delete" on public.mega_vault;

create policy "Owner can read" on public.mega_vault
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Owner can insert" on public.mega_vault
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Owner can update" on public.mega_vault
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Owner can delete" on public.mega_vault
  for delete to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.mega_vault from anon;
grant select, insert, update, delete on table public.mega_vault to authenticated;

-- -----------------------------------------------------------------------------
-- Two-factor sign-in (2FA). The app makes you add an authenticator app the
-- first time you sign in. From then on these RESTRICTIVE policies refuse every
-- read and write unless the session also passed the 6-digit code ("aal2"),
-- so a stolen Supabase password alone gets nothing.
--
-- Users without a verified 2FA factor are not blocked (that's how the app
-- can let you set 2FA up). Supabase itself refuses to remove a verified
-- factor, or add another one, without a 2FA-verified session.
--
-- Stricter alternative (blocks users who never set up 2FA, too): make the
-- function below return  coalesce((select auth.jwt() ->> 'aal'), '') = 'aal2'
-- -----------------------------------------------------------------------------

-- True when this request may touch the data: the session passed the 2FA code,
-- or the user has no verified 2FA factor yet. SECURITY DEFINER so it can look
-- at auth.mfa_factors whatever the signed-in role may read; it only ever
-- answers about the caller (auth.uid()).
create or replace function public.mega_mfa_ok()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select auth.jwt() ->> 'aal'), '') = 'aal2'
      or not exists (
           select 1
           from auth.mfa_factors
           where user_id = (select auth.uid())
             and status = 'verified'
         );
$$;

revoke all on function public.mega_mfa_ok() from public, anon;
grant execute on function public.mega_mfa_ok() to authenticated;

drop policy if exists "Require 2FA once enrolled" on public.mega_accounts;
create policy "Require 2FA once enrolled" on public.mega_accounts
  as restrictive
  for all to authenticated
  using ((select public.mega_mfa_ok()))
  with check ((select public.mega_mfa_ok()));

drop policy if exists "Require 2FA once enrolled" on public.mega_vault;
create policy "Require 2FA once enrolled" on public.mega_vault
  as restrictive
  for all to authenticated
  using ((select public.mega_mfa_ok()))
  with check ((select public.mega_mfa_ok()));

-- Make the API (PostgREST) pick up new columns right away.
notify pgrst, 'reload schema';
