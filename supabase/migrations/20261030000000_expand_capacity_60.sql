-- Expand the confirmed student limit to 60 without demoting anyone.
-- Apply before deploying the 60-place website copy.
begin;

create or replace function public.assign_registration(p_user_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  perform pg_advisory_xact_lock(20261107);
  select count(*) into v_count from public.profiles
    where registration_status = 'confirmed';
  update public.profiles
    set registration_status = case when v_count < 60 then 'confirmed' else 'waitlisted' end,
        assigned_at = clock_timestamp()
    where id = p_user_id and registration_status = 'pending_assignment';
end;
$$;

revoke all on function public.assign_registration(uuid) from public, anon, authenticated;

-- Delete only the signed-in Auth account. The profile and related rows cascade.
-- Use the seat-assignment lock so a confirmed student's place is restored once.
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_status text;
  v_admin boolean;
  v_team uuid;
  v_team_creator uuid;
  v_next_member uuid;
  v_waitlisted uuid;
  v_count integer;
begin
  if v_user is null then raise exception 'Sign in to delete your account.'; end if;
  perform pg_advisory_xact_lock(20261107);
  select registration_status, admin into v_status, v_admin
    from public.profiles where id = v_user for update;
  if not found then raise exception 'Account profile not found.'; end if;

  select team_id into v_team from public.team_members where user_id = v_user;
  if v_team is not null then
    select created_by into v_team_creator from public.teams where id = v_team for update;
  end if;

  delete from auth.users where id = v_user;
  if not found then raise exception 'Account could not be deleted.'; end if;

  if v_team is not null then
    select user_id into v_next_member from public.team_members
      where team_id = v_team order by joined_at, user_id limit 1;
    if v_next_member is null then
      delete from public.teams where id = v_team;
    elsif v_team_creator = v_user or v_team_creator is null then
      update public.teams set created_by = v_next_member where id = v_team;
    end if;
  end if;

  if not v_admin and v_status = 'confirmed' then
    select count(*) into v_count from public.profiles
      where registration_status = 'confirmed';
    if v_count < 60 then
      select id into v_waitlisted from public.profiles
        where registration_status = 'waitlisted' and admin = false
        order by assigned_at, registered_at, id limit 1 for update;
      if v_waitlisted is not null then
        update public.profiles set registration_status = 'confirmed'
          where id = v_waitlisted;
      end if;
    end if;
  end if;
end;
$$;

revoke all on function public.delete_my_account() from public, anon, authenticated;
grant execute on function public.delete_my_account() to authenticated;

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
  if v_previous = 'confirmed' and v_count < 60 then
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

-- Fill newly available places in the same queue order used by other promotions.
do $capacity$
declare
  v_count integer;
  v_next uuid;
begin
  perform pg_advisory_xact_lock(20261107);
  select count(*) into v_count from public.profiles
    where registration_status = 'confirmed' and admin = false;
  if v_count > 60 then
    raise warning 'There are % confirmed students, above the new limit of 60; review manually.', v_count;
  end if;
  while v_count < 60 loop
    select id into v_next from public.profiles
      where registration_status = 'waitlisted' and admin = false
      order by assigned_at, registered_at, id limit 1 for update;
    exit when v_next is null;
    update public.profiles set registration_status = 'confirmed' where id = v_next;
    v_count := v_count + 1;
  end loop;
end;
$capacity$;

commit;
