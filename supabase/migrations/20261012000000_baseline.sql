-- Rebuild a fresh Supabase preview from the manually maintained project schema.
-- Production already has profiles, so this baseline records history without replaying DDL there.
do $baseline_guard$
begin
  if to_regclass('public.profiles') is null then
    execute $baseline_sql$
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
  -- Serializes seat assignment so concurrent signups cannot pass 50.
  perform pg_advisory_xact_lock(20261107);
  select count(*) into v_count from public.profiles
    where registration_status = 'confirmed';
  update public.profiles
    set registration_status = case when v_count < 50 then 'confirmed' else 'waitlisted' end,
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
  code text not null unique check (code ~ '^[0-9A-F]{6}$'),
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
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
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
  if v_code !~ '^[0-9A-F]{6}$' then raise exception 'Enter a valid 6-character team code.'; end if;

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

-- Apply after 20261011_dashboard_teams.sql. All event times below are fixed Eastern instants.
-- The offset is private and zero in production. A separate test project can
-- move its event clock without changing production deadlines or user clocks.
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;
create table if not exists app_private.event_clock_offset (
  singleton boolean primary key default true check (singleton),
  preview_enabled boolean not null default false,
  clock_offset interval not null default interval '0 seconds',
  check (preview_enabled or clock_offset = interval '0 seconds')
);
revoke all on app_private.event_clock_offset from public, anon, authenticated;
insert into app_private.event_clock_offset (singleton)
values (true) on conflict (singleton) do nothing;

create or replace function public.event_now()
returns timestamptz language sql volatile security definer set search_path = '' as $$
  select clock_timestamp() + case when preview_enabled then clock_offset else interval '0 seconds' end
  from app_private.event_clock_offset where singleton = true;
$$;
revoke all on function public.event_now() from public, anon, authenticated;
grant execute on function public.event_now() to authenticated;

alter table public.profiles
  add column if not exists checked_in_at timestamptz,
  add column if not exists checked_in_by uuid references public.profiles(id) on delete set null;

create or replace function public.set_check_in(p_user_id uuid, p_arrived boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.current_user_is_admin() then raise exception 'Organizer access required.'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id and registration_status = 'confirmed' and admin = false) then
    raise exception 'Only confirmed participants can be checked in.';
  end if;
  update public.profiles set
    checked_in_at = case when p_arrived then public.event_now() else null end,
    checked_in_by = case when p_arrived then auth.uid() else null end
  where id = p_user_id;
end; $$;
revoke all on function public.set_check_in(uuid, boolean) from public, anon, authenticated;
grant execute on function public.set_check_in(uuid, boolean) to authenticated;

-- An earlier attempt may already have created the table. Preserve its rows.
create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  team_id uuid unique references public.teams(id) on delete cascade,
  solo_user_id uuid unique references public.profiles(id) on delete cascade,
  status text not null default 'draft' check (status in ('draft', 'submitted')),
  title text,
  description text,
  track text check (track in ('AI', 'Social good', 'Creative build')),
  github_url text,
  public_repo_confirmed boolean not null default false,
  ai_level text check (ai_level in ('none', 'assisted', 'substantial')),
  ai_disclosure text,
  slide_path text,
  onsite_confirmed boolean not null default false,
  no_outside_help_confirmed boolean not null default false,
  created_at timestamptz not null default public.event_now(),
  updated_at timestamptz not null default public.event_now(),
  submitted_at timestamptz,
  updated_by uuid references public.profiles(id) on delete set null,
  check (num_nonnulls(team_id, solo_user_id) = 1)
);
create index if not exists submissions_track_idx on public.submissions (track, status);
alter table public.submissions enable row level security;
revoke all on public.submissions from public, anon, authenticated;

create or replace function public.can_read_submission(p_team_id uuid, p_solo_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_is_admin() or
    (p_solo_user_id = auth.uid()) or
    exists (select 1 from public.team_members where team_id = p_team_id and user_id = auth.uid());
$$;
revoke all on function public.can_read_submission(uuid,uuid) from public, anon, authenticated;
grant execute on function public.can_read_submission(uuid,uuid) to authenticated;
drop policy if exists "Members and organizers read submissions" on public.submissions;
create policy "Members and organizers read submissions" on public.submissions
  for select to authenticated using (public.can_read_submission(team_id, solo_user_id));
grant select on public.submissions to authenticated;

-- Path format: team/<team UUID>/<random UUID>.<extension> or solo/<user UUID>/<random UUID>.<extension>.
create or replace function public.slide_scope(p_name text)
returns text language sql immutable set search_path = '' as $$
  select case when p_name ~ '^(team|solo)/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pptx|key|pdf)$'
    then split_part(p_name, '/', 1) else null end;
$$;
create or replace function public.can_read_slide(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare v_scope text := public.slide_scope(p_name); v_id uuid;
begin
  if v_scope is null then return false; end if;
  v_id := split_part(p_name, '/', 2)::uuid;
  return public.current_user_is_admin() or
    (v_scope = 'solo' and v_id = auth.uid()) or
    (v_scope = 'team' and exists (select 1 from public.team_members where team_id = v_id and user_id = auth.uid()));
end; $$;
create or replace function public.can_write_slide(p_name text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_scope text := public.slide_scope(p_name); v_id uuid;
begin
  if v_scope is null or public.event_now() < timestamptz '2026-11-07 10:00:00-05'
    or public.event_now() >= timestamptz '2026-11-08 10:00:00-05' then return false; end if;
  v_id := split_part(p_name, '/', 2)::uuid;
  if not exists (select 1 from public.profiles where id = auth.uid() and registration_status = 'confirmed' and admin = false and checked_in_at is not null) then return false; end if;
  if v_scope = 'solo' then
    return v_id = auth.uid() and not exists (select 1 from public.team_members where user_id = auth.uid());
  end if;
  return exists (select 1 from public.team_members where team_id = v_id and user_id = auth.uid());
end; $$;
create or replace function public.can_delete_slide(p_name text)
returns boolean language sql volatile security definer set search_path = '' as $$
  select public.can_read_slide(p_name) and not exists (
    select 1 from public.submissions where slide_path = p_name
  );
$$;
revoke all on function public.slide_scope(text), public.can_read_slide(text), public.can_write_slide(text), public.can_delete_slide(text) from public, anon, authenticated;
grant execute on function public.slide_scope(text), public.can_read_slide(text), public.can_write_slide(text), public.can_delete_slide(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit)
values ('submission-slides', 'submission-slides', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = 10485760;

drop policy if exists "Authorized slide downloads" on storage.objects;
create policy "Authorized slide downloads" on storage.objects for select to authenticated
  using (bucket_id = 'submission-slides' and public.can_read_slide(name));
drop policy if exists "Checked-in slide uploads" on storage.objects;
create policy "Checked-in slide uploads" on storage.objects for insert to authenticated
  with check (bucket_id = 'submission-slides' and public.can_write_slide(name));
drop policy if exists "Remove unused slides" on storage.objects;
create policy "Remove unused slides" on storage.objects for delete to authenticated
  using (bucket_id = 'submission-slides' and public.can_delete_slide(name));

create or replace function public.get_my_submission()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_team_id uuid; v_result jsonb;
begin
  select team_id into v_team_id from public.team_members where user_id = auth.uid();
  select to_jsonb(s) into v_result from public.submissions s
  where (v_team_id is not null and s.team_id = v_team_id)
     or (v_team_id is null and s.solo_user_id = auth.uid());
  return v_result;
end; $$;
revoke all on function public.get_my_submission() from public, anon, authenticated;
grant execute on function public.get_my_submission() to authenticated;

create or replace function public.save_submission(
  p_title text, p_description text, p_track text, p_github_url text,
  p_public_repo_confirmed boolean, p_ai_level text, p_ai_disclosure text,
  p_slide_path text, p_submit boolean, p_onsite_confirmed boolean,
  p_no_outside_help_confirmed boolean, p_expected_updated_at timestamptz
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_team uuid; v_scope text; v_id uuid; v_existing public.submissions%rowtype;
  v_title text := nullif(btrim(coalesce(p_title,'')), '');
  v_description text := nullif(btrim(coalesce(p_description,'')), '');
  v_url text := nullif(btrim(coalesce(p_github_url,'')), '');
  v_ai text := nullif(btrim(coalesce(p_ai_disclosure,'')), '');
  v_slide text := nullif(p_slide_path, '');
  v_now timestamptz := public.event_now(); v_size bigint; v_created_id uuid;
begin
  if v_now < timestamptz '2026-11-07 10:00:00-05' or v_now >= timestamptz '2026-11-08 10:00:00-05' then
    raise exception 'The submission window is closed.';
  end if;
  if not exists (select 1 from public.profiles where id = v_user and registration_status = 'confirmed' and admin = false and checked_in_at is not null) then
    raise exception 'Check in with an organizer before submitting.';
  end if;
  select team_id into v_team from public.team_members where user_id = v_user;
  v_scope := case when v_team is null then 'solo' else 'team' end;
  v_id := coalesce(v_team, v_user);
  if char_length(coalesce(v_title,'')) > 120 or char_length(coalesce(v_description,'')) > 500 or char_length(coalesce(v_ai,'')) > 1000 then
    raise exception 'A text field is too long.';
  end if;
  if p_track is not null and p_track not in ('AI','Social good','Creative build') then raise exception 'Choose a valid track.'; end if;
  if p_ai_level is not null and p_ai_level not in ('none','assisted','substantial') then raise exception 'Choose a valid AI-use level.'; end if;
  if v_url is not null and v_url !~* '^https://github\.com/[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]+(\.git)?/?$' then
    raise exception 'Enter a GitHub repository URL.';
  end if;
  if v_slide is not null then
    if public.slide_scope(v_slide) is distinct from v_scope or split_part(v_slide,'/',2)::uuid <> v_id then
      raise exception 'Slide file does not belong to this submission.';
    end if;
    select (metadata->>'size')::bigint into v_size from storage.objects
      where bucket_id = 'submission-slides' and name = v_slide;
    if v_size is null or v_size > 10485760 then raise exception 'Slides must be an uploaded file of 10 MB or less.'; end if;
  end if;
  if p_submit and (v_title is null or v_description is null or p_track is null or v_url is null
    or not coalesce(p_public_repo_confirmed,false) or p_ai_level is null or v_ai is null or v_slide is null
    or not coalesce(p_onsite_confirmed,false) or not coalesce(p_no_outside_help_confirmed,false)) then
    raise exception 'Complete every field, upload slides, and confirm the rules before submitting.';
  end if;
  insert into public.submissions (team_id, solo_user_id, updated_by)
    values (v_team, case when v_team is null then v_user else null end, v_user)
    on conflict do nothing returning id into v_created_id;
  select * into v_existing from public.submissions
    where (v_team is not null and team_id = v_team) or (v_team is null and solo_user_id = v_user)
    for update;
  if v_created_id is null and v_existing.updated_at is distinct from p_expected_updated_at then
    raise exception 'A teammate changed this submission. Refresh and review their changes before saving.';
  end if;
  if public.event_now() >= timestamptz '2026-11-08 10:00:00-05' then
    raise exception 'The submission window is closed.';
  end if;
  update public.submissions set
    status = case when p_submit then 'submitted' else 'draft' end,
    title = v_title, description = v_description, track = p_track, github_url = v_url,
    public_repo_confirmed = coalesce(p_public_repo_confirmed,false), ai_level = p_ai_level,
    ai_disclosure = v_ai, slide_path = v_slide,
    onsite_confirmed = coalesce(p_onsite_confirmed,false),
    no_outside_help_confirmed = coalesce(p_no_outside_help_confirmed,false),
    updated_at = v_now, updated_by = v_user,
    submitted_at = case when p_submit then v_now else null end
  where id = v_existing.id;
end; $$;
revoke all on function public.save_submission(text,text,text,text,boolean,text,text,text,boolean,boolean,boolean,timestamptz) from public, anon, authenticated;
grant execute on function public.save_submission(text,text,text,text,boolean,text,text,text,boolean,boolean,boolean,timestamptz) to authenticated;

-- After the deadline, only the repository URL can change. Other fields and slides stay locked.
create or replace function public.update_submission_repo(p_github_url text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_team uuid; v_url text := btrim(coalesce(p_github_url,''));
begin
  if public.event_now() < timestamptz '2026-11-08 10:00:00-05' then raise exception 'Use the submission form before the deadline.'; end if;
  if v_url !~* '^https://github\.com/[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]+(\.git)?/?$' then
    raise exception 'Enter a GitHub repository URL.';
  end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and registration_status = 'confirmed' and checked_in_at is not null and admin = false) then
    raise exception 'Check in with an organizer before updating the link.';
  end if;
  select team_id into v_team from public.team_members where user_id = auth.uid();
  update public.submissions set github_url = v_url, updated_at = public.event_now(), updated_by = auth.uid()
    where (v_team is not null and team_id = v_team) or (v_team is null and solo_user_id = auth.uid());
  if not found then raise exception 'No submission was found.'; end if;
end; $$;
revoke all on function public.update_submission_repo(text) from public, anon, authenticated;
grant execute on function public.update_submission_repo(text) to authenticated;

create or replace function public.get_organizer_submissions()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_result jsonb;
begin
  if not public.current_user_is_admin() then raise exception 'Organizer access required.'; end if;
  select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object(
    'team_name', t.name,
    'members', coalesce((select jsonb_agg(jsonb_build_object('name',p.full_name,'checked_in_at',p.checked_in_at))
      from public.team_members m join public.profiles p on p.id=m.user_id where m.team_id=s.team_id),
      (select jsonb_agg(jsonb_build_object('name',p.full_name,'checked_in_at',p.checked_in_at))
        from public.profiles p where p.id=s.solo_user_id))
  ) order by s.track nulls last, s.updated_at desc), '[]'::jsonb) into v_result
  from public.submissions s left join public.teams t on t.id=s.team_id;
  return v_result;
end; $$;
revoke all on function public.get_organizer_submissions() from public, anon, authenticated;
grant execute on function public.get_organizer_submissions() to authenticated;

-- Apply before deploying the invitation pages. Run once on existing projects.
-- The first organizer remains a trusted account established in Supabase.
create table if not exists public.organizer_invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null check (email = lower(btrim(email)) and email ~ '^[^@[:space:]]+@fandm\.edu$'),
  token_hash bytea not null unique,
  invited_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  used_at timestamptz,
  used_by uuid references public.profiles(id) on delete set null,
  revoked_at timestamptz
);
create index if not exists organizer_invitations_email_idx on public.organizer_invitations (email);
alter table public.organizer_invitations enable row level security;
revoke all on public.organizer_invitations from public, anon, authenticated;

-- Organizer-only RPCs return metadata, never the token hash.
create or replace function public.create_organizer_invitation(p_email text, p_token_hash text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_id uuid;
begin
  if not public.current_user_is_admin() then raise exception 'Organizer access required.'; end if;
  if v_email !~ '^[^@[:space:]]+@fandm\.edu$' then raise exception 'Use an F&M email address.'; end if;
  if coalesce(p_token_hash, '') !~ '^[0-9a-f]{64}$' then raise exception 'Invalid invitation token.'; end if;
  insert into public.organizer_invitations (email, token_hash, invited_by)
    values (v_email, decode(p_token_hash, 'hex'), auth.uid()) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.list_organizer_invitations()
returns table (id uuid, email text, invited_by uuid, created_at timestamptz, expires_at timestamptz, used_at timestamptz, revoked_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  if not public.current_user_is_admin() then raise exception 'Organizer access required.'; end if;
  return query select i.id, i.email, i.invited_by, i.created_at, i.expires_at, i.used_at, i.revoked_at
    from public.organizer_invitations i order by i.created_at desc;
end;
$$;

create or replace function public.revoke_organizer_invitation(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.current_user_is_admin() then raise exception 'Organizer access required.'; end if;
  update public.organizer_invitations set revoked_at = clock_timestamp()
    where id = p_id and used_at is null and revoked_at is null;
  if not found then raise exception 'Invitation is unavailable.'; end if;
end;
$$;

-- Called only from the auth trigger. The SHA-256 digest is passed through Auth
-- metadata and removed from that metadata before the signup transaction commits.
create or replace function public.consume_organizer_invitation(p_hash text, p_email text, p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(p_hash, '') !~ '^[0-9a-f]{64}$' then raise exception 'Invalid invitation.'; end if;
  update public.organizer_invitations
    set used_at = clock_timestamp(), used_by = p_user_id
    where token_hash = decode(p_hash, 'hex') and email = lower(p_email)
      and used_at is null and revoked_at is null and expires_at > clock_timestamp();
  if not found then raise exception 'Invitation is invalid, expired, or already used.'; end if;
end;
$$;
revoke all on function public.consume_organizer_invitation(text,text,uuid) from public, anon, authenticated;

-- Participant fields are required only for participants.
alter table public.profiles alter column grade drop not null;
alter table public.profiles alter column tshirt_size drop not null;
alter table public.profiles alter column attendance_committed_at drop not null;
alter table public.profiles drop constraint if exists profiles_participant_fields_check;
alter table public.profiles add constraint profiles_participant_fields_check check (
  (admin = true and registration_status = 'organizer') or
  (admin = false and registration_status <> 'organizer' and grade is not null and tshirt_size is not null and attendance_committed_at is not null)
) not valid;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(coalesce(new.email, ''));
  v_name text := btrim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  v_hash text := coalesce(new.raw_user_meta_data ->> 'organizer_invite_hash', '');
  v_grade text := coalesce(new.raw_user_meta_data ->> 'grade', '');
  v_size text := coalesce(new.raw_user_meta_data ->> 'tshirt_size', '');
begin
  if v_email !~ '^[^@[:space:]]+@fandm\.edu$' then raise exception 'An F&M email address is required'; end if;
  if char_length(v_name) not between 2 and 120 then raise exception 'Enter a full name'; end if;
  if v_hash <> '' then
    -- Invitation and profile creation share the Auth signup transaction.
    insert into public.profiles (id, email, full_name, admin, registration_status)
      values (new.id, v_email, v_name, true, 'organizer');
    perform public.consume_organizer_invitation(v_hash, v_email, new.id);
    update auth.users set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) - 'organizer_invite_hash'
      where id = new.id;
  else
    if clock_timestamp() >= timestamptz '2026-11-04 00:00:00-05' then raise exception 'Registration is closed'; end if;
    if coalesce(new.raw_user_meta_data ->> 'attendance_commitment', '') <> 'true' then raise exception 'Attendance commitment is required'; end if;
    insert into public.profiles (id, email, full_name, grade, tshirt_size, attendance_committed_at)
      values (new.id, v_email, v_name, v_grade, v_size, now());
    perform public.assign_registration(new.id);
  end if;
  return new;
end;
$$;

-- The caller must be signed in as the account whose email matches the invite.
create or replace function public.accept_organizer_invitation(p_hash text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_email text;
  v_previous text;
  v_next uuid;
  v_count integer;
begin
  if v_user is null then raise exception 'Sign in to accept this invitation.'; end if;
  if coalesce(p_hash, '') !~ '^[0-9a-f]{64}$' then raise exception 'Invitation is invalid.'; end if;
  -- Same lock as assign_registration, including the waitlist replacement.
  perform pg_advisory_xact_lock(20261107);
  select email, registration_status into v_email, v_previous
    from public.profiles where id = v_user for update;
  if v_email is null or v_previous = 'organizer' then raise exception 'Account cannot accept this invitation.'; end if;
  update public.organizer_invitations set used_at = clock_timestamp(), used_by = v_user
    where token_hash = decode(p_hash, 'hex') and email = v_email
      and used_at is null and revoked_at is null and expires_at > clock_timestamp();
  if not found then raise exception 'Invitation is invalid, expired, or already used for another account.'; end if;
  update public.profiles set admin = true, registration_status = 'organizer',
    checked_in_at = null, checked_in_by = null where id = v_user;
  if v_previous = 'confirmed' then
    select count(*) into v_count from public.profiles where registration_status = 'confirmed';
  end if;
  if v_previous = 'confirmed' and v_count < 50 then
    select id into v_next from public.profiles
      where registration_status = 'waitlisted' and admin = false
      order by assigned_at, registered_at, id limit 1 for update;
    if v_next is not null then
      update public.profiles set registration_status = 'confirmed' where id = v_next;
    end if;
  end if;
  return (select email from public.profiles where id = v_next);
end;
$$;

revoke all on function public.create_organizer_invitation(text,text), public.list_organizer_invitations(),
  public.revoke_organizer_invitation(uuid), public.accept_organizer_invitation(text) from public, anon, authenticated;
grant execute on function public.create_organizer_invitation(text,text), public.list_organizer_invitations(),
  public.revoke_organizer_invitation(uuid), public.accept_organizer_invitation(text) to authenticated;

-- Normalize previously trusted organizers, then fill available places in queue order.
-- Existing confirmed students are never demoted.
do $$
declare
  v_count integer;
  v_person uuid;
begin
  perform pg_advisory_xact_lock(20261107);
  update public.profiles set registration_status = 'organizer', checked_in_at = null, checked_in_by = null
    where admin = true and registration_status <> 'organizer';
  select count(*) into v_count from public.profiles where registration_status = 'confirmed';
  if v_count > 50 then raise warning 'There are % pre-existing confirmed participants; review manually.', v_count; end if;
  while v_count < 50 loop
    select id into v_person from public.profiles where registration_status = 'waitlisted' and admin = false
      order by assigned_at, registered_at, id limit 1;
    exit when v_person is null;
    update public.profiles set registration_status = 'confirmed' where id = v_person;
    v_count := v_count + 1;
  end loop;
end;
$$;
alter table public.profiles validate constraint profiles_participant_fields_check;

-- Apply after 20261027_organizer_invitations.sql on projects that already ran it.
-- Keep invitation history without preventing Auth user/profile deletion.
alter table public.organizer_invitations
  alter column invited_by drop not null,
  drop constraint if exists organizer_invitations_invited_by_fkey,
  add constraint organizer_invitations_invited_by_fkey
    foreign key (invited_by) references public.profiles(id) on delete set null,
  drop constraint if exists organizer_invitations_used_by_fkey,
  add constraint organizer_invitations_used_by_fkey
    foreign key (used_by) references public.profiles(id) on delete set null;

-- Organizer-only team names for the registration roster.
-- Team tables remain private; no direct table grants are added.
create or replace function public.get_organizer_roster_teams()
returns table (user_id uuid, team_name text)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.current_user_is_admin() then
    raise exception 'Organizer access required.';
  end if;

  return query
    select member.user_id, team.name
    from public.team_members member
    join public.teams team on team.id = member.team_id;
end;
$$;

revoke all on function public.get_organizer_roster_teams() from public, anon, authenticated;
grant execute on function public.get_organizer_roster_teams() to authenticated;

-- Require a track for every new draft save and final submission.
-- Existing drafts with a null track remain in place for participants to edit.
-- The submitted-row constraint validates existing final submissions.
create or replace function public.save_submission(
  p_title text, p_description text, p_track text, p_github_url text,
  p_public_repo_confirmed boolean, p_ai_level text, p_ai_disclosure text,
  p_slide_path text, p_submit boolean, p_onsite_confirmed boolean,
  p_no_outside_help_confirmed boolean, p_expected_updated_at timestamptz
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_team uuid; v_scope text; v_id uuid; v_existing public.submissions%rowtype;
  v_title text := nullif(btrim(coalesce(p_title,'')), '');
  v_description text := nullif(btrim(coalesce(p_description,'')), '');
  v_url text := nullif(btrim(coalesce(p_github_url,'')), '');
  v_ai text := nullif(btrim(coalesce(p_ai_disclosure,'')), '');
  v_slide text := nullif(p_slide_path, '');
  v_now timestamptz := public.event_now(); v_size bigint; v_created_id uuid;
begin
  if v_now < timestamptz '2026-11-07 10:00:00-05' or v_now >= timestamptz '2026-11-08 10:00:00-05' then
    raise exception 'The submission window is closed.';
  end if;
  if not exists (select 1 from public.profiles where id = v_user and registration_status = 'confirmed' and admin = false and checked_in_at is not null) then
    raise exception 'Check in with an organizer before submitting.';
  end if;
  select team_id into v_team from public.team_members where user_id = v_user;
  v_scope := case when v_team is null then 'solo' else 'team' end;
  v_id := coalesce(v_team, v_user);
  if char_length(coalesce(v_title,'')) > 120 or char_length(coalesce(v_description,'')) > 500 or char_length(coalesce(v_ai,'')) > 1000 then
    raise exception 'A text field is too long.';
  end if;
  if p_track is null or p_track not in ('AI','Social good','Creative build') then raise exception 'Choose a valid track before saving or submitting.'; end if;
  if p_ai_level is not null and p_ai_level not in ('none','assisted','substantial') then raise exception 'Choose a valid AI-use level.'; end if;
  if v_url is not null and v_url !~* '^https://github\.com/[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]+(\.git)?/?$' then
    raise exception 'Enter a GitHub repository URL.';
  end if;
  if v_slide is not null then
    if public.slide_scope(v_slide) is distinct from v_scope or split_part(v_slide,'/',2)::uuid <> v_id then
      raise exception 'Slide file does not belong to this submission.';
    end if;
    select (metadata->>'size')::bigint into v_size from storage.objects
      where bucket_id = 'submission-slides' and name = v_slide;
    if v_size is null or v_size > 10485760 then raise exception 'Slides must be an uploaded file of 10 MB or less.'; end if;
  end if;
  if p_submit and (v_title is null or v_description is null or p_track is null or v_url is null
    or not coalesce(p_public_repo_confirmed,false) or p_ai_level is null or v_ai is null or v_slide is null
    or not coalesce(p_onsite_confirmed,false) or not coalesce(p_no_outside_help_confirmed,false)) then
    raise exception 'Complete every field, upload slides, and confirm the rules before submitting.';
  end if;
  insert into public.submissions (team_id, solo_user_id, updated_by)
    values (v_team, case when v_team is null then v_user else null end, v_user)
    on conflict do nothing returning id into v_created_id;
  select * into v_existing from public.submissions
    where (v_team is not null and team_id = v_team) or (v_team is null and solo_user_id = v_user)
    for update;
  if v_created_id is null and v_existing.updated_at is distinct from p_expected_updated_at then
    raise exception 'A teammate changed this submission. Refresh and review their changes before saving.';
  end if;
  if public.event_now() >= timestamptz '2026-11-08 10:00:00-05' then
    raise exception 'The submission window is closed.';
  end if;
  update public.submissions set
    status = case when p_submit then 'submitted' else 'draft' end,
    title = v_title, description = v_description, track = p_track, github_url = v_url,
    public_repo_confirmed = coalesce(p_public_repo_confirmed,false), ai_level = p_ai_level,
    ai_disclosure = v_ai, slide_path = v_slide,
    onsite_confirmed = coalesce(p_onsite_confirmed,false),
    no_outside_help_confirmed = coalesce(p_no_outside_help_confirmed,false),
    updated_at = v_now, updated_by = v_user,
    submitted_at = case when p_submit then v_now else null end
  where id = v_existing.id;
end; $$;

revoke all on function public.save_submission(text,text,text,text,boolean,text,text,text,boolean,boolean,boolean,timestamptz) from public, anon, authenticated;
grant execute on function public.save_submission(text,text,text,text,boolean,text,text,text,boolean,boolean,boolean,timestamptz) to authenticated;

alter table public.submissions
  add constraint submissions_submitted_track_required
  check (status <> 'submitted' or track is not null);

-- Organizers and judges see submitted projects only. Participants keep access
-- to their own drafts and slides while editing them.

drop policy if exists "Members and organizers read submissions" on public.submissions;
drop function if exists public.can_read_submission(uuid, uuid);

create or replace function public.can_read_submission(p_team_id uuid, p_solo_user_id uuid, p_status text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case when public.current_user_is_admin() then p_status = 'submitted'
    else (p_solo_user_id = auth.uid()) or exists (
      select 1 from public.team_members
      where team_id = p_team_id and user_id = auth.uid()
    ) end;
$$;
revoke all on function public.can_read_submission(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.can_read_submission(uuid,uuid,text) to authenticated;
create policy "Members and organizers read submissions" on public.submissions
  for select to authenticated using (public.can_read_submission(team_id, solo_user_id, status));

create or replace function public.can_read_slide(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_scope text := public.slide_scope(p_name);
  v_id uuid;
begin
  if v_scope is null then return false; end if;
  if public.current_user_is_admin() then
    return exists (
      select 1 from public.submissions
      where status = 'submitted' and slide_path = p_name
    );
  end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and admin = false) then
    return false;
  end if;
  v_id := split_part(p_name, '/', 2)::uuid;
  return (v_scope = 'solo' and v_id = auth.uid()) or
    (v_scope = 'team' and exists (
      select 1 from public.team_members where team_id = v_id and user_id = auth.uid()
    ));
end; $$;
revoke all on function public.can_read_slide(text) from public, anon, authenticated;
grant execute on function public.can_read_slide(text) to authenticated;

create or replace function public.get_my_submission()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_team_id uuid;
  v_result jsonb;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and admin = false and registration_status = 'confirmed'
  ) then return null; end if;
  select team_id into v_team_id from public.team_members where user_id = auth.uid();
  select to_jsonb(s) into v_result from public.submissions s
  where (v_team_id is not null and s.team_id = v_team_id)
     or (v_team_id is null and s.solo_user_id = auth.uid());
  return v_result;
end; $$;
revoke all on function public.get_my_submission() from public, anon, authenticated;
grant execute on function public.get_my_submission() to authenticated;

create or replace function public.get_organizer_submissions()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_result jsonb;
begin
  if not public.current_user_is_admin() then raise exception 'Organizer access required.'; end if;
  select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object(
    'team_name', t.name,
    'members', coalesce((select jsonb_agg(jsonb_build_object('name',p.full_name,'checked_in_at',p.checked_in_at))
      from public.team_members m join public.profiles p on p.id=m.user_id where m.team_id=s.team_id),
      (select jsonb_agg(jsonb_build_object('name',p.full_name,'checked_in_at',p.checked_in_at))
        from public.profiles p where p.id=s.solo_user_id))
  ) order by s.track, s.updated_at desc), '[]'::jsonb) into v_result
  from public.submissions s left join public.teams t on t.id=s.team_id
  where s.status = 'submitted';
  return v_result;
end; $$;
revoke all on function public.get_organizer_submissions() from public, anon, authenticated;
grant execute on function public.get_organizer_submissions() to authenticated;
$baseline_sql$;
  end if;
end;
$baseline_guard$;
