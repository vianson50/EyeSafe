/// Client go2rtc — serveur vidéo relais.
///
/// Architecture : le serveur go2rtc (installé chez le client ou dans le
/// cloud) va chercher les flux RTSP des caméras sur le réseau local et
/// les rediffuse en HLS/WebRTC vers l'application via une seule adresse
/// (ex: http://site-client.ddns.net:1984). Pas de redirection de port par
/// caméra, pas d'exposition du RTSP.
///
/// API utilisée : `GET /api/streams` (liste des flux configurés) et
/// `GET /api/stream.m3u8?src=<nom>` (lecture HLS).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Déduit l'URL de snapshot JPEG (`/api/frame.jpeg`) d'une URL de flux
/// go2rtc HLS — utilisée par la mosaïque pour les tuiles hors quota live.
/// [ts] casse le cache pour forcer une image fraîche. Retourne null si
/// l'URL n'est pas un flux go2rtc.
String? deriveGo2rtcSnapshotUrl(String url, {int? ts}) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return null;
  if (!uri.path.endsWith('/api/stream.m3u8')) return null;
  final src = uri.queryParameters['src'];
  if (src == null || src.isEmpty) return null;
  final base = uri.path.substring(
    0,
    uri.path.length - '/api/stream.m3u8'.length,
  );
  var query = uri.query;
  if (ts != null) {
    query = query.isEmpty ? 'ts=$ts' : '$query&ts=$ts';
  }
  return uri.replace(path: '$base/api/frame.jpeg', query: query).toString();
}

/// Récupère un snapshot JPEG (auth Basic si l'URL contient user:pass).
/// Retourne null en cas d'échec — jamais d'exception (tuile = placeholder).
Future<Uint8List?> fetchGo2rtcSnapshot(
  String url, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final target = Uri.tryParse(url);
  if (target == null || !target.hasScheme) return null;
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(target).timeout(timeout);
    if (target.userInfo.isNotEmpty) {
      final token = base64Encode(utf8.encode(Uri.decodeFull(target.userInfo)));
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
    }
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) return null;
    final builder = BytesBuilder();
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > 4 * 1024 * 1024) return null; // > 4 Mo : refusé
    }
    return builder.takeBytes();
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

/// Appairage « Cloud P2P » façon Hik-Connect : chaque boîtier de site porte
/// un code (ex: EYE-7F3K2) ; son relais go2rtc pousse ses flux vers le
/// cloud EyeSafe sous des noms préfixés par ce code (ex: EYE7F3K2-1).
/// L'app n'a plus qu'à filtrer les flux du code — aucun port ouvert chez
/// le client, la connexion est sortante depuis le boîtier.
///
/// Les clouds fabricants (Hik-Connect, DMSS…) imposent leur SDK natif
/// propriétaire : ce mode s'appuie sur TON cloud go2rtc à la place.
class CloudPairing {
  CloudPairing._();

  /// Normalise un code ou un nom de flux : majuscules, sans séparateurs.
  static String normalize(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Le flux appartient-il au boîtier identifié par [normalizedCode] ?
  static bool matches(String streamName, String normalizedCode) =>
      normalizedCode.isNotEmpty &&
      normalize(streamName).startsWith(normalizedCode);

  /// Nom de caméra lisible : EYE7F3K2-3 → « Caméra 3 », sinon le nom brut.
  static String cameraName(String streamName) {
    final match = RegExp(r'(\d+)$').firstMatch(streamName.trim());
    if (match != null) {
      final channel = int.tryParse(match.group(1)!);
      if (channel != null) return 'Caméra $channel';
    }
    return streamName;
  }

  /// Filtre les flux du cloud correspondant au code d'appairage.
  static List<Go2rtcStream> filter(
    List<Go2rtcStream> streams,
    String pairingCode,
  ) {
    final code = normalize(pairingCode);
    return streams.where((s) => matches(s.name, code)).toList();
  }
}

/// Erreur go2rtc explicite pour l'UI.
class Go2rtcException implements Exception {
  Go2rtcException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Flux déclaré sur le serveur go2rtc.
class Go2rtcStream {
  const Go2rtcStream({required this.name, required this.active});

  /// Nom du flux tel que déclaré dans go2rtc.yaml (clé `streams:`).
  final String name;

  /// true si le serveur tire déjà ce flux (producteurs actifs).
  final bool active;

  @override
  String toString() => 'Go2rtcStream($name, active: $active)';
}

/// Connexion à un serveur go2rtc.
class Go2rtcServer {
  Go2rtcServer({
    required this.baseUrl,
    this.username,
    this.password,
    Duration timeout = const Duration(seconds: 6),
  }) : _timeout = timeout; // ignore: prefer_initializing_formals

  /// Adresse de base, ex: `http://192.168.100.14:1984`.
  final String baseUrl;

  /// Identifiants API go2rtc (config `api: username/password`), optionnels.
  final String? username;
  final String? password;
  final Duration _timeout;

  String get normalizedBase => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  /// URL HLS de lecture du flux (à stocker dans `stream_url`).
  String hlsUrl(String streamName) =>
      '$normalizedBase/api/stream.m3u8?src=${Uri.encodeComponent(streamName)}';

  /// Hôte du serveur (pour l'affichage).
  String get hostLabel {
    final uri = Uri.tryParse(normalizedBase);
    return uri?.host ?? normalizedBase;
  }

  /// Parse la réponse de `GET /api/streams` :
  /// `{"cocody_entree": {"producers": [...], "consumers": []}, …}`
  @visibleForTesting
  static List<Go2rtcStream> parseStreams(String body) {
    final dynamic data;
    try {
      data = jsonDecode(body);
    } on FormatException {
      throw Go2rtcException('Réponse illisible — est-ce un serveur go2rtc ?');
    }
    if (data is! Map<String, dynamic>) {
      throw Go2rtcException('Réponse inattendue du serveur go2rtc.');
    }
    final streams = [
      for (final entry in data.entries)
        Go2rtcStream(
          name: entry.key,
          active:
              entry.value is Map &&
              (entry.value['producers'] as List?)?.isNotEmpty == true,
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return streams;
  }

  /// Liste les flux configurés sur le serveur.
  Future<List<Go2rtcStream>> listStreams() async {
    final uri = Uri.tryParse('$normalizedBase/api/streams');
    if (uri == null || !uri.hasScheme) {
      throw Go2rtcException(
        'URL du serveur invalide (ex: http://ip-serveur:1984).',
      );
    }

    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client
          .getUrl(uri)
          .timeout(
            _timeout,
            onTimeout: () => throw Go2rtcException(
              'Délai dépassé — le serveur ne répond pas.',
            ),
          );
      if (username != null && username!.isNotEmpty) {
        final token = base64Encode(utf8.encode('$username:$password'));
        request.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
      }
      final response = await request.close().timeout(_timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);

      if (response.statusCode == 401) {
        throw Go2rtcException('Identifiants refusés par le serveur go2rtc.');
      }
      if (response.statusCode != 200) {
        throw Go2rtcException(
          'Serveur go2rtc : erreur HTTP ${response.statusCode}.',
        );
      }
      return parseStreams(body);
    } on Go2rtcException {
      rethrow;
    } on SocketException {
      throw Go2rtcException(
        'Serveur injoignable — vérifiez l\'URL et le port (1984 par défaut).',
      );
    } on TimeoutException {
      throw Go2rtcException('Délai dépassé — le serveur ne répond pas.');
    } on HttpException {
      throw Go2rtcException(
        'Serveur injoignable — vérifiez l\'URL et le port (1984 par défaut).',
      );
    } finally {
      client.close();
    }
  }
}
