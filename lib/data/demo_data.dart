import 'package:flutter/material.dart';

import 'models.dart';

/// Données de démonstration — utilisées quand le backend Supabase
/// n'est pas configuré (--dart-define absent).

final DateTime _now = DateTime.now();

final List<Equipment> demoEquipment = [
  Equipment(
    id: 'EQ-001',
    name: 'Caméra dôme entrée',
    model: 'Hikvision DS-2CD2143G2-I',
    serial: 'HK-2143-88421-A',
    location: 'Entrée principale',
    category: EquipmentCategory.camera,
    installedAt: _now.subtract(const Duration(days: 420)),
    warrantyUntil: _now.add(const Duration(days: 510)),
    streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ),
  Equipment(
    id: 'EQ-002',
    name: 'Caméra tube parking',
    model: 'Dahua IPC-HFW2441T',
    serial: 'DH-2441-51702-B',
    location: 'Parking extérieur',
    category: EquipmentCategory.camera,
    installedAt: _now.subtract(const Duration(days: 420)),
    warrantyUntil: _now.add(const Duration(days: 62)),
  ),
  Equipment(
    id: 'EQ-003',
    name: 'Caméra PTZ entrepôt',
    model: 'Axis P3265-LV',
    serial: 'AX-3265-90347-C',
    location: 'Entrepôt',
    category: EquipmentCategory.camera,
    installedAt: _now.subtract(const Duration(days: 210)),
    warrantyUntil: _now.add(const Duration(days: 720)),
    streamUrl:
        'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_hls/master.m3u8',
  ),
  Equipment(
    id: 'EQ-004',
    name: 'Caméra caisse',
    model: 'Hikvision DS-2CD2087G2H',
    serial: 'HK-2087-33918-D',
    location: 'Zone caisse',
    category: EquipmentCategory.camera,
    installedAt: _now.subtract(const Duration(days: 1180)),
  ),
  Equipment(
    id: 'EQ-005',
    name: 'NVR principal 32 canaux',
    model: 'Hikvision DS-7732NI-K4',
    serial: 'HK-7732-10455-E',
    location: 'Local technique',
    category: EquipmentCategory.recorder,
    installedAt: _now.subtract(const Duration(days: 420)),
    warrantyUntil: _now.add(const Duration(days: 510)),
  ),
  Equipment(
    id: 'EQ-006',
    name: 'Disque NVR 4 TO',
    model: 'WD Purple WD40PURZ',
    serial: 'WD-40PZ-77213-F',
    location: 'NVR — baie 1',
    category: EquipmentCategory.storage,
    installedAt: _now.subtract(const Duration(days: 420)),
    storageUsed: 0.68,
    storageTotal: '4 TO',
  ),
  Equipment(
    id: 'EQ-007',
    name: 'Disque NVR 4 TO (miroir)',
    model: 'WD Purple WD40PURZ',
    serial: 'WD-40PZ-77214-G',
    location: 'NVR — baie 2',
    category: EquipmentCategory.storage,
    installedAt: _now.subtract(const Duration(days: 210)),
    storageUsed: 0.68,
    storageTotal: '4 TO',
  ),
  Equipment(
    id: 'EQ-008',
    name: 'Switch PoE 16 ports',
    model: 'TP-Link TL-SG1216P',
    serial: 'TP-1216-60892-H',
    location: 'Local technique',
    category: EquipmentCategory.network,
    installedAt: _now.subtract(const Duration(days: 420)),
    warrantyUntil: _now.add(const Duration(days: 40)),
  ),
];

List<Ticket> demoTickets = [
  Ticket(
    id: 'TK-2041',
    title: 'Caméra déplacée — angle mort',
    equipment: 'EQ-002 · Caméra tube parking',
    description:
        'La caméra du parking semble avoir été déplacée, une partie du parking n\'est plus visible.',
    status: TicketStatus.enRoute,
    openedAt: _now.subtract(const Duration(hours: 5)),
    hasPhoto: true,
  ),
  Ticket(
    id: 'TK-2038',
    title: 'Écran noir sur visionnage mobile',
    equipment: 'EQ-005 · NVR principal',
    description:
        'Le flux distant reste noir depuis l\'application mobile ce matin.',
    status: TicketStatus.pending,
    openedAt: _now.subtract(const Duration(days: 1, hours: 2)),
  ),
  Ticket(
    id: 'TK-2029',
    title: 'Câble détérioré caméra caisse',
    equipment: 'EQ-004 · Caméra caisse',
    description:
        'Gainé plastique abîmé près du connecteur, image qui scintille.',
    status: TicketStatus.resolved,
    openedAt: _now.subtract(const Duration(days: 9)),
  ),
];

const List<SupportAlert> demoAlerts = [
  SupportAlert(
    title: 'Espace disque du NVR',
    message:
        'Le disque du NVR atteint 68 % de remplissage. Pensez à vérifier la durée de rétention.',
    time: 'IL Y A 2 H',
    icon: Icons.storage_outlined,
  ),
  SupportAlert(
    title: 'Coupure réseau détectée',
    message:
        'Le switch PoE a redémarré hier à 03h12. Aucune perte d\'enregistrement constatée.',
    time: 'HIER · 03H12',
    icon: Icons.wifi_off_outlined,
  ),
  SupportAlert(
    title: 'Nettoyage des objectifs recommandé',
    message:
        'La caméra du parking n\'a pas été nettoyée depuis plus de 6 mois.',
    time: 'IL Y A 3 J',
    icon: Icons.cleaning_services_outlined,
  ),
];

final List<MaintenanceVisit> demoVisits = [
  MaintenanceVisit(
    date: _now.add(const Duration(days: 24)),
    technician: 'Konan Y. — Technicien certifié',
    tasks: [
      'Nettoyage des objectifs (4 caméras)',
      'Contrôle alimentation & onduleur',
      'Vérification santé des disques',
      'Mise à jour firmware NVR',
    ],
  ),
  MaintenanceVisit(
    date: _now.subtract(const Duration(days: 96)),
    technician: 'Konan Y. — Technicien certifié',
    tasks: [
      'Nettoyage des objectifs',
      'Contrôle alimentation & onduleur',
      'Vérification santé des disques',
    ],
    reportRef: 'RPT-2025-118',
  ),
  MaintenanceVisit(
    date: _now.subtract(const Duration(days: 188)),
    technician: 'Aya K. — Technicienne certifiée',
    tasks: ['Réalignement caméra PTZ', 'Contrôle général du site'],
    reportRef: 'RPT-2025-092',
  ),
];

final maintenanceContract = ContractInfo(
  plan: 'Contrat Maintenance Premium',
  renewalLabel: '15 mars 2027',
  siteLabel: 'Boutique Cocody Angré',
);
