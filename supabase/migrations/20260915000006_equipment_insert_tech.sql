-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Migration 7 : connexion des caméras par le technicien
--
-- Le technicien installe/connecte le matériel chez le client :
-- il doit pouvoir créer les équipements (caméras du NVR) sur les
-- sites qui lui sont assignés — pas seulement le propriétaire.
-- ═══════════════════════════════════════════════════════════

drop policy if exists "equipment_insert" on public.equipment;

create policy "equipment_insert" on public.equipment
  for insert to authenticated
  with check ( public.can_access_site(site_id) );
