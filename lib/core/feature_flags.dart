/// Feature flags — active/désactive des blocs fonctionnels sans supprimer le code.
///
/// ⚠️ Après retour terrain (oct. 2026) :
///   - CGNAT Orange CI bloque tout flux entrant → WebRTC/WHEP inutile à distance
///   - Le direct vidéo doit être simple : RTSP local ou go2rtc sur site suffisent
///   - Replay et talk-back multi-marques sont complexes et pas essentiels au support
///
/// Le code est conservé — remettre un flag à true réactive la fonctionnalité.
class FeatureFlags {
  FeatureFlags._();

  /// Direct vidéo plein écran (RTSP/HLS). Garder — c'est le cœur.
  static const bool enableVideoLive = true;

  /// WebRTC/WHEP pour latence < 1s. Désactivé : CGNAT Orange CI bloque,
  /// et le RTSP local suffit sur le WiFi du client.
  static const bool enableWebRtc = false;

  /// Aperçus WebRTC dans la mosaïque (tuiles). Dépend de [enableWebRtc].
  static const bool enableTilePreviews = false;

  /// Replay ONVIF (Recording Search) + repli ISAPI. Complexe, pas critique.
  static const bool enableReplay = false;

  /// Talk-back Hikvision (ISAPI). Fonctionnel mais peu demandé.
  static const bool enableTalkBack = false;

  /// PTZ / filtre IR (ONVIF Imaging). Garder pour caméras motorisées sur site.
  static const bool enablePtz = true;

  /// Événements temps réel (PullPoint, badge mouvement, sons).
  /// Garder — c'est le cœur des alertes.
  static const bool enableEvents = true;

  /// Méthodes de connexion étendues : ONVIF découverte, API marque,
  /// relais go2rtc, cloud P2P, ngrok. Réduit à NVR LOCAL + IP/DOMAINE + URL.
  static const bool enableExtendedConnectMethods = false;

  /// Bande passante mosaïque (quota live, snapshots 5s).
  /// Garder — évite de saturer le réseau.
  static const bool enableBandwidthScheduler = true;

  // ═══════════════════════════════════════════════════════
  // Phase 2 — Signalement de panne
  // ═════════════════════════════════════════════════════

  /// Gravité sur les tickets (bloquant/dégradé/mineur).
  static const bool enableTicketSeverity = true;

  /// Bouton signalement express sur chaque tuile caméra.
  static const bool enableQuickReport = true;

  /// Badge HORS LIGNE renforcé.
  static const bool enableOfflineBadge = true;

  // ═════════════════════════════════════════════════════
  // Phase 3 — Diagnostic automatique
  // ═══════════════════════════════════════════════════

  /// Health check (Edge Function ping TCP 5 min, table equipment_health).
  static const bool enableHealthCheck = true; // Phase 3 — activé

  /// Badge uptime 7 jours sur le dashboard.
  static const bool enableUptimeBadge = true; // Phase 3 — activé

  // ═════════════════════════════════════════════════════
  // Phase 4 — Communication
  // ═══════════════════════════════════════════════════

  /// Chat par ticket (Supabase Realtime).
  static const bool enableTicketChat = true; // Phase 4 — activé

  /// Rappels de maintenance J-7/J-1.
  static const bool enableMaintenanceReminders = true; // Phase 4 — activé
}
