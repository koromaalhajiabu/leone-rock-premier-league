# send-league-alerts

Sends league alerts to every subscribed device. Deployed to the SLFA Supabase project and run every two minutes by pg_cron (job `send-league-alerts`).

- Reads the queue `league_alerts`, which the database fills when a fixture is added, a match goes live, a result is approved, or news is published.
- Sends each alert to every row in `push_subscriptions`, and removes subscriptions that the browser has withdrawn.
- Requires the existing `push_vapid_keys` row (id 1).
- Deployed with JWT verification on. The scheduler sends the project's anon key.
