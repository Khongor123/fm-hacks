-- Run once in a new Supabase project's SQL Editor.
-- Supabase Auth owns passwords and email verification; this table stores app data.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  full_name text not null check (char_length(trim(full_name)) between 2 and 120),
  grade text not null check (grade in ('first-year', 'sophomore', 'junior', 'senior')),
  tshirt_size text not null check (tshirt_size in ('XS', 'S', 'M', 'L', 'XL', '2XL', '3XL')),
  admin boolean not null default false,
  registration_status text not null default 'pending_verification'
    check (registration_status in ('pending_verification', 'confirmed', 'waitlisted', 'organizer')),
  attendance_committed_at timestamptz not null,
  registered_at timestamptz not null default now(),
  verified_at timestamptz
);

create index if not exists profiles_status_verified_idx
  on public.profiles (registration_status, verified_at);

alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;

create or replace function public.current_user_is_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and admin = true
  );
$$;

revoke all on function public.current_user_is_admin() from public;
grant execute on function public.current_user_is_admin() to authenticated;

drop policy if exists "Users read own profile or admins read roster" on public.profiles;
create policy "Users read own profile or admins read roster"
on public.profiles for select to authenticated
using (id = (select auth.uid()) or (select public.current_user_is_admin()));

create or replace function public.assign_verified_registration(p_user_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_email text;
  v_count integer;
begin
  -- Serializes seat assignment so concurrent confirmations cannot pass 75.
  perform pg_advisory_xact_lock(20261107);
  select lower(email) into v_email from auth.users
    where id = p_user_id and email_confirmed_at is not null;
  if v_email is null then return; end if;

  if v_email = 'kochirkh@fandm.edu' then
    update public.profiles
      set admin = true, registration_status = 'organizer', verified_at = clock_timestamp()
      where id = p_user_id and registration_status = 'pending_verification';
    return;
  end if;

  select count(*) into v_count from public.profiles
    where registration_status = 'confirmed';
  update public.profiles
    set registration_status = case when v_count < 75 then 'confirmed' else 'waitlisted' end,
        verified_at = clock_timestamp()
    where id = p_user_id and registration_status = 'pending_verification';
end;
$$;

revoke all on function public.assign_verified_registration(uuid) from public, anon, authenticated;

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
    raise exception 'A verified F&M email address is required';
  end if;
  if v_email <> 'kochirkh@fandm.edu'
     and clock_timestamp() >= timestamptz '2026-11-05 00:00:00-05' then
    raise exception 'Registration is closed';
  end if;
  if coalesce(new.raw_user_meta_data ->> 'attendance_commitment', '') <> 'true' then
    raise exception 'Attendance commitment is required';
  end if;

  insert into public.profiles (id, email, full_name, grade, tshirt_size, attendance_committed_at)
  values (new.id, v_email, v_name, v_grade, v_size, now());

  if new.email_confirmed_at is not null then
    perform public.assign_verified_registration(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.handle_email_confirmed()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if old.email_confirmed_at is null and new.email_confirmed_at is not null then
    perform public.assign_verified_registration(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_confirmed on auth.users;
create trigger on_auth_user_confirmed
after update of email_confirmed_at on auth.users
for each row execute function public.handle_email_confirmed();

-- Email changes are intentionally unsupported in this first release.
create or replace function public.prevent_email_change()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if lower(coalesce(new.email, '')) <> lower(coalesce(old.email, '')) then
    raise exception 'Email changes are not supported';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_auth_email_change on auth.users;
create trigger prevent_auth_email_change
before update of email on auth.users
for each row execute function public.prevent_email_change();
