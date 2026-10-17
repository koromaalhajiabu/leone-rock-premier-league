-- Leone Rock Premier League: referee and league-staff access requests
-- Additive migration only. Does not delete or reset league data.
-- Run in the Supabase SQL Editor for project ticcaervmjdzbprdpxxv.

begin;

create table if not exists public.role_access_requests (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  requested_role text not null check (requested_role in ('REFEREE','STAFF')),
  contact_name text not null default '',
  contact_email text not null default '',
  contact_phone text,
  application_notes text,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  reviewer_id uuid references auth.users(id),
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create index if not exists role_access_requests_status_created_idx
  on public.role_access_requests(status, created_at asc);

alter table public.role_access_requests enable row level security;
revoke all on public.role_access_requests from public, anon, authenticated;

-- Only league leadership can read requests. Actual access is also protected by RLS.
drop policy if exists role_access_requests_leadership_read on public.role_access_requests;
create policy role_access_requests_leadership_read
  on public.role_access_requests
  for select to authenticated
  using (lower(coalesce(public.league_current_role(), '')) in ('developer','super_admin'));

grant select on public.role_access_requests to authenticated;

create or replace function public.capture_role_access_request()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_role text := upper(trim(coalesce(m->>'requested_role','')));
begin
  if lower(coalesce(m->>'registration_type','')) = 'role_request'
     and v_role in ('REFEREE','STAFF') then
    insert into public.role_access_requests
      (auth_user_id, requested_role, contact_name, contact_email, contact_phone, application_notes)
    values (
      new.id,
      v_role,
      trim(coalesce(m->>'full_name','')),
      lower(trim(coalesce(new.email,''))),
      nullif(trim(coalesce(m->>'contact_phone','')), ''),
      nullif(trim(coalesce(m->>'application_notes','')), '')
    )
    on conflict (auth_user_id) do update
      set requested_role = excluded.requested_role,
          contact_name = excluded.contact_name,
          contact_email = excluded.contact_email,
          contact_phone = excluded.contact_phone,
          application_notes = excluded.application_notes,
          status = 'pending',
          reviewer_id = null,
          review_notes = null,
          reviewed_at = null,
          updated_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists capture_role_access_request_trigger on auth.users;
create trigger capture_role_access_request_trigger
after insert on auth.users
for each row execute function public.capture_role_access_request();

create or replace function public.review_role_access_request(
  p_request_id uuid,
  p_decision text,
  p_review_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_req public.role_access_requests%rowtype;
  v_role text;
  v_requested_role text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to review access requests.';
  end if;

  v_role := lower(coalesce(public.league_current_role(), ''));
  if v_role not in ('developer','super_admin') then
    raise exception 'Only the General Overseer or Super Admin can review access requests.';
  end if;

  if lower(coalesce(p_decision,'')) not in ('approved','rejected') then
    raise exception 'Decision must be approved or rejected.';
  end if;

  select * into v_req
  from public.role_access_requests
  where id = p_request_id
  for update;

  if not found then raise exception 'Access request not found.'; end if;
  if v_req.status <> 'pending' then raise exception 'This request has already been reviewed.'; end if;

  if p_decision = 'approved' then
    v_requested_role := v_req.requested_role;
    update public.user_profiles
      set system_role = v_requested_role,
          status = 'Active'
      where id = v_req.auth_user_id;

    if not found then
      raise exception 'No user_profiles row exists for this applicant. Create the profile safely before approval.';
    end if;
  end if;

  update public.role_access_requests
    set status = p_decision,
        reviewer_id = auth.uid(),
        review_notes = nullif(trim(coalesce(p_review_notes,'')), ''),
        reviewed_at = now(),
        updated_at = now()
    where id = p_request_id;

  return jsonb_build_object('request_id', p_request_id, 'status', p_decision);
end;
$$;

revoke all on function public.review_role_access_request(uuid,text,text) from public, anon;
grant execute on function public.review_role_access_request(uuid,text,text) to authenticated;

commit;

select status, requested_role, count(*) as request_count
from public.role_access_requests
group by status, requested_role
order by status, requested_role;
