-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Purge du CONTENU de démonstration (SANS toucher aux sites)
--
-- Contrairement à purge_demo_data.sql (qui supprime des SITES entiers
-- par nom — dangereux si le vrai client porte le nom du site de démo),
-- ce script ne supprime QUE les lignes de démo connues de seed.sql :
--   • 3 tickets  (« Caméra déplacée — angle mort », etc.)
--   • 3 visites  (Konan Y. / Aya K., rapports RPT-2025-118 / 092)
--   • 3 alertes  (« Espace disque du NVR », etc.)
--
-- ✅ Les sites, équipements, caméras et comptes ne sont PAS touchés.
-- ✅ Les vrais tickets créés depuis l'app ne correspondent pas aux
--    titres de démo → jamais supprimés.
--
-- Exécuter dans le SQL Editor Supabase.
-- ═══════════════════════════════════════════════════════════

begin;

-- ── Aperçu avant suppression (contrôle visuel) ──
select 'tickets' as table, count(*) from public.tickets
 where title in (
   'Caméra déplacée — angle mort',
   'Écran noir sur visionnage mobile',
   'Câble détérioré caméra caisse'
 );

select 'visites' as table, count(*) from public.maintenance_visits
 where report_ref in ('RPT-2025-118', 'RPT-2025-092')
    or technician_name in (
       'Konan Y. — Technicien certifié',
       'Aya K. — Technicienne certifiée'
     );

select 'alertes' as table, count(*) from public.alerts
 where title in (
   'Espace disque du NVR',
   'Coupure réseau détectée',
   'Nettoyage des objectifs recommandé'
 );

-- ── Purge : tickets de démo ──
delete from public.tickets
 where title in (
   'Caméra déplacée — angle mort',
   'Écran noir sur visionnage mobile',
   'Câble détérioré caméra caisse'
 );

-- ── Purge : visites d'entretien de démo ──
delete from public.maintenance_visits
 where report_ref in ('RPT-2025-118', 'RPT-2025-092')
    or technician_name in (
       'Konan Y. — Technicien certifié',
       'Aya K. — Technicienne certifiée'
     );

-- ── Purge : alertes de démo ──
delete from public.alerts
 where title in (
   'Espace disque du NVR',
   'Coupure réseau détectée',
   'Nettoyage des objectifs recommandé'
 );

commit;

-- ═══════════════════════════════════════════════════════════
-- Vérification après purge : les compteurs doivent refléter
-- uniquement le contenu réel.
-- ═══════════════════════════════════════════════════════════
select
  (select count(*) from public.sites)               as sites,
  (select count(*) from public.equipment)           as equipements,
  (select count(*) from public.tickets)             as tickets,
  (select count(*) from public.maintenance_visits)  as visites,
  (select count(*) from public.alerts)              as alertes;
