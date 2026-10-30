-- Run on a disposable Supabase project with both invitation migrations applied.
-- Run before the Nov 4 public registration cutoff. The transaction rolls back
-- all fixture users, profiles, and invitations.
begin;
do $$
declare
  v_admin uuid := gen_random_uuid();
  v_confirmed uuid := gen_random_uuid();
  v_wait1 uuid := gen_random_uuid();
  v_wait2 uuid := gen_random_uuid();
  v_invited uuid := gen_random_uuid();
  v_bad uuid := gen_random_uuid();
  v_id uuid;
  v_teammate uuid;
  v_team uuid;
  v_promoted text;
  v_hash1 text := repeat('a', 64);
  v_hash2 text := repeat('b', 64);
  v_hash3 text := repeat('c', 64);
  v_hash4 text := repeat('d', 64);
  v_hash5 text := repeat('e', 64);
  v_hash6 text := repeat('f', 64);
begin
  if has_table_privilege('authenticated', 'public.organizer_invitations', 'SELECT')
     or has_function_privilege('anon', 'public.create_organizer_invitation(text,text)', 'EXECUTE') then
    raise exception 'Invitation permissions are too broad';
  end if;
  -- Existing trusted organizer fixture. Direct table inserts emulate the bootstrap.
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
    values (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'invite-admin@fandm.edu', jsonb_build_object('full_name', 'Invite Admin', 'grade', 'senior', 'tshirt_size', 'M', 'attendance_commitment', true));
  if not exists (select 1 from public.profiles where id = v_admin and admin = false and registration_status = 'confirmed') then
    raise exception 'Ordinary signup unexpectedly granted organizer access or missed a place';
  end if;
  update public.profiles set admin = true, registration_status = 'organizer' where id = v_admin;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  -- New signup: token hash is consumed once, and no participant place is used.
  perform public.create_organizer_invitation('INVITED@fandm.edu', v_hash1);
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
    values (v_invited, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'invited@fandm.edu', jsonb_build_object('full_name', 'New Organizer', 'organizer_invite_hash', v_hash1));
  if not exists (select 1 from public.profiles where id = v_invited and admin and registration_status = 'organizer' and grade is null)
     or exists (select 1 from auth.users where id = v_invited and raw_user_meta_data ? 'organizer_invite_hash') then
    raise exception 'New invitee was not created directly as a private organizer';
  end if;
  begin
    insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
      values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'reused@fandm.edu', jsonb_build_object('full_name', 'Reused Invite', 'organizer_invite_hash', v_hash1));
    raise exception 'Reused invitation succeeded';
  exception when others then
    if sqlerrm = 'Reused invitation succeeded' then raise; end if;
  end;

  perform public.create_organizer_invitation('bad@fandm.edu', v_hash2);
  begin
    insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
      values (v_bad, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'wrong@fandm.edu', jsonb_build_object('full_name', 'Wrong Address', 'organizer_invite_hash', v_hash2));
    raise exception 'Email mismatch succeeded';
  exception when others then
    if sqlerrm = 'Email mismatch succeeded' then raise; end if;
  end;
  select id into v_id from public.organizer_invitations where token_hash = decode(v_hash2, 'hex');
  perform public.revoke_organizer_invitation(v_id);
  if not exists (select 1 from public.organizer_invitations where id = v_id and revoked_at is not null and used_at is null) then
    raise exception 'Revocation failed';
  end if;
  perform public.create_organizer_invitation('confirmed-invite@fandm.edu', v_hash3);
  update public.organizer_invitations set expires_at = clock_timestamp() - interval '1 second' where token_hash = decode(v_hash3, 'hex');
  perform public.create_organizer_invitation('confirmed-invite@fandm.edu', v_hash4);
  select id into v_id from public.organizer_invitations where token_hash = decode(v_hash4, 'hex');
  perform public.revoke_organizer_invitation(v_id);

  -- Fill the remaining seats, then queue two people in signup order.
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
    values (v_confirmed, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'confirmed-invite@fandm.edu', jsonb_build_object('full_name', 'Confirmed Person', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true));
  for n in 1..49 loop
    insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
      values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'seat-' || n || '-invite@fandm.edu', jsonb_build_object('full_name', 'Seat Person', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true))
      returning id into v_id;
    if n = 1 then v_teammate := v_id; end if;
  end loop;
  insert into public.teams (name, code, created_by)
    values ('Invited Creator Team', 'A11CE0', v_confirmed) returning id into v_team;
  insert into public.team_members (team_id, user_id)
    values (v_team, v_confirmed), (v_team, v_teammate);
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
    values (v_wait1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'wait-one-invite@fandm.edu', jsonb_build_object('full_name', 'First Waitlisted', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true));
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
    values (v_wait2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'wait-two-invite@fandm.edu', jsonb_build_object('full_name', 'Second Waitlisted', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true));
  if (select count(*) from public.profiles where registration_status = 'confirmed') <> 50 then
    raise exception 'Seat cap failed before promotion';
  end if;
  perform set_config('request.jwt.claim.sub', v_confirmed::text, true);
  begin
    perform public.accept_organizer_invitation(v_hash3);
    raise exception 'Expired invitation succeeded';
  exception when others then
    if sqlerrm = 'Expired invitation succeeded' then raise; end if;
  end;
  begin
    perform public.accept_organizer_invitation(v_hash4);
    raise exception 'Revoked invitation succeeded';
  exception when others then
    if sqlerrm = 'Revoked invitation succeeded' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', v_confirmed::text, true);
  begin
    perform public.create_organizer_invitation('unauthorized@fandm.edu', v_hash5);
    raise exception 'Participant created invitation';
  exception when others then
    if sqlerrm = 'Participant created invitation' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.create_organizer_invitation('confirmed-invite@fandm.edu', v_hash5);
  perform set_config('request.jwt.claim.sub', v_confirmed::text, true);
  v_promoted := public.accept_organizer_invitation(v_hash5);
  if v_promoted <> 'wait-one-invite@fandm.edu'
     or (select count(*) from public.profiles where registration_status = 'confirmed') <> 50
     or not exists (select 1 from public.profiles where id = v_wait1 and registration_status = 'confirmed')
     or not exists (select 1 from public.profiles where id = v_wait2 and registration_status = 'waitlisted')
     or exists (select 1 from public.team_members where user_id = v_confirmed)
     or (select created_by from public.teams where id = v_team) is distinct from v_teammate then
    raise exception 'Organizer conversion did not restore the seat and transfer team membership';
  end if;
  begin
    perform public.accept_organizer_invitation(v_hash5);
    raise exception 'Used invitation succeeded';
  exception when others then
    if sqlerrm = 'Used invitation succeeded' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.create_organizer_invitation('wait-two-invite@fandm.edu', v_hash6);
  perform set_config('request.jwt.claim.sub', v_wait2::text, true);
  perform public.accept_organizer_invitation(v_hash6);
  if (select count(*) from public.profiles where registration_status = 'confirmed') <> 50
     or not exists (select 1 from public.profiles where id = v_wait2 and admin and registration_status = 'organizer') then
    raise exception 'Waitlisted acceptance changed confirmed capacity';
  end if;
  delete from auth.users where id = v_invited;
  if exists (select 1 from public.profiles where id = v_invited)
     or not exists (select 1 from public.organizer_invitations
       where token_hash = decode(v_hash1, 'hex') and used_by is null) then
    raise exception 'Used invitation blocked account deletion';
  end if;
  delete from auth.users where id = v_admin;
  if exists (select 1 from public.profiles where id = v_admin)
     or not exists (select 1 from public.organizer_invitations
       where token_hash = decode(v_hash1, 'hex') and invited_by is null) then
    raise exception 'Created invitation blocked account deletion';
  end if;
  raise notice 'Organizer invitation regression checks passed';
end;
$$;
rollback;
