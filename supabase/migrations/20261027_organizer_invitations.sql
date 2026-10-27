-- Apply before deploying the invitation pages. Run once on existing projects.
-- The first organizer remains a trusted account established in Supabase.
create table if not exists public.organizer_invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null check (email = lower(btrim(email)) and email ~ '^[^@[:space:]]+@fandm\.edu$'),
  token_hash bytea not null unique,
  invited_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  used_at timestamptz,
  used_by uuid references public.profiles(id),
  revoked_at timestamptz
);
create index if not exists organizer_invitations_email_idx on public.organizer_invitations (email);
alter table public.organizer_invitations enable row level security;
revoke all on public.organizer_invitations from public, anon, authenticated;

-- Organizer-only RPCs return metadata, never the token hash.
create or replace function public.create_organizer_invitation(p_email text, p_token_hash text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_id uuid;
begin
  if not public.current_user_is_admin() then raise exception 'Organizer access required.'; end if;
  if v_email !~ '^[^@[:space:]]+@fandm\.edu$' then raise exception 'Use an F&M email address.'; end if;
  if coalesce(p_token_hash, '') !~ '^[0-9a-f]{64}$' then raise exception 'Invalid invitation token.'; end if;
  insert into public.organizer_invitations (email, token_hash, invited_by)
    values (v_email, decode(p_token_hash, 'hex'), auth.uid()) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.list_organizer_invitations()
returns table (id uuid, email text, invited_by uuid, created_at timestamptz, expires_at timestamptz, used_at timestamptz, revoked_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  if not public.current_user_is_admin() then raise exception 'Organizer access required.'; end if;
  return query select i.id, i.email, i.invited_by, i.created_at, i.expires_at, i.used_at, i.revoked_at
    from public.organizer_invitations i order by i.created_at desc;
end;
$$;

create or replace function public.revoke_organizer_invitation(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.current_user_is_admin() then raise exception 'Organizer access required.'; end if;
  update public.organizer_invitations set revoked_at = clock_timestamp()
    where id = p_id and used_at is null and revoked_at is null;
  if not found then raise exception 'Invitation is unavailable.'; end if;
end;
$$;

-- Called only from the auth trigger. The SHA-256 digest is passed through Auth
-- metadata and removed from that metadata before the signup transaction commits.
create or replace function public.consume_organizer_invitation(p_hash text, p_email text, p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(p_hash, '') !~ '^[0-9a-f]{64}$' then raise exception 'Invalid invitation.'; end if;
  update public.organizer_invitations
    set used_at = clock_timestamp(), used_by = p_user_id
    where token_hash = decode(p_hash, 'hex') and email = lower(p_email)
      and used_at is null and revoked_at is null and expires_at > clock_timestamp();
  if not found then raise exception 'Invitation is invalid, expired, or already used.'; end if;
end;
$$;
revoke all on function public.consume_organizer_invitation(text,text,uuid) from public, anon, authenticated;

-- Participant fields are required only for participants.
alter table public.profiles alter column grade drop not null;
alter table public.profiles alter column tshirt_size drop not null;
alter table public.profiles alter column attendance_committed_at drop not null;
alter table public.profiles drop constraint if exists profiles_participant_fields_check;
alter table public.profiles add constraint profiles_participant_fields_check check (
  (admin = true and registration_status = 'organizer') or
  (admin = false and registration_status <> 'organizer' and grade is not null and tshirt_size is not null and attendance_committed_at is not null)
) not valid;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(coalesce(new.email, ''));
  v_name text := btrim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  v_hash text := coalesce(new.raw_user_meta_data ->> 'organizer_invite_hash', '');
  v_grade text := coalesce(new.raw_user_meta_data ->> 'grade', '');
  v_size text := coalesce(new.raw_user_meta_data ->> 'tshirt_size', '');
begin
  if v_email !~ '^[^@[:space:]]+@fandm\.edu$' then raise exception 'An F&M email address is required'; end if;
  if char_length(v_name) not between 2 and 120 then raise exception 'Enter a full name'; end if;
  if v_hash <> '' then
    -- Invitation and profile creation share the Auth signup transaction.
    insert into public.profiles (id, email, full_name, admin, registration_status)
      values (new.id, v_email, v_name, true, 'organizer');
    perform public.consume_organizer_invitation(v_hash, v_email, new.id);
    update auth.users set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) - 'organizer_invite_hash'
      where id = new.id;
  else
    if clock_timestamp() >= timestamptz '2026-11-04 00:00:00-05' then raise exception 'Registration is closed'; end if;
    if coalesce(new.raw_user_meta_data ->> 'attendance_commitment', '') <> 'true' then raise exception 'Attendance commitment is required'; end if;
    insert into public.profiles (id, email, full_name, grade, tshirt_size, attendance_committed_at)
      values (new.id, v_email, v_name, v_grade, v_size, now());
    perform public.assign_registration(new.id);
  end if;
  return new;
end;
$$;

-- The caller must be signed in as the account whose email matches the invite.
create or replace function public.accept_organizer_invitation(p_hash text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_email text;
  v_previous text;
  v_next uuid;
  v_count integer;
begin
  if v_user is null then raise exception 'Sign in to accept this invitation.'; end if;
  if coalesce(p_hash, '') !~ '^[0-9a-f]{64}$' then raise exception 'Invitation is invalid.'; end if;
  -- Same lock as assign_registration, including the waitlist replacement.
  perform pg_advisory_xact_lock(20261107);
  select email, registration_status into v_email, v_previous
    from public.profiles where id = v_user for update;
  if v_email is null or v_previous = 'organizer' then raise exception 'Account cannot accept this invitation.'; end if;
  update public.organizer_invitations set used_at = clock_timestamp(), used_by = v_user
    where token_hash = decode(p_hash, 'hex') and email = v_email
      and used_at is null and revoked_at is null and expires_at > clock_timestamp();
  if not found then raise exception 'Invitation is invalid, expired, or already used for another account.'; end if;
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

revoke all on function public.create_organizer_invitation(text,text), public.list_organizer_invitations(),
  public.revoke_organizer_invitation(uuid), public.accept_organizer_invitation(text) from public, anon, authenticated;
grant execute on function public.create_organizer_invitation(text,text), public.list_organizer_invitations(),
  public.revoke_organizer_invitation(uuid), public.accept_organizer_invitation(text) to authenticated;

-- Normalize previously trusted organizers, then fill available places in queue order.
-- Existing confirmed students are never demoted.
do $$
declare
  v_count integer;
  v_person uuid;
begin
  perform pg_advisory_xact_lock(20261107);
  update public.profiles set registration_status = 'organizer', checked_in_at = null, checked_in_by = null
    where admin = true and registration_status <> 'organizer';
  select count(*) into v_count from public.profiles where registration_status = 'confirmed';
  if v_count > 50 then raise warning 'There are % pre-existing confirmed participants; review manually.', v_count; end if;
  while v_count < 50 loop
    select id into v_person from public.profiles where registration_status = 'waitlisted' and admin = false
      order by assigned_at, registered_at, id limit 1;
    exit when v_person is null;
    update public.profiles set registration_status = 'confirmed' where id = v_person;
    v_count := v_count + 1;
  end loop;
end;
$$;
alter table public.profiles validate constraint profiles_participant_fields_check;
