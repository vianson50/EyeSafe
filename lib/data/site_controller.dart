import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'demo_data.dart';
import 'go2rtc.dart';
import 'isapi.dart';
import 'models.dart';
import 'onvif.dart';
import 'stream_scheduler.dart';

/// Contrôleur de données du site actif.
///
/// - `SiteController.demoForTest()` : données locales (réservé aux tests).
/// - `SiteController.live(client)` : sites Supabase (possédés ou assignés
///   au technicien) + actualisation temps réel — **mode exclusif en
///   production**.
///
/// Multi-sites : [sites] liste toutes les installations accessibles,
/// [switchSite] bascule entre elles (le choix est mémorisé sur l'appareil).
class SiteController extends ChangeNotifier {
  /// ⚠️ Réservé aux TESTS (données locales sans backend). En production,
  /// l'app fonctionne exclusivement en mode réel ([SiteController.live]) —
  /// AuthGate bloque tout démarrage sans backend configuré.
  SiteController.demoForTest()
    : _client = null,
      _siteId = null,
      contract = maintenanceContract,
      equipment = List.of(demoEquipment),
      tickets = List.of(demoTickets),
      visits = List.of(demoVisits),
      alerts = List.of(demoAlerts),
      sites = const [
        SiteSummary(
          id: 'demo',
          name: 'Boutique Cocody Angré',
          isOwner: true,
          plan: 'Contrat Maintenance Premium',
        ),
      ] {
    unawaited(streams.loadPrefs());
  }

  SiteController.live(this._client) : _siteId = null {
    unawaited(streams.loadPrefs());
  }

  final SupabaseClient? _client;
  String? _siteId;
  RealtimeChannel? _channel;

  /// Tous les sites accessibles (possédés puis assignés, sans doublon).
  List<SiteSummary> sites = const [];

  /// Identifiant du site affiché.
  String? get activeSiteId => _siteId;

  // ── Événements caméras temps réel (ONVIF PullPoint) ──
  /// Un poller par caméra ONVIF connectée — voir [CameraEventPoller].
  final Map<String, CameraEventPoller> _eventPollers = {};

  /// Derniers événements reçus (toutes caméras), plus récents d'abord.
  List<CameraEventRecord> cameraEvents = const [];
  static const _maxCameraEvents = 100;
  static const _motionGracePeriod = Duration(seconds: 4);

  /// Environnement de test → pas de boucles réseau/timers (les tests
  /// widget cramperaient sur des timers pendants).
  static bool get _eventsPollingDisabled =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// Enregistre un événement caméra (appelé par les pollers) : historique
  /// borné + notification UI (mosaïque, dashboard…).
  void recordEvent(Equipment camera, OnvifEvent event) {
    cameraEvents = <CameraEventRecord>[
      CameraEventRecord(
        cameraId: camera.id,
        cameraName: camera.name,
        event: event,
        receivedAt: DateTime.now(),
      ),
      ...cameraEvents,
    ].take(_maxCameraEvents).toList();
    notifyListeners();
  }

  /// Mouvement ACTIF sur cette caméra ? (dernier événement = mouvement,
  /// reçu il y a moins de 4 s — évite le clignotement sur micro-pauses).
  bool isMotionActive(String cameraId) {
    for (final r in cameraEvents) {
      if (r.cameraId != cameraId) continue;
      if (DateTime.now().difference(r.receivedAt) > _motionGracePeriod) {
        return false; // dernier événement trop vieux
      }
      return r.event.isMotionActive;
    }
    return false;
  }

  /// Synchronise les pollers avec l'inventaire : démarre un poller par
  /// caméra ONVIF nouvelle, arrête ceux des caméras retirées.
  void _syncEventPollers() {
    if (_eventsPollingDisabled) return;

    _eventPollers.removeWhere((id, poller) {
      if (equipment.any((e) => e.id == id)) return false;
      unawaited(poller.stop());
      return true;
    });

    for (final cam in equipment) {
      if (cam.category != EquipmentCategory.camera) continue;
      if (_eventPollers.containsKey(cam.id)) continue;
      final poller = CameraEventPoller(camera: cam, controller: this);
      if (!poller.isSupported) continue; // relais/cloud/URL sans creds
      _eventPollers[cam.id] = poller;
      unawaited(poller.start());
    }
  }

  /// Arrête tous les pollers (changement de site / dispose).
  void stopEventPollers() {
    for (final p in _eventPollers.values) {
      unawaited(p.stop());
    }
    _eventPollers.clear();
  }

  /// Ordonnanceur de bande passante de la mosaïque (flux live limités,
  /// snapshots périodiques, dégradation automatique sur congestion).
  final StreamScheduler streams = StreamScheduler();

  ContractInfo? contract;
  List<Equipment> equipment = const [];
  List<Ticket> tickets = const [];
  List<MaintenanceVisit> visits = const [];
  List<SupportAlert> alerts = const [];
  List<NotificationItem> notifications = const [];

  /// Rôle du compte connecté : 'client' ou 'technicien'.
  String role = 'client';

  bool get isTechnician => role == 'technicien';
  String get roleLabel => isTechnician ? 'Technicien certifié' : 'Client Pro';

  int get unreadCount => notifications.where((n) => n.isUnread).length;

  bool loading = false;
  String? error;
  bool get noSite =>
      _client != null && _siteId == null && error == null && !loading;

  bool get isLive => _client != null;

  /// Crée la première installation du compte (auto-service à l'inscription)
  /// ou une installation supplémentaire. Le propriétaire est l'utilisateur
  /// connecté. Retourne null si succès.
  Future<String?> createSite({
    required String name,
    String? address,
    String? contractPlan,
  }) async {
    final client = _client;
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null) {
      return 'Session expirée — reconnectez-vous.';
    }

    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Donnez un nom à votre installation.';

    try {
      await client.from('sites').insert({
        'owner_id': uid,
        'name': trimmed,
        'address': address?.trim(),
        'contract_plan': contractPlan,
      });
      await load(); // recharge sites + données, sélectionne le premier site
      return null;
    } catch (e) {
      debugPrint('createSite: $e');
      return 'Création impossible. Vérifiez votre connexion et réessayez.';
    }
  }

  /// Charge les données puis s'abonne aux changements temps réel.
  Future<void> load() async {
    if (_client == null) return;
    final client = _client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

    loading = true;
    error = null;
    notifyListeners();

    try {
      final allSites = await _resolveSites(client, uid);
      sites = allSites
          .map(
            (s) => SiteSummary(
              id: s['id'] as String,
              name: s['name'] as String? ?? 'Site',
              isOwner: s['owner_id'] == uid,
              plan: s['contract_plan'] as String?,
            ),
          )
          .toList();

      if (sites.isEmpty) {
        loading = false;
        notifyListeners();
        return;
      }

      // Site actif : le dernier choisi (mémorisé), sinon le premier.
      final saved = await _savedSiteId(uid);
      _siteId = sites.any((s) => s.id == saved) ? saved : sites.first.id;
      final site = allSites.firstWhere(
        (s) => s['id'] == _siteId,
        orElse: () => allSites.first,
      );
      contract = _contractFromSite(site);

      // Rôle du compte (jamais lu depuis user_metadata : source = profiles).
      final profileRows = await client
          .from('profiles')
          .select('role')
          .eq('id', uid)
          .limit(1);
      if (profileRows.isNotEmpty) {
        role = profileRows.first['role'] as String? ?? 'client';
      }

      await Future.wait([
        _loadEquipment(),
        _loadTickets(),
        _loadVisits(),
        _loadAlerts(),
        _loadNotifications(),
      ]);
      loading = false;
      notifyListeners();
      _subscribeRealtime();
    } catch (e) {
      loading = false;
      error =
          'Impossible de charger les données du site. Vérifiez votre connexion.';
      debugPrint('SiteController: $e');
      notifyListeners();
    }
  }

  /// Bascule vers un autre site : recharge les données et réabonne
  /// le temps réel au nouveau site. Mémorise le choix.
  Future<void> switchSite(String siteId) async {
    final client = _client;
    if (client == null || siteId == _siteId) return;
    final summary = sites.where((s) => s.id == siteId).firstOrNull;
    if (summary == null) return;

    loading = true;
    error = null;
    notifyListeners();

    try {
      _siteId = siteId;
      contract = ContractInfo(
        plan: summary.plan ?? 'Contrat maintenance',
        renewalLabel: '—',
        siteLabel: summary.name,
      );

      await Future.wait([
        _loadEquipment(),
        _loadTickets(),
        _loadVisits(),
        _loadAlerts(),
      ]);

      // Temps réel : on réabonne au nouveau site.
      final oldChannel = _channel;
      if (oldChannel != null) {
        await client.removeChannel(oldChannel);
        _channel = null;
      }
      _subscribeRealtime();

      loading = false;
      notifyListeners();
      _saveSiteId(siteId);
    } catch (e) {
      loading = false;
      error = 'Impossible de changer de site. Réessayez.';
      debugPrint('switchSite: $e');
      notifyListeners();
    }
  }

  Future<String?> _savedSiteId(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('active_site_$uid');
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSiteId(String siteId) async {
    final uid = _client?.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_site_$uid', siteId);
    } catch (_) {
      /* préférence non critique */
    }
  }

  /// Tous les sites accessibles.
  ///
  /// Modèle équipe (migration 9) : un technicien voit TOUTES les
  /// installations (la RLS `sites_select` filtre côté serveur) — plus
  /// besoin d'assignation site par site. Un client ne voit que les siens.
  Future<List<Map<String, dynamic>>> _resolveSites(
    SupabaseClient client,
    String uid,
  ) async {
    // Le rôle doit être lu AVANT : il détermine si on liste tout ou non.
    // (Repli défensif : si le profil est illisible, on retombe sur les
    // sites possédés — un client ne voit jamais plus que son périmètre.)
    String role = 'client';
    try {
      final profile = await client
          .from('profiles')
          .select('role')
          .eq('id', uid)
          .limit(1);
      role = profile.isNotEmpty
          ? (profile.first['role'] as String? ?? 'client')
          : 'client';
    } catch (_) {
      // profiles illisible → requête simple ci-dessous, filtrée par RLS.
    }

    if (role == 'technicien') {
      // RLS sites_select : le technicien reçoit TOUTES les installations.
      return await client.from('sites').select().order('created_at');
    }

    // Client : ses installations uniquement (RLS garde-fou en plus).
    return await client
        .from('sites')
        .select()
        .eq('owner_id', uid)
        .order('created_at');
  }

  ContractInfo _contractFromSite(Map<String, dynamic> site) {
    final renews = site['contract_renews_on'] as String?;
    String renewal = '—';
    if (renews != null) {
      final d = DateTime.parse(renews);
      const months = [
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
      renewal = '${d.day} ${months[d.month - 1]} ${d.year}';
    }
    return ContractInfo(
      plan: site['contract_plan'] as String? ?? 'Contrat maintenance',
      renewalLabel: renewal,
      siteLabel: site['name'] as String? ?? 'Mon site',
    );
  }

  Future<void> _loadEquipment() async {
    final rows = await _client!
        .from('equipment')
        .select()
        .eq('site_id', _siteId!)
        .order('name');
    equipment = rows.map(Equipment.fromDb).toList();
    _syncEventPollers();
  }

  Future<void> _loadTickets() async {
    final rows = await _client!
        .from('tickets')
        .select('*, equipment:equipment_id(name)')
        .eq('site_id', _siteId!)
        .order('opened_at', ascending: false);
    tickets = rows.map(_ticketFromDb).toList();
  }

  Ticket _ticketFromDb(Map<String, dynamic> row) {
    final eq = row['equipment'];
    return Ticket(
      id: (row['id'] as String).substring(0, 8).toUpperCase(),
      dbId: row['id'] as String,
      title: row['title'] as String,
      equipment: eq == null ? 'Équipement supprimé' : eq['name'] as String,
      description: row['description'] as String? ?? '',
      status: TicketStatusX.fromDb(row['status'] as String),
      openedAt: DateTime.parse(row['opened_at'] as String),
      hasPhoto: row['photo_url'] != null,
      photoPath: row['photo_url'] as String?,
      interventionAt: row['intervention_deadline'] == null
          ? null
          : DateTime.parse(row['intervention_deadline'] as String),
      technicianNote: row['technician_note'] as String?,
    );
  }

  Future<void> _loadVisits() async {
    final rows = await _client!
        .from('maintenance_visits')
        .select()
        .eq('site_id', _siteId!)
        .order('scheduled_on', ascending: false);
    visits = rows.map(MaintenanceVisit.fromDb).toList();
  }

  Future<void> _loadAlerts() async {
    final rows = await _client!
        .from('alerts')
        .select()
        .eq('site_id', _siteId!)
        .order('created_at', ascending: false)
        .limit(20);
    alerts = rows.map(_alertFromDb).toList();
  }

  SupportAlert _alertFromDb(Map<String, dynamic> row) => SupportAlert(
    title: row['title'] as String,
    message: row['message'] as String? ?? '',
    time: _relativeTimeLabel(DateTime.parse(row['created_at'] as String)),
    icon: _iconFor(row['icon_hint'] as String?),
  );

  static IconData _iconFor(String? hint) => switch (hint) {
    'storage' => Icons.storage_outlined,
    'wifi_off' => Icons.wifi_off_outlined,
    'cleaning_services' => Icons.cleaning_services_outlined,
    'videocam' => Icons.videocam_outlined,
    'warning' => Icons.warning_amber_outlined,
    _ => Icons.info_outline,
  };

  static String _relativeTimeLabel(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return "À L'INSTANT";
    if (diff.inHours < 24) return 'IL Y A ${diff.inHours} H';
    if (diff.inDays == 1) {
      final hh = time.hour.toString().padLeft(2, '0');
      final mm = time.minute.toString().padLeft(2, '0');
      return 'HIER · ${hh}H$mm';
    }
    return 'IL Y A ${diff.inDays} J';
  }

  /// Libellé relatif public (« IL Y A 2 H »…) utilisé par le centre
  /// de notifications.
  static String relativeTimeLabel(DateTime time) => _relativeTimeLabel(time);

  Future<void> _loadNotifications() async {
    final client = _client;
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null) return;
    final rows = await client
        .from('notifications')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(50);
    notifications = rows.map(NotificationItem.fromDb).toList();
  }

  /// Marque une notification comme lue (optimiste côté UI).
  Future<void> markRead(NotificationItem notification) async {
    if (!notification.isUnread) return;
    notifications = notifications
        .map(
          (n) => n.id == notification.id
              ? NotificationItem(
                  id: n.id,
                  title: n.title,
                  body: n.body,
                  createdAt: n.createdAt,
                  readAt: DateTime.now(),
                  type: n.type,
                )
              : n,
        )
        .toList();
    notifyListeners();
    final client = _client;
    if (client == null) return;
    try {
      await client
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('id', notification.id);
    } catch (e) {
      debugPrint('markRead: $e');
    }
  }

  /// Marque toutes les notifications comme lues.
  Future<void> markAllRead() async {
    if (unreadCount == 0) return;
    final now = DateTime.now();
    notifications = notifications
        .map(
          (n) => n.isUnread
              ? NotificationItem(
                  id: n.id,
                  title: n.title,
                  body: n.body,
                  createdAt: n.createdAt,
                  readAt: now,
                  type: n.type,
                )
              : n,
        )
        .toList();
    notifyListeners();
    final client = _client;
    if (client == null) return;
    try {
      await client
          .from('notifications')
          .update({'read_at': now.toIso8601String()})
          .eq('user_id', client.auth.currentUser!.id)
          .filter('read_at', 'is', 'null');
    } catch (e) {
      debugPrint('markAllRead: $e');
    }
  }

  void _subscribeRealtime() {
    final client = _client;
    final siteId = _siteId;
    if (client == null || siteId == null) return;
    final siteFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'site_id',
      value: siteId,
    );
    final uid = client.auth.currentUser?.id;
    _channel = client
        .channel('site:$siteId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tickets',
          filter: siteFilter,
          callback: (_) => _safeReload(_loadTickets),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'alerts',
          filter: siteFilter,
          callback: (_) => _safeReload(_loadAlerts),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'maintenance_visits',
          filter: siteFilter,
          callback: (_) => _safeReload(_loadVisits),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: uid == null
              ? null
              : PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'user_id',
                  value: uid,
                ),
          callback: (_) => _safeReload(_loadNotifications),
        )
        .subscribe();
  }

  Future<void> _safeReload(Future<void> Function() loader) async {
    try {
      await loader();
      notifyListeners();
    } catch (e) {
      debugPrint('SiteController reload: $e');
    }
  }

  /// Crée un ticket. Retourne null si succès, sinon un message d'erreur.
  Future<String?> createTicket({
    required String title,
    required String equipmentId,
    required String description,
    Uint8List? photoBytes,
    String photoExtension = 'jpg',
  }) async {
    final equipmentLabel = equipment
        .where((e) => e.id == equipmentId)
        .map((e) => '${e.id} · ${e.name}')
        .followedBy([equipmentId])
        .first;

    if (_client == null) {
      // Mode démo : ajout local (+ pollers d'événements).
      tickets = List.of(tickets)
        ..insert(
          0,
          Ticket(
            id: 'TK-${2042 + tickets.length}',
            title: title,
            equipment: equipmentLabel,
            description: description,
            status: TicketStatus.pending,
            openedAt: DateTime.now(),
            hasPhoto: photoBytes != null,
          ),
        );
      _syncEventPollers();
      notifyListeners();
      return null;
    }

    final uid = _client.auth.currentUser?.id;
    if (uid == null) return 'Session expirée — reconnectez-vous.';

    try {
      // Upload de la photo dans le bucket privé (chemin : {site_id}/{…}).
      String? photoPath;
      if (photoBytes != null) {
        final ext = photoExtension.replaceAll('.', '').toLowerCase();
        final safeExt = switch (ext) {
          'png' => 'png',
          'webp' => 'webp',
          'heic' || 'heif' => 'heic',
          _ => 'jpg',
        };
        final rand = Random().nextInt(0x7FFFFFFF);
        photoPath =
            '$_siteId/${DateTime.now().microsecondsSinceEpoch}-$rand.$safeExt';
        await _client.storage
            .from('ticket-photos')
            .uploadBinary(
              photoPath,
              photoBytes,
              fileOptions: FileOptions(contentType: 'image/$safeExt'),
            );
      }

      await _client.from('tickets').insert({
        'site_id': _siteId,
        'equipment_id': equipmentId,
        'title': title,
        'description': description,
        'status': 'pending',
        'opened_by': uid,
        'photo_url': ?photoPath,
      });
      await _safeReload(_loadTickets);
      return null;
    } catch (e) {
      debugPrint('createTicket: $e');
      return 'Envoi impossible. Vérifiez votre connexion et réessayez.';
    }
  }

  /// Demande d'extension d'installation : ticket global SANS équipement
  /// précis (porte sur l'installation entière — ajout caméras/équipements).
  /// Retourne null si succès.
  Future<String?> createExtensionRequest({required String description}) async {
    final uid = _client?.auth.currentUser?.id;
    if (_client == null || uid == null) {
      return 'Session expirée — reconnectez-vous.';
    }

    try {
      await _client.from('tickets').insert({
        'site_id': _siteId,
        'equipment_id': null,
        'title': "Demande d'extension d'installation",
        'description': description,
        'status': 'pending',
        'opened_by': uid,
      });
      await _safeReload(_loadTickets);
      return null;
    } catch (e) {
      debugPrint('createExtensionRequest: $e');
      return 'Envoi impossible. Vérifiez votre connexion et réessayez.';
    }
  }

  /// Génère l'URL RTSP d'un canal selon la marque (adaptateurs par
  /// constructeur). Utilise le flux SECONDAIRE (plus léger — idéal
  /// mobile/réseau CI).
  ///
  /// Chemins documentés par marque :
  ///  - Hikvision : `/Streaming/Channels/{ch}02` (chX0Y : Y=2 → sous-flux)
  ///  - Dahua     : `/cam/realmonitor?channel={ch}&subtype=1`
  ///  - Imou      : gamme grand public de Dahua → mêmes chemins que Dahua
  ///  - Axis      : `/axis-media/media.amp` (VAPIX) — le sous-flux se
  ///                demande par paramètres de résolution/débit
  ///  - Uniview   : `/unicast/c{ch}/s1/live` (s0 = principal, s1 = secondaire)
  static String rtspUrlFor({
    required String brand,
    required String host,
    required String port,
    required String user,
    required String password,
    required int channel,
  }) {
    final creds =
        '${Uri.encodeComponent(user)}:${Uri.encodeComponent(password)}';
    final path = switch (brand) {
      'Hikvision' =>
        '/Streaming/Channels/${channel}02', // chX0Y : Y=2 → flux secondaire
      'Dahua' => '/cam/realmonitor?channel=$channel&subtype=1',
      'Imou' => '/cam/realmonitor?channel=$channel&subtype=1',
      'Axis' =>
        '/axis-media/media.amp?camera=$channel'
            '&videocodec=h264&resolution=640x360&fps=15',
      'Uniview' => '/unicast/c$channel/s1/live',
      _ => '/Streaming/Channels/${channel}02',
    };
    return 'rtsp://$creds@$host:$port$path';
  }

  /// Assistant « Connecter un NVR » : crée automatiquement une caméra
  /// par canal, avec son flux RTSP. Retourne null si succès.
  ///
  /// [remote] : accès distant par IP publique / domaine (redirection de
  /// port sur le routeur du client) — méthode « IP directe » type
  /// iDMSS / tinyCam. L'hôte et le port utilisés sont alors publics.
  Future<String?> connectNvr({
    required String brand,
    required String host,
    required String port,
    required String user,
    required String password,
    required int channels,
    String namePrefix = 'Caméra',
    bool remote = false,
  }) async {
    if (channels < 1 || channels > 32) {
      return 'Nombre de canaux invalide (1 à 32).';
    }

    final now = DateTime.now();
    final created = List<int>.generate(channels, (i) => i + 1);

    if (_client == null) {
      // Mode démo : ajout local (+ pollers d'événements).
      equipment = [
        ...equipment,
        ...created.map(
          (ch) => Equipment(
            id: 'CAM-$now-$ch',
            name: '$namePrefix $ch',
            model: remote ? 'NVR $brand · distant' : 'NVR $brand',
            serial: 'NVR-${now.millisecondsSinceEpoch}-$ch',
            location: remote ? 'Accès distant · Canal $ch' : 'Canal $ch',
            category: EquipmentCategory.camera,
            installedAt: now,
            streamUrl: rtspUrlFor(
              brand: brand,
              host: host,
              port: port,
              user: user,
              password: password,
              channel: ch,
            ),
          ),
        ),
      ];
      _syncEventPollers();
      notifyListeners();
      return null;
    }

    final stamp = now.millisecondsSinceEpoch;
    try {
      await _client.from('equipment').insert([
        for (final ch in created)
          {
            'site_id': _siteId,
            'name': '$namePrefix $ch',
            'model': remote ? 'NVR $brand · distant' : 'NVR $brand',
            'serial': 'NVR-$stamp-$ch',
            'location': remote ? 'Accès distant · Canal $ch' : 'Canal $ch',
            'category': 'camera',
            'installed_on': now.toIso8601String().substring(0, 10),
            'stream_url': rtspUrlFor(
              brand: brand,
              host: host,
              port: port,
              user: user,
              password: password,
              channel: ch,
            ),
          },
      ]);
      await _safeReload(_loadEquipment);
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('connectNvr: $e');
      return 'Création impossible. Vérifiez votre connexion.';
    }
  }

  /// Teste la joignabilité d'un hôte:port (IP publique, domaine DynDNS…)
  /// avant de connecter les caméras en accès distant. Retourne null si
  /// l'hôte répond, sinon un message d'aide pour l'installateur.
  static Future<String?> testEndpoint({
    required String host,
    required String port,
  }) async {
    final parsedPort = int.tryParse(port.trim());
    if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
      return 'Port invalide (1 à 65535).';
    }
    final target = host.trim();
    if (target.isEmpty) {
      return 'Renseignez l\'IP publique ou le domaine.';
    }
    try {
      final socket = await Socket.connect(
        target,
        parsedPort,
        timeout: const Duration(seconds: 6),
      );
      socket.destroy();
      return null;
    } on SocketException catch (e) {
      debugPrint('testEndpoint: $e');
      return 'Hôte injoignable — vérifiez l\'IP/le domaine et la '
          'redirection TCP $parsedPort → 554 sur le routeur.';
    } on ArgumentError {
      return 'Adresse invalide (caractères interdits dans l\'hôte).';
    } catch (e) {
      debugPrint('testEndpoint: $e');
      return 'Test impossible : $e';
    }
  }

  /// Ajoute une seule caméra via une URL de flux directe (marque
  /// exotique, serveur go2rtc…). Retourne null si succès.
  Future<String?> addCameraByUrl({
    required String name,
    required String url,
  }) async {
    if (url.trim().isEmpty) return 'URL de flux obligatoire.';

    if (_client == null) {
      equipment = [
        ...equipment,
        Equipment(
          id: 'CAM-${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          model: 'Flux direct',
          serial: 'URL-${DateTime.now().millisecondsSinceEpoch}',
          location: 'Direct',
          category: EquipmentCategory.camera,
          installedAt: DateTime.now(),
          streamUrl: url.trim(),
        ),
      ];
      notifyListeners();
      return null;
    }

    try {
      await _client.from('equipment').insert({
        'site_id': _siteId,
        'name': name,
        'model': 'Flux direct',
        'serial': 'URL-${DateTime.now().millisecondsSinceEpoch}',
        'location': 'Direct',
        'category': 'camera',
        'installed_on': DateTime.now().toIso8601String().substring(0, 10),
        'stream_url': url.trim(),
      });
      await _safeReload(_loadEquipment);
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('addCameraByUrl: $e');
      return 'Création impossible. Vérifiez votre connexion.';
    }
  }

  /// Ajoute des caméras via ONVIF (standard multi-marques) : chaque profil
  /// sélectionné devient une caméra avec son URL RTSP fournie par
  /// l'appareil lui-même (GetStreamUri). [cameraName] surcharge le nom.
  /// Retourne null si succès, sinon un message d'erreur.
  Future<String?> addOnvifCameras({
    required OnvifDevice device,
    required List<OnvifProfile> profiles,
    String Function(OnvifProfile profile)? cameraName,
  }) async {
    if (profiles.isEmpty) {
      return 'Aucun profil sélectionné.';
    }

    final now = DateTime.now();
    final stamp = now.millisecondsSinceEpoch;

    // Résout les URLs RTSP de chaque profil avant toute écriture.
    final List<({OnvifProfile profile, String url})> resolved;
    try {
      resolved = [
        for (final p in profiles)
          (
            profile: p,
            url: await device.getStreamUri(
              token: p.token,
              user: device.user,
              password: device.password,
            ),
          ),
      ];
    } on OnvifException catch (e) {
      return e.message;
    }

    final deviceLabel = device.host;

    if (_client == null) {
      // Mode démo : ajout local (+ pollers d'événements).
      equipment = [
        ...equipment,
        ...resolved.map(
          (r) => Equipment(
            id: 'CAM-$stamp-${r.profile.token.hashCode.abs()}',
            name:
                cameraName?.call(r.profile) ??
                '${r.profile.name} · $deviceLabel',
            model:
                'ONVIF · ${r.profile.resolutionLabel}'
                '${r.profile.hasPtz ? ' · PTZ' : ''}'
                '${r.profile.hasAudio ? ' · AUDIO' : ''}',
            serial: 'ONVIF-$stamp-${r.profile.token.hashCode.abs()}',
            location: r.profile.isMainStream
                ? 'Flux principal'
                : 'Flux secondaire',
            category: EquipmentCategory.camera,
            installedAt: now,
            streamUrl: r.url,
          ),
        ),
      ];
      _syncEventPollers();
      notifyListeners();
      return null;
    }

    try {
      await _client.from('equipment').insert([
        for (final r in resolved)
          {
            'site_id': _siteId,
            'name':
                cameraName?.call(r.profile) ??
                '${r.profile.name} · $deviceLabel',
            'model':
                'ONVIF · ${r.profile.resolutionLabel}'
                '${r.profile.hasPtz ? ' · PTZ' : ''}'
                '${r.profile.hasAudio ? ' · AUDIO' : ''}',
            'serial': 'ONVIF-$stamp-${r.profile.token.hashCode.abs()}',
            'location': r.profile.isMainStream
                ? 'Flux principal'
                : 'Flux secondaire',
            'category': 'camera',
            'installed_on': now.toIso8601String().substring(0, 10),
            'stream_url': r.url,
          },
      ]);
      await _safeReload(_loadEquipment);
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('addOnvifCameras: $e');
      return 'Création impossible. Vérifiez votre connexion.';
    }
  }

  /// Ajoute des caméras relayées par un serveur go2rtc (méthode « relais ») :
  /// un seul point d'accès HTTP par site, pas de RTSP exposé, aucune
  /// redirection de port par caméra. [streams] sont les flux choisis sur
  /// le serveur. [locationLabel] surcharge la localisation affichée
  /// (ex: « Cloud · EYE-7F3K2 »). Retourne null si succès.
  Future<String?> addGo2rtcCameras({
    required Go2rtcServer server,
    required List<Go2rtcStream> streams,
    String? locationLabel,
  }) async {
    if (streams.isEmpty) {
      return 'Aucun flux sélectionné.';
    }

    final now = DateTime.now();
    final stamp = now.millisecondsSinceEpoch;
    final serverLabel = server.hostLabel;
    final location = locationLabel ?? 'Relais $serverLabel';

    if (_client == null) {
      // Mode démo : ajout local (+ pollers d'événements).
      equipment = [
        ...equipment,
        ...streams.map(
          (s) => Equipment(
            id: 'CAM-$stamp-${s.name.hashCode.abs()}',
            name: s.name,
            model: 'go2rtc · relais',
            serial: 'G2RTC-$stamp-${s.name.hashCode.abs()}',
            location: location,
            category: EquipmentCategory.camera,
            installedAt: now,
            streamUrl: server.hlsUrl(s.name),
          ),
        ),
      ];
      _syncEventPollers();
      notifyListeners();
      return null;
    }

    try {
      await _client.from('equipment').insert([
        for (final s in streams)
          {
            'site_id': _siteId,
            'name': s.name,
            'model': 'go2rtc · relais',
            'serial': 'G2RTC-$stamp-${s.name.hashCode.abs()}',
            'location': location,
            'category': 'camera',
            'installed_on': now.toIso8601String().substring(0, 10),
            'stream_url': server.hlsUrl(s.name),
          },
      ]);
      await _safeReload(_loadEquipment);
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('addGo2rtcCameras: $e');
      return 'Création impossible. Vérifiez votre connexion.';
    }
  }

  /// URL du cloud EyeSafe mémorisée sur l'appareil (saisie une seule fois
  /// par le technicien). Vide → valeur par défaut.
  static const _cloudUrlPrefsKey = 'eyesafe_cloud_url';
  static const defaultCloudUrl = 'https://cloud.eyesafe.ci';

  Future<String> loadCloudUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_cloudUrlPrefsKey) ?? defaultCloudUrl;
    } catch (_) {
      return defaultCloudUrl;
    }
  }

  Future<void> saveCloudUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cloudUrlPrefsKey, url.trim());
    } catch (_) {
      // Mémoire indisponible : la saisie restera volatile.
    }
  }

  /// Ajoute des caméras via l'API propriétaire de la marque (adaptateurs
  /// ISAPI/VAPIX/LAPI — « SDK » HTTP du constructeur) : modèle et n° série
  /// réels du deviceInfo, URL RTSP construite par l'adaptateur de marque.
  /// [motionDetection] (Hikvision uniquement) active l'alerte intrusion.
  /// Retourne null si succès.
  Future<String?> addBrandCameras({
    required String brand,
    required String host,
    required int httpPort,
    required int rtspPort,
    required String user,
    required String password,
    required bool allowSelfSigned,
    required IsapiDeviceInfo info,
    required List<IsapiChannel> channels,
    bool motionDetection = false,
  }) async {
    if (channels.isEmpty) {
      return 'Aucun canal sélectionné.';
    }

    final now = DateTime.now();
    final stamp = now.millisecondsSinceEpoch;
    final creds =
        '${Uri.encodeComponent(user)}:'
        '${Uri.encodeComponent(password)}';

    // Préfixe du libellé selon l'API de la marque.
    final apiLabel = switch (brand) {
      'Axis' => 'VAPIX',
      'Uniview' => 'LAPI',
      'Dahua' => 'DAHUA',
      _ => 'ISAPI',
    };

    // URL RTSP du canal : Hikvision → chemin ISAPI exact du canal ;
    // Axis/Uniview → adaptateur de chemin de rtspUrlFor.
    String streamUrlFor(IsapiChannel c) => brand == 'Hikvision'
        ? 'rtsp://$creds@$host:$rtspPort/Streaming/Channels/${c.id}'
        : rtspUrlFor(
            brand: brand,
            host: host,
            port: '$rtspPort',
            user: user,
            password: password,
            channel: c.cameraNumber,
          );

    // Capacités PTZ : interrogées uniquement via ISAPI (Hikvision).
    final ptzCameras = <int>{};
    if (brand == 'Hikvision') {
      final device = IsapiDevice(
        host: host,
        httpPort: httpPort,
        user: user,
        password: password,
        allowSelfSigned: allowSelfSigned,
      );
      for (final n in channels.map((c) => c.cameraNumber).toSet()) {
        try {
          if (await device.hasPtzChannel(n)) ptzCameras.add(n);
        } catch (e) {
          debugPrint('hasPtzChannel($n): $e');
        }
      }
    }

    if (_client == null) {
      // Mode démo : ajout local (+ pollers d'événements).
      equipment = [
        ...equipment,
        ...channels.map(
          (c) => Equipment(
            id: 'CAM-$stamp-${c.id}',
            name: c.name == 'Canal ${c.id}'
                ? 'Caméra ${c.cameraNumber}'
                : c.name,
            model:
                '$apiLabel · ${info.model.isEmpty ? brand : info.model}'
                '${c.isMainStream ? '' : ' · sub'}'
                '${ptzCameras.contains(c.cameraNumber) ? ' · PTZ' : ''}',
            serial: '${info.serial.isEmpty ? apiLabel : info.serial}-${c.id}',
            location: c.isMainStream ? 'Flux principal' : 'Flux secondaire',
            category: EquipmentCategory.camera,
            installedAt: now,
            streamUrl: streamUrlFor(c),
          ),
        ),
      ];
      _syncEventPollers();
      notifyListeners();
      if (motionDetection && brand == 'Hikvision') {
        await _applyMotionBestEffort(
          IsapiDevice(
            host: host,
            httpPort: httpPort,
            user: user,
            password: password,
            allowSelfSigned: allowSelfSigned,
          ),
          channels,
        );
      }
      return null;
    }

    try {
      await _client.from('equipment').insert([
        for (final c in channels)
          {
            'site_id': _siteId,
            'name': c.name == 'Canal ${c.id}'
                ? 'Caméra ${c.cameraNumber}'
                : c.name,
            'model':
                '$apiLabel · ${info.model.isEmpty ? brand : info.model}'
                '${c.isMainStream ? '' : ' · sub'}'
                '${ptzCameras.contains(c.cameraNumber) ? ' · PTZ' : ''}',
            'serial': '${info.serial.isEmpty ? apiLabel : info.serial}-${c.id}',
            'location': c.isMainStream ? 'Flux principal' : 'Flux secondaire',
            'category': 'camera',
            'installed_on': now.toIso8601String().substring(0, 10),
            'stream_url': streamUrlFor(c),
          },
      ]);
      await _safeReload(_loadEquipment);
      notifyListeners();
      if (motionDetection && brand == 'Hikvision') {
        await _applyMotionBestEffort(
          IsapiDevice(
            host: host,
            httpPort: httpPort,
            user: user,
            password: password,
            allowSelfSigned: allowSelfSigned,
          ),
          channels,
        );
      }
      return null;
    } catch (e) {
      debugPrint('addBrandCameras: $e');
      return 'Création impossible. Vérifiez votre connexion.';
    }
  }

  /// Applique la détection de mouvement sur les caméras distinctes
  /// (ignore les échecs — certains appareils ne l'exposent pas).
  Future<void> _applyMotionBestEffort(
    IsapiDevice device,
    List<IsapiChannel> channels,
  ) async {
    final cameras = channels.map((c) => c.cameraNumber).toSet();
    for (final n in cameras) {
      try {
        await device.setMotionDetection(n, true);
      } catch (e) {
        debugPrint('setMotionDetection($n): $e');
      }
    }
  }

  /// URL de flux AUTORISÉE côté serveur pour un direct/playback/PTZ.
  ///
  /// « Ne jamais faire confiance au client » : en mode live, la RPC
  /// `get_stream_url` vérifie pour CHAQUE requête que l'utilisateur
  /// est propriétaire du site ou technicien assigné (tenant + rôle),
  /// et journalise l'accès. En mode démo, retourne l'URL stockée.
  /// Retourne null si l'accès est refusé.
  Future<String?> authorizedStreamUrl(Equipment camera) async {
    final client = _client;
    if (client == null) return camera.streamUrl;
    try {
      final result = await client.rpc(
        'get_stream_url',
        params: {'p_equipment': camera.id},
      );
      return (result as String?)?.trim().isNotEmpty == true
          ? result as String
          : null;
    } catch (e) {
      debugPrint('authorizedStreamUrl: $e');
      // RPC absente (migration non appliquée) → repli sur la ligne lue
      // (la policy equipment_select a déjà filtré par tenant).
      return camera.streamUrl;
    }
  }

  /// Le contrôle PTZ (action physique sensible) est vérifié côté serveur
  /// pour CHAQUE usage — tenant + rôle, journalisé (action 'ptz').
  /// En mode démo : autorisé. Repli si la migration n'est pas appliquée :
  /// l'accès au flux vaut accès PTZ.
  Future<bool> authorizedPtzControl(Equipment camera) async {
    final client = _client;
    if (client == null) return true;
    try {
      final result = await client.rpc(
        'can_control_ptz',
        params: {'p_equipment': camera.id},
      );
      return result == true;
    } catch (e) {
      debugPrint('authorizedPtzControl: $e');
      return camera.streamUrl != null;
    }
  }

  /// Déconnecte / retire un équipement (caméra connectée via NVR, ONVIF,
  /// relais go2rtc…). Retourne null si succès, sinon un message d'erreur.
  Future<String?> removeEquipment(Equipment item) async {
    if (_client == null) {
      // Mode démo : suppression locale.
      equipment = equipment.where((e) => e.id != item.id).toList();
      _syncEventPollers();
      notifyListeners();
      return null;
    }

    try {
      await _client.from('equipment').delete().eq('id', item.id);
      await _safeReload(_loadEquipment);
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('removeEquipment: $e');
      return 'Suppression impossible. Vérifiez votre connexion.';
    }
  }

  /// URL signée temporaire (1 h) pour afficher une photo de ticket
  /// stockée dans le bucket privé. Mise en cache par chemin.
  Future<String?> signedPhotoUrl(String? path) async {
    if (path == null || _client == null) return null;
    final cached = _signedUrlCache[path];
    if (cached != null) return cached;
    try {
      final url = await _client.storage
          .from('ticket-photos')
          .createSignedUrl(path, 3600);
      _signedUrlCache[path] = url;
      return url;
    } catch (e) {
      debugPrint('signedPhotoUrl: $e');
      return null;
    }
  }

  final Map<String, String> _signedUrlCache = {};

  /// URL réelle du rapport d'intervention PDF :
  /// - `reportRef` déjà absolu (http/https) → retournée telle quelle ;
  /// - sinon considérée comme chemin du bucket privé
  ///   `maintenance-reports` → URL signée temporaire (1 h, mise en cache).
  /// Retourne null si le rapport est indisponible.
  Future<String?> signedReportUrl(String? reportRef) async {
    if (reportRef == null || reportRef.trim().isEmpty) return null;
    final ref = reportRef.trim();
    if (ref.startsWith('http://') || ref.startsWith('https://')) return ref;
    final client = _client;
    if (client == null) return null;
    final cached = _signedUrlCache[ref];
    if (cached != null) return cached;
    try {
      final url = await client.storage
          .from('maintenance-reports')
          .createSignedUrl(ref, 3600);
      _signedUrlCache[ref] = url;
      return url;
    } catch (e) {
      debugPrint('signedReportUrl: $e');
      return null;
    }
  }

  /// Préférence « rappels automatiques » de la page Entretien,
  /// mémorisée par site sur l'appareil.
  static const _remindersPrefsPrefix = 'maintenance_reminders_';

  Future<bool> loadMaintenanceReminders() async {
    final siteId = _siteId ?? 'default';
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_remindersPrefsPrefix$siteId') ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> saveMaintenanceReminders(bool enabled) async {
    final siteId = _siteId ?? 'default';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_remindersPrefsPrefix$siteId', enabled);
    } catch (_) {
      /* préférence non critique */
    }
  }

  /// Réponse du technicien à un signalement : passe le ticket en
  /// « en route » avec un délai d'intervention et une note éventuelle.
  /// Retourne null si succès, sinon un message d'erreur.
  Future<String?> respondToTicket({
    required Ticket ticket,
    required DateTime deadline,
    String? note,
  }) async {
    if (_client == null) {
      // Mode démo : mise à jour locale.
      tickets = tickets
          .map(
            (t) => t.id == ticket.id
                ? Ticket(
                    id: t.id,
                    dbId: t.dbId,
                    title: t.title,
                    equipment: t.equipment,
                    description: t.description,
                    status: TicketStatus.enRoute,
                    openedAt: t.openedAt,
                    hasPhoto: t.hasPhoto,
                    interventionAt: deadline,
                    technicianNote: note,
                  )
                : t,
          )
          .toList();
      notifyListeners();
      return null;
    }

    final uid = _client.auth.currentUser?.id;
    if (uid == null) return 'Session expirée — reconnectez-vous.';
    if (ticket.dbId.isEmpty) return 'Ticket introuvable.';

    try {
      await _client
          .from('tickets')
          .update({
            'status': 'en_route',
            'intervention_deadline': deadline.toUtc().toIso8601String(),
            'technician_note': (note == null || note.trim().isEmpty)
                ? null
                : note.trim(),
            'assigned_to': uid,
            'responded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', ticket.dbId);
      await _safeReload(_loadTickets);
      return null;
    } catch (e) {
      debugPrint('respondToTicket: $e');
      return 'Réponse impossible. Vérifiez votre connexion et réessayez.';
    }
  }

  @override
  void dispose() {
    stopEventPollers();
    final channel = _channel;
    final client = _client;
    if (channel != null && client != null) {
      // Fire-and-forget : la socket sera fermée peu après.
      client.removeChannel(channel);
    }
    _channel = null;
    super.dispose();
  }
}

/// Événement caméra centralisé dans [SiteController] : l'alarme ONVIF
/// enrichie de la caméra émettrice et de l'heure de réception locale.
class CameraEventRecord {
  const CameraEventRecord({
    required this.cameraId,
    required this.cameraName,
    required this.event,
    required this.receivedAt,
  });

  final String cameraId;
  final String cameraName;
  final OnvifEvent event;
  final DateTime receivedAt;
}

/// Un poller d'événements ONVIF (PullPoint) par caméra connectée.
///
/// Cycle de vie :
///  1. [start] → souscription PullPoint (PT1M par défaut)
///  2. `_pullTimer` → pull toutes les 3 s (garde anti-chevauchement :
///     un long-poll lent ne cumule jamais les requêtes)
///  3. `_renewTimer` → renouvellement à mi-vie (expiration / 2)
///  4. chaque événement → [SiteController.recordEvent]
///  5. [stop] → `unsubscribe` propre
///
/// Auto-réparation : souscription expirée ou caméra injoignable →
/// re-souscription après un repos (jamais d'exception vers l'UI).
class CameraEventPoller {
  CameraEventPoller({
    required this.camera,
    required this.controller,
    this._pullInterval = const Duration(seconds: 3),
  });

  final Equipment camera;
  final SiteController controller;
  final Duration _pullInterval;

  Timer? _renewTimer;
  Timer? _pullTimer;
  PullPointSubscription? _subscription;
  bool _pulling = false;
  bool _stopped = false;

  /// La caméra expose-t-elle un flux RTSP avec identifiants ONVIF ?
  /// (les relais go2rtc/cloud n'ont pas de PullPoint direct.)
  late final bool isSupported = _resolveSupport();

  Uri? _deviceUri;
  OnvifCredentials? _creds;

  bool _resolveSupport() {
    final url = Uri.tryParse(camera.streamUrl ?? '');
    if (url == null || !url.isScheme('rtsp')) return false;
    final parts = url.userInfo.split(':');
    if (parts.length < 2 || parts[0].isEmpty) return false;
    _creds = OnvifCredentials(
      user: Uri.decodeComponent(parts[0]),
      password: Uri.decodeComponent(parts.sublist(1).join(':')),
    );
    _deviceUri = Uri(
      scheme: 'http',
      host: url.host,
      port: url.hasPort ? url.port : 80,
      path: '/onvif/device_service',
    );
    return true;
  }

  /// Démarre la boucle (silencieux si non supporté).
  Future<void> start() async {
    if (_stopped || !isSupported) return;
    await _subscribe();
  }

  Future<void> _subscribe() async {
    if (_stopped) return;
    try {
      final sub = await createPullPointSubscription(
        _deviceUri!.toString(),
        _creds!,
      );
      if (_stopped) {
        // Arrêté pendant la souscription → libérer immédiatement.
        await unsubscribe(sub.url, _creds!).catchError((_) {});
        return;
      }
      _subscription = sub;
      _armTimers(sub);
    } catch (e) {
      debugPrint(
        'CameraEventPoller(${camera.name}): souscription échouée '
        '($e) — nouvelle tentative dans 30 s',
      );
      if (!_stopped) {
        Timer(const Duration(seconds: 30), _subscribe);
      }
    }
  }

  void _armTimers(PullPointSubscription sub) {
    _pullTimer?.cancel();
    _renewTimer?.cancel();

    _pullTimer = Timer.periodic(_pullInterval, (_) => unawaited(_pull()));

    // Renouvellement à mi-vie (expiration / 2), borné 5–60 s.
    var half = const Duration(seconds: 30);
    if (sub.terminationTime != null && sub.currentTime != null) {
      final life = sub.terminationTime!.difference(sub.currentTime!);
      if (life.inSeconds > 0) half = life * 0.5;
    }
    if (half.inSeconds < 5) half = const Duration(seconds: 5);
    if (half.inSeconds > 60) half = const Duration(seconds: 60);
    _renewTimer = Timer.periodic(half, (_) => unawaited(_renew()));
  }

  Future<void> _pull() async {
    // Garde anti-chevauchement : un long-poll lent ne doit jamais
    // empiler les requêtes (le tick suivant est simplement ignoré).
    if (_pulling || _stopped || _subscription == null) return;
    _pulling = true;
    try {
      final events = await pullMessages(
        _subscription!.url,
        _creds!,
        timeout: _pullInterval + const Duration(seconds: 2),
      );
      for (final e in events) {
        controller.recordEvent(camera, e);
      }
    } catch (e) {
      // Souscription expirée (TerminationTime dépassé) ou réseau coupé :
      // on re-souscrit from scratch au prochain cycle.
      debugPrint('CameraEventPoller(${camera.name}): pull échoué ($e)');
      await _resubscribe();
    } finally {
      _pulling = false;
    }
  }

  Future<void> _renew() async {
    final sub = _subscription;
    if (sub == null || _stopped) return;
    try {
      await renewSubscription(
        sub.url,
        _creds!,
        terminationTime: const Duration(minutes: 1),
      );
    } catch (e) {
      debugPrint('CameraEventPoller(${camera.name}): renew échoué ($e)');
      await _resubscribe();
    }
  }

  Future<void> _resubscribe() async {
    _cancelTimers();
    _subscription = null;
    if (!_stopped) await _subscribe();
  }

  void _cancelTimers() {
    _pullTimer?.cancel();
    _pullTimer = null;
    _renewTimer?.cancel();
    _renewTimer = null;
  }

  /// Arrête la boucle et libère la souscription côté appareil.
  Future<void> stop() async {
    _stopped = true;
    _cancelTimers();
    final sub = _subscription;
    _subscription = null;
    if (sub != null) {
      try {
        await unsubscribe(sub.url, _creds!);
      } catch (e) {
        // Appareil déjà parti : on ignore.
        debugPrint('CameraEventPoller.stop: $e');
      }
    }
  }
}
