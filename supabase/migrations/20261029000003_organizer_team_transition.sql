-- A participant who accepts an organizer invitation must leave their team.
-- Keep a team submission intact if other members remain.
create or replace function public.accept_organizer_invitation(p_hash text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_email text;
  v_previous text;
  v_next uuid;
  v_count integer;
  v_team uuid;
  v_creator uuid;
  v_next_member uuid;
begin
  if v_user is null then raise exception 'Sign in to accept this invitation.'; end if;
  if coalesce(p_hash, '') !~ '^[0-9a-f]{64}$' then raise exception 'Invitation is invalid.'; end if;
  perform pg_advisory_xact_lock(20261107);
  select email, registration_status into v_email, v_previous
    from public.profiles where id = v_user for update;
  if v_email is null or v_previous = 'organizer' then raise exception 'Account cannot accept this invitation.'; end if;
  update public.organizer_invitations set used_at = clock_timestamp(), used_by = v_user
    where token_hash = decode(p_hash, 'hex') and email = v_email
      and used_at is null and revoked_at is null and expires_at > clock_timestamp();
  if not found then raise exception 'Invitation is invalid, expired, or already used for another account.'; end if;

  select team_id into v_team from public.team_members where user_id = v_user;
  if v_team is not null then
    select created_by into v_creator from public.teams where id = v_team for update;
    delete from public.team_members where team_id = v_team and user_id = v_user;
    select user_id into v_next_member from public.team_members
      where team_id = v_team order by joined_at, user_id limit 1;
    if v_next_member is null then
      if exists (select 1 from public.submissions where team_id = v_team) then
        raise exception 'A team submission exists. Ask an organizer for help before accepting this invitation.';
      end if;
      delete from public.teams where id = v_team;
    elsif v_creator = v_user or v_creator is null then
      update public.teams set created_by = v_next_member where id = v_team;
    end if;
  end if;

  update public.profiles set admin = true, registration_status = 'organizer',
    checked_in_at = null, checked_in_by = null where id = v_user;
  if v_previous = 'confirmed' then
    select count(*) into v_count from public.profiles where registration_status = 'confirmed';
  end if;
  if v_previous = 'confirmed' and v_count < 50 then
    select id into v_next from public.profiles
      where registration_status = 'waitlisted' and admin = false
      order by assigned_at, registered_at, id limit 1 for update;
    if v_next is not null then
      update public.profiles set registration_status = 'confirmed' where id = v_next;
    end if;
  end if;
  return (select email from public.profiles where id = v_next);
end;
$$;

revoke all on function public.accept_organizer_invitation(text) from public, anon, authenticated;
grant execute on function public.accept_organizer_invitation(text) to authenticated;

-- Repair organizer accounts that were promoted before this function changed.
-- Keep a team with a submission so its project record is not cascaded away.
do $$
declare
  v_member record;
  v_creator uuid;
  v_next_member uuid;
begin
  for v_member in
    select m.team_id, m.user_id
    from public.team_members m
    join public.profiles p on p.id = m.user_id
    where p.admin = true
    order by m.team_id, m.user_id
  loop
    select created_by into v_creator from public.teams
      where id = v_member.team_id for update;
    delete from public.team_members
      where team_id = v_member.team_id and user_id = v_member.user_id;
    select user_id into v_next_member from public.team_members
      where team_id = v_member.team_id order by joined_at, user_id limit 1;
    if v_next_member is null then
      if exists (select 1 from public.submissions where team_id = v_member.team_id) then
        update public.teams set created_by = null where id = v_member.team_id;
        raise warning 'Team % has a submission but no participant members after organizer cleanup', v_member.team_id;
      else
        delete from public.teams where id = v_member.team_id;
      end if;
    elsif v_creator = v_member.user_id or v_creator is null then
      update public.teams set created_by = v_next_member where id = v_member.team_id;
    end if;
  end loop;
end;
$$;
