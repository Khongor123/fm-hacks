-- Shift the event schedule and reopen registration through November 6 at 11:59 p.m. Eastern.
-- Apply after 20261105000000_open_teams_and_video_submissions.sql.
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
    if clock_timestamp() >= timestamptz '2026-11-07 00:00:00-05' then raise exception 'Registration is closed'; end if;
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

create or replace function public.can_write_slide(p_name text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_scope text := public.slide_scope(p_name); v_id uuid;
begin
  if v_scope is null or public.event_now() < timestamptz '2026-11-07 11:00:00-05'
    or public.event_now() >= timestamptz '2026-11-08 11:00:00-05' then return false; end if;
  v_id := split_part(p_name, '/', 2)::uuid;
  if not exists (select 1 from public.profiles where id = auth.uid() and registration_status = 'confirmed' and admin = false and checked_in_at is not null) then return false; end if;
  if v_scope = 'solo' then
    return v_id = auth.uid() and not exists (select 1 from public.team_members where user_id = auth.uid());
  end if;
  return exists (select 1 from public.team_members where team_id = v_id and user_id = auth.uid());
end; $$;
create or replace function public.save_submission(
  p_title text, p_description text, p_track text, p_github_url text,
  p_public_repo_confirmed boolean, p_ai_level text, p_ai_disclosure text,
  p_slide_path text, p_submit boolean, p_onsite_confirmed boolean,
  p_no_outside_help_confirmed boolean, p_expected_updated_at timestamptz,
  p_repo_created_after_start_confirmed boolean, p_presentation_format text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_team uuid; v_scope text; v_id uuid; v_existing public.submissions%rowtype;
  v_title text := nullif(btrim(coalesce(p_title,'')), '');
  v_description text := nullif(btrim(coalesce(p_description,'')), '');
  v_url text := nullif(btrim(coalesce(p_github_url,'')), '');
  v_ai text := nullif(btrim(coalesce(p_ai_disclosure,'')), '');
  v_slide text := nullif(p_slide_path, '');
  v_extension text := lower(split_part(v_slide, '.', 2));
  v_now timestamptz := public.event_now(); v_size bigint; v_created_id uuid;
begin
  if v_now < timestamptz '2026-11-07 11:00:00-05' or v_now >= timestamptz '2026-11-08 11:00:00-05' then
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
    if v_extension not in ('pdf','pptx','key','mp4') or v_size is null or v_size < 1
      or (v_extension = 'mp4' and v_size > 52428800)
      or (v_extension <> 'mp4' and v_size > 10485760) then
      raise exception 'Presentation file must be slides of 10 MB or less or an MP4 of 50 MB or less.';
    end if;
  end if;
  if p_presentation_format is not null and p_presentation_format not in ('live','video') then
    raise exception 'Choose a valid presentation format.';
  end if;
  if v_slide is not null and p_presentation_format is not null and
    ((p_presentation_format = 'video') is distinct from (v_extension = 'mp4')) then
    raise exception 'Upload an MP4 for a video demo, or slides for a live presentation.';
  end if;
  if p_submit and (v_title is null or v_description is null or p_track is null or v_url is null
    or not coalesce(p_public_repo_confirmed,false) or not coalesce(p_repo_created_after_start_confirmed,false)
    or p_presentation_format is null or p_ai_level is null or v_ai is null or v_slide is null
    or not coalesce(p_onsite_confirmed,false) or not coalesce(p_no_outside_help_confirmed,false)) then
    raise exception 'Complete every field, upload presentation slides or an MP4 video, and confirm the rules before submitting.';
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
  if public.event_now() >= timestamptz '2026-11-08 11:00:00-05' then
    raise exception 'The submission window is closed.';
  end if;
  update public.submissions set
    status = case when p_submit then 'submitted' else 'draft' end,
    title = v_title, description = v_description, track = p_track, github_url = v_url,
    public_repo_confirmed = coalesce(p_public_repo_confirmed,false),
    repo_created_after_start_confirmed = coalesce(p_repo_created_after_start_confirmed,false),
    presentation_format = p_presentation_format, ai_level = p_ai_level,
    ai_disclosure = v_ai, slide_path = v_slide,
    onsite_confirmed = coalesce(p_onsite_confirmed,false),
    no_outside_help_confirmed = coalesce(p_no_outside_help_confirmed,false),
    updated_at = v_now, updated_by = v_user,
    submitted_at = case when p_submit then v_now else null end
  where id = v_existing.id;
end; $$;

create or replace function public.update_submission_repo(p_github_url text, p_repo_created_after_start_confirmed boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_team uuid; v_url text := btrim(coalesce(p_github_url,''));
begin
  if public.event_now() < timestamptz '2026-11-08 11:00:00-05' then raise exception 'Use the submission form before the deadline.'; end if;
  if v_url !~* '^https://github\.com/[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]+(\.git)?/?$' then
    raise exception 'Enter a GitHub repository URL.';
  end if;
  if not coalesce(p_repo_created_after_start_confirmed,false) then
    raise exception 'Confirm the repository was created after 11:00 a.m. ET on November 7.';
  end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and registration_status = 'confirmed' and checked_in_at is not null and admin = false) then
    raise exception 'Check in with an organizer before updating the link.';
  end if;
  select team_id into v_team from public.team_members where user_id = auth.uid();
  update public.submissions set github_url = v_url, repo_created_after_start_confirmed = true, updated_at = public.event_now(), updated_by = auth.uid()
    where (v_team is not null and team_id = v_team) or (v_team is null and solo_user_id = auth.uid());
  if not found then raise exception 'No submission was found.'; end if;
end; $$;
commit;
