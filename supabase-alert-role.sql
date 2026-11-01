-- alert_role: queues an email to every active account with the given system role.
-- Used by finance and other alerts (for example trg_alert_finance_recorded).
-- Recorded from the live database so the repo matches what is running.
-- Emails are queued in email_outbox and sent by the send-alerts function.

CREATE OR REPLACE FUNCTION public.alert_role(p_role text, p_subject text, p_body text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO ''
AS $function$
  insert into public.email_outbox (to_email, subject, body)
  select p.email, p_subject, p_body
  from public.user_profiles p
  where p.system_role = p_role and p.status = 'Active' and p.email is not null;
$function$;
