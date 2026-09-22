/// Écouteur d'événements ONVIF PullPoint par caméra (mouvement/intrusion).
///
/// Boucle d'arrière-plan par caméra ONVIF :
///  1. `createPullPointSubscription` (via ONVIF standard, repli auto)
///  2. `pullMessages` en long-poll (5 s) — bloque jusqu'à un événement
///  3. `renewSubscription` périodique (à mi-vie de la souscription)
///  4. `unsubscribe` à l'arrêt ([stop])
///
/// Silencieux par design : toute erreur (caméra non ONVIF, réseau coupé,
/// credentials refusés) est journalisée en debug puis la boucle reprend au
/// prochain cycle — une caméra qui tombe ne fait jamais planter la mosaïque.
///
/// Usage (dans un State de tuile) :
/// ```dart
/// final listener = OnvifEventsListener(
///   deviceUrl: 'http://192.168.1.64/onvif/device_service',
///   credentials: const OnvifCredentials(user: 'admin', password: '…'),
/// );
/// listener.events.listen((event) { … });
/// listener.start();            // initState
/// listener.stop();             // dispose
/// ```
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'onvif.dart';

class OnvifEventsListener {
  OnvifEventsListener({
    required this.deviceUrl,
    required this.credentials,
    this.onEvent,
    Duration? pullTimeout,
  }) : _pullTimeout = pullTimeout ?? const Duration(seconds: 5);

  /// URL de base de l'appareil (service device ONVIF).
  final String deviceUrl;

  /// Identifiants ONVIF (WS-Security Digest).
  final OnvifCredentials credentials;

  /// Callback d'événement (alarme mouvement, audio…). Appelé hors zone de
  /// build — utiliser un SchedulerBinding/addPostFrameCallback si un
  /// setState suit, ou préférer le flux [events].
  final void Function(OnvifEvent event)? onEvent;

  /// Durée d'un long-poll serveur.
  final Duration _pullTimeout;

  final _controller = StreamController<OnvifEvent>.broadcast();
  Timer? _cycle;
  bool _running = false;

  /// Dernière alarme de mouvement active reçue (null si aucune/finie).
  OnvifEvent? lastMotion;

  /// Flux broadcast des événements de la caméra.
  Stream<OnvifEvent> get events => _controller.stream;

  bool get isRunning => _running;

  /// Démarre la boucle d'écoute (idempotent).
  void start() {
    if (_running) return;
    _running = true;
    unawaited(_run());
  }

  /// Arrête la boucle et libère la souscription côté appareil.
  Future<void> stop() async {
    _running = false;
    _cycle?.cancel();
    _cycle = null;
    final sub = _subscription;
    _subscription = null;
    if (sub != null) {
      try {
        await unsubscribe(sub.url, credentials);
      } catch (e) {
        debugPrint('OnvifEventsListener.unsubscribe: $e');
      }
    }
  }

  void dispose() {
    unawaited(stop());
    unawaited(_controller.close().catchError((_) {}));
  }

  PullPointSubscription? _subscription;

  Future<void> _run() async {
    while (_running) {
      try {
        // (Re)souscription si nécessaire — expiration de l'ancienne.
        final sub = _subscription;
        final shouldRenew =
            sub != null &&
            (sub.terminationTime == null ||
                sub.terminationTime!.isBefore(
                  DateTime.now().add(const Duration(seconds: 20)),
                ));
        if (sub == null) {
          _subscription = await createPullPointSubscription(
            deviceUrl,
            credentials,
          );
        } else if (shouldRenew) {
          await renewSubscription(
            sub.url,
            credentials,
            terminationTime: const Duration(minutes: 1),
          );
        }

        // Long-poll : bloque jusqu'à événement ou timeout.
        final events = await pullMessages(
          _subscription!.url,
          credentials,
          timeout: _pullTimeout,
        );
        if (!_running) break;
        for (final e in events) {
          if (e.isMotionActive) lastMotion = e;
          if (!_controller.isClosed) _controller.add(e);
          onEvent?.call(e);
        }
      } catch (e) {
        // Caméra injoignable / non ONVIF / souscription expirée :
        // on repart de zéro au prochain cycle.
        debugPrint('OnvifEventsListener($deviceUrl): $e');
        _subscription = null;
        if (!_running) break;
        // Repos avant reconnexion (évite le hammering réseau).
        await Future<void>.delayed(const Duration(seconds: 10));
      }
    }
  }
}
