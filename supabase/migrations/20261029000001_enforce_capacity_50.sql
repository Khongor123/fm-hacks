-- Production still had the old 75-place assignment function after the schema
-- baseline skipped its already-existing profiles table. Serialize the repair
-- with signup and keep the earliest 50 student registrations confirmed.
do $repair$
begin
  perform pg_advisory_xact_lock(20261107);

  execute $assignment_function$
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
        set registration_status = case when v_count < 50 then 'confirmed' else 'waitlisted' end,
            assigned_at = clock_timestamp()
        where id = p_user_id and registration_status = 'pending_assignment';
    end;
    $$;
  $assignment_function$;

  execute 'revoke all on function public.assign_registration(uuid) from public, anon, authenticated';

  with ranked as (
    select id, row_number() over (order by registered_at, id) as place
    from public.profiles
    where admin = false and registration_status = 'confirmed'
  )
  update public.profiles p
  set registration_status = 'waitlisted'
  from ranked r
  where p.id = r.id and r.place > 50;
end;
$repair$;

select registration_status, count(*) as students
from public.profiles
where admin = false
group by registration_status
order by registration_status;
