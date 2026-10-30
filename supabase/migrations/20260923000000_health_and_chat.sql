-- ═══════════════════════════════════════════════════════════
-- Migration 12 : Phase 3 — Diagnostic automatique
--
-- Table equipment_health pour le suivi de l'état des équipements.
-- Peuplée par l'Edge Function "health-check" (ping TCP toutes les 5 min).
-- ═══════════════════════════════════════════════════════════

create table if not exists public.equipment_health (
  id uuid primary key default gen_random_uuid(),
  equipment_id uuid not null references public.equipment(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  online boolean not null,
  latency_ms integer,
  last_seen timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.equipment_health enable row level security;

drop policy if exists "equipment_health_select" on public.equipment_health;
create policy "equipment_health_select" on public.equipment_health
  for select to authenticated
  using ( public.can_access_site(site_id) );

drop policy if exists "equipment_health_insert" on public.equipment_health;
create policy "equipment_health_insert" on public.equipment_health
  for insert to authenticated
  with check ( public.can_access_site(site_id) );

create index if not exists equipment_health_equipment_time_idx
  on public.equipment_health (equipment_id, created_at desc);

grant select, insert on public.equipment_health to authenticated;

-- ═══════════════════════════════════════════════════════════
-- Migration 12b : Phase 4 — Chat par ticket
-- ═══════════════════════════════════════════════════════════

create table if not exists public.ticket_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.tickets(id) on delete cascade,
  sender_id uuid not null references public.profiles(id),
  sender_role text not null check (sender_role in ('client', 'technicien')),
  message text not null,
  photo_url text,
  created_at timestamptz not null default now()
);

alter table public.ticket_messages enable row level security;

drop policy if exists "ticket_messages_select" on public.ticket_messages;
create policy "ticket_messages_select" on public.ticket_messages
  for select to authenticated
  using (
    exists (
      select 1 from public.tickets t
      where t.id = ticket_id and public.can_access_site(t.site_id)
    )
  );

drop policy if exists "ticket_messages_insert" on public.ticket_messages;
create policy "ticket_messages_insert" on public.ticket_messages
  for insert to authenticated
  with check (
    exists (
      select 1 from public.tickets t
      where t.id = ticket_id and public.can_access_site(t.site_id)
    )
  );

create index if not exists ticket_messages_ticket_time_idx
  on public.ticket_messages (ticket_id, created_at);

grant select, insert on public.ticket_messages to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.ticket_messages;
exception
  when duplicate_object then null;
end $$;
