-- Removes the developer lock from the database. Run in the Supabase SQL editor.
drop trigger if exists guard_developer_lock on public.user_profiles;
drop function if exists public.guard_developer_lock();
drop function if exists public.set_developer_lock(boolean, text);
drop table if exists public.developer_lock;
