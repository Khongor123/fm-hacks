-- Reopen participant registration and team changes through November 5, 2026,
-- 11:59 p.m. Eastern. The cutoff is November 6 at 00:00 EST.
begin;

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
    insert into public.profiles (id, email, full_name, admin, registration_status)
      values (new.id, v_email, v_name, true, 'organizer');
    perform public.consume_organizer_invitation(v_hash, v_email, new.id);
    update auth.users
      set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) - 'organizer_invite_hash'
      where id = new.id;
  else
    if clock_timestamp() >= timestamptz '2026-11-06 00:00:00-05' then raise exception 'Registration is closed'; end if;
    if coalesce(new.raw_user_meta_data ->> 'attendance_commitment', '') <> 'true' then
      raise exception 'Attendance commitment is required';
    end if;
    insert into public.profiles (id, email, full_name, grade, tshirt_size, attendance_committed_at)
      values (new.id, v_email, v_name, v_grade, v_size, now());
    perform public.assign_registration(new.id);
  end if;
  return new;
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
  if clock_timestamp() >= timestamptz '2026-11-06 00:00:00-05' then
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
  if clock_timestamp() >= timestamptz '2026-11-06 00:00:00-05' then
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
  if clock_timestamp() >= timestamptz '2026-11-06 00:00:00-05' then
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

revoke all on function public.create_team(text), public.join_team(text), public.leave_team()
  from public, anon, authenticated;
grant execute on function public.create_team(text), public.join_team(text), public.leave_team()
  to authenticated;

commit;
