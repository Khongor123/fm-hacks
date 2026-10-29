-- Require a track for every new draft save and final submission.
-- Existing drafts with a null track remain in place for participants to edit.
-- The submitted-row constraint validates existing final submissions.
create or replace function public.save_submission(
  p_title text, p_description text, p_track text, p_github_url text,
  p_public_repo_confirmed boolean, p_ai_level text, p_ai_disclosure text,
  p_slide_path text, p_submit boolean, p_onsite_confirmed boolean,
  p_no_outside_help_confirmed boolean, p_expected_updated_at timestamptz
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_team uuid; v_scope text; v_id uuid; v_existing public.submissions%rowtype;
  v_title text := nullif(btrim(coalesce(p_title,'')), '');
  v_description text := nullif(btrim(coalesce(p_description,'')), '');
  v_url text := nullif(btrim(coalesce(p_github_url,'')), '');
  v_ai text := nullif(btrim(coalesce(p_ai_disclosure,'')), '');
  v_slide text := nullif(p_slide_path, '');
  v_now timestamptz := public.event_now(); v_size bigint; v_created_id uuid;
begin
  if v_now < timestamptz '2026-11-07 10:00:00-05' or v_now >= timestamptz '2026-11-08 10:00:00-05' then
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
    if v_size is null or v_size > 10485760 then raise exception 'Slides must be an uploaded file of 10 MB or less.'; end if;
  end if;
  if p_submit and (v_title is null or v_description is null or p_track is null or v_url is null
    or not coalesce(p_public_repo_confirmed,false) or p_ai_level is null or v_ai is null or v_slide is null
    or not coalesce(p_onsite_confirmed,false) or not coalesce(p_no_outside_help_confirmed,false)) then
    raise exception 'Complete every field, upload slides, and confirm the rules before submitting.';
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
  if public.event_now() >= timestamptz '2026-11-08 10:00:00-05' then
    raise exception 'The submission window is closed.';
  end if;
  update public.submissions set
    status = case when p_submit then 'submitted' else 'draft' end,
    title = v_title, description = v_description, track = p_track, github_url = v_url,
    public_repo_confirmed = coalesce(p_public_repo_confirmed,false), ai_level = p_ai_level,
    ai_disclosure = v_ai, slide_path = v_slide,
    onsite_confirmed = coalesce(p_onsite_confirmed,false),
    no_outside_help_confirmed = coalesce(p_no_outside_help_confirmed,false),
    updated_at = v_now, updated_by = v_user,
    submitted_at = case when p_submit then v_now else null end
  where id = v_existing.id;
end; $$;

revoke all on function public.save_submission(text,text,text,text,boolean,text,text,text,boolean,boolean,boolean,timestamptz) from public, anon, authenticated;
grant execute on function public.save_submission(text,text,text,text,boolean,text,text,text,boolean,boolean,boolean,timestamptz) to authenticated;

alter table public.submissions
  add constraint submissions_submitted_track_required
  check (status <> 'submitted' or track is not null);
