-- Team sheets: club admins submit their starting 11 and up to 7 substitutes for a match.
-- Run in the Supabase SQL editor.

create table if not exists public.match_team_sheets (
  id bigserial primary key,
  match_id bigint not null references public.matches(id) on delete cascade,
  club_id uuid not null,
  starting_player_ids bigint[] not null,
  substitute_player_ids bigint[] not null default '{}',
  submitted_by uuid default auth.uid(),
  submitted_at timestamptz not null default now(),
  unique (match_id, club_id)
);

alter table public.match_team_sheets enable row level security;

drop policy if exists "team sheets read signed in" on public.match_team_sheets;
create policy "team sheets read signed in" on public.match_team_sheets
  for select to authenticated using (true);

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
