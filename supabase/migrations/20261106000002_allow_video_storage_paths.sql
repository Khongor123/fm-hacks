-- Storage access checks use slide_scope for uploads, downloads, and cleanup.
-- Include MP4 files so video demos satisfy the same ownership and check-in rules as slides.
begin;

create or replace function public.slide_scope(p_name text)
returns text language sql immutable set search_path = '' as $$
  select case when p_name ~ '^(team|solo)/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pptx|key|pdf|mp4)$'
    then split_part(p_name, '/', 1) else null end;
$$;
revoke all on function public.slide_scope(text) from public, anon, authenticated;
grant execute on function public.slide_scope(text) to authenticated;

commit;
