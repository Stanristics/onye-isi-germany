-- ONYE ISI: complete database setup (all four scripts in the right order)
-- Paste this whole file into Supabase > SQL Editor > New query, then click Run.
-- Safe to run more than once.


-- ════════════════ schema.sql ════════════════
-- ONYE ISI: database schema and row-level security
-- Run once in Supabase: SQL Editor > New query > paste > Run.

-- ───────────── Tables ─────────────
create table if not exists public.stylists (
  id          bigint generated always as identity primary key,
  owner_id    uuid references auth.users(id) on delete set null,
  name        text   not null check (char_length(name) between 2 and 80),
  spec        text   not null check (char_length(spec) <= 120),
  city        text   not null check (char_length(city) <= 60),
  type        text   not null check (type in ('braiding','locs','natural','barbing','weave')),
  price_from  text   check (char_length(price_from) <= 30),
  bio         text   check (char_length(bio) <= 600),
  avail       text   check (char_length(avail) <= 80),
  color       text   default '#F6E2B8' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  services    jsonb  not null default '[]'::jsonb,   -- [["Knotless braids","€110–180"], ...]
  status      text   not null default 'pending' check (status in ('pending','approved','rejected')),
  is_example  boolean not null default false,        -- sample rows; delete them once you have real stylists
  created_at  timestamptz not null default now()
);

create table if not exists public.bookings (
  id             bigint generated always as identity primary key,
  stylist_id     bigint not null references public.stylists(id) on delete cascade,
  customer_id    uuid references auth.users(id) on delete set null,  -- null for guest bookings
  customer_name  text not null check (char_length(customer_name) between 2 and 80),
  customer_email text not null check (customer_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(customer_email) <= 120),
  customer_phone text check (char_length(customer_phone) <= 30),
  service        text not null check (char_length(service) <= 120),
  preferred_date date not null,
  notes          text check (char_length(notes) <= 1000),
  status         text not null default 'pending' check (status in ('pending','confirmed','cancelled')),
  created_at     timestamptz not null default now()
);

create index if not exists bookings_stylist_idx  on public.bookings (stylist_id);
create index if not exists bookings_customer_idx on public.bookings (customer_id);
create unique index if not exists stylists_one_per_owner on public.stylists (owner_id) where owner_id is not null;

-- ───────────── Row-level security ─────────────
alter table public.stylists enable row level security;
alter table public.bookings enable row level security;

-- Stylists: everyone sees approved profiles; owners also see their own (any status)
drop policy if exists "public reads approved stylists" on public.stylists;
create policy "public reads approved stylists" on public.stylists
  for select to anon, authenticated using (status = 'approved');
drop policy if exists "owners read own stylist" on public.stylists;
create policy "owners read own stylist" on public.stylists
  for select to authenticated using (owner_id = auth.uid());
-- A logged-in user can apply; new applications are always pending (status is not insertable)
drop policy if exists "users apply as stylist" on public.stylists;
create policy "users apply as stylist" on public.stylists
  for insert to authenticated with check (owner_id = auth.uid());
-- Owners can edit their own profile (but never status: see column grants below)
drop policy if exists "owners update own stylist" on public.stylists;
create policy "owners update own stylist" on public.stylists
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Bookings: anyone can request a booking with an approved stylist (guest or logged in)
drop policy if exists "anyone requests booking" on public.bookings;
create policy "anyone requests booking" on public.bookings
  for insert to anon, authenticated
  with check (
    (customer_id is null or customer_id = auth.uid())
    and exists (select 1 from public.stylists s where s.id = bookings.stylist_id and s.status = 'approved')
  );
-- Customers see their own bookings; stylists see bookings made with them
drop policy if exists "customers read own bookings" on public.bookings;
create policy "customers read own bookings" on public.bookings
  for select to authenticated using (customer_id = auth.uid());
drop policy if exists "stylists read their bookings" on public.bookings;
create policy "stylists read their bookings" on public.bookings
  for select to authenticated using (
    exists (select 1 from public.stylists s where s.id = bookings.stylist_id and s.owner_id = auth.uid())
  );
-- Stylists can change the status of their bookings (confirm / cancel), nothing else
drop policy if exists "stylists update booking status" on public.bookings;
create policy "stylists update booking status" on public.bookings
  for update to authenticated
  using (exists (select 1 from public.stylists s where s.id = bookings.stylist_id and s.owner_id = auth.uid()))
  with check (exists (select 1 from public.stylists s where s.id = bookings.stylist_id and s.owner_id = auth.uid()));

-- ───────────── Column-level privileges (least privilege) ─────────────
revoke all on public.stylists from anon, authenticated;
revoke all on public.bookings from anon, authenticated;

grant select on public.stylists to anon, authenticated;
grant insert (owner_id, name, spec, city, type, price_from, bio, avail, color, services)
  on public.stylists to authenticated;
grant update (name, spec, city, type, price_from, bio, avail, color, services)
  on public.stylists to authenticated;          -- status and is_example can only be changed in the dashboard

grant select on public.bookings to authenticated;
grant insert (stylist_id, customer_id, customer_name, customer_email, customer_phone, service, preferred_date, notes)
  on public.bookings to anon, authenticated;
grant update (status) on public.bookings to authenticated;

-- ───────────── Example data (approved, flagged so you can remove it later) ─────────────
do $$
begin
  if not exists (select 1 from public.stylists where is_example) then
  insert into public.stylists (name, spec, city, type, price_from, bio, avail, color, services, status, is_example) values
   ('Ngozi Obi','Knotless braids & box braids','Berlin','braiding','from €90','Specialist in lightweight knotless braids with a gentle approach to the edges.','Tue–Sat','#F6E2B8','[["Knotless braids","€110–180"],["Box braids","€90–150"],["Take-down & wash","€35"]]','approved',true),
   ('Tunde Bello','Fades, tapers & beard design','Munich','barbing','from €25','Barber focused on clean fades and sharp line-ups for textured hair.','Mon–Sat','#D9E6D3','[["Fade & line-up","€25–35"],["Beard shaping","€15"],["Cut & beard","€40"]]','approved',true),
   ('Chiamaka Eze','Starter locs & loc maintenance','Frankfurt','locs','from €60','Helps clients start, maintain and style healthy locs.','Wed–Sun','#E6D5EA','[["Starter locs","€150–250"],["Retwist","€60–90"],["Loc styling","€45"]]','approved',true),
   ('Amara Johnson','Natural hair care & silk press','Hamburg','natural','from €55','Moisture-first natural hair care, twist-outs and heat-safe silk presses.','Mon–Fri','#F2D7CF','[["Wash & twist-out","€55"],["Silk press","€80"],["Deep conditioning","€40"]]','approved',true),
   ('Folake Adeyemi','Wigs, closures & sew-ins','Cologne','weave','from €70','Natural-looking installs and custom wig making.','Thu–Sun','#D3E3EE','[["Closure sew-in","€120–180"],["Wig install","€70"],["Custom wig","€200+"]]','approved',true),
   ('Emeka Nwosu','Braids, cornrows & men''s styles','Düsseldorf','braiding','from €40','Clean cornrows and braided styles for men, women and children.','Mon–Sat','#EFE0C2','[["Cornrows","€40–90"],["Men''s braids","€50–100"],["Kids'' braids","€35–70"]]','approved',true);
  end if;
end $$;


-- ════════════════ upgrade_accounts.sql ════════════════
-- ONYE ISI: upgrade for profile photos and account deletion
-- Run once in Supabase (SQL Editor > New query > Run), after schema.sql. Safe to run again.

-- One stylist profile per account
create unique index if not exists stylists_one_per_owner on public.stylists (owner_id) where owner_id is not null;

-- Profile photo: only URLs from this project's public photo bucket are accepted
alter table public.stylists add column if not exists photo_url text;
alter table public.stylists drop constraint if exists stylists_photo_url_check;
alter table public.stylists add constraint stylists_photo_url_check
  check (photo_url is null or photo_url like 'https://hregrxngtmekccxzxotz.supabase.co/storage/v1/object/public/stylist-photos/%');
grant insert (photo_url) on public.stylists to authenticated;
grant update (photo_url) on public.stylists to authenticated;

-- Storage bucket: public read, 2 MB limit, images only; each user writes only inside their own folder
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('stylist-photos', 'stylist-photos', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 2097152,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "photos: read own folder" on storage.objects;
create policy "photos: read own folder" on storage.objects for select to authenticated
  using (bucket_id = 'stylist-photos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "photos: upload own folder" on storage.objects;
create policy "photos: upload own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'stylist-photos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "photos: update own folder" on storage.objects;
create policy "photos: update own folder" on storage.objects for update to authenticated
  using (bucket_id = 'stylist-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'stylist-photos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "photos: delete own folder" on storage.objects;
create policy "photos: delete own folder" on storage.objects for delete to authenticated
  using (bucket_id = 'stylist-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- Account deletion: removes the stylist profile, anonymises the person's bookings, deletes the login
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  delete from public.stylists where owner_id = auth.uid();   -- cascades to bookings made with that stylist
  update public.bookings
     set customer_name = 'Deleted user', customer_email = 'deleted@example.invalid',
         customer_phone = null, notes = null, customer_id = null
   where customer_id = auth.uid();
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;


-- ════════════════ admin.sql ════════════════
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


-- ════════════════ profiles.sql ════════════════
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
