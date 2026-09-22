-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Données de démonstration
--
-- ⚠️ AVANT D'EXÉCUTER :
--   1. Créez les comptes (script supabase/create_users.sh ou dashboard)
--   2. Renseignez les emails ci-dessous
--   3. Exécutez ce script dans le SQL Editor Supabase
-- ═══════════════════════════════════════════════════════════
do $$
declare
  -- ← ADAPTER : emails des comptes créés
  v_email     text := 'client@eyesafe.dev';
  v_tech_mail text := 'technicien@eyesafe.dev';
  v_owner     uuid;
  v_tech      uuid;
  v_site      uuid;
begin
  select p.id into v_owner
  from public.profiles p
  join auth.users u on u.id = p.id
  where u.email = v_email
  limit 1;

  if v_owner is null then
    raise notice '➜ Aucun compte trouvé pour « % ». Créez le compte puis relancez ce script.', v_email;
    return;
  end if;

  -- Technicien : promotion + assignation au site
  select p.id into v_tech
  from public.profiles p
  join auth.users u on u.id = p.id
  where u.email = v_tech_mail
  limit 1;

  -- Site
  insert into public.sites (owner_id, name, address, contract_plan, contract_renews_on)
  values (v_owner, 'Boutique Cocody Angré', 'Rue L112, Cocody Angré, Abidjan',
          'Contrat Maintenance Premium', date '2027-03-15')
  returning id into v_site;

  -- Promotion du technicien + assignation au site
  if v_tech is not null then
    update public.profiles set role = 'technicien' where id = v_tech;
    insert into public.site_technicians (site_id, technician_id)
    values (v_site, v_tech)
    on conflict do nothing;
  else
    raise notice '➜ Technicien « % » introuvable — assignation ignorée.', v_tech_mail;
  end if;

  -- Équipements (repris de demo_data.dart)
  insert into public.equipment (site_id, name, model, serial, location, category, installed_on, warranty_until, storage_used_pct, storage_total_label)
  values
    (v_site, 'Caméra dôme entrée',       'Hikvision DS-2CD2143G2-I', 'HK-2143-88421-A', 'Entrée principale', 'camera',   current_date - 420, current_date + 510, null,  null),
    (v_site, 'Caméra tube parking',      'Dahua IPC-HFW2441T',       'DH-2441-51702-B', 'Parking extérieur', 'camera',   current_date - 420, current_date + 62,  null,  null),
    (v_site, 'Caméra PTZ entrepôt',      'Axis P3265-LV',            'AX-3265-90347-C', 'Entrepôt',          'camera',   current_date - 210, current_date + 720, null,  null),
    (v_site, 'Caméra caisse',            'Hikvision DS-2CD2087G2H',  'HK-2087-33918-D', 'Zone caisse',       'camera',   current_date - 1180, null,               null,  null),
    (v_site, 'NVR principal 32 canaux',  'Hikvision DS-7732NI-K4',   'HK-7732-10455-E', 'Local technique',   'recorder', current_date - 420, current_date + 510, null,  null),
    (v_site, 'Disque NVR 4 TO',          'WD Purple WD40PURZ',       'WD-40PZ-77213-F', 'NVR — baie 1',      'storage',  current_date - 420, null,               68.00, '4 TO'),
    (v_site, 'Disque NVR 4 TO (miroir)', 'WD Purple WD40PURZ',       'WD-40PZ-77214-G', 'NVR — baie 2',      'storage',  current_date - 210, null,               68.00, '4 TO'),
    (v_site, 'Switch PoE 16 ports',      'TP-Link TL-SG1216P',       'TP-1216-60892-H', 'Local technique',   'network',  current_date - 420, current_date + 40,  null,  null);

  -- Tickets (lié à l'équipement via le numéro de série)
  insert into public.tickets (site_id, equipment_id, title, description, status, opened_by, opened_at)
  select v_site, e.id,
         'Caméra déplacée — angle mort',
         'La caméra du parking semble avoir été déplacée, une partie du parking n''est plus visible.',
         'en_route', v_owner, now() - interval '5 hours'
  from public.equipment e where e.site_id = v_site and e.serial = 'DH-2441-51702-B';

  insert into public.tickets (site_id, equipment_id, title, description, status, opened_by, opened_at)
  select v_site, e.id,
         'Écran noir sur visionnage mobile',
         'Le flux distant reste noir depuis l''application mobile ce matin.',
         'pending', v_owner, now() - interval '1 day 2 hours'
  from public.equipment e where e.site_id = v_site and e.serial = 'HK-7732-10455-E';

  insert into public.tickets (site_id, equipment_id, title, description, status, opened_by, opened_at)
  select v_site, e.id,
         'Câble détérioré caméra caisse',
         'Gainé plastique abîmé près du connecteur, image qui scintille.',
         'resolved', v_owner, now() - interval '9 days'
  from public.equipment e where e.site_id = v_site and e.serial = 'HK-2087-33918-D';

  -- Visites d'entretien (Konan Y. est lié au compte technicien si trouvé)
  insert into public.maintenance_visits (site_id, technician_id, technician_name, scheduled_on, tasks, report_ref)
  values
    (v_site, v_tech, 'Konan Y. — Technicien certifié', current_date + 24,
     array['Nettoyage des objectifs (4 caméras)', 'Contrôle alimentation & onduleur',
           'Vérification santé des disques', 'Mise à jour firmware NVR'], null),
    (v_site, v_tech, 'Konan Y. — Technicien certifié', current_date - 96,
     array['Nettoyage des objectifs', 'Contrôle alimentation & onduleur',
           'Vérification santé des disques'], 'RPT-2025-118'),
    (v_site, null, 'Aya K. — Technicienne certifiée', current_date - 188,
     array['Réalignement caméra PTZ', 'Contrôle général du site'], 'RPT-2025-092');

  -- Alertes
  insert into public.alerts (site_id, title, message, severity, icon_hint, created_at)
  values
    (v_site, 'Espace disque du NVR',
             'Le disque du NVR atteint 68 % de remplissage. Pensez à vérifier la durée de rétention.',
             'warning', 'storage', now() - interval '2 hours'),
    (v_site, 'Coupure réseau détectée',
             'Le switch PoE a redémarré hier à 03h12. Aucune perte d''enregistrement constatée.',
             'info', 'wifi_off', now() - interval '1 day'),
    (v_site, 'Nettoyage des objectifs recommandé',
             'La caméra du parking n''a pas été nettoyée depuis plus de 6 mois.',
             'info', 'cleaning_services', now() - interval '3 days');

  raise notice '✔ Données de démonstration créées pour « % » (site %).', v_email, v_site;
end $$;
