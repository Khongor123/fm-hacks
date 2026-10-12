-- Apply after 20261011_dashboard_teams.sql. All event times below are fixed Eastern instants.
-- The offset is private and zero in production. A separate test project can
-- move its event clock without changing production deadlines or user clocks.
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;
create table if not exists app_private.event_clock_offset (
  singleton boolean primary key default true check (singleton),
  preview_enabled boolean not null default false,
  offset interval not null default interval '0 seconds',
  check (preview_enabled or offset = interval '0 seconds')
);
revoke all on app_private.event_clock_offset from public, anon, authenticated;
insert into app_private.event_clock_offset (singleton)
values (true) on conflict (singleton) do nothing;

create or replace function public.event_now()
returns timestamptz language sql volatile security definer set search_path = '' as $$
  select clock_timestamp() + case when preview_enabled then offset else interval '0 seconds' end
  from app_private.event_clock_offset where singleton = true;
$$;
revoke all on function public.event_now() from public, anon, authenticated;
grant execute on function public.event_now() to authenticated;

alter table public.profiles
  add column if not exists checked_in_at timestamptz,
  add column if not exists checked_in_by uuid references public.profiles(id) on delete set null;

create or replace function public.set_check_in(p_user_id uuid, p_arrived boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.current_user_is_admin() then raise exception 'Organizer access required.'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id and registration_status = 'confirmed' and admin = false) then
    raise exception 'Only confirmed participants can be checked in.';
  end if;
  update public.profiles set
    checked_in_at = case when p_arrived then public.event_now() else null end,
    checked_in_by = case when p_arrived then auth.uid() else null end
  where id = p_user_id;
end; $$;
revoke all on function public.set_check_in(uuid, boolean) from public, anon, authenticated;
grant execute on function public.set_check_in(uuid, boolean) to authenticated;

create table public.submissions (
  id uuid primary key default gen_random_uuid(),
  team_id uuid unique references public.teams(id) on delete cascade,
  solo_user_id uuid unique references public.profiles(id) on delete cascade,
  status text not null default 'draft' check (status in ('draft', 'submitted')),
  title text,
  description text,
  track text check (track in ('AI', 'Social good', 'Creative build')),
  github_url text,
  public_repo_confirmed boolean not null default false,
  ai_level text check (ai_level in ('none', 'assisted', 'substantial')),
  ai_disclosure text,
  slide_path text,
  onsite_confirmed boolean not null default false,
  no_outside_help_confirmed boolean not null default false,
  created_at timestamptz not null default public.event_now(),
  updated_at timestamptz not null default public.event_now(),
  submitted_at timestamptz,
  updated_by uuid references public.profiles(id) on delete set null,
  check (num_nonnulls(team_id, solo_user_id) = 1)
);
create index submissions_track_idx on public.submissions (track, status);
alter table public.submissions enable row level security;
revoke all on public.submissions from public, anon, authenticated;

create or replace function public.can_read_submission(p_team_id uuid, p_solo_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.current_user_is_admin() or
    (p_solo_user_id = auth.uid()) or
    exists (select 1 from public.team_members where team_id = p_team_id and user_id = auth.uid());
$$;
revoke all on function public.can_read_submission(uuid,uuid) from public, anon, authenticated;
grant execute on function public.can_read_submission(uuid,uuid) to authenticated;
create policy "Members and organizers read submissions" on public.submissions
  for select to authenticated using (public.can_read_submission(team_id, solo_user_id));
grant select on public.submissions to authenticated;

-- Path format: team/<team UUID>/<random UUID>.<extension> or solo/<user UUID>/<random UUID>.<extension>.
create or replace function public.slide_scope(p_name text)
returns text language sql immutable set search_path = '' as $$
  select case when p_name ~ '^(team|solo)/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pptx|key|pdf)$'
    then split_part(p_name, '/', 1) else null end;
$$;
create or replace function public.can_read_slide(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare v_scope text := public.slide_scope(p_name); v_id uuid;
begin
  if v_scope is null then return false; end if;
  v_id := split_part(p_name, '/', 2)::uuid;
  return public.current_user_is_admin() or
    (v_scope = 'solo' and v_id = auth.uid()) or
    (v_scope = 'team' and exists (select 1 from public.team_members where team_id = v_id and user_id = auth.uid()));
end; $$;
create or replace function public.can_write_slide(p_name text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_scope text := public.slide_scope(p_name); v_id uuid;
begin
  if v_scope is null or public.event_now() < timestamptz '2026-11-07 10:00:00-05'
    or public.event_now() >= timestamptz '2026-11-08 10:00:00-05' then return false; end if;
  v_id := split_part(p_name, '/', 2)::uuid;
  if not exists (select 1 from public.profiles where id = auth.uid() and registration_status = 'confirmed' and admin = false and checked_in_at is not null) then return false; end if;
  if v_scope = 'solo' then
    return v_id = auth.uid() and not exists (select 1 from public.team_members where user_id = auth.uid());
  end if;
  return exists (select 1 from public.team_members where team_id = v_id and user_id = auth.uid());
end; $$;
create or replace function public.can_delete_slide(p_name text)
returns boolean language sql volatile security definer set search_path = '' as $$
  select public.can_read_slide(p_name) and not exists (
    select 1 from public.submissions where slide_path = p_name
  );
$$;
revoke all on function public.slide_scope(text), public.can_read_slide(text), public.can_write_slide(text), public.can_delete_slide(text) from public, anon, authenticated;
grant execute on function public.slide_scope(text), public.can_read_slide(text), public.can_write_slide(text), public.can_delete_slide(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit)
values ('submission-slides', 'submission-slides', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = 10485760;

create policy "Authorized slide downloads" on storage.objects for select to authenticated
  using (bucket_id = 'submission-slides' and public.can_read_slide(name));
create policy "Checked-in slide uploads" on storage.objects for insert to authenticated
  with check (bucket_id = 'submission-slides' and public.can_write_slide(name));
create policy "Remove unused slides" on storage.objects for delete to authenticated
  using (bucket_id = 'submission-slides' and public.can_delete_slide(name));

create or replace function public.get_my_submission()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_team_id uuid; v_result jsonb;
begin
  select team_id into v_team_id from public.team_members where user_id = auth.uid();
  select to_jsonb(s) into v_result from public.submissions s
  where (v_team_id is not null and s.team_id = v_team_id)
     or (v_team_id is null and s.solo_user_id = auth.uid());
  return v_result;
end; $$;
revoke all on function public.get_my_submission() from public, anon, authenticated;
grant execute on function public.get_my_submission() to authenticated;

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
  if p_track is not null and p_track not in ('AI','Social good','Creative build') then raise exception 'Choose a valid track.'; end if;
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

-- After the deadline, only the repository URL can change. Other fields and slides stay locked.
create or replace function public.update_submission_repo(p_github_url text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_team uuid; v_url text := btrim(coalesce(p_github_url,''));
begin
  if public.event_now() < timestamptz '2026-11-08 10:00:00-05' then raise exception 'Use the submission form before the deadline.'; end if;
  if v_url !~* '^https://github\.com/[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]+(\.git)?/?$' then
    raise exception 'Enter a GitHub repository URL.';
  end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and registration_status = 'confirmed' and checked_in_at is not null and admin = false) then
    raise exception 'Check in with an organizer before updating the link.';
  end if;
  select team_id into v_team from public.team_members where user_id = auth.uid();
  update public.submissions set github_url = v_url, updated_at = public.event_now(), updated_by = auth.uid()
    where (v_team is not null and team_id = v_team) or (v_team is null and solo_user_id = auth.uid());
  if not found then raise exception 'No submission was found.'; end if;
end; $$;
revoke all on function public.update_submission_repo(text) from public, anon, authenticated;
grant execute on function public.update_submission_repo(text) to authenticated;

create or replace function public.get_organizer_submissions()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_result jsonb;
begin
  if not public.current_user_is_admin() then raise exception 'Organizer access required.'; end if;
  select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object(
    'team_name', t.name,
    'members', coalesce((select jsonb_agg(jsonb_build_object('name',p.full_name,'checked_in_at',p.checked_in_at))
      from public.team_members m join public.profiles p on p.id=m.user_id where m.team_id=s.team_id),
      (select jsonb_agg(jsonb_build_object('name',p.full_name,'checked_in_at',p.checked_in_at))
        from public.profiles p where p.id=s.solo_user_id))
  ) order by s.track nulls last, s.updated_at desc), '[]'::jsonb) into v_result
  from public.submissions s left join public.teams t on t.id=s.team_id;
  return v_result;
end; $$;
revoke all on function public.get_organizer_submissions() from public, anon, authenticated;
grant execute on function public.get_organizer_submissions() to authenticated;
