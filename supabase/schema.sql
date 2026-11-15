-- =============================================================================
-- MEGA Keep-Alive — Supabase schema
--
-- Run ONCE: Supabase dashboard → your project → SQL Editor → "New query" →
-- paste this whole file → "Run". It is safe to run again (idempotent).
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
  last_login_at       timestamptz,                       -- last SUCCESSFUL login
  last_checked_at     timestamptz,                       -- last attempt (ok or not)
  last_status         text        check (last_status in ('ok', 'failed')),
  last_error          text,
  storage_used_bytes  bigint,                            -- from `mega-df` on last success
  storage_total_bytes bigint,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint mega_accounts_user_email_key unique (user_id, email)
);

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
