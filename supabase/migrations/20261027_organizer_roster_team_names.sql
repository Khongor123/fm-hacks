-- Organizer-only team names for the registration roster.
-- Team tables remain private; no direct table grants are added.
create or replace function public.get_organizer_roster_teams()
returns table (user_id uuid, team_name text)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.current_user_is_admin() then
    raise exception 'Organizer access required.';
  end if;

  return query
    select member.user_id, team.name
    from public.team_members member
    join public.teams team on team.id = member.team_id;
end;
$$;

revoke all on function public.get_organizer_roster_teams() from public, anon, authenticated;
grant execute on function public.get_organizer_roster_teams() to authenticated;
