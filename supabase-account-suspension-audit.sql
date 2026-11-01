-- Account suspension with reason and audit log.
-- Run in the Supabase SQL editor (or apply as a migration).

create table if not exists public.account_status_log (
  id bigserial primary key,
  user_id uuid not null,
  user_email text,
  previous_status text,
  new_status text not null,
  reason text not null,
  changed_by uuid default auth.uid(),
  changed_at timestamptz not null default now()
);

alter table public.account_status_log enable row level security;
-- No client policies: the log is written by set_account_status() only.

create or replace function public.set_account_status(p_user uuid, p_status text, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text;
  target public.user_profiles%rowtype;
begin
  caller_role := public.app_role();
  if caller_role not in ('DEVELOPER', 'SUPER_ADMIN') then
    raise exception 'Only the Developer or Super Admin can change account status.';
  end if;
  if p_status not in ('Active', 'Suspended') then
    raise exception 'Status must be Active or Suspended.';
  end if;
  if p_reason is null or length(btrim(p_reason)) < 5 then
    raise exception 'Give a reason of at least 5 characters. It is kept in the log.';
  end if;
  if p_user = auth.uid() then
    raise exception 'You cannot change your own account status.';
  end if;

  select * into target from public.user_profiles where id = p_user;
  if not found then
    raise exception 'Account not found.';
  end if;
  if target.system_role = 'DEVELOPER' then
    raise exception 'The Developer account cannot be suspended.';
  end if;
  if caller_role = 'SUPER_ADMIN' and target.system_role = 'SUPER_ADMIN' then
    raise exception 'A Super Admin cannot change another Super Admin.';
  end if;

  update public.user_profiles set status = p_status where id = p_user;

  insert into public.account_status_log (user_id, user_email, previous_status, new_status, reason, changed_by)
  values (p_user, target.email, target.status, p_status, btrim(p_reason), auth.uid());
end;
$$;

revoke execute on function public.set_account_status(uuid, text, text) from public, anon;
grant execute on function public.set_account_status(uuid, text, text) to authenticated;
