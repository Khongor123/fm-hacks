-- Student directory: expose only name, email, and team status.
-- Organizer profiles and private roster fields stay outside this RPC.
create or replace function public.list_participants()
returns table (full_name text, email text, team_status text)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and admin = false
  ) then
    raise exception 'Student account required.';
  end if;

  return query
    select p.full_name, p.email, coalesce(t.name, 'Solo')
    from public.profiles p
    left join public.team_members m on m.user_id = p.id
    left join public.teams t on t.id = m.team_id
    where p.admin = false
    order by p.full_name, p.email;
end;
$$;

revoke all on function public.list_participants() from public, anon, authenticated;
grant execute on function public.list_participants() to authenticated;
