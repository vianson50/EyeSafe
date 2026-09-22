-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Migration 8 : autorisation serveur du PTZ
--
-- « Ne jamais faire confiance au client » — suite : le contrôle PTZ
-- est une action sensible (mouvement de caméra physique). Il doit
-- être vérifié côté serveur pour CHAQUE usage, selon le tenant et
-- le rôle, comme le flux (cf. migration 7).
--
-- ⚠️ AUTO-SUFFISANTE : ce fichier inclut les objets de la migration 7
-- (table stream_audit, fonction get_stream_url) au cas où elle n'aurait
-- pas été appliquée. Tout est idempotent : ré-exécutable sans erreur.
-- ═══════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────
-- 1. Journal d'accès (créé par la migration 7 — gardé ici en repli)
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

-- Le journal distingue désormais flux et PTZ.
alter table public.stream_audit
  add column if not exists action text not null default 'stream';

comment on column public.stream_audit.action is
  'Action contrôlée : stream (lecture) ou ptz (contrôle moteur).';

-- ───────────────────────────────────────────────────────────
-- 2. Autorisation d'accès à un flux (migration 7, réinstallée ici)
-- ───────────────────────────────────────────────────────────
create or replace function public.get_stream_url(p_equipment uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row  public.equipment%rowtype;
  v_user uuid := auth.uid();
begin
  if v_user is null then
    return null;
  end if;

  select * into v_row from public.equipment e where e.id = p_equipment;
  if not found then
    return null;
  end if;

  if not public.can_access_site(v_row.site_id) then
    insert into public.stream_audit (user_id, equipment_id, site_id, granted, action)
    values (v_user, p_equipment, v_row.site_id, false, 'stream');
    return null;
  end if;

  insert into public.stream_audit (user_id, equipment_id, site_id, granted, action)
  values (v_user, p_equipment, v_row.site_id, true, 'stream');

  return v_row.stream_url;
end;
$$;

grant execute on function public.get_stream_url(uuid) to authenticated;

-- ───────────────────────────────────────────────────────────
-- 3. Autorisation de contrôle PTZ (migration 8)
-- ───────────────────────────────────────────────────────────
create or replace function public.can_control_ptz(p_equipment uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_site uuid;
  v_user uuid := auth.uid();
begin
  if v_user is null then
    return false;
  end if;

  select site_id into v_site from public.equipment
  where id = p_equipment;

  if v_site is null or not public.can_access_site(v_site) then
    if v_site is not null then
      insert into public.stream_audit (user_id, equipment_id, site_id, granted, action)
      values (v_user, p_equipment, v_site, false, 'ptz');
    end if;
    return false;
  end if;

  insert into public.stream_audit (user_id, equipment_id, site_id, granted, action)
  values (v_user, p_equipment, v_site, true, 'ptz');

  return true;
end;
$$;

grant execute on function public.can_control_ptz(uuid) to authenticated;

-- ───────────────────────────────────────────────────────────
-- 4. Option verrouillage total (production stricte, cf. migration 7)
-- ───────────────────────────────────────────────────────────
-- Quand TOUS les flux passent par le relais go2rtc/cloud (aucun
-- RTSP direct), retirer la lecture directe de la colonne pour que
-- get_stream_url devienne l'unique porte d'entrée :
--
-- revoke select (stream_url) on public.equipment from authenticated;
