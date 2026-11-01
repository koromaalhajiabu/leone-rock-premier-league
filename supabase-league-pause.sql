-- League pause for disputes. Only the Super Admin can pause or resume.
-- While paused, match results, match events, Man of the Match and referee
-- assignments cannot be changed by anyone (including the Super Admin).
-- Disputes can still be raised. Run in the Supabase SQL editor.

create table if not exists public.system_pause (
  id int primary key default 1 check (id = 1),
  paused boolean not null default false,
  reason text,
  changed_by uuid,
  changed_at timestamptz not null default now()
);

insert into public.system_pause (id) values (1) on conflict (id) do nothing;

create table if not exists public.system_pause_log (
  id bigserial primary key,
  paused boolean not null,
  reason text not null,
  changed_by uuid default auth.uid(),
  changed_at timestamptz not null default now()
);

alter table public.system_pause enable row level security;
alter table public.system_pause_log enable row level security;

drop policy if exists "system pause read" on public.system_pause;
create policy "system pause read" on public.system_pause
  for select to anon, authenticated using (true);

create or replace function public.set_system_pause(p_paused boolean, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.app_role() is distinct from 'SUPER_ADMIN' then
    raise exception 'Only the Super Admin can pause or resume the league.';
  end if;
  if p_reason is null or length(btrim(p_reason)) < 5 then
    raise exception 'Give a reason of at least 5 characters. It is kept in the log.';
  end if;
  update public.system_pause
     set paused = p_paused,
         reason = btrim(p_reason),
         changed_by = auth.uid(),
         changed_at = now()
   where id = 1;
  insert into public.system_pause_log (paused, reason, changed_by)
  values (p_paused, btrim(p_reason), auth.uid());
end;
$$;

revoke execute on function public.set_system_pause(boolean, text) from public, anon;
grant execute on function public.set_system_pause(boolean, text) to authenticated;

create or replace function public.guard_system_pause()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paused boolean;
begin
  select coalesce(paused, false) into v_paused from public.system_pause where id = 1;
  if v_paused then
    raise exception 'The league is paused for a dispute. Changes are not allowed until the Super Admin resumes it.';
  end if;
  if TG_OP = 'DELETE' then return OLD; end if;
  return NEW;
end;
$$;

drop trigger if exists guard_system_pause on public.matches;
create trigger guard_system_pause before insert or update or delete on public.matches
  for each row execute function public.guard_system_pause();

drop trigger if exists guard_system_pause on public.match_results;
create trigger guard_system_pause before insert or update or delete on public.match_results
  for each row execute function public.guard_system_pause();

drop trigger if exists guard_system_pause on public.match_events;
create trigger guard_system_pause before insert or update or delete on public.match_events
  for each row execute function public.guard_system_pause();

drop trigger if exists guard_system_pause on public.man_of_the_match;
create trigger guard_system_pause before insert or update or delete on public.man_of_the_match
  for each row execute function public.guard_system_pause();

drop trigger if exists guard_system_pause on public.match_referee_assignments;
create trigger guard_system_pause before insert or update or delete on public.match_referee_assignments
  for each row execute function public.guard_system_pause();
