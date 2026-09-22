-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Migration 7 : sécurité multi-clients des flux
--
-- Principe « ne jamais faire confiance au client » :
--   L'accès à un flux (live / playback / PTZ) est revérifié côté
--   serveur POUR CHAQUE requête, selon le tenant (site) et le rôle.
--
--   1. get_stream_url(equipment_id) : RPC security definer qui ne
--      retourne l'URL du flux QUE si l'appelant est propriétaire du
--      site ou technicien assigné. L'app l'appelle avant chaque
--      ouverture de direct — même si la ligne equipment est lisible,
--      c'est le serveur qui tranche.
--
--   2. stream_audit : journal des accès (qui, quoi, quand) pour
--      détecter les usages anormaux.
--
--   ⚠️ Limite assumée : la colonne equipment.stream_url reste lisible
--   par les policies existantes (le direct RTSP/IP directe en a
--   besoin côté téléphone). Pour la verrouiller totalement, passer
--   par le relais go2rtc/cloud (aucun identifiant dans l'URL) et
--   révoquer le SELECT colonne ci-dessous (décommenter).
-- ═══════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────
-- 1. Journal d'accès aux flux
-- ───────────────────────────────────────────────────────────
create table if not exists public.stream_audit (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  equipment_id uuid not null references public.equipment(id) on delete cascade,
  site_id      uuid not null references public.sites(id) on delete cascade,
  granted      boolean not null,
  created_at   timestamptz not null default now()
);

alter table public.stream_audit enable row level security;

-- Personne ne lit le journal depuis l'app (réservé à l'admin SQL).
drop policy if exists "stream_audit_no_select" on public.stream_audit;
create policy "stream_audit_no_select" on public.stream_audit
  for select to authenticated using (false);

-- ───────────────────────────────────────────────────────────
-- 2. Autorisation d'accès à un flux — vérifiée côté serveur
-- ───────────────────────────────────────────────────────────
create or replace function public.get_stream_url(p_equipment uuid)
returns text
language plpgsql
security definer            -- vérifie auth.uid() lui-même
set search_path = ''
as $$
declare
  v_row  public.equipment%rowtype;
  v_user uuid := auth.uid();
begin
  if v_user is null then
    return null;            -- non authentifié → rien
  end if;

  select * into v_row from public.equipment e where e.id = p_equipment;
  if not found then
    return null;
  end if;

  -- Tenant + rôle : propriétaire du site OU technicien assigné.
  if not public.can_access_site(v_row.site_id) then
    insert into public.stream_audit (user_id, equipment_id, site_id, granted)
    values (v_user, p_equipment, v_row.site_id, false);
    return null;            -- accès refusé
  end if;

  insert into public.stream_audit (user_id, equipment_id, site_id, granted)
  values (v_user, p_equipment, v_row.site_id, true);

  return v_row.stream_url;  -- autorisé → URL du flux
end;
$$;

grant execute on function public.get_stream_url(uuid) to authenticated;

-- ───────────────────────────────────────────────────────────
-- 3. Option verrouillage total (production stricte)
-- ───────────────────────────────────────────────────────────
-- Quand TOUS les flux passent par le relais go2rtc/cloud (aucun
-- RTSP direct), retirer la lecture directe de la colonne pour que
-- get_stream_url devienne l'unique porte d'entrée :
--
-- revoke select (stream_url) on public.equipment from authenticated;
