-- Player eligibility: a player can be on a team sheet only when
-- 1. the Super Admin has approved the squad registration,
-- 2. medical consent is confirmed by the club,
-- 3. the National ID number is unique across active squads,
-- 4. no transfer or loan involving the player is still pending.
-- Run in the Supabase SQL editor.

alter table public.club_squad
  add column if not exists registration_status text not null default 'Pending';

alter table public.club_squad drop constraint if exists club_squad_registration_status_check;
alter table public.club_squad add constraint club_squad_registration_status_check
  check (registration_status in ('Pending', 'Approved', 'Rejected'));

create unique index if not exists club_squad_active_nin_unique
  on public.club_squad (player_nin)
  where player_nin is not null and coalesce(status, 'Active') = 'Active';

create or replace function public.player_eligibility_problem(p_squad_id bigint)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when not exists (select 1 from public.club_squad s where s.id = p_squad_id)
      then 'the player was not found'
    when (select s.registration_status from public.club_squad s where s.id = p_squad_id) is distinct from 'Approved'
      then 'the squad registration has not been approved by the Super Admin'
    when not exists (
      select 1 from public.player_medical_records r
      where r.squad_id = p_squad_id and r.consent_confirmed = true and r.player_consent_withdrawn_at is null)
      then 'medical consent has not been confirmed by the club'
    when exists (
      select 1 from public.player_transfer_requests t
      where t.player_ref = p_squad_id::text
        and t.status not in ('COMPLETED', 'REJECTED', 'CANCELLED', 'DECLINED'))
      then 'a transfer or loan is still pending'
    else null
  end;
$$;

revoke execute on function public.player_eligibility_problem(bigint) from public, anon;
grant execute on function public.player_eligibility_problem(bigint) to authenticated;

create or replace function public.approve_squad_registration(p_squad_id bigint, p_decision text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.app_role() is distinct from 'SUPER_ADMIN' then
    raise exception 'Only the Super Admin can approve squad registrations.';
  end if;
  if p_decision not in ('Approved', 'Rejected') then
    raise exception 'Decision must be Approved or Rejected.';
  end if;
  update public.club_squad set registration_status = p_decision where id = p_squad_id;
  if not found then
    raise exception 'That squad player was not found.';
  end if;
end;
$$;

revoke execute on function public.approve_squad_registration(bigint, text) from public, anon;
grant execute on function public.approve_squad_registration(bigint, text) to authenticated;

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
  r record;
  v_problem text;
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

  for r in
    select s.id, s.player_name from public.club_squad s where s.id = any(p_starting || v_subs)
  loop
    v_problem := public.player_eligibility_problem(r.id);
    if v_problem is not null then
      raise exception '% cannot play: %.', r.player_name, v_problem;
    end if;
  end loop;

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
