-- Remove draft saving and extra attestations while retaining public-repository confirmation.
-- Apply after 20261106000000_shift_event_schedule.sql, before deploying the updated form.
begin;

-- Legacy confirmation parameters remain in this signature for already-open clients.
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
  if not coalesce(p_submit,false) then raise exception 'Submit a complete project; drafts are no longer supported.'; end if;
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
  if v_title is null or v_description is null or p_track is null or v_url is null
    or not coalesce(p_public_repo_confirmed,false)
    or p_presentation_format is null or p_ai_level is null or v_ai is null or v_slide is null then
    raise exception 'Complete every field, upload presentation slides or an MP4 video, and confirm the repository is public before submitting.';
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
    status = 'submitted',
    title = v_title, description = v_description, track = p_track, github_url = v_url,
    public_repo_confirmed = coalesce(p_public_repo_confirmed,false),
    repo_created_after_start_confirmed = false,
    presentation_format = p_presentation_format, ai_level = p_ai_level,
    ai_disclosure = v_ai, slide_path = v_slide,
    onsite_confirmed = false,
    no_outside_help_confirmed = false,
    updated_at = v_now, updated_by = v_user,
    submitted_at = v_now
  where id = v_existing.id;
end; $$;

revoke all on function public.save_submission(text,text,text,text,boolean,text,text,text,boolean,boolean,boolean,timestamptz,boolean,text) from public, anon, authenticated;
grant execute on function public.save_submission(text,text,text,text,boolean,text,text,text,boolean,boolean,boolean,timestamptz,boolean,text) to authenticated;

create or replace function public.update_submission_repo_public(p_github_url text, p_public_repo_confirmed boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_team uuid; v_url text := btrim(coalesce(p_github_url,''));
begin
  if public.event_now() < timestamptz '2026-11-08 11:00:00-05' then raise exception 'Use the submission form before the deadline.'; end if;
  if v_url !~* '^https://github\.com/[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]+(\.git)?/?$' then
    raise exception 'Enter a GitHub repository URL.';
  end if;
  if not coalesce(p_public_repo_confirmed,false) then
    raise exception 'Confirm that the repository is public.';
  end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and registration_status = 'confirmed' and checked_in_at is not null and admin = false) then
    raise exception 'Check in with an organizer before updating the link.';
  end if;
  select team_id into v_team from public.team_members where user_id = auth.uid();
  update public.submissions set github_url = v_url, public_repo_confirmed = true,
    repo_created_after_start_confirmed = false, updated_at = public.event_now(), updated_by = auth.uid()
    where (v_team is not null and team_id = v_team) or (v_team is null and solo_user_id = auth.uid());
  if not found then raise exception 'No submission was found.'; end if;
end; $$;
revoke all on function public.update_submission_repo_public(text,boolean) from public, anon, authenticated;
grant execute on function public.update_submission_repo_public(text,boolean) to authenticated;

-- The former late-link RPC accepted a creation-time attestation instead of a public-repo confirmation.
drop function if exists public.update_submission_repo(text,boolean);

commit;
