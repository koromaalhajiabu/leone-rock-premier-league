-- Registration check when a club adds a player.
-- 1. A player already on an active squad at another league club is refused:
--    he must move through a transfer request.
-- 2. A new player is saved as Pending and the club admin and Super Admin are alerted
--    that he is not registered with the league and cannot play until approved.
-- Run in the Supabase SQL editor after supabase-player-eligibility.sql.

create or replace function public.trg_check_player_registration()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_other_club text;
begin
  if new.player_nin is not null and coalesce(new.status, 'Active') = 'Active' then
    select lc.club_name into v_other_club
    from public.club_squad s
    left join public.league_clubs lc on lc.id = s.club_id
    where s.player_nin = new.player_nin
      and coalesce(s.status, 'Active') = 'Active'
      and s.club_id is distinct from new.club_id
    limit 1;
    if v_other_club is not null then
      raise exception 'This player is already registered with %. He must move through a transfer request, not a new registration.', v_other_club;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists check_player_registration on public.club_squad;
create trigger check_player_registration
  before insert on public.club_squad
  for each row execute function public.trg_check_player_registration();

create or replace function public.trg_alert_new_registration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_club text;
begin
  if new.registration_status is distinct from 'Pending' then
    return new;
  end if;
  select club_name into v_club from public.league_clubs where id = new.club_id;

  if new.created_by is not null then
    perform public.alert_user(new.created_by::text, 'Player submitted for registration',
      new.player_name || ' is not yet registered with the league. He cannot play until the Super Admin approves his registration and his medical consent is confirmed.');
  end if;

  for r in
    select up.id::text as uid from public.user_profiles up
    where up.system_role = 'SUPER_ADMIN' and up.status = 'Active'
  loop
    perform public.alert_user(r.uid, 'New player waiting for registration approval',
      new.player_name || ' from ' || coalesce(v_club, 'a club') || ' is waiting for registration approval.');
  end loop;
  return new;
end;
$$;

drop trigger if exists alert_new_registration on public.club_squad;
create trigger alert_new_registration
  after insert on public.club_squad
  for each row execute function public.trg_alert_new_registration();
