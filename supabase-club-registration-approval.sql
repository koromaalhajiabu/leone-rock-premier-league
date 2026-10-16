-- Leone Rock Premier League: controlled Club Admin registration
-- Safe additive migration: does not delete existing league records.
begin;

create table if not exists public.club_registration_applications (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  club_name text not null check (length(trim(club_name)) between 2 and 120),
  contact_name text not null check (length(trim(contact_name)) between 2 and 120),
  contact_email text not null,
  contact_phone text,
  application_notes text,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','changes_requested')),
  reviewer_id uuid references auth.users(id),
  review_notes text,
  approved_club_id uuid references public.league_clubs(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create index if not exists club_registration_applications_status_created_idx
  on public.club_registration_applications(status, created_at desc);

alter table public.club_registration_applications enable row level security;

drop policy if exists club_registration_applications_admin_read
  on public.club_registration_applications;
create policy club_registration_applications_admin_read
  on public.club_registration_applications
  for select to authenticated
  using (public.league_current_role() in ('super_admin','developer'));

-- Applicants cannot directly insert, update, or approve application rows.
revoke all on public.club_registration_applications from public, anon, authenticated;
grant select on public.club_registration_applications to authenticated;

create or replace function public.capture_club_registration_application()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  if lower(coalesce(m->>'registration_type','')) = 'club_admin' then
    insert into public.club_registration_applications
      (auth_user_id, club_name, contact_name, contact_email, contact_phone, application_notes)
    values (
      new.id,
      trim(coalesce(m->>'club_name','')),
      trim(coalesce(m->>'full_name','')),
      lower(trim(coalesce(new.email,''))),
      nullif(trim(coalesce(m->>'contact_phone','')), ''),
      nullif(trim(coalesce(m->>'application_notes','')), '')
    )
    on conflict (auth_user_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists capture_club_registration_application_trigger on auth.users;
create trigger capture_club_registration_application_trigger
after insert on auth.users
for each row execute function public.capture_club_registration_application();

create or replace function public.review_club_registration_application(
  p_application_id uuid,
  p_decision text,
  p_review_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_app public.club_registration_applications%rowtype;
  v_club_id uuid;
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to review applications.';
  end if;

  v_role := lower(coalesce(public.league_current_role(), ''));
  if v_role <> 'super_admin' then
    raise exception 'Only the Super Admin can approve or reject club applications.';
  end if;

  if lower(coalesce(p_decision,'')) not in ('approved','rejected','changes_requested') then
    raise exception 'Decision must be approved, rejected, or changes_requested.';
  end if;

  select * into v_app
  from public.club_registration_applications
  where id = p_application_id
  for update;

  if not found then raise exception 'Application not found.'; end if;
  if v_app.status <> 'pending' and v_app.status <> 'changes_requested' then
    raise exception 'This application has already been reviewed.';
  end if;

  if p_decision = 'approved' then
    select id into v_club_id
    from public.league_clubs
    where lower(trim(club_name)) = lower(trim(v_app.club_name))
    order by created_at nulls last
    limit 1;

    if v_club_id is null then
      insert into public.league_clubs (club_name, is_active)
      values (v_app.club_name, true)
      returning id into v_club_id;
    else
      update public.league_clubs set is_active = true where id = v_club_id;
    end if;

    update public.user_profiles
    set system_role = 'CLUB_ADMIN',
        status = 'Active',
        club_id = v_club_id
    where id = v_app.auth_user_id;

    if not found then
      raise exception 'No user_profiles row exists for this applicant. Create the profile safely before approving.';
    end if;
  end if;

  update public.club_registration_applications
  set status = p_decision,
      reviewer_id = auth.uid(),
      review_notes = nullif(trim(coalesce(p_review_notes,'')), ''),
      approved_club_id = case when p_decision = 'approved' then v_club_id else approved_club_id end,
      reviewed_at = now(),
      updated_at = now()
  where id = p_application_id;

  return jsonb_build_object(
    'application_id', p_application_id,
    'status', p_decision,
    'club_id', v_club_id
  );
end;
$$;

revoke all on function public.review_club_registration_application(uuid,text,text) from public, anon;
grant execute on function public.review_club_registration_application(uuid,text,text) to authenticated;

commit;

-- Post-migration check
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'club_registration_applications'
order by ordinal_position;
