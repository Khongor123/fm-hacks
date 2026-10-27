-- Run on a disposable Supabase project after the submitted-projects migration.
-- Run before public registration closes; all fixture data is rolled back.
begin;
do $$
declare
  v_admin uuid := gen_random_uuid();
  v_draft_owner uuid := gen_random_uuid();
  v_final_owner uuid := gen_random_uuid();
  v_draft_id uuid;
  v_final_id uuid;
  v_draft_path text;
  v_final_path text;
  v_rows jsonb;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
  values
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'submitted-admin@fandm.edu', jsonb_build_object('full_name', 'Submitted Admin', 'grade', 'senior', 'tshirt_size', 'M', 'attendance_commitment', true)),
    (v_draft_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'submitted-draft@fandm.edu', jsonb_build_object('full_name', 'Draft Owner', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true)),
    (v_final_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'submitted-final@fandm.edu', jsonb_build_object('full_name', 'Final Owner', 'grade', 'junior', 'tshirt_size', 'M', 'attendance_commitment', true));
  update public.profiles set admin = true, registration_status = 'organizer' where id = v_admin;
  v_draft_path := format('solo/%s/%s.pdf', v_draft_owner, gen_random_uuid());
  v_final_path := format('solo/%s/%s.pdf', v_final_owner, gen_random_uuid());
  insert into public.submissions (solo_user_id, status, title, track, slide_path)
    values (v_draft_owner, 'draft', 'Private draft', 'AI', v_draft_path) returning id into v_draft_id;
  insert into public.submissions (solo_user_id, status, title, track, slide_path)
    values (v_final_owner, 'submitted', 'Final project', 'AI', v_final_path) returning id into v_final_id;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  v_rows := public.get_organizer_submissions();
  if jsonb_array_length(v_rows) <> 1 or v_rows -> 0 ->> 'id' <> v_final_id::text then
    raise exception 'Organizer submission RPC exposed a draft or omitted the submitted project';
  end if;
  if public.can_read_submission(null, v_draft_owner, 'draft')
     or not public.can_read_submission(null, v_final_owner, 'submitted')
     or public.can_read_slide(v_draft_path)
     or not public.can_read_slide(v_final_path)
     or public.get_my_submission() is not null then
    raise exception 'Organizer direct read or slide access did not hide drafts';
  end if;

  perform set_config('request.jwt.claim.sub', v_draft_owner::text, true);
  if not public.can_read_submission(null, v_draft_owner, 'draft')
     or not public.can_read_slide(v_draft_path)
     or public.get_my_submission() ->> 'id' <> v_draft_id::text then
    raise exception 'Participant lost access to their own draft';
  end if;
  if public.can_read_submission(null, v_final_owner, 'submitted')
     or public.can_read_slide(v_final_path) then
    raise exception 'Participant gained access to another project';
  end if;
  raise notice 'Submitted-project visibility checks passed';
end;
$$;
rollback;
