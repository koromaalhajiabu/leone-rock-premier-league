-- Leone Rock Premier League: player transfer and loan workflow
-- Additive migration only: does not alter or delete existing league records.
-- Run in the Supabase SQL Editor after reviewing the profile/club schema.
-- Existing player and club identifiers are stored as text until mapped to the live schema.

create extension if not exists pgcrypto;

create table if not exists public.player_transfer_requests (
  id uuid primary key default gen_random_uuid(),
  request_type text not null check (request_type in ('PERMANENT','LOAN')),
  player_ref text not null,
  player_name_snapshot text not null,
  from_club_ref text not null,
  to_club_ref text not null,
  effective_date date not null,
  loan_end_date date,
  reason text,
  supporting_documents jsonb not null default '[]'::jsonb,
  status text not null default 'PENDING_CURRENT_CLUB'
    check (status in ('PENDING_CURRENT_CLUB','PENDING_RECEIVING_CLUB','UNDER_REVIEW','PENDING_SUPER_ADMIN','APPROVED','REJECTED','CANCELLED','COMPLETED')),
  submitted_by uuid not null references auth.users(id),
  current_club_confirmed_by uuid references auth.users(id),
  current_club_confirmed_at timestamptz,
  receiving_club_confirmed_by uuid references auth.users(id),
  receiving_club_confirmed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_notes text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transfer_clubs_differ check (from_club_ref <> to_club_ref),
  constraint loan_dates_valid check (
    (request_type = 'PERMANENT' and loan_end_date is null)
    or (request_type = 'LOAN' and loan_end_date is not null and loan_end_date > effective_date)
  )
);

create table if not exists public.player_registration_history (
  id uuid primary key default gen_random_uuid(),
  transfer_request_id uuid not null unique references public.player_transfer_requests(id),
  player_ref text not null,
  player_name_snapshot text not null,
  move_type text not null check (move_type in ('PERMANENT','LOAN')),
  from_club_ref text not null,
  to_club_ref text not null,
  effective_date date not null,
  loan_end_date date,
  recorded_by uuid not null references auth.users(id),
  recorded_at timestamptz not null default now(),
  details jsonb not null default '{}'::jsonb
);

create index if not exists player_transfer_requests_status_created_idx
  on public.player_transfer_requests(status, created_at desc);
create index if not exists player_transfer_requests_player_idx
  on public.player_transfer_requests(player_ref, created_at desc);
create index if not exists player_registration_history_player_idx
  on public.player_registration_history(player_ref, recorded_at desc);

alter table public.player_transfer_requests enable row level security;
alter table public.player_registration_history enable row level security;

-- No direct browser writes: controlled changes must go through audited RPC functions.
drop policy if exists "transfer requests readable by authenticated users" on public.player_transfer_requests;
create policy "transfer requests visible to involved authorized users"
  on public.player_transfer_requests for select to authenticated using (
    exists (
      select 1 from public.user_profiles p
      where p.id = auth.uid() and p.status <> 'Suspended'
        and (
          p.system_role in ('DEVELOPER','SUPER_ADMIN','REGISTRATION_ADMIN')
          or (p.system_role = 'CLUB_ADMIN' and p.club_id::text in (from_club_ref, to_club_ref))
        )
    )
  );

drop policy if exists "registration history readable by authenticated users" on public.player_registration_history;
create policy "registration history visible to authorized users"
  on public.player_registration_history for select to authenticated using (
    exists (
      select 1 from public.user_profiles p
      where p.id = auth.uid() and p.status <> 'Suspended'
        and (
          p.system_role in ('DEVELOPER','SUPER_ADMIN','REGISTRATION_ADMIN')
          or (p.system_role = 'CLUB_ADMIN' and exists (
            select 1 from public.player_transfer_requests r
            where r.id = transfer_request_id
              and p.club_id::text in (r.from_club_ref, r.to_club_ref)
          ))
        )
    )
  );

revoke insert, update, delete on public.player_transfer_requests from anon, authenticated;
revoke insert, update, delete on public.player_registration_history from anon, authenticated;
grant select on public.player_transfer_requests, public.player_registration_history to authenticated;

-- Uses the portal's existing profile shape: user_profiles.id = auth.uid(),
-- with system_role, status, and club_id fields. If your live schema differs,
-- stop and adjust these functions before running the migration.
create or replace function public.submit_player_transfer_request(
  p_request_type text,
  p_player_ref text,
  p_player_name text,
  p_from_club_ref text,
  p_to_club_ref text,
  p_effective_date date,
  p_loan_end_date date default null,
  p_reason text default null,
  p_documents jsonb default '[]'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_profile public.user_profiles%rowtype;
  v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign-in required'; end if;
  select * into v_profile from public.user_profiles where id = auth.uid();
  if not found or v_profile.status = 'Suspended' then raise exception 'Active profile required'; end if;
  if v_profile.system_role not in ('DEVELOPER','SUPER_ADMIN','CLUB_ADMIN','REGISTRATION_ADMIN') then
    raise exception 'Not authorized to submit transfer requests';
  end if;
  if v_profile.system_role = 'CLUB_ADMIN' and v_profile.club_id::text <> p_from_club_ref then
    raise exception 'Club Admin may submit only for their own club';
  end if;
  if p_request_type not in ('PERMANENT','LOAN') then raise exception 'Invalid move type'; end if;
  if p_from_club_ref = p_to_club_ref then raise exception 'Source and destination clubs must differ'; end if;
  if p_request_type = 'LOAN' and (p_loan_end_date is null or p_loan_end_date <= p_effective_date) then
    raise exception 'A loan requires an end date after its start date';
  end if;
  if p_request_type = 'PERMANENT' and p_loan_end_date is not null then
    raise exception 'Permanent transfers cannot have a loan end date';
  end if;
  insert into public.player_transfer_requests
    (request_type, player_ref, player_name_snapshot, from_club_ref, to_club_ref,
     effective_date, loan_end_date, reason, supporting_documents, submitted_by)
  values
    (p_request_type, p_player_ref, p_player_name, p_from_club_ref, p_to_club_ref,
     p_effective_date, p_loan_end_date, p_reason, coalesce(p_documents,'[]'::jsonb), auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.confirm_player_transfer_request(
  p_request_id uuid,
  p_confirm boolean,
  p_note text default null
) returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_profile public.user_profiles%rowtype;
  v_request public.player_transfer_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign-in required'; end if;
  select * into v_profile from public.user_profiles where id = auth.uid();
  if not found or v_profile.status = 'Suspended' then raise exception 'Active profile required'; end if;
  if v_profile.system_role not in ('DEVELOPER','SUPER_ADMIN','CLUB_ADMIN','REGISTRATION_ADMIN') then
    raise exception 'Not authorized to process transfer requests';
  end if;
  select * into v_request from public.player_transfer_requests where id = p_request_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_profile.system_role = 'CLUB_ADMIN' then
    if v_profile.club_id::text = v_request.from_club_ref and v_request.status = 'PENDING_CURRENT_CLUB' then
      if not p_confirm then
        update public.player_transfer_requests set status='REJECTED', review_notes=concat_ws(E'\n',review_notes,p_note), updated_at=now() where id=p_request_id;
        return;
      end if;
      update public.player_transfer_requests set status='PENDING_RECEIVING_CLUB',
        current_club_confirmed_by=auth.uid(), current_club_confirmed_at=now(), updated_at=now()
        where id=p_request_id;
      return;
    elsif v_profile.club_id::text = v_request.to_club_ref and v_request.status = 'PENDING_RECEIVING_CLUB' then
      if not p_confirm then
        update public.player_transfer_requests set status='REJECTED', review_notes=concat_ws(E'\n',review_notes,p_note), updated_at=now() where id=p_request_id;
        return;
      end if;
      update public.player_transfer_requests set status='UNDER_REVIEW',
        receiving_club_confirmed_by=auth.uid(), receiving_club_confirmed_at=now(), updated_at=now()
        where id=p_request_id;
      return;
    else
      raise exception 'Club Admin may confirm only for their own club and current workflow stage';
    end if;
  end if;
  if v_profile.system_role = 'REGISTRATION_ADMIN' then
    if v_request.status <> 'UNDER_REVIEW' then
      raise exception 'Both clubs must confirm before Registration Admin review';
    end if;
    if not p_confirm then
      update public.player_transfer_requests set status='REJECTED',
        reviewed_by=auth.uid(), reviewed_at=now(),
        review_notes=concat_ws(E'\\n',review_notes,'Registration Admin: ' || coalesce(p_note,'Rejected')),
        updated_at=now() where id=p_request_id;
    else
      update public.player_transfer_requests set status='PENDING_SUPER_ADMIN',
        reviewed_by=auth.uid(), reviewed_at=now(),
        review_notes=concat_ws(E'\\n',review_notes,'Registration Admin checked: ' || coalesce(p_note,'Forwarded for Super Admin decision')),
        updated_at=now() where id=p_request_id;
    end if;
    return;
  end if;

  if v_profile.system_role = 'SUPER_ADMIN' then
    if v_request.status <> 'PENDING_SUPER_ADMIN' then
      raise exception 'Super Admin can decide only requests forwarded by Registration Admin';
    end if;
    if not p_confirm then
      update public.player_transfer_requests set status='REJECTED',
        reviewed_by=auth.uid(), reviewed_at=now(),
        review_notes=concat_ws(E'\\n',review_notes,'Super Admin: ' || coalesce(p_note,'Rejected')),
        updated_at=now() where id=p_request_id;
    else
      update public.player_transfer_requests set status='APPROVED',
        reviewed_by=auth.uid(), reviewed_at=now(),
        review_notes=concat_ws(E'\\n',review_notes,'Super Admin approved: ' || coalesce(p_note,'Approved')),
        updated_at=now() where id=p_request_id;
    end if;
    return;
  end if;

  if v_profile.system_role = 'DEVELOPER' then
    if v_request.status not in ('UNDER_REVIEW','PENDING_SUPER_ADMIN') then
      raise exception 'Developer override requires both clubs to have confirmed';
    end if;
    update public.player_transfer_requests set
      status=case when p_confirm then 'APPROVED' else 'REJECTED' end,
      reviewed_by=auth.uid(), reviewed_at=now(),
      review_notes=concat_ws(E'\\n',review_notes,'Developer override: ' || coalesce(p_note,'')),
      updated_at=now() where id=p_request_id;
    return;
  end if;
  raise exception 'Role cannot make the final decision';
end;
$$;

create or replace function public.complete_player_transfer_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_profile public.user_profiles%rowtype;
  v_request public.player_transfer_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign-in required'; end if;
  select * into v_profile from public.user_profiles where id = auth.uid();
  if not found or v_profile.status = 'Suspended' then raise exception 'Active profile required'; end if;
  if v_profile.system_role not in ('DEVELOPER','REGISTRATION_ADMIN') then
    raise exception 'Only Developer or Registration Admin may complete an approved move';
  end if;
  select * into v_request from public.player_transfer_requests where id=p_request_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_request.status <> 'APPROVED' then raise exception 'Only approved transfers can be completed'; end if;
  insert into public.player_registration_history
    (transfer_request_id, player_ref, player_name_snapshot, move_type, from_club_ref,
     to_club_ref, effective_date, loan_end_date, recorded_by)
  values
    (v_request.id, v_request.player_ref, v_request.player_name_snapshot, v_request.request_type,
     v_request.from_club_ref, v_request.to_club_ref, v_request.effective_date,
     v_request.loan_end_date, auth.uid())
  on conflict (transfer_request_id) do nothing;
  update public.player_transfer_requests set status='COMPLETED', completed_at=now(), updated_at=now()
    where id=p_request_id;
end;
$$;

revoke all on function public.submit_player_transfer_request(text,text,text,text,text,date,date,text,jsonb) from public, anon;
revoke all on function public.confirm_player_transfer_request(uuid,boolean,text) from public, anon;
revoke all on function public.complete_player_transfer_request(uuid) from public, anon;
grant execute on function public.submit_player_transfer_request(text,text,text,text,text,date,date,text,jsonb) to authenticated;
grant execute on function public.confirm_player_transfer_request(uuid,boolean,text) to authenticated;
grant execute on function public.complete_player_transfer_request(uuid) to authenticated;
