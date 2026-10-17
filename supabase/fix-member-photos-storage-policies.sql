-- Leone Rock Premier League: member photo write-access hardening
-- Review the existing policies before running this migration in Supabase SQL Editor.
-- Public reads remain unchanged because the bucket is intentionally public.
-- Writes: DEVELOPER/SUPER_ADMIN may manage photos; CLUB_ADMIN may write only
-- inside squad/<their-auth-user-id>/. VIEWER, STAFF, REFEREE, and other roles are denied.
begin;

-- Remove the known overly broad policies from the earlier setup.
drop policy if exists "Authenticated users upload member photos" on storage.objects;
drop policy if exists "Authenticated users update member photos" on storage.objects;
drop policy if exists "Authenticated users delete member photos" on storage.objects;

-- Remove this migration's policies so it can be safely rerun.
drop policy if exists "LRPL member photos insert allowed roles" on storage.objects;
drop policy if exists "LRPL member photos update allowed roles" on storage.objects;
drop policy if exists "LRPL member photos delete allowed roles" on storage.objects;
drop policy if exists "LRPL member photos insert role guard" on storage.objects;
drop policy if exists "LRPL member photos update role guard" on storage.objects;
drop policy if exists "LRPL member photos delete role guard" on storage.objects;

-- Permissive policies grant writes only to approved roles and paths.
create policy "LRPL member photos insert allowed roles"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'member-photos'
  and (
    exists (
      select 1 from public.user_profiles p
      where p.id = auth.uid()
        and coalesce(p.status, 'Active') <> 'Suspended'
        and p.system_role in ('DEVELOPER', 'SUPER_ADMIN')
    )
    or (
      (storage.foldername(name))[1] = 'squad'
      and (storage.foldername(name))[2] = auth.uid()::text
      and exists (
        select 1 from public.user_profiles p
        where p.id = auth.uid()
          and coalesce(p.status, 'Active') <> 'Suspended'
          and p.system_role = 'CLUB_ADMIN'
          and p.club_id is not null
      )
    )
  )
);

create policy "LRPL member photos update allowed roles"
on storage.objects for update to authenticated
using (
  bucket_id = 'member-photos'
  and (
    exists (
      select 1 from public.user_profiles p
      where p.id = auth.uid()
        and coalesce(p.status, 'Active') <> 'Suspended'
        and p.system_role in ('DEVELOPER', 'SUPER_ADMIN')
    )
    or (
      (storage.foldername(name))[1] = 'squad'
      and (storage.foldername(name))[2] = auth.uid()::text
      and exists (
        select 1 from public.user_profiles p
        where p.id = auth.uid()
          and coalesce(p.status, 'Active') <> 'Suspended'
          and p.system_role = 'CLUB_ADMIN'
          and p.club_id is not null
      )
    )
  )
)
with check (
  bucket_id = 'member-photos'
  and (
    exists (
      select 1 from public.user_profiles p
      where p.id = auth.uid()
        and coalesce(p.status, 'Active') <> 'Suspended'
        and p.system_role in ('DEVELOPER', 'SUPER_ADMIN')
    )
    or (
      (storage.foldername(name))[1] = 'squad'
      and (storage.foldername(name))[2] = auth.uid()::text
      and exists (
        select 1 from public.user_profiles p
        where p.id = auth.uid()
          and coalesce(p.status, 'Active') <> 'Suspended'
          and p.system_role = 'CLUB_ADMIN'
          and p.club_id is not null
      )
    )
  )
);

create policy "LRPL member photos delete allowed roles"
on storage.objects for delete to authenticated
using (
  bucket_id = 'member-photos'
  and (
    exists (
      select 1 from public.user_profiles p
      where p.id = auth.uid()
        and coalesce(p.status, 'Active') <> 'Suspended'
        and p.system_role in ('DEVELOPER', 'SUPER_ADMIN')
    )
    or (
      (storage.foldername(name))[1] = 'squad'
      and (storage.foldername(name))[2] = auth.uid()::text
      and exists (
        select 1 from public.user_profiles p
        where p.id = auth.uid()
          and coalesce(p.status, 'Active') <> 'Suspended'
          and p.system_role = 'CLUB_ADMIN'
          and p.club_id is not null
      )
    )
  )
);

-- Restrictive guards are intentional: they also constrain any other permissive
-- write policy that might still exist for this bucket. PostgreSQL combines
-- restrictive policies with AND, preventing an older broad policy from
-- reopening access to read-only accounts.
create policy "LRPL member photos insert role guard"
on storage.objects as restrictive for insert to authenticated
with check (
  bucket_id <> 'member-photos'
  or exists (
    select 1 from public.user_profiles p
    where p.id = auth.uid()
      and coalesce(p.status, 'Active') <> 'Suspended'
      and (
        p.system_role in ('DEVELOPER', 'SUPER_ADMIN')
        or (
          p.system_role = 'CLUB_ADMIN'
          and p.club_id is not null
          and (storage.foldername(name))[1] = 'squad'
          and (storage.foldername(name))[2] = auth.uid()::text
        )
      )
  )
);

create policy "LRPL member photos update role guard"
on storage.objects as restrictive for update to authenticated
using (
  bucket_id <> 'member-photos'
  or exists (
    select 1 from public.user_profiles p
    where p.id = auth.uid()
      and coalesce(p.status, 'Active') <> 'Suspended'
      and (
        p.system_role in ('DEVELOPER', 'SUPER_ADMIN')
        or (
          p.system_role = 'CLUB_ADMIN'
          and p.club_id is not null
          and (storage.foldername(name))[1] = 'squad'
          and (storage.foldername(name))[2] = auth.uid()::text
        )
      )
  )
)
with check (
  bucket_id <> 'member-photos'
  or exists (
    select 1 from public.user_profiles p
    where p.id = auth.uid()
      and coalesce(p.status, 'Active') <> 'Suspended'
      and (
        p.system_role in ('DEVELOPER', 'SUPER_ADMIN')
        or (
          p.system_role = 'CLUB_ADMIN'
          and p.club_id is not null
          and (storage.foldername(name))[1] = 'squad'
          and (storage.foldername(name))[2] = auth.uid()::text
        )
      )
  )
);

create policy "LRPL member photos delete role guard"
on storage.objects as restrictive for delete to authenticated
using (
  bucket_id <> 'member-photos'
  or exists (
    select 1 from public.user_profiles p
    where p.id = auth.uid()
      and coalesce(p.status, 'Active') <> 'Suspended'
      and (
        p.system_role in ('DEVELOPER', 'SUPER_ADMIN')
        or (
          p.system_role = 'CLUB_ADMIN'
          and p.club_id is not null
          and (storage.foldername(name))[1] = 'squad'
          and (storage.foldername(name))[2] = auth.uid()::text
        )
      )
  )
);

commit;
