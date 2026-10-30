-- Production can retain the participant-only auth trigger when the baseline
-- skips an existing profiles table. Restore the invitation-aware signup path.
begin;

alter table public.profiles
  alter column grade drop not null,
  alter column tshirt_size drop not null,
  alter column attendance_committed_at drop not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_participant_fields_check'
  ) then
    alter table public.profiles add constraint profiles_participant_fields_check check (
      (admin = true and registration_status = 'organizer') or
      (admin = false and registration_status <> 'organizer'
        and grade is not null and tshirt_size is not null and attendance_committed_at is not null)
    ) not valid;
  end if;
end;
$$;

create or replace function public.consume_organizer_invitation(
  p_hash text, p_email text, p_user_id uuid
)
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
revoke all on function public.consume_organizer_invitation(text,text,uuid)
  from public, anon, authenticated;

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
    insert into public.profiles (id, email, full_name, admin, registration_status)
      values (new.id, v_email, v_name, true, 'organizer');
    perform public.consume_organizer_invitation(v_hash, v_email, new.id);
    update auth.users
      set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) - 'organizer_invite_hash'
      where id = new.id;
  else
    if clock_timestamp() >= timestamptz '2026-11-04 00:00:00-05' then raise exception 'Registration is closed'; end if;
    if coalesce(new.raw_user_meta_data ->> 'attendance_commitment', '') <> 'true' then
      raise exception 'Attendance commitment is required';
    end if;
    insert into public.profiles (id, email, full_name, grade, tshirt_size, attendance_committed_at)
      values (new.id, v_email, v_name, v_grade, v_size, now());
    perform public.assign_registration(new.id);
  end if;
  return new;
end;
$$;

commit;
