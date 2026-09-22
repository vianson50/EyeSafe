/// Configuration ICE (STUN/TURN) pour les connexions WebRTC.
///
/// Modèle P2P à grande échelle : on tente d'abord le direct par
/// « hole punching » UDP (STUN) ; si le NAT est trop restrictif
/// (NAT symétrique, 4G entreprise), le relais TURN prend le relais —
/// sinon l'app retombe sur le HLS cloud, plus lourd en bande passante
/// serveur et en latence.
///
/// Réglage technicien (mémorisé sur l'appareil) : STUN par défaut Google ;
/// TURN optionnel (ex: coturn `turn:turn.mondomaine.ci:3478`).
library;

import 'package:shared_preferences/shared_preferences.dart';

class RtcConfig {
  RtcConfig._();

  static const _stunKey = 'eyesafe_stun_urls';
  static const _turnUrlKey = 'eyesafe_turn_url';
  static const _turnUserKey = 'eyesafe_turn_user';
  static const _turnPassKey = 'eyesafe_turn_pass';

  static const defaultStunUrls = 'stun:stun.l.google.com:19302';

  static List<Map<String, dynamic>>? _cachedIceServers;

  /// Construit la liste iceServers pour `createPeerConnection`.
  /// STUN multiples acceptés (séparés virgule/retour ligne) ; TURN
  /// optionnel avec identifiants.
  static List<Map<String, dynamic>> buildIceServers({
    String stunUrls = defaultStunUrls,
    String turnUrl = '',
    String turnUser = '',
    String turnPass = '',
  }) {
    final servers = <Map<String, dynamic>>[
      for (final u in stunUrls.split(RegExp(r'[,\n]')))
        if (u.trim().isNotEmpty) {'urls': u.trim()},
    ];
    if (servers.isEmpty) {
      servers.add({'urls': defaultStunUrls});
    }
    final turn = turnUrl.trim();
    if (turn.isNotEmpty) {
      servers.add({
        'urls': turn,
        if (turnUser.trim().isNotEmpty) 'username': turnUser.trim(),
        if (turnPass.isNotEmpty) 'credential': turnPass,
      });
    }
    return servers;
  }

  /// Charge les réglages complets (pré-remplissage du dialogue).
  static Future<
    ({String stunUrls, String turnUrl, String turnUser, String turnPass})
  >
  loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (
        stunUrls: prefs.getString(_stunKey) ?? defaultStunUrls,
        turnUrl: prefs.getString(_turnUrlKey) ?? '',
        turnUser: prefs.getString(_turnUserKey) ?? '',
        turnPass: prefs.getString(_turnPassKey) ?? '',
      );
    } catch (_) {
      return (
        stunUrls: defaultStunUrls,
        turnUrl: '',
        turnUser: '',
        turnPass: '',
      );
    }
  }

  /// iceServers prêts à l'emploi (mis en cache après le premier accès —
  /// les tuiles de la mosaïque ouvrent plusieurs connexions d'affilée).
  static Future<List<Map<String, dynamic>>> loadIceServers() async {
    final cached = _cachedIceServers;
    if (cached != null) return cached;
    final settings = await loadAll();
    final servers = buildIceServers(
      stunUrls: settings.stunUrls,
      turnUrl: settings.turnUrl,
      turnUser: settings.turnUser,
      turnPass: settings.turnPass,
    );
    _cachedIceServers = servers;
    return servers;
  }

  /// Mémorise les réglages et rafraîchit le cache.
  static Future<void> save({
    required String stunUrls,
    required String turnUrl,
    required String turnUser,
    required String turnPass,
  }) async {
    _cachedIceServers = buildIceServers(
      stunUrls: stunUrls,
      turnUrl: turnUrl,
      turnUser: turnUser,
      turnPass: turnPass,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stunKey, stunUrls.trim());
      await prefs.setString(_turnUrlKey, turnUrl.trim());
      await prefs.setString(_turnUserKey, turnUser.trim());
      await prefs.setString(_turnPassKey, turnPass);
    } catch (_) {
      // Stockage indisponible : le cache mémoire garde le réglage volatile.
    }
  }
}
