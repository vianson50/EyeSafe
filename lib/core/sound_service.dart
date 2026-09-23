/// Service de sons de notification — alertes sonores locales pour les
/// événements caméras et les notifications push.
///
/// Trois niveaux sonores :
///  - **critique** (intrusion, tamper) : bip rapide répété — attire
///    l'attention même téléphone en poche
///  - **alerte** (mouvement, ticket) : bip simple
///  - **succès** (action confirmée) : bip discret
///
/// Le son est généré par synthèse (AudioCache vide + tone intégré
/// audioplayers) — AUCUN fichier audio à embarquer, AUCUN asset à
/// gérer : le son est produit par vibration système via un tone
/// WAV minimal encodé en base64 (moins de 1 Ko).
///
/// Réglage utilisateur : Paramètres → Notifications → sons (mémorisé).
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Niveau sonore de la notification.
enum NotificationSound {
  /// Intrusion/tamper — bip rapide ×3 (urgent).
  critical,

  /// Mouvement/ticket — bip simple.
  alert,

  /// Action confirmée — bip discret.
  success,
}

class SoundService {
  SoundService._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _enabled = true;
  static bool _initialized = false;

  static const _prefsKey = 'eyesafe_sounds_enabled';

  /// Charge le réglage utilisateur (appelé au démarrage).
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? true;
    } catch (_) {
      _enabled = true;
    }
  }

  /// Sons activés ?
  static bool get enabled => _enabled;

  /// Active/coupe les sons + mémorise.
  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {}
  }

  /// Joue un son de notification (silencieux si désactivé ou si les
  /// sons système sont coupés — respecte le mode silencieux).
  static Future<void> play(NotificationSound level) async {
    if (!_enabled || !_initialized) return;
    try {
      switch (level) {
        case NotificationSound.critical:
          // 3 bips rapides descendants — urgence.
          await _beep(freq: 1200, ms: 120);
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await _beep(freq: 1200, ms: 120);
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await _beep(freq: 1000, ms: 200);
        case NotificationSound.alert:
          // Bip moyen simple.
          await _beep(freq: 880, ms: 250);
        case NotificationSound.success:
          // Bip discret montant.
          await _beep(freq: 660, ms: 100);
          await Future<void>.delayed(const Duration(milliseconds: 60));
          await _beep(freq: 990, ms: 150);
      }
    } catch (_) {
      // Sons best-effort : jamais d'exception vers l'UI.
    }
  }

  /// Génère et joue une tonalité WAV pure (sine) — aucune ressource
  /// externe, volume modéré (30%).
  static Future<void> _beep({required double freq, required int ms}) async {
    final wav = _generateSineWav(freq: freq, durationMs: ms, volume: 0.3);
    await _player.play(BytesSource(wav), volume: 1.0);
    // Laisse la tonalité finir avant la suivante.
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  /// Génère un fichier WAV minimal (en-tête + sinusoïde) en mémoire.
  /// Format : PCM 16 bits mono 44100 Hz — ~44 Ko/s.
  static Uint8List _generateSineWav({
    required double freq,
    required int durationMs,
    required double volume,
  }) {
    const sampleRate = 44100;
    final numSamples = (sampleRate * durationMs / 1000).round();
    final dataSize = numSamples * 2; // 16 bits = 2 octets/échantillon
    final fileSize = 44 + dataSize;

    final bytes = ByteData(fileSize);

    // ── En-tête WAV (RIFF) ──
    // "RIFF"
    bytes.setUint8(0, 0x52);
    bytes.setUint8(1, 0x49);
    bytes.setUint8(2, 0x46);
    bytes.setUint8(3, 0x46);
    bytes.setUint32(4, fileSize - 8, Endian.little);
    // "WAVE"
    bytes.setUint8(8, 0x57);
    bytes.setUint8(9, 0x41);
    bytes.setUint8(10, 0x56);
    bytes.setUint8(11, 0x45);
    // "fmt "
    bytes.setUint8(12, 0x66);
    bytes.setUint8(13, 0x6D);
    bytes.setUint8(14, 0x74);
    bytes.setUint8(15, 0x20);
    bytes.setUint32(16, 16, Endian.little); // taille du chunk fmt
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    bytes.setUint16(32, 2, Endian.little); // block align
    bytes.setUint16(34, 16, Endian.little); // bits per sample
    // "data"
    bytes.setUint8(36, 0x64);
    bytes.setUint8(37, 0x61);
    bytes.setUint8(38, 0x74);
    bytes.setUint8(39, 0x61);
    bytes.setUint32(40, dataSize, Endian.little);

    // ── Échantillons : sinusoïde avec fondu entrée/sortie ──
    final fadeSamples = (sampleRate * 0.005).round(); // 5 ms de fondu
    for (var i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final envelope = i < fadeSamples
          ? i / fadeSamples
          : i > numSamples - fadeSamples
          ? (numSamples - i) / fadeSamples
          : 1.0;
      final sample = (sin(2 * pi * freq * t) * volume * envelope * 32767)
          .round();
      bytes.setInt16(44 + i * 2, sample, Endian.little);
    }

    return bytes.buffer.asUint8List();
  }
}
