-- Leone Rock Premier League: registration/approval preflight (READ ONLY)
-- Run in Supabase SQL Editor BEFORE any registration tests.
-- This script performs SELECTs only. It does not insert, update, delete, or alter data.
-- Project: ticcaervmjdzbprdpxxv

-- 1) Verify the columns available on user_profiles before changing approval code.
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'user_profiles'
ORDER BY ordinal_position;

-- 2) List non-internal triggers attached to auth.users and whether each is enabled.
-- PostgreSQL tgenabled: O = enabled for origin/local sessions; D = disabled;
-- R = replica only; A = always enabled.
SELECT
  t.tgname AS trigger_name,
  CASE t.tgenabled::text
    WHEN 'O' THEN 'enabled (origin)'
    WHEN 'D' THEN 'DISABLED'
    WHEN 'R' THEN 'replica only'
    WHEN 'A' THEN 'always enabled'
    ELSE concat('unknown: ', t.tgenabled::text)
  END AS trigger_status,
  p.proname AS function_name,
  pg_get_functiondef(p.oid) AS function_definition
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE n.nspname = 'auth'
  AND c.relname = 'users'
  AND NOT t.tgisinternal
ORDER BY t.tgname;

-- 3) Check whether the role-request trigger/function exist in the database.
SELECT
  to_regclass('public.role_access_requests') AS role_access_requests_table,
  to_regclass('public.user_profiles') AS user_profiles_table,
  to_regprocedure('public.capture_role_access_request()') AS capture_function,
  to_regprocedure('public.review_role_access_request(uuid,text,text)') AS review_function;

-- 4) Show the profile-creation triggers specifically (if present).
SELECT
  t.tgname AS trigger_name,
  CASE t.tgenabled::text
    WHEN 'O' THEN 'enabled (origin)'
    WHEN 'D' THEN 'DISABLED'
    WHEN 'R' THEN 'replica only'
    WHEN 'A' THEN 'always enabled'
    ELSE 'unknown: ' || t.tgenabled::text
  END AS trigger_status,
  p.proname AS function_name
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE n.nspname = 'auth'
  AND c.relname = 'users'
  AND NOT t.tgisinternal
  AND (
    lower(t.tgname) LIKE '%profile%'
    OR lower(p.proname) LIKE '%profile%'
    OR t.tgname = 'capture_role_access_request_trigger'
    OR p.proname = 'capture_role_access_request'
  )
ORDER BY t.tgname;

-- 5) Current role-request counts. Zero rows is normal until a request is submitted.
SELECT status, requested_role, count(*) AS request_count
FROM public.role_access_requests
GROUP BY status, requested_role
ORDER BY status, requested_role;

-- END: all statements above are read-only.
