-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Migration 9 : techniciens GLOBAUX
--
-- Modèle demandé : une ÉQUIPE de techniciens (4+) qui peut
-- intervenir PARTOUT. Plus d'assignation site par site :
--   - client    → ne voit que SES sites (inchangé)
--   - technicien→ voit TOUS les sites, sur tous les écrans
--                 (équipements, tickets, flux, PTZ…)
--
-- La coordination d'équipe reste par les tickets : quand un
-- technicien répond (statut « en_route »), les autres le voient
-- en temps réel et servent les autres clients.
-- ═══════════════════════════════════════════════════════════

-- 1. Helper : l'utilisateur connecté est-il technicien ?
--    (security definer : lecture du rôle SANS déclencher la RLS
--    de profiles — évite toute récursion avec les policies.)
create or replace function public.is_technician()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'technicien'
  )
$$;

-- 2. can_access_site : un technicien passe PARTOUT.
--    (Toutes les policies équipements/tickets/visites/alertes/
--    flux/PTX l'utilisent déjà — un seul point de bascule.)
create or replace function public.can_access_site(p_site uuid)
returns boolean
language sql stable security invoker set search_path = ''
as $$
  select public.is_site_owner(p_site) or public.is_technician()
$$;

-- 3. Lecture des sites : les techniciens voient TOUTES les
--    installations (les clients restent limités aux leurs).
drop policy if exists "sites_select" on public.sites;
create policy "sites_select" on public.sites
  for select to authenticated
  using ( owner_id = auth.uid() or public.is_technician() );

-- 4. La table site_technicians reste pour l'historique/organisation
--    future, mais n'est PLUS requise pour l'accès.
