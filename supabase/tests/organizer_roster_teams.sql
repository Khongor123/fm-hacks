-- Run on a disposable Supabase project after the roster-team migration.
-- Run before public registration closes; all fixtures are rolled back.
begin;
do $$
declare
  v_admin uuid := gen_random_uuid();
  v_member uuid := gen_random_uuid();
  v_solo uuid := gen_random_uuid();
  v_team uuid;
  v_name text;
begin
  if has_table_privilege('authenticated', 'public.team_members', 'SELECT')
     or has_table_privilege('authenticated', 'public.teams', 'SELECT')
     or has_function_privilege('anon', 'public.get_organizer_roster_teams()', 'EXECUTE') then
    raise exception 'Team membership access is too broad';
  end if;

  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
  values
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'roster-admin@fandm.edu', jsonb_build_object('full_name', 'Roster Admin', 'grade', 'senior', 'tshirt_size', 'M', 'attendance_commitment', true)),
    (v_member, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'roster-member@fandm.edu', jsonb_build_object('full_name', 'Roster Member', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true)),
    (v_solo, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'roster-solo@fandm.edu', jsonb_build_object('full_name', 'Roster Solo', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true));
  update public.profiles set admin = true, registration_status = 'organizer' where id = v_admin;
  insert into public.teams (name, code, created_by)
    values ('Test Team', upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)), v_member)
    returning id into v_team;
  insert into public.team_members (team_id, user_id) values (v_team, v_member);

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  select team_name into v_name from public.get_organizer_roster_teams() where user_id = v_member;
  if v_name is distinct from 'Test Team' then raise exception 'Team name missing from organizer roster'; end if;
  if exists (select 1 from public.get_organizer_roster_teams() where user_id = v_solo) then
    raise exception 'Solo participant unexpectedly has a team';
  end if;

  perform set_config('request.jwt.claim.sub', v_member::text, true);
  begin
    perform 1 from public.get_organizer_roster_teams();
    raise exception 'Participant read the organizer team list';
  exception when others then
    if sqlerrm = 'Participant read the organizer team list' then raise; end if;
  end;
  raise notice 'Organizer roster team checks passed';
end;
$$;
rollback;
