-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Migration 10 : persistance des événements caméras
--
-- Complète les tables créées par l'utilisateur (camera_events,
-- camera_event_subscriptions) :
--   1. RLS + policies tenant (lecture = can_access_site uniquement)
--   2. Index temps réel (site + horodatage) pour l'UI et Realtime
--   3. Nettoyage automatique : purge des événements > 7 jours
--      (une caméra active = des milliers de lignes/jour, même
--      dédupliquée côté app)
--   4. GRANT explicites (Data API moderne)
-- ═══════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────
-- 1. RLS — isolation multi-clients
-- ───────────────────────────────────────────────────────────
alter table public.camera_events enable row level security;
alter table public.camera_event_subscriptions enable row level security;

-- Événements : lisibles par les utilisateurs du site (client
-- propriétaire OU technicien — globale via migration 9). Écriture
-- réservée aux membres du site (l'app du technicien y insère via
-- les pollers ONVIF, avec son JWT).
drop policy if exists "camera_events_select" on public.camera_events;
create policy "camera_events_select" on public.camera_events
  for select to authenticated
  using ( public.can_access_site(site_id) );

drop policy if exists "camera_events_insert" on public.camera_events;
create policy "camera_events_insert" on public.camera_events
  for insert to authenticated
  with check ( public.can_access_site(site_id) );

-- Souscriptions : internes à l'app (état des pollers) — mêmes règles.
drop policy if exists "camera_event_subs_select" on public.camera_event_subscriptions;
create policy "camera_event_subs_select" on public.camera_event_subscriptions
  for select to authenticated
  using ( public.can_access_site(
    (select site_id from public.equipment e where e.id = equipment_id)
  ) );

drop policy if exists "camera_event_subs_write" on public.camera_event_subscriptions;
create policy "camera_event_subs_write" on public.camera_event_subscriptions
  for insert to authenticated
  with check ( public.can_access_site(
    (select site_id from public.equipment e where e.id = equipment_id)
  ) );

-- ───────────────────────────────────────────────────────────
-- 2. Index — UI (chronologie par site) + Realtime (filtre site)
-- ───────────────────────────────────────────────────────────
create index if not exists camera_events_site_time_idx
  on public.camera_events (site_id, event_time desc);

create index if not exists camera_events_equipment_idx
  on public.camera_events (equipment_id, event_time desc);

-- ───────────────────────────────────────────────────────────
-- 3. Purge automatique : événements de plus de 7 jours
--    (pg_cron si l'extension est disponible, sinon la requête est
--    fournie pour un planificateur externe)
-- ───────────────────────────────────────────────────────────
-- Variante pg_cron (décommenter si activé sur le projet) :
--
-- create extension if not exists pg_cron;
-- select cron.schedule(
--   'purge_camera_events',
--   '0 3 * * *',  -- tous les jours à 03:00 UTC
--   $job$
--     delete from public.camera_events
--     where event_time < now() - interval '7 days'
--       and topic not in ('intrusion', 'tamper');  -- garder les preuves
--   $job$
-- );

-- Requête de purge manuelle / test :
delete from public.camera_events
where event_time < now() - interval '7 days'
  and topic not in ('intrusion', 'tamper');  -- garder les preuves

-- ───────────────────────────────────────────────────────────
-- 4. Realtime — diffuser camera_events aux apps connectées
--    (l'app technique écrit, les apps clients reçoivent en push —
--    plus élégant que du polling côté client)
-- ───────────────────────────────────────────────────────────
do $$
begin
  alter publication supabase_realtime add table public.camera_events;
exception
  when duplicate_object then
    null; -- déjà dans la publication
end $$;

-- GRANT explicites (les nouvelles tables ne sont plus exposées
-- automatiquement à la Data API).
grant select, insert on public.camera_events to authenticated;
grant select, insert, update, delete
  on public.camera_event_subscriptions to authenticated;
