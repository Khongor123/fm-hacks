-- Apply to existing Supabase projects before deploying the 6-character team-code UI.
-- Existing teams keep their members, but receive new codes to share with teammates.
begin;

lock table public.teams in access exclusive mode;
alter table public.teams drop constraint if exists teams_code_check;

do $$
declare
  v_team record;
  v_code text;
begin
  for v_team in
    select id from public.teams where code !~ '^[0-9A-F]{6}$' order by id
  loop
    loop
      v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
      exit when not exists (select 1 from public.teams where code = v_code);
    end loop;
    update public.teams set code = v_code where id = v_team.id;
  end loop;
end;
$$;

alter table public.teams add constraint teams_code_check
  check (code ~ '^[0-9A-F]{6}$');

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

revoke all on function public.create_team(text), public.join_team(text)
  from public, anon, authenticated;
grant execute on function public.create_team(text), public.join_team(text)
  to authenticated;

commit;
