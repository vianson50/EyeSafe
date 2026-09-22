-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Purge des données de DÉMONSTRATION
--
-- Supprime les sites de démo créés par seed.sql / reseed_demo.py
-- (« Boutique Cocody Angré », second site de démo…) avec TOUT leur
-- contenu (équipements, tickets, visites, alertes, notifications) —
-- les clés étrangères sont ON DELETE CASCADE.
--
-- ⚠️ SÉCURITÉ : ne supprime QUE les sites dont le nom correspond aux
-- libellés de démo connus. Les vrais clients ne sont pas touchés.
-- Exécuter dans le SQL Editor Supabase.
-- ═══════════════════════════════════════════════════════════

begin;

-- Aperçu avant suppression (contrôle) :
select id, name, owner_id, created_at
from public.sites
where name in (
  'Boutique Cocody Angré',
  'Résidence Les Palmiers',
  'Boutique Marcory Zone 4'
);

-- Purge : suppression des sites de démo (cascade → equipment, tickets,
-- maintenance_visits, alerts, notifications, stream_audit,
-- site_technicians).
delete from public.sites
where name in (
  'Boutique Cocody Angré',
  'Résidence Les Palmiers',
  'Boutique Marcory Zone 4'
);

commit;

-- Vérification après purge : il ne doit rester que les vrais sites.
select count(*) as sites_restants from public.sites;
select count(*) as equipements_restants from public.equipment;
select count(*) as tickets_restants from public.tickets;
