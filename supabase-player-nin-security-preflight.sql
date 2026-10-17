-- Leone Rock Premier League: targeted player NIN security preflight
-- READ ONLY: this script does not alter schema, permissions, or records.
-- Run in the Supabase SQL Editor for the football project before any NIN migration.

-- 1) Confirm club_squad columns and data types.
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'club_squad'
ORDER BY ordinal_position;

-- 2) Check RLS state and table owner.
SELECT c.relname AS table_name,
       pg_get_userbyid(c.relowner) AS table_owner,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'club_squad';

-- 3) List every RLS policy on club_squad, including command, roles, and predicates.
SELECT policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'club_squad'
ORDER BY policyname;

-- 4) Show effective table-level privileges for anon, authenticated, and PUBLIC.
SELECT grantee, privilege_type, is_grantable
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'club_squad'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY grantee, privilege_type;

-- 5) Check column-level grants specifically for player_nin.
SELECT grantee, column_name, privilege_type, is_grantable
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name = 'club_squad'
  AND column_name = 'player_nin'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY grantee, privilege_type;

-- 6) Check whether club_squad is in a Realtime publication.
SELECT p.pubname, c.relname AS table_name
FROM pg_publication p
JOIN pg_publication_rel pr ON pr.prpubid = p.oid
JOIN pg_class c ON c.oid = pr.prrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'club_squad'
ORDER BY p.pubname;

-- 7) Check related role helper functions that exist; no function is executed.
SELECT p.oid::regprocedure AS function_signature,
       p.prosecdef AS security_definer,
       p.proconfig AS function_settings
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('app_role', 'league_current_role', 'has_finance_access')
ORDER BY p.proname, p.oid::regprocedure::text;

-- END: read-only preflight. Do not drop or rename player_nin until a migration
-- has copied and validated existing values and the application is updated.
