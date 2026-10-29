-- Run this once in the existing Supabase project's SQL Editor BEFORE disabling Confirm Email.
-- Organizer access is no longer granted based on an unverified email address.

drop trigger if exists on_auth_user_confirmed on auth.users;
drop function if exists public.handle_email_confirmed();

alter table public.profiles rename column verified_at to assigned_at;
alter table public.profiles drop constraint if exists profiles_registration_status_check;
alter table public.profiles alter column registration_status set default 'pending_assignment';
update public.profiles
  set registration_status = 'pending_assignment'
  where registration_status = 'pending_verification';
alter table public.profiles add constraint profiles_registration_status_check
  check (registration_status in ('pending_assignment', 'confirmed', 'waitlisted', 'organizer'));

drop index if exists public.profiles_status_verified_idx;
create index if not exists profiles_status_assigned_idx
  on public.profiles (registration_status, assigned_at);

create or replace function public.assign_registration(p_user_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  perform pg_advisory_xact_lock(20261107);
  select count(*) into v_count from public.profiles
    where registration_status = 'confirmed';
  update public.profiles
    set registration_status = case when v_count < 75 then 'confirmed' else 'waitlisted' end,
        assigned_at = clock_timestamp()
    where id = p_user_id and registration_status = 'pending_assignment';
end;
$$;

revoke all on function public.assign_registration(uuid) from public, anon, authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_email text := lower(coalesce(new.email, ''));
  v_name text := trim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  v_grade text := coalesce(new.raw_user_meta_data ->> 'grade', '');
  v_size text := coalesce(new.raw_user_meta_data ->> 'tshirt_size', '');
begin
  if v_email !~ '^[^@[:space:]]+@fandm\.edu$' then
    raise exception 'An F&M email address is required';
  end if;
  if clock_timestamp() >= timestamptz '2026-11-05 00:00:00-05' then
    raise exception 'Registration is closed';
  end if;
  if coalesce(new.raw_user_meta_data ->> 'attendance_commitment', '') <> 'true' then
    raise exception 'Attendance commitment is required';
  end if;

  insert into public.profiles (id, email, full_name, grade, tshirt_size, attendance_committed_at)
  values (new.id, v_email, v_name, v_grade, v_size, now());

  perform public.assign_registration(new.id);
  return new;
end;
$$;

-- Earlier registrations waiting for email confirmation receive places in signup order.
do $$
declare
  person record;
begin
  for person in
    select id from public.profiles
    where registration_status = 'pending_assignment'
    order by registered_at, id
  loop
    perform public.assign_registration(person.id);
  end loop;
end;
$$;
