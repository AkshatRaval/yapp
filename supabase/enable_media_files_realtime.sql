-- Enable Supabase Realtime UPDATE events for media_files.
-- Run once in the Supabase SQL Editor.

alter table public.media_files replica identity full;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'media_files'
  ) then
    alter publication supabase_realtime add table public.media_files;
  end if;
end $$;

