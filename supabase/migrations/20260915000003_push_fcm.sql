-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Migration 4 : push FCM sur notification
--
-- Prérequis (voir README/consignes) :
--   1. Extension pg_net activée
--   2. Clé service_role stockée dans le Vault sous 'service_role_key'
--   3. Edge Function « push-notify » déployée + secret
--      GOOGLE_SERVICE_ACCOUNT_JSON configuré
-- ═══════════════════════════════════════════════════════════

-- 1. Extension réseau (idempotent)
create extension if not exists pg_net;

-- 2. Trigger : chaque notification insérée déclenche un push
create or replace function public.push_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name = 'service_role_key'
  limit 1;

  if v_key is null then
    raise notice 'push_notification: secret service_role_key introuvable — push ignoré.';
    return new;
  end if;

  perform net.http_post(
    url := 'https://rmhftiafvboelygsundz.supabase.co/functions/v1/push-notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := jsonb_build_object('notification', to_jsonb(new)),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;

drop trigger if exists on_notification_push on public.notifications;
create trigger on_notification_push
  after insert on public.notifications
  for each row execute function public.push_notification();

-- Pas d'appel direct via l'API : trigger uniquement.
revoke execute on function public.push_notification() from anon, authenticated;
