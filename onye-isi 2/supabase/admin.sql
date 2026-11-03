-- ONYE ISI: admin role and stylist approval
-- Run once in Supabase (SQL Editor > New query > Run), after schema.sql. Safe to run again.

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;   -- no direct access from the website; only the functions below read it

create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid())
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- Admins can read every stylist profile (pending and rejected included)
drop policy if exists "admins read all stylists" on public.stylists;
create policy "admins read all stylists" on public.stylists
  for select to authenticated using (public.is_admin());

-- Approving or rejecting goes through this function, so no one else can change a status
create or replace function public.admin_set_stylist_status(p_id bigint, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p_status not in ('pending','approved','rejected') then raise exception 'invalid status'; end if;
  update public.stylists set status = p_status where id = p_id;
end $$;
revoke all on function public.admin_set_stylist_status(bigint, text) from public, anon;
grant execute on function public.admin_set_stylist_status(bigint, text) to authenticated;

-- ───────────── Make yourself an admin ─────────────
-- 1) Create your account on the site first (Log in > Create account).
-- 2) Then run this line with YOUR email in place of the placeholder:
--
-- insert into public.admins (user_id) select id from auth.users where email = 'you@example.com' on conflict do nothing;
