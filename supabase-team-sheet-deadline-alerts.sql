-- Team sheets close at kickoff, and referees and the Super Admin are alerted when a sheet is submitted or changed.
-- Run in the Supabase SQL editor after supabase-team-sheets.sql.

create or replace function public.submit_team_sheet(p_match_id bigint, p_starting bigint[], p_subs bigint[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_club uuid;
  m public.matches%rowtype;
  v_subs bigint[] := coalesce(p_subs, '{}'::bigint[]);
  v_total int;
  v_valid int;
begin
  if public.app_role() is distinct from 'CLUB_ADMIN' then
    raise exception 'Only a Club Admin can submit a team sheet.';
  end if;
  v_club := public.my_club_id();
  if v_club is null then
    raise exception 'Your account is not linked to a club.';
  end if;

  select * into m from public.matches where id = p_match_id;
  if not found then
    raise exception 'That match was not found.';
  end if;
  if v_club is distinct from m.home_club_id and v_club is distinct from m.away_club_id then
    raise exception 'Your club is not playing in this match.';
  end if;
  if m.match_date is not null and now() >= m.match_date then
    raise exception 'The team sheet closed at kickoff. Contact the referee or the Super Admin.';
  end if;

  if coalesce(cardinality(p_starting), 0) <> 11 then
    raise exception 'A team sheet needs exactly 11 starting players.';
  end if;
  if cardinality(v_subs) > 7 then
    raise exception 'A team sheet can have at most 7 substitutes.';
  end if;

  v_total := cardinality(p_starting) + cardinality(v_subs);
  select count(distinct x) into v_valid from unnest(p_starting || v_subs) as x;
  if v_valid <> v_total then
    raise exception 'A player can only appear once on the team sheet.';
  end if;

  select count(*) into v_valid
  from public.club_squad s
  where s.id = any(p_starting || v_subs)
    and s.club_id = v_club
    and coalesce(s.status, 'Active') = 'Active';
  if v_valid <> v_total then
    raise exception 'Every player on the team sheet must be an active member of your squad.';
  end if;

  insert into public.match_team_sheets (match_id, club_id, starting_player_ids, substitute_player_ids, submitted_by, submitted_at)
  values (p_match_id, v_club, p_starting, v_subs, auth.uid(), now())
  on conflict (match_id, club_id) do update
    set starting_player_ids = excluded.starting_player_ids,
        substitute_player_ids = excluded.substitute_player_ids,
        submitted_by = auth.uid(),
        submitted_at = now();
end;
$$;

revoke execute on function public.submit_team_sheet(bigint, bigint[], bigint[]) from public, anon;
grant execute on function public.submit_team_sheet(bigint, bigint[], bigint[]) to authenticated;

create or replace function public.trg_alert_team_sheet()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  m record;
  v_club_name text;
  r record;
begin
  select home_team, away_team into m from public.matches where id = new.match_id;
  select club_name into v_club_name from public.league_clubs where id = new.club_id;

  for r in
    select distinct a.referee_user_id::text as uid
    from public.match_referee_assignments a
    where a.match_id::text = new.match_id::text and a.assignment_status = 'ACTIVE'
    union
    select up.id::text from public.user_profiles up
    where up.system_role = 'SUPER_ADMIN' and up.status = 'Active'
  loop
    perform public.alert_user(r.uid, 'Team sheet submitted',
      coalesce(v_club_name, 'A club') || ' submitted a team sheet for ' || coalesce(m.home_team, '') || ' v ' || coalesce(m.away_team, '') || '. Sign in to the SLFA system to see it.');
  end loop;
  return new;
end;
$$;

drop trigger if exists alert_team_sheet on public.match_team_sheets;
create trigger alert_team_sheet
  after insert or update on public.match_team_sheets
  for each row execute function public.trg_alert_team_sheet();
