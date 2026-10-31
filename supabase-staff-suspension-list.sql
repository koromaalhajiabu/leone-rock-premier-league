-- Suspension flags for league staff and assigned referees.
-- Signed-in DEVELOPER, SUPER_ADMIN or STAFF users, and referees with an active assignment, can read it.
-- Everyone else is refused. Run once in the Supabase SQL editor. Additive only.

create or replace function public.staff_suspension_flags()
returns setof public.player_suspension_flags
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.user_profiles p
    where p.id = auth.uid()
      and p.status is distinct from 'Suspended'
      and (
        p.system_role in ('DEVELOPER', 'SUPER_ADMIN', 'STAFF')
        or exists (
          select 1 from public.match_referee_assignments a
          where a.referee_user_id = auth.uid() and a.assignment_status = 'ACTIVE'
        )
      )
  ) then
    raise exception 'Not authorised to view suspension flags' using errcode = '42501';
  end if;

  return query select f.* from public.player_suspension_flags f;
end;
$$;

revoke all on function public.staff_suspension_flags() from public, anon;
grant execute on function public.staff_suspension_flags() to authenticated;
