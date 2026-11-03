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
