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
  if clock_timestamp() >= timestamptz '2026-11-04 00:00:00-05' then
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

-- Team creation, code joining, and private team reads.
create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 40),
  code text not null unique check (code ~ '^[0-9A-F]{12}$'),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

create index if not exists team_members_team_joined_idx
  on public.team_members (team_id, joined_at, user_id);

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
revoke all on public.teams, public.team_members from public, anon, authenticated;

create or replace function public.get_my_team()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_team_id uuid;
  v_result jsonb;
begin
  select team_id into v_team_id from public.team_members where user_id = (select auth.uid());
  if v_team_id is null then return null; end if;

  select jsonb_build_object(
    'id', t.id,
    'name', t.name,
    'code', t.code,
    'created_by', t.created_by,
    'members', coalesce((
      select jsonb_agg(
        jsonb_build_object('id', p.id, 'full_name', p.full_name, 'joined_at', m.joined_at)
        order by m.joined_at, m.user_id
      )
      from public.team_members m
      join public.profiles p on p.id = m.user_id
      where m.team_id = t.id
    ), '[]'::jsonb)
  ) into v_result
  from public.teams t where t.id = v_team_id;
  return v_result;
end;
$$;

create or replace function public.create_team(p_name text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_team_id uuid;
  v_code text;
  v_name text := btrim(coalesce(p_name, ''));
begin
  if clock_timestamp() >= timestamptz '2026-11-04 00:00:00-05' then
    raise exception 'Team changes have closed.';
  end if;
  if v_user_id is null or not exists (
    select 1 from public.profiles
    where id = v_user_id and registration_status = 'confirmed' and admin = false
  ) then
    raise exception 'Only confirmed participants can join teams.';
  end if;
  if char_length(v_name) not between 2 and 40 then
    raise exception 'Team names must be 2 to 40 characters.';
  end if;
  if exists (select 1 from public.team_members where user_id = v_user_id) then
    raise exception 'Leave your current team before creating another.';
  end if;

  for attempt in 1..8 loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
    insert into public.teams (name, code, created_by)
      values (v_name, v_code, v_user_id)
      on conflict (code) do nothing
      returning id into v_team_id;
    exit when v_team_id is not null;
  end loop;
  if v_team_id is null then raise exception 'Could not create a team code. Try again.'; end if;

  insert into public.team_members (team_id, user_id) values (v_team_id, v_user_id);
end;
$$;

create or replace function public.join_team(p_code text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_team_id uuid;
  v_count integer;
  v_code text := upper(btrim(coalesce(p_code, '')));
begin
  if clock_timestamp() >= timestamptz '2026-11-04 00:00:00-05' then
    raise exception 'Team changes have closed.';
  end if;
  if v_user_id is null or not exists (
    select 1 from public.profiles
    where id = v_user_id and registration_status = 'confirmed' and admin = false
  ) then
    raise exception 'Only confirmed participants can join teams.';
  end if;
  if exists (select 1 from public.team_members where user_id = v_user_id) then
    raise exception 'Leave your current team before joining another.';
  end if;
  if v_code !~ '^[0-9A-F]{12}$' then raise exception 'Enter a valid 12-character team code.'; end if;

  select id into v_team_id from public.teams where code = v_code for update;
  if v_team_id is null then raise exception 'Team code not found.'; end if;
  select count(*) into v_count from public.team_members where team_id = v_team_id;
  if v_count >= 4 then raise exception 'This team is full.'; end if;
  insert into public.team_members (team_id, user_id) values (v_team_id, v_user_id);
end;
$$;

create or replace function public.leave_team()
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_team_id uuid;
  v_creator_id uuid;
  v_next_creator uuid;
begin
  if clock_timestamp() >= timestamptz '2026-11-04 00:00:00-05' then
    raise exception 'Team changes have closed.';
  end if;
  select team_id into v_team_id from public.team_members where user_id = v_user_id;
  if v_team_id is null then raise exception 'You are not on a team.'; end if;

  select created_by into v_creator_id from public.teams where id = v_team_id for update;
  if not found then raise exception 'This team no longer exists.'; end if;
  delete from public.team_members where team_id = v_team_id and user_id = v_user_id;

  select user_id into v_next_creator from public.team_members
    where team_id = v_team_id order by joined_at, user_id limit 1;
  if v_next_creator is null then
    delete from public.teams where id = v_team_id;
  elsif v_creator_id = v_user_id or v_creator_id is null then
    update public.teams set created_by = v_next_creator where id = v_team_id;
  end if;
end;
$$;

revoke all on function public.get_my_team(), public.create_team(text), public.join_team(text), public.leave_team()
  from public, anon, authenticated;
grant execute on function public.get_my_team(), public.create_team(text), public.join_team(text), public.leave_team()
  to authenticated;
