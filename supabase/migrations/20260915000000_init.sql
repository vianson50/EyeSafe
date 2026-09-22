-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Schéma initial (Supabase / PostgreSQL)
--
-- Rôles :
--   client     → propriétaire d'un ou plusieurs sites
--   technicien → assigné à des sites via site_technicians
--   admin      → gestion interne (assigné via SQL, pas via l'app)
--
-- ⚠️ Depuis mai 2026, les nouvelles tables ne sont plus exposées
-- automatiquement à la Data API : les GRANT explicites ci-dessous
-- sont donc obligatoires.
-- ═══════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────
-- 1. PROFILS (extension de auth.users)
-- ───────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        text not null default 'client'
              check (role in ('client', 'technicien', 'admin')),
  full_name   text not null default '',
  phone       text,
  fcm_token   text,
  created_at  timestamptz not null default now()
);

comment on table public.profiles is
  'Rôle et coordonnées des utilisateurs. Le rôle n''est JAMAIS lu depuis user_metadata (éditable par l''utilisateur).';

-- Création automatique du profil à l'inscription.
-- ⚠️ Le rôle reste 'client' par défaut : passer un utilisateur en
-- 'technicien' doit se faire côté administration (SQL/dashboard).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────────────────────────────────────────────────────
-- 2. SITES (installations des clients)
-- ───────────────────────────────────────────────────────────
create table if not exists public.sites (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null references public.profiles(id) on delete cascade,
  name               text not null,
  address            text,
  contract_plan      text,
  contract_renews_on date,
  created_at         timestamptz not null default now()
);

-- ───────────────────────────────────────────────────────────
-- 3. ASSIGNATION TECHNICIENS ↔ SITES
-- ───────────────────────────────────────────────────────────
create table if not exists public.site_technicians (
  site_id       uuid not null references public.sites(id) on delete cascade,
  technician_id uuid not null references public.profiles(id) on delete cascade,
  assigned_at   timestamptz not null default now(),
  primary key (site_id, technician_id)
);

-- ───────────────────────────────────────────────────────────
-- 4. ÉQUIPEMENTS
-- ───────────────────────────────────────────────────────────
create table if not exists public.equipment (
  id                  uuid primary key default gen_random_uuid(),
  site_id             uuid not null references public.sites(id) on delete cascade,
  name                text not null,
  model               text,
  serial              text unique,
  location            text,
  category            text not null
                      check (category in ('camera', 'recorder', 'storage', 'network')),
  installed_on        date,
  warranty_until      date,
  storage_used_pct    numeric(5, 2),
  storage_total_label text,
  created_at          timestamptz not null default now()
);

-- ───────────────────────────────────────────────────────────
-- 5. TICKETS (incidents)
-- ───────────────────────────────────────────────────────────
create table if not exists public.tickets (
  id           uuid primary key default gen_random_uuid(),
  site_id      uuid not null references public.sites(id) on delete cascade,
  equipment_id uuid references public.equipment(id) on delete set null,
  title        text not null,
  description  text,
  status       text not null default 'pending'
               check (status in ('pending', 'en_route', 'resolved')),
  photo_url    text,
  opened_by    uuid not null references public.profiles(id),
  assigned_to  uuid references public.profiles(id),
  opened_at    timestamptz not null default now()
);

-- ───────────────────────────────────────────────────────────
-- 6. VISITES D'ENTRETIEN
-- ───────────────────────────────────────────────────────────
create table if not exists public.maintenance_visits (
  id              uuid primary key default gen_random_uuid(),
  site_id         uuid not null references public.sites(id) on delete cascade,
  technician_id   uuid references public.profiles(id) on delete set null,
  technician_name text,
  scheduled_on    date not null,
  tasks           text[] not null default '{}',
  report_ref      text,
  created_at      timestamptz not null default now()
);

-- ───────────────────────────────────────────────────────────
-- 7. ALERTES (événements système par site)
-- ───────────────────────────────────────────────────────────
create table if not exists public.alerts (
  id         uuid primary key default gen_random_uuid(),
  site_id    uuid not null references public.sites(id) on delete cascade,
  title      text not null,
  message    text,
  severity   text not null default 'info'
             check (severity in ('info', 'warning', 'critical')),
  icon_hint  text,
  created_at timestamptz not null default now()
);

-- ───────────────────────────────────────────────────────────
-- 8. NOTIFICATIONS (historique in-app / push FCM)
-- ───────────────────────────────────────────────────────────
create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  title      text not null,
  body       text,
  data       jsonb,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);

-- ═══════════════════════════════════════════════════════════
-- INDEXES (clés étrangères + filtres fréquents)
-- ═══════════════════════════════════════════════════════════
create index if not exists idx_sites_owner            on public.sites(owner_id);
create index if not exists idx_site_tech_technician   on public.site_technicians(technician_id);
create index if not exists idx_equipment_site         on public.equipment(site_id);
create index if not exists idx_tickets_site           on public.tickets(site_id);
create index if not exists idx_tickets_equipment      on public.tickets(equipment_id);
create index if not exists idx_tickets_status_opened  on public.tickets(status, opened_at desc);
create index if not exists idx_visits_site_date       on public.maintenance_visits(site_id, scheduled_on desc);
create index if not exists idx_alerts_site_created    on public.alerts(site_id, created_at desc);
create index if not exists idx_notif_user_unread      on public.notifications(user_id) where read_at is null;
create index if not exists idx_notif_user_created     on public.notifications(user_id, created_at desc);

-- ═══════════════════════════════════════════════════════════
-- FONCTIONS D'AIDE (security invoker — respectent la RLS)
-- ═══════════════════════════════════════════════════════════
create or replace function public.is_site_owner(p_site uuid)
returns boolean
language sql stable security invoker set search_path = ''
as $$ select exists (
  select 1 from public.sites s
  where s.id = p_site and s.owner_id = auth.uid()
) $$;

create or replace function public.is_site_technician(p_site uuid)
returns boolean
language sql stable security invoker set search_path = ''
as $$ select exists (
  select 1 from public.site_technicians st
  where st.site_id = p_site and st.technician_id = auth.uid()
) $$;

create or replace function public.can_access_site(p_site uuid)
returns boolean
language sql stable security invoker set search_path = ''
as $$ select public.is_site_owner(p_site) or public.is_site_technician(p_site) $$;

-- ═══════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════
alter table public.profiles           enable row level security;
alter table public.sites              enable row level security;
alter table public.site_technicians   enable row level security;
alter table public.equipment          enable row level security;
alter table public.tickets            enable row level security;
alter table public.maintenance_visits enable row level security;
alter table public.alerts             enable row level security;
alter table public.notifications      enable row level security;

-- profiles : chacun voit et modifie uniquement son profil
create policy "profiles_select_own" on public.profiles
  for select to authenticated using ( id = auth.uid() );

create policy "profiles_insert_self" on public.profiles
  for insert to authenticated with check ( id = auth.uid() );

create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using ( id = auth.uid() ) with check ( id = auth.uid() );
-- (la colonne `role` reste protégée par un GRANT column-level, cf. ci-dessous)

-- sites : visibles par le propriétaire et les techniciens assignés
create policy "sites_select" on public.sites
  for select to authenticated
  using ( owner_id = auth.uid() or public.is_site_technician(id) );

create policy "sites_insert" on public.sites
  for insert to authenticated with check ( owner_id = auth.uid() );

create policy "sites_update" on public.sites
  for update to authenticated
  using ( owner_id = auth.uid() ) with check ( owner_id = auth.uid() );

create policy "sites_delete" on public.sites
  for delete to authenticated using ( owner_id = auth.uid() );

-- site_technicians : gestion par le propriétaire du site
create policy "site_tech_select" on public.site_technicians
  for select to authenticated
  using ( technician_id = auth.uid()
          or public.can_access_site(site_id) );

create policy "site_tech_insert" on public.site_technicians
  for insert to authenticated with check ( public.is_site_owner(site_id) );

create policy "site_tech_update" on public.site_technicians
  for update to authenticated
  using ( public.is_site_owner(site_id) ) with check ( public.is_site_owner(site_id) );

create policy "site_tech_delete" on public.site_technicians
  for delete to authenticated using ( public.is_site_owner(site_id) );

-- equipment : lecture propriétaire + techniciens ; écriture partagée
create policy "equipment_select" on public.equipment
  for select to authenticated using ( public.can_access_site(site_id) );

create policy "equipment_insert" on public.equipment
  for insert to authenticated with check ( public.is_site_owner(site_id) );

create policy "equipment_update" on public.equipment
  for update to authenticated
  using ( public.can_access_site(site_id) ) with check ( public.can_access_site(site_id) );

create policy "equipment_delete" on public.equipment
  for delete to authenticated using ( public.is_site_owner(site_id) );

-- tickets : ouverts par le client, suivis par client et technicien
create policy "tickets_select" on public.tickets
  for select to authenticated using ( public.can_access_site(site_id) );

create policy "tickets_insert" on public.tickets
  for insert to authenticated
  with check ( public.is_site_owner(site_id) and opened_by = auth.uid() );

create policy "tickets_update" on public.tickets
  for update to authenticated
  using ( public.can_access_site(site_id) ) with check ( public.can_access_site(site_id) );

create policy "tickets_delete" on public.tickets
  for delete to authenticated using ( public.is_site_owner(site_id) );

-- maintenance_visits
create policy "visits_select" on public.maintenance_visits
  for select to authenticated using ( public.can_access_site(site_id) );

create policy "visits_insert" on public.maintenance_visits
  for insert to authenticated with check ( public.is_site_owner(site_id) );

create policy "visits_update" on public.maintenance_visits
  for update to authenticated
  using ( public.can_access_site(site_id) ) with check ( public.can_access_site(site_id) );

create policy "visits_delete" on public.maintenance_visits
  for delete to authenticated using ( public.is_site_owner(site_id) );

-- alerts
create policy "alerts_select" on public.alerts
  for select to authenticated using ( public.can_access_site(site_id) );

create policy "alerts_insert" on public.alerts
  for insert to authenticated with check ( public.can_access_site(site_id) );

create policy "alerts_update" on public.alerts
  for update to authenticated
  using ( public.is_site_owner(site_id) ) with check ( public.is_site_owner(site_id) );

create policy "alerts_delete" on public.alerts
  for delete to authenticated using ( public.is_site_owner(site_id) );

-- notifications : strictement personnelles
create policy "notifications_select" on public.notifications
  for select to authenticated using ( user_id = auth.uid() );

create policy "notifications_insert" on public.notifications
  for insert to authenticated with check ( user_id = auth.uid() );

create policy "notifications_update" on public.notifications
  for update to authenticated
  using ( user_id = auth.uid() ) with check ( user_id = auth.uid() );

-- ═══════════════════════════════════════════════════════════
-- GRANTS — exposition explicite à la Data API
-- (obligatoire sur les projets créés après mai 2026)
-- ═══════════════════════════════════════════════════════════
grant usage on schema public to anon, authenticated;

-- profiles : INSERT/UPDATE limités aux colonnes sûres → le rôle
-- ne peut pas être auto-modifié par un client ou un technicien.
grant select on public.profiles to authenticated;
grant insert (id, full_name, phone) on public.profiles to authenticated;
grant update (full_name, phone, fcm_token) on public.profiles to authenticated;

grant select, insert, update, delete on public.sites              to authenticated;
grant select, insert, update, delete on public.site_technicians   to authenticated;
grant select, insert, update, delete on public.equipment          to authenticated;
grant select, insert, update, delete on public.tickets            to authenticated;
grant select, insert, update, delete on public.maintenance_visits to authenticated;
grant select, insert, update, delete on public.alerts             to authenticated;
grant select, insert, update         on public.notifications      to authenticated;

grant execute on function public.is_site_owner(uuid)      to authenticated;
grant execute on function public.is_site_technician(uuid) to authenticated;
grant execute on function public.can_access_site(uuid)    to authenticated;

-- ═══════════════════════════════════════════════════════════
-- REALTIME (temps réel filtré par RLS)
-- ═══════════════════════════════════════════════════════════
-- replica identity full : nécessaire pour que Realtime applique
-- correctement la RLS sur UPDATE/DELETE.
alter table public.tickets            replica identity full;
alter table public.alerts             replica identity full;
alter table public.maintenance_visits replica identity full;
alter table public.notifications      replica identity full;

do $$
begin
  alter publication supabase_realtime add table public.tickets;
exception when duplicate_object then null; end $$;

do $$
begin
  alter publication supabase_realtime add table public.alerts;
exception when duplicate_object then null; end $$;

do $$
begin
  alter publication supabase_realtime add table public.maintenance_visits;
exception when duplicate_object then null; end $$;

do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception when duplicate_object then null; end $$;
