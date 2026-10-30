-- Run on a disposable project after the team-code repair migration.
-- Run before team changes close; fixtures are rolled back.
begin;
do $$
declare
  v_creator uuid := gen_random_uuid();
  v_joiner uuid := gen_random_uuid();
  v_third uuid := gen_random_uuid();
  v_fourth uuid := gen_random_uuid();
  v_fifth uuid := gen_random_uuid();
  v_code text;
  v_team_id uuid;
begin
  if not has_function_privilege('authenticated', 'public.join_team(text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.join_team(text)', 'EXECUTE') then
    raise exception 'Team join permissions are incorrect';
  end if;

  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
  values
    (v_creator, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'team-creator-test@fandm.edu', jsonb_build_object('full_name', 'Team Creator', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true)),
    (v_joiner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'team-joiner-test@fandm.edu', jsonb_build_object('full_name', 'Team Joiner', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true)),
    (v_third, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'team-third-test@fandm.edu', jsonb_build_object('full_name', 'Team Third', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true)),
    (v_fourth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'team-fourth-test@fandm.edu', jsonb_build_object('full_name', 'Team Fourth', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true)),
    (v_fifth, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'team-fifth-test@fandm.edu', jsonb_build_object('full_name', 'Team Fifth', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true));

  perform set_config('request.jwt.claim.sub', v_creator::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform public.create_team('Join Test Team');
  select t.id, t.code into v_team_id, v_code
    from public.teams t where t.created_by = v_creator;
  if v_code !~ '^[0-9A-F]{6}$' then
    raise exception 'Team creation did not generate a six-character code';
  end if;

  perform set_config('request.jwt.claim.sub', v_joiner::text, true);
  perform public.join_team(lower(v_code));
  if not exists (
    select 1 from public.team_members where team_id = v_team_id and user_id = v_joiner
  ) then
    raise exception 'Joining an existing team by code failed';
  end if;
  if (public.get_my_team() ->> 'code') is distinct from v_code then
    raise exception 'New member cannot read the joined team';
  end if;
  perform set_config('request.jwt.claim.sub', v_third::text, true);
  perform public.join_team(v_code);
  perform set_config('request.jwt.claim.sub', v_fourth::text, true);
  perform public.join_team(v_code);
  if (select count(*) from public.team_members where team_id = v_team_id) <> 4 then
    raise exception 'The third or fourth member could not join';
  end if;
  perform set_config('request.jwt.claim.sub', v_fifth::text, true);
  begin
    perform public.join_team(v_code);
    raise exception 'A fifth member joined a full team';
  exception when others then
    if sqlerrm <> 'This team is full.' then raise; end if;
  end;
end;
$$;
rollback;
