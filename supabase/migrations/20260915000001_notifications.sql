-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Migration 2 : Storage photos + notifications
--
-- 1. Bucket privé « ticket-photos » (chemin : {site_id}/{fichier})
-- 2. Déclenchement de notifications in-app :
--    - nouveau ticket   → notifie les techniciens assignés
--    - statut modifié   → notifie le propriétaire du site
--    - nouvelle alerte  → notifie propriétaire + techniciens
-- ═══════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────
-- 1. STORAGE — bucket privé des photos de tickets
-- ───────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('ticket-photos', 'ticket-photos', false)
on conflict (id) do nothing;

-- Écriture : utilisateur ayant accès au site (1er dossier du chemin)
create policy "ticket_photos_insert"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'ticket-photos'
    and public.can_access_site((storage.foldername(name))[1]::uuid)
  );

-- Lecture : même règle (URLs signées générées côté client)
create policy "ticket_photos_select"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'ticket-photos'
    and public.can_access_site((storage.foldername(name))[1]::uuid)
  );

-- ───────────────────────────────────────────────────────────
-- 2. NOTIFICATIONS — triggers
-- ───────────────────────────────────────────────────────────
create or replace function public.notify_ticket_events()
returns trigger
language plpgsql
security definer
set search_path = ''
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
    -- Nouveau signalement : prévenir les techniciens assignés au site
    insert into public.notifications (user_id, title, body, data)
    select st.technician_id,
           'Nouveau signalement',
           new.title,
           jsonb_build_object('type', 'ticket', 'ticket_id', new.id, 'status', new.status)
    from public.site_technicians st
    where st.site_id = new.site_id;
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    -- Changement de statut : prévenir le client propriétaire
    if v_owner is not null and v_owner is distinct from (select auth.uid()) then
      insert into public.notifications (user_id, title, body, data)
      values (v_owner,
              'Ticket mis à jour',
              v_status_label || ' · ' || new.title,
              jsonb_build_object('type', 'ticket', 'ticket_id', new.id, 'status', new.status));
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists on_ticket_event on public.tickets;
create trigger on_ticket_event
  after insert or update of status on public.tickets
  for each row execute function public.notify_ticket_events();

create or replace function public.notify_new_alert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Nouvelle alerte système : prévenir propriétaire + techniciens assignés
  insert into public.notifications (user_id, title, body, data)
  select u.user_id, new.title, coalesce(new.message, ''),
         jsonb_build_object('type', 'alert', 'alert_id', new.id, 'severity', new.severity)
  from (
    select s.owner_id as user_id from public.sites s where s.id = new.site_id
    union
    select st.technician_id from public.site_technicians st where st.site_id = new.site_id
  ) u;

  return new;
end;
$$;

drop trigger if exists on_alert_created on public.alerts;
create trigger on_alert_created
  after insert on public.alerts
  for each row execute function public.notify_new_alert();

-- Les fonctions trigger ne doivent pas être appelables via l'API
revoke execute on function public.notify_ticket_events() from anon, authenticated;
revoke execute on function public.notify_new_alert() from anon, authenticated;
