-- Leone Rock Premier League: restrict browser reads of player NIN.
-- REVIEW REQUIRED: merge the companion roster UI change (PR #4) before applying.
-- This migration does not delete or move player records and does not change RLS policies.
-- It removes table-level SELECT from authenticated and grants SELECT only on the
-- non-sensitive roster columns required by the current application.
-- Existing INSERT/UPDATE/DELETE grants are intentionally not changed here.

BEGIN;

REVOKE SELECT ON TABLE public.club_squad FROM authenticated;
REVOKE SELECT (player_nin) ON TABLE public.club_squad FROM authenticated;

GRANT SELECT (
  id,
  player_name,
  position,
  status,
  photo_url,
  created_by,
  created_at,
  club_id
) ON TABLE public.club_squad TO authenticated;

COMMIT;

-- After applying, verify:
-- 1) authenticated can SELECT the explicit non-sensitive columns above;
-- 2) authenticated cannot SELECT player_nin;
-- 3) club roster registration, photo update, and delete still work;
-- 4) test as Developer, Super Admin, and a Club Admin using test accounts.
-- Note: PostgreSQL table owners, service_role, and privileged server access may
-- still read NIN. Keep service_role keys out of browser code.
