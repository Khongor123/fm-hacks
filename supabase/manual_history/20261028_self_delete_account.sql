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
    if v_count < 50 then
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
