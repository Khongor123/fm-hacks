-- Run once in a new Supabase project's SQL Editor.
-- Supabase Auth owns passwords; this table stores app data.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  full_name text not null check (char_length(trim(full_name)) between 2 and 120),
  grade text not null check (grade in ('first-year', 'sophomore', 'junior', 'senior')),
  tshirt_size text not null check (tshirt_size in ('XS', 'S', 'M', 'L', 'XL', '2XL', '3XL')),
  admin boolean not null default false,
  registration_status text not null default 'pending_assignment'
    check (registration_status in ('pending_assignment', 'confirmed', 'waitlisted', 'organizer')),
  attendance_committed_at timestamptz not null,
  registered_at timestamptz not null default now(),
  assigned_at timestamptz
);

create index if not exists profiles_status_assigned_idx
  on public.profiles (registration_status, assigned_at);

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

create or replace function public.assign_registration(p_user_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  -- Serializes seat assignment so concurrent signups cannot pass 75.
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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

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
