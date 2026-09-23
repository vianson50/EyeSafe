-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Migration 11 : GRANTS Data API (changement 30 oct.)
--
-- À partir du 30 octobre 2025, Supabase n'expose PLUS les nouvelles
-- tables à l'API Data sans GRANT explicite. Cette migration
-- rattrape les tables créées avant cette date SANS grant complet,
-- et ajoute les GRANTS pour tous les rôles.
--
-- ⚠️ Idempotent — exécutable sans erreur même si déjà partiellement
-- appliqué.
-- ═══════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────
-- Tables métier (lecture = authenticated, RLS contrôle l'accès)
-- ───────────────────────────────────────────────────────────

-- notifications (créée migration 1, SANS grant)
grant select, insert, update, delete
  on public.notifications to authenticated;
grant select
  on public.notifications to anon;

-- Toutes les tables métier : s'assurer que authenticated a les droits
-- (les policies RLS contrôlent QUI voit QUOI — le GRANT ouvre la porte,
-- la RLS filtre)

grant select, insert, update, delete
  on public.sites to authenticated;
grant select
  on public.sites to anon;

grant select, insert, update, delete
  on public.site_technicians to authenticated;

grant select, insert, update, delete
  on public.equipment to authenticated;
grant select
  on public.equipment to anon;

grant select, insert, update
  on public.tickets to authenticated;
grant select
  on public.tickets to anon;

grant select, insert, update
  on public.maintenance_visits to authenticated;
grant select
  on public.maintenance_visits to anon;

grant select, insert
  on public.alerts to authenticated;
grant select
  on public.alerts to anon;

grant select, update
  on public.profiles to authenticated;

-- stream_audit : INSERT uniquement (journalisation), SELECT interdit
-- via l'app (policy RLS bloque déjà, mais on retire aussi le droit).
grant insert
  on public.stream_audit to authenticated;

-- camera_events / camera_event_subscriptions (migration 10 — déjà
-- partiellement couverts, on complète)
grant select, insert, update, delete
  on public.camera_events to authenticated;
grant select
  on public.camera_events to anon;

grant select, insert, update, delete
  on public.camera_event_subscriptions to authenticated;

-- ───────────────────────────────────────────────────────────
-- Fonctions RPC (execution)
-- ───────────────────────────────────────────────────────────
grant execute on function public.get_stream_url(uuid) to authenticated;
grant execute on function public.can_control_ptz(uuid) to authenticated;
grant execute on function public.is_technician() to authenticated;
