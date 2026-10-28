-- Run on a disposable project after the self-delete migration and before Nov 4.
-- The transaction rolls back all fixture accounts.
begin;
do $$
declare
  v_confirmed uuid;
  v_teammate uuid;
  v_wait1 uuid := gen_random_uuid();
  v_wait2 uuid := gen_random_uuid();
  v_organizer uuid := gen_random_uuid();
  v_team uuid;
begin
  if has_function_privilege('anon', 'public.delete_my_account()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.delete_my_account()', 'EXECUTE') then
    raise exception 'Self-deletion permissions are incorrect';
  end if;

  for n in 1..50 loop
    insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
      values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'delete-seat-' || n || '@fandm.edu', jsonb_build_object('full_name', 'Seat Person', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true))
      returning id into v_confirmed;
    if n = 1 then v_teammate := v_confirmed; end if;
  end loop;
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
    values (v_wait1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'delete-wait-one@fandm.edu', jsonb_build_object('full_name', 'First Waitlisted', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true));
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
    values (v_wait2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'delete-wait-two@fandm.edu', jsonb_build_object('full_name', 'Second Waitlisted', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true));
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
    values (v_organizer, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'delete-organizer@fandm.edu', jsonb_build_object('full_name', 'Organizer Person', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true));
  update public.profiles set admin = true, registration_status = 'organizer' where id = v_organizer;

  insert into public.teams (name, code, created_by)
    values ('Deletion Team', 'D3117E', v_confirmed) returning id into v_team;
  insert into public.team_members (team_id, user_id) values (v_team, v_confirmed), (v_team, v_teammate);

  perform set_config('request.jwt.claim.sub', v_confirmed::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform public.delete_my_account();
  if exists (select 1 from auth.users where id = v_confirmed)
     or exists (select 1 from public.profiles where id = v_confirmed)
     or (select count(*) from public.profiles where registration_status = 'confirmed') <> 50
     or not exists (select 1 from public.profiles where id = v_wait1 and registration_status = 'confirmed')
     or (select created_by from public.teams where id = v_team) <> v_teammate then
    raise exception 'Confirmed deletion did not remove account, promote first waitlisted, and transfer team';
  end if;

  perform set_config('request.jwt.claim.sub', v_wait2::text, true);
  perform public.delete_my_account();
  if exists (select 1 from auth.users where id = v_wait2)
     or (select count(*) from public.profiles where registration_status = 'confirmed') <> 50 then
    raise exception 'Waitlisted deletion changed capacity';
  end if;

  perform set_config('request.jwt.claim.sub', v_organizer::text, true);
  perform public.delete_my_account();
  if exists (select 1 from auth.users where id = v_organizer)
     or (select count(*) from public.profiles where registration_status = 'confirmed') <> 50 then
    raise exception 'Organizer deletion changed capacity';
  end if;
end;
$$;
rollback;
