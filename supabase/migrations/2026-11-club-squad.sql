-- Club squads: Club Managers add players (pending), Super Admin approves, public sees approved players only.
-- Already applied to the project; kept here for the record.

-- Public visitors must not see player NIN or date of birth
revoke select (player_nin, date_of_birth) on public.club_squad from anon;

-- Club Managers add players as Pending; only the Super Admin approves or rejects
create or replace function public.guard_squad_registration()
returns trigger language plpgsql set search_path = public as $$
begin
  if app_role() = 'CLUB_ADMIN' then
    if tg_op = 'INSERT' then
      new.registration_status := 'Pending';
    elsif new.registration_status is distinct from old.registration_status then
      raise exception 'Only the Super Admin can approve or reject a player';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists guard_squad_registration on public.club_squad;
create trigger guard_squad_registration
  before insert or update on public.club_squad
  for each row execute function public.guard_squad_registration();

-- The Technical Director assigns a club to a Club Manager account
create or replace function public.set_user_club(p_user uuid, p_club uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_role text;
begin
  if app_role() <> 'DEVELOPER' then
    raise exception 'Only the Technical Director can assign clubs';
  end if;
  select system_role into v_role from public.user_profiles where id = p_user;
  if v_role is null then raise exception 'Account not found'; end if;
  if upper(v_role) <> 'CLUB_ADMIN' then
    raise exception 'Clubs can only be assigned to Club Manager accounts';
  end if;
  if p_club is not null and not exists (select 1 from public.league_clubs where id = p_club) then
    raise exception 'Club not found';
  end if;
  update public.user_profiles set club_id = p_club where id = p_user;
end $$;

revoke all on function public.set_user_club(uuid, uuid) from public, anon;
grant execute on function public.set_user_club(uuid, uuid) to authenticated;
