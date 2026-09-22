import 'package:flutter/material.dart';

/// Modèles métier partagés par tout l'app.
/// Alimentés soit par les données de démo, soit par Supabase.

enum EquipmentCategory { camera, recorder, storage, network }

extension EquipmentCategoryX on EquipmentCategory {
  String get label => switch (this) {
    EquipmentCategory.camera => 'Caméra',
    EquipmentCategory.recorder => 'Enregistreur',
    EquipmentCategory.storage => 'Stockage',
    EquipmentCategory.network => 'Réseau',
  };

  IconData get icon => switch (this) {
    EquipmentCategory.camera => Icons.videocam_outlined,
    EquipmentCategory.recorder => Icons.dvr_outlined,
    EquipmentCategory.storage => Icons.storage_outlined,
    EquipmentCategory.network => Icons.lan_outlined,
  };

  Color get color => switch (this) {
    EquipmentCategory.camera => const Color(0xFF6D3BD7),
    EquipmentCategory.recorder => const Color(0xFF0891B2),
    EquipmentCategory.storage => const Color(0xFF0C9E6C),
    EquipmentCategory.network => const Color(0xFFD97706),
  };

  String get dbValue => switch (this) {
    EquipmentCategory.camera => 'camera',
    EquipmentCategory.recorder => 'recorder',
    EquipmentCategory.storage => 'storage',
    EquipmentCategory.network => 'network',
  };

  static EquipmentCategory fromDb(String value) =>
      EquipmentCategory.values.byName(value);
}

class Equipment {
  const Equipment({
    required this.id,
    required this.name,
    required this.model,
    required this.serial,
    required this.location,
    required this.category,
    required this.installedAt,
    this.warrantyUntil,
    this.storageUsed,
    this.storageTotal,
    this.streamUrl,
  });

  final String id;
  final String name;
  final String model;
  final String serial;
  final String location;
  final EquipmentCategory category;
  final DateTime installedAt;
  final DateTime? warrantyUntil;
  final double? storageUsed;
  final String? storageTotal;

  /// URL du flux en direct (HLS/RTSP) — null si non configuré.
  final String? streamUrl;

  bool get isLive => streamUrl != null;

  bool get underWarranty =>
      warrantyUntil != null && warrantyUntil!.isAfter(DateTime.now());

  bool get warrantyExpiringSoon =>
      underWarranty && warrantyUntil!.difference(DateTime.now()).inDays < 90;

  String get installDateLabel =>
      '${installedAt.day.toString().padLeft(2, '0')}/${installedAt.month.toString().padLeft(2, '0')}/${installedAt.year}';

  factory Equipment.fromDb(Map<String, dynamic> row) => Equipment(
    id: row['id'] as String,
    name: row['name'] as String,
    model: row['model'] as String? ?? '',
    serial: row['serial'] as String? ?? '',
    location: row['location'] as String? ?? '',
    category: EquipmentCategoryX.fromDb(row['category'] as String),
    installedAt: DateTime.parse(row['installed_on'] as String),
    warrantyUntil: row['warranty_until'] == null
        ? null
        : DateTime.parse(row['warranty_until'] as String),
    storageUsed: row['storage_used_pct'] == null
        ? null
        : (row['storage_used_pct'] as num).toDouble() / 100,
    storageTotal: row['storage_total_label'] as String?,
    streamUrl: row['stream_url'] as String?,
  );
}

enum TicketStatus { pending, enRoute, resolved }

extension TicketStatusX on TicketStatus {
  String get label => switch (this) {
    TicketStatus.pending => 'En attente',
    TicketStatus.enRoute => 'Technicien en route',
    TicketStatus.resolved => 'Résolu',
  };

  Color get color => switch (this) {
    TicketStatus.pending => const Color(0xFFD97706),
    TicketStatus.enRoute => const Color(0xFF6D3BD7),
    TicketStatus.resolved => const Color(0xFF0C9E6C),
  };

  static TicketStatus fromDb(String value) => switch (value) {
    'pending' => TicketStatus.pending,
    'en_route' => TicketStatus.enRoute,
    _ => TicketStatus.resolved,
  };
}

class Ticket {
  const Ticket({
    required this.id,
    required this.title,
    required this.equipment,
    required this.description,
    required this.status,
    required this.openedAt,
    this.hasPhoto = false,
    this.dbId = '',
    this.interventionAt,
    this.technicianNote,
    this.photoPath,
  });

  final String id;

  /// UUID complet côté base (mode live) — utilisé pour les updates.
  final String dbId;
  final String title;
  final String equipment;
  final String description;
  final TicketStatus status;
  final DateTime openedAt;
  final bool hasPhoto;

  /// Chemin dans le bucket privé ticket-photos (mode live).
  final String? photoPath;

  /// Délai d'intervention annoncé par le technicien.
  final DateTime? interventionAt;
  final String? technicianNote;

  String get openedLabel =>
      '${openedAt.day.toString().padLeft(2, '0')}/${openedAt.month.toString().padLeft(2, '0')} · '
      '${openedAt.hour.toString().padLeft(2, '0')}:${openedAt.minute.toString().padLeft(2, '0')}';

  String get interventionLabel {
    final d = interventionAt;
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}'
        ' · ${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
  }
}

class SupportAlert {
  const SupportAlert({
    required this.title,
    required this.message,
    required this.time,
    required this.icon,
  });

  final String title;
  final String message;
  final String time;
  final IconData icon;
}

class MaintenanceVisit {
  const MaintenanceVisit({
    required this.date,
    required this.technician,
    required this.tasks,
    this.reportRef,
  });

  final DateTime date;
  final String technician;
  final List<String> tasks;
  final String? reportRef;

  bool get isPast => reportRef != null;

  String get dateLabel =>
      '${date.day.toString().padLeft(2, '0')} ${_months[date.month - 1]} ${date.year}';

  String get dayNumber => date.day.toString().padLeft(2, '0');

  String get monthLabel => _months[date.month - 1].toUpperCase();

  static const _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  factory MaintenanceVisit.fromDb(Map<String, dynamic> row) => MaintenanceVisit(
    date: DateTime.parse(row['scheduled_on'] as String),
    technician: row['technician_name'] as String? ?? 'Technicien EyeSafe',
    tasks: (row['tasks'] as List<dynamic>? ?? const [])
        .map((t) => t as String)
        .toList(),
    reportRef: row['report_ref'] as String?,
  );
}

/// Résumé d'un site accessible à l'utilisateur (multi-sites).
class SiteSummary {
  const SiteSummary({
    required this.id,
    required this.name,
    required this.isOwner,
    this.plan,
  });

  final String id;
  final String name;

  /// Vrai si l'utilisateur est propriétaire (client), faux s'il est
  /// technicien assigné.
  final bool isOwner;
  final String? plan;
}

/// Notification in-app (cloche) — alimentée par les triggers base.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.type,
  });

  final String id;
  final String title;
  final String? body;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? type; // 'ticket' | 'alert'

  bool get isUnread => readAt == null;

  factory NotificationItem.fromDb(Map<String, dynamic> row) => NotificationItem(
    id: row['id'] as String,
    title: row['title'] as String,
    body: row['body'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    readAt: row['read_at'] == null
        ? null
        : DateTime.parse(row['read_at'] as String),
    type: (row['data'] as Map<String, dynamic>?)?['type'] as String?,
  );
}

/// Infos du contrat affichées sur la page entretien et la barre latérale.
class ContractInfo {
  const ContractInfo({
    required this.plan,
    required this.renewalLabel,
    required this.siteLabel,
  });

  final String plan;
  final String renewalLabel;
  final String siteLabel;
}
