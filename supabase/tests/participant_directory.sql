-- Run on a disposable project after the participant-directory migration.
-- Run before public registration closes; fixtures are rolled back.
begin;
do $$
declare
  v_student uuid := gen_random_uuid();
  v_solo uuid := gen_random_uuid();
  v_organizer uuid := gen_random_uuid();
  v_team uuid;
  v_row record;
begin
  if has_function_privilege('anon', 'public.list_participants()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.list_participants()', 'EXECUTE')
     or has_table_privilege('authenticated', 'public.teams', 'SELECT') then
    raise exception 'Participant directory permissions are incorrect';
  end if;

  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
  values
    (v_student, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'directory-student@fandm.edu', jsonb_build_object('full_name', 'Directory Student', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true)),
    (v_solo, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'directory-solo@fandm.edu', jsonb_build_object('full_name', 'Directory Solo', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true)),
    (v_organizer, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'directory-organizer@fandm.edu', jsonb_build_object('full_name', 'Directory Organizer', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true));
  update public.profiles set admin = true, registration_status = 'organizer' where id = v_organizer;
  insert into public.teams (name, code, created_by)
    values ('Directory Team', upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)), v_student)
    returning id into v_team;
  insert into public.team_members (team_id, user_id) values (v_team, v_student);

  perform set_config('request.jwt.claim.sub', v_student::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  if (select count(*) from public.list_participants()) <> 2
     or exists (select 1 from public.list_participants() where email = 'directory-organizer@fandm.edu')
     or not exists (select 1 from public.list_participants() where email = 'directory-student@fandm.edu' and team_status = 'Directory Team')
     or not exists (select 1 from public.list_participants() where email = 'directory-solo@fandm.edu' and team_status = 'Solo') then
    raise exception 'Student directory returned the wrong people or team status';
  end if;
  select * into v_row from public.list_participants() limit 1;
  if (select array_agg(field order by field) from jsonb_object_keys(to_jsonb(v_row)) as keys(field))
     <> array['email', 'full_name', 'team_status'] then
    raise exception 'Student directory exposed extra fields';
  end if;

  perform set_config('request.jwt.claim.sub', v_organizer::text, true);
  begin
    perform 1 from public.list_participants();
    raise exception 'Organizer read the student-only directory';
  exception when others then
    if sqlerrm = 'Organizer read the student-only directory' then raise; end if;
  end;
end;
$$;
rollback;
