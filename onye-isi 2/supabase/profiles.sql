-- ONYE ISI: user profiles for customers and vendors (stylists)
-- Run once in Supabase (SQL Editor > New query > Run), after schema.sql. Safe to run again.

create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       text not null default 'customer' check (role in ('customer','stylist')),
  full_name  text check (char_length(full_name) <= 80),
  phone      text check (char_length(phone) <= 30),
  hair_type  text check (char_length(hair_type) <= 30),   -- customers only (optional)
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- Every new sign-up (email or Google) automatically gets a profile; the role comes from the sign-up form
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, role, full_name)
  values (
    new.id,
    case when new.raw_user_meta_data->>'role' = 'stylist' then 'stylist' else 'customer' end,
    left(coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), nullif(new.raw_user_meta_data->>'name', ''), split_part(new.email, '@', 1)), 80)
  )
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Create profiles for accounts that already exist
insert into public.profiles (id, role, full_name)
select u.id,
       case when u.raw_user_meta_data->>'role' = 'stylist' then 'stylist' else 'customer' end,
       left(coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), nullif(u.raw_user_meta_data->>'name', ''), split_part(u.email, '@', 1)), 80)
from auth.users u
on conflict (id) do nothing;

-- Each person can read and edit only their own profile (no inserting or deleting from the website)
drop policy if exists "read own profile" on public.profiles;
create policy "read own profile" on public.profiles for select to authenticated using (id = auth.uid());
drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (role, full_name, phone, hair_type) on public.profiles to authenticated;
