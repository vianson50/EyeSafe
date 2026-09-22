-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Migration 5 : correction récursion RLS
--
-- Problème : « stack depth limit exceeded » sur SELECT sites.
-- Cause : cycle de policies —
--   sites_select → is_site_technician() lit site_technicians
--   → site_tech_select → can_access_site() → is_site_owner() lit sites
--   → sites_select → ∞
--
-- Solution standard Supabase : les fonctions d'aide passent en
-- SECURITY DEFINER (elles lisent les tables SOUN rer déclencher la
-- RLS). Elles ne font que retourner un booléen sur l'accès de
-- L'APPELANT (auth.uid()) — aucune élévation de privilèges.
-- ═══════════════════════════════════════════════════════════

create or replace function public.is_site_owner(p_site uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.sites s
    where s.id = p_site and s.owner_id = auth.uid()
  )
$$;

create or replace function public.is_site_technician(p_site uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.site_technicians st
    where st.site_id = p_site and st.technician_id = auth.uid()
  )
$$;

create or replace function public.can_access_site(p_site uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_site_owner(p_site) or public.is_site_technician(p_site)
$$;

-- Vérification rapide (doit retourner la liste sans erreur) :
-- select id, name from public.sites; -- en tant qu'utilisateur connecté
