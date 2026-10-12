-- Read-only smoke check for the separate event-preview Supabase project.
-- Run in SQL Editor after schema.sql and 20261011_event_submissions.sql.
do $$
begin
  if to_regclass('public.profiles') is null or to_regclass('public.teams') is null
    or to_regclass('public.submissions') is null then
    raise exception 'A required public table is missing.';
  end if;
  if to_regclass('app_private.event_clock_offset') is null then
    raise exception 'The private preview clock is missing.';
  end if;
  if not exists (
    select 1 from storage.buckets
    where id = 'submission-slides' and public = false and file_size_limit = 10485760
  ) then
    raise exception 'The private 10 MiB slides bucket is missing or misconfigured.';
  end if;
  if not exists (
    select 1 from app_private.event_clock_offset
    where singleton = true and preview_enabled = false and clock_offset = interval '0 seconds'
  ) then
    raise exception 'The event clock does not have its safe real-time default.';
  end if;
  if not has_function_privilege('authenticated', 'public.event_now()', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.save_submission(text,text,text,text,boolean,text,text,text,boolean,boolean,boolean,timestamptz)', 'EXECUTE') then
    raise exception 'Participant RPC grants are missing.';
  end if;
  if has_schema_privilege('authenticated', 'app_private', 'USAGE')
    or has_table_privilege('authenticated', 'public.submissions', 'INSERT') then
    raise exception 'Private clock or submission table permissions are too broad.';
  end if;
  if (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
      and policyname in ('Authorized slide downloads', 'Checked-in slide uploads', 'Remove unused slides')) <> 3 then
    raise exception 'A slides Storage policy is missing.';
  end if;
  raise notice 'Event preview schema and access checks passed.';
end;
$$;
select public.event_now() as current_event_time;
