-- Organizers and judges see submitted projects only. Participants keep access
-- to their own drafts and slides while editing them.

drop policy if exists "Members and organizers read submissions" on public.submissions;
drop function if exists public.can_read_submission(uuid, uuid);

create or replace function public.can_read_submission(p_team_id uuid, p_solo_user_id uuid, p_status text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case when public.current_user_is_admin() then p_status = 'submitted'
    else (p_solo_user_id = auth.uid()) or exists (
      select 1 from public.team_members
      where team_id = p_team_id and user_id = auth.uid()
    ) end;
$$;
revoke all on function public.can_read_submission(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.can_read_submission(uuid,uuid,text) to authenticated;
create policy "Members and organizers read submissions" on public.submissions
  for select to authenticated using (public.can_read_submission(team_id, solo_user_id, status));

create or replace function public.can_read_slide(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_scope text := public.slide_scope(p_name);
  v_id uuid;
begin
  if v_scope is null then return false; end if;
  if public.current_user_is_admin() then
    return exists (
      select 1 from public.submissions
      where status = 'submitted' and slide_path = p_name
    );
  end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and admin = false) then
    return false;
  end if;
  v_id := split_part(p_name, '/', 2)::uuid;
  return (v_scope = 'solo' and v_id = auth.uid()) or
    (v_scope = 'team' and exists (
      select 1 from public.team_members where team_id = v_id and user_id = auth.uid()
    ));
end; $$;
revoke all on function public.can_read_slide(text) from public, anon, authenticated;
grant execute on function public.can_read_slide(text) to authenticated;

create or replace function public.get_my_submission()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_team_id uuid;
  v_result jsonb;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and admin = false and registration_status = 'confirmed'
  ) then return null; end if;
  select team_id into v_team_id from public.team_members where user_id = auth.uid();
  select to_jsonb(s) into v_result from public.submissions s
  where (v_team_id is not null and s.team_id = v_team_id)
     or (v_team_id is null and s.solo_user_id = auth.uid());
  return v_result;
end; $$;
revoke all on function public.get_my_submission() from public, anon, authenticated;
grant execute on function public.get_my_submission() to authenticated;

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
  ) order by s.track, s.updated_at desc), '[]'::jsonb) into v_result
  from public.submissions s left join public.teams t on t.id=s.team_id
  where s.status = 'submitted';
  return v_result;
end; $$;
revoke all on function public.get_organizer_submissions() from public, anon, authenticated;
grant execute on function public.get_organizer_submissions() to authenticated;
