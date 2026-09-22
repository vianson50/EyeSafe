import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Mode d'affichage d'une tuile caméra dans la mosaïque.
enum PreviewMode {
  /// Aperçu live (WebRTC sub-stream) — réservé aux N premières caméras.
  live,

  /// Snapshot JPG rafraîchi périodiquement (5 s) — bande passante minimale.
  snapshot,
}

/// Ordonnanceur de bande passante de la mosaïque.
///
/// Une mosaïque 4×4 = 16 caméras : impossible de lire 16 flux simultanés
/// sur une 4G ou un ADSL client. Règles appliquées :
///
///  1. **Limite configurable** de flux live simultanés ([maxLivePreviews],
///     défaut 4, mémorisé sur l'appareil) — les caméras au-delà passent en
///     snapshot périodique.
///  2. **Priorité** : les premières caméras de la liste reçoivent le live
///     (ordre d'affichage de la mosaïque).
///  3. **Dégradation automatique** : la durée de récupération d'un snapshot
///     sert de sonde de congestion (> 3 s = réseau saturé → un flux live
///     de moins ; < 1 s = réseau sain → un flux de plus). Borné à
///     [minLivePreviews]..[maxLivePreviews], avec hystérésis de 10 s.
///
/// Les flux eux-mêmes sont déjà des sous-flux (sub-stream 640×360) :
/// les URLs NVR/ISAPI construites par l'app ciblent le flux secondaire,
/// et côté go2rtc le `src` expose le sous-flux configuré sur le serveur.
class StreamScheduler {
  StreamScheduler({
    int maxLivePreviews = defaultMaxLivePreviews,
    DateTime Function()? now,
  }) : _maxLive = maxLivePreviews.clamp(1, 16),
       _now = now ?? DateTime.now {
    _activeLimit = _maxLive;
  }

  static const defaultMaxLivePreviews = 4;
  static const _prefsKey = 'eyesafe_max_live_previews';
  static const minLivePreviews = 1;

  final DateTime Function() _now;

  int _maxLive;
  int _activeLimit = defaultMaxLivePreviews;
  List<String> _order = const [];
  DateTime _lastAdjust = DateTime.fromMillisecondsSinceEpoch(0);

  /// Limite maximale configurée par l'installateur.
  int get maxLivePreviews => _maxLive;

  /// Limite effective actuelle (ajustée par la congestion réseau).
  int get activeLimit => _activeLimit;

  /// Ordre courant des caméras (celles de la mosaïque).
  List<String> get order => List.unmodifiable(_order);

  /// Met à jour la liste des caméras affichées (silencieux : la mosaïque
  /// est reconstruite par l'appelant, pas besoin de notification).
  void updateCameras(List<String> cameraIds) {
    _order = List.of(cameraIds);
  }

  /// Mode d'affichage d'une caméra : live pour les [activeLimit]
  /// premières de la mosaïque, snapshot pour les autres.
  PreviewMode modeFor(String cameraId) {
    final index = _order.indexOf(cameraId);
    if (index < 0) return PreviewMode.snapshot;
    return index < _activeLimit ? PreviewMode.live : PreviewMode.snapshot;
  }

  /// Change la limite maximale (réglage installateur).
  void setMaxLivePreviews(int value) {
    _maxLive = value.clamp(minLivePreviews, 16);
    if (_activeLimit > _maxLive) _activeLimit = _maxLive;
  }

  /// Sonde de congestion : durée de récupération d'un snapshot.
  /// Voir la doc de classe pour les seuils et l'hystérésis.
  void reportProbeDuration(Duration duration) {
    final now = _now();
    if (now.difference(_lastAdjust) < const Duration(seconds: 10)) return;

    if (duration > const Duration(seconds: 3) &&
        _activeLimit > minLivePreviews) {
      _activeLimit--;
      _lastAdjust = now;
    } else if (duration < const Duration(seconds: 1) &&
        _activeLimit < _maxLive) {
      _activeLimit = min(_activeLimit + 1, _maxLive);
      _lastAdjust = now;
    }
  }

  /// Recharge la limite mémorisée (best-effort, sans effet en test).
  Future<void> loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_prefsKey);
      if (stored != null) setMaxLivePreviews(stored);
    } catch (_) {
      // Stockage indisponible (mode démo/test) : valeur par défaut.
    }
  }

  /// Mémorise la limite choisie par l'installateur.
  Future<void> savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, _maxLive);
    } catch (_) {
      // Stockage indisponible : réglage volatile.
    }
  }
}
