-- 1. Turn on head-to-head tie-breaking for the 2026/27 League rules.
update public.competition_rules r
set use_head_to_head = true
from public.seasons s
where s.id = r.season_id and s.name = '2026/27' and r.competition_name = 'League';

-- 2. Suspension flags: league staff see everyone; referees see only players from the teams in their own active matches.
create or replace function public.staff_suspension_flags()
returns setof public.player_suspension_flags
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.user_profiles p
    where p.id = auth.uid()
      and p.status is distinct from 'Suspended'
      and p.system_role in ('DEVELOPER', 'SUPER_ADMIN', 'STAFF')
  ) then
    return query select f.* from public.player_suspension_flags f;
    return;
  end if;

  if not exists (
    select 1 from public.match_referee_assignments a
    where a.referee_user_id = auth.uid() and a.assignment_status = 'ACTIVE'
  ) then
    raise exception 'Not authorised to view suspension flags' using errcode = '42501';
  end if;

  return query
    select f.* from public.player_suspension_flags f
    where f.team_name in (
      select m.home_team from public.matches m
      join public.match_referee_assignments a on a.match_id::text = m.id::text
      where a.referee_user_id = auth.uid() and a.assignment_status = 'ACTIVE'
      union
      select m.away_team from public.matches m
      join public.match_referee_assignments a on a.match_id::text = m.id::text
      where a.referee_user_id = auth.uid() and a.assignment_status = 'ACTIVE'
    );
end;
$$;

revoke all on function public.staff_suspension_flags() from public, anon;
grant execute on function public.staff_suspension_flags() to authenticated;

-- 3. Refresh standings with head-to-head on.
select public.recalculate_leone_rock_standings();
