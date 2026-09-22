-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Migration 3 : réponse technicien (délai d'intervention)
--
-- Flux métier :
--   1. Le CLIENT signale un incident (policy inchangée : client only)
--   2. Les TECHNICIENS assignés reçoivent la notification
--   3. Le TECHNICIEN répond : statut « en_route » + délai + note
--   4. Le CLIENT reçoit une notification avec le délai annoncé
-- ═══════════════════════════════════════════════════════════

-- 1. Colonnes de réponse sur les tickets
alter table public.tickets
  add column if not exists intervention_deadline timestamptz,
  add column if not exists technician_note text,
  add column if not exists responded_at timestamptz;

-- Index pour les tableaux de bord « interventions à venir »
create index if not exists idx_tickets_intervention
  on public.tickets(intervention_deadline)
  where intervention_deadline is not null;

-- 2. Sécurité : l'insertion reste réservée au propriétaire (client).
--    (Re-créée explicitement pour neutraliser toute version antérieure.)
drop policy if exists "tickets_insert" on public.tickets;
create policy "tickets_insert" on public.tickets
  for insert to authenticated
  with check (
    public.is_site_owner(site_id)
    and opened_by = auth.uid()
  );

-- 3. Trigger enrichi
create or replace function public.notify_ticket_events()
returns trigger
language plpgsql
security definer
set search_path = ''
set timezone = 'Africa/Abidjan'
as $$
declare
  v_owner uuid;
  v_status_label text;
begin
  select owner_id into v_owner from public.sites where id = new.site_id;

  v_status_label := case new.status
    when 'pending'   then 'En attente'
    when 'en_route'  then 'Technicien en route'
    when 'resolved'  then 'Résolu'
    else new.status
  end;

  if tg_op = 'INSERT' then
    -- Signalement reçu : prévenir les techniciens assignés (jamais l'auteur).
    insert into public.notifications (user_id, title, body, data)
    select st.technician_id,
           'Nouveau signalement',
           new.title,
           jsonb_build_object('type', 'ticket', 'ticket_id', new.id, 'status', new.status)
    from public.site_technicians st
    where st.site_id = new.site_id
      and st.technician_id is distinct from new.opened_by;
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    -- Prise en charge / résolution : prévenir le client, avec le délai
    -- annoncé si le technicien a répondu.
    if v_owner is not null and v_owner is distinct from (select auth.uid()) then
      insert into public.notifications (user_id, title, body, data)
      values (v_owner,
              case when new.status = 'en_route' then 'Intervention planifiée'
                   else 'Ticket mis à jour' end,
              case
                when new.status = 'en_route' and new.intervention_deadline is not null then
                  'Sous 24h ou moins — prévu le ' ||
                  to_char(new.intervention_deadline, 'DD/MM/YYYY à HH24hMI') || ' · ' || new.title
                else v_status_label || ' · ' || new.title
              end,
              jsonb_build_object(
                'type', 'ticket', 'ticket_id', new.id, 'status', new.status,
                'intervention_deadline', new.intervention_deadline
              ));
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.notify_ticket_events() from anon, authenticated;
