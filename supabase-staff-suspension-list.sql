-- Staff-only list of players due a suspension.
-- Only signed-in league staff (DEVELOPER, SUPER_ADMIN, STAFF) who are not suspended can read it.
-- Run once in the Supabase SQL editor. Additive only.

create or replace function public.staff_suspension_flags()
returns setof public.player_suspension_flags
language sql
stable
security definer
set search_path = ''
as $$
  select f.*
  from public.player_suspension_flags f
  where exists (
    select 1 from public.user_profiles p
    where p.id = auth.uid()
      and p.system_role in ('DEVELOPER', 'SUPER_ADMIN', 'STAFF')
      and p.status is distinct from 'Suspended'
  );
$$;

revoke all on function public.staff_suspension_flags() from public, anon;
grant execute on function public.staff_suspension_flags() to authenticated;
