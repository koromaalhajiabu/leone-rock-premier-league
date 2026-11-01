-- Developer self-lock: while switched on, the Developer cannot change roles,
-- suspend or restore accounts, or remove accounts. Other staff are not affected.
-- Run in the Supabase SQL editor.

create table if not exists public.developer_lock (
  id int primary key default 1 check (id = 1),
  locked boolean not null default false,
  reason text,
  changed_by uuid,
  changed_at timestamptz not null default now()
);

insert into public.developer_lock (id) values (1) on conflict (id) do nothing;

alter table public.developer_lock enable row level security;

drop policy if exists "developer lock read signed in" on public.developer_lock;
create policy "developer lock read signed in" on public.developer_lock
  for select to authenticated using (true);

create or replace function public.set_developer_lock(p_locked boolean, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.app_role() is distinct from 'DEVELOPER' then
    raise exception 'Only the Developer can change the developer lock.';
  end if;
  if p_locked and (p_reason is null or length(btrim(p_reason)) < 5) then
    raise exception 'Give a reason of at least 5 characters.';
  end if;
  update public.developer_lock
     set locked = p_locked,
         reason = case when p_locked then btrim(p_reason) else null end,
         changed_by = auth.uid(),
         changed_at = now()
   where id = 1;
end;
$$;

revoke execute on function public.set_developer_lock(boolean, text) from public, anon;
grant execute on function public.set_developer_lock(boolean, text) to authenticated;

create or replace function public.guard_developer_lock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_locked boolean;
begin
  if public.app_role() is distinct from 'DEVELOPER' then
    if TG_OP = 'DELETE' then return OLD; end if;
    return NEW;
  end if;

  select coalesce(locked, false) into v_locked from public.developer_lock where id = 1;
  if not v_locked then
    if TG_OP = 'DELETE' then return OLD; end if;
    return NEW;
  end if;

  if TG_OP = 'DELETE' then
    raise exception 'The developer lock is on. Unlock it before removing accounts.';
  end if;

  if new.system_role is distinct from old.system_role or new.status is distinct from old.status then
    raise exception 'The developer lock is on. Unlock it before changing roles or account status.';
  end if;
  return NEW;
end;
$$;

drop trigger if exists guard_developer_lock on public.user_profiles;
create trigger guard_developer_lock
  before update or delete on public.user_profiles
  for each row execute function public.guard_developer_lock();
