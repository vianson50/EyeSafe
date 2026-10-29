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
}
