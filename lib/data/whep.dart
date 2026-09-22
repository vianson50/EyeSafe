/// Client WHEP (WebRTC-HTTP Egress Protocol) pour go2rtc.
///
/// Pourquoi : le HLS (`/api/stream.m3u8`) introduit 2 à 6 s de latence —
/// inacceptable pour de la surveillance. go2rtc expose le WebRTC via
/// WHEP : `POST /api/webrtc?src=<nom>` avec une offre SDP → réponse SDP.
/// Résultat : direct à moins d'une seconde.
///
/// Stratégie dans l'app :
///  1. URL go2rtc détectée (`/api/stream.m3u8?src=…`) → négociation WHEP
///     et lecture WebRTC (flutter_webrtc) ;
///  2. échec (NAT trop restrictif, vieux go2rtc, HTTPS mal configuré) →
///     repli automatique sur le HLS media_kit.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Erreur WHEP explicite pour l'UI/logs.
class WhepException implements Exception {
  WhepException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WhepClient {
  WhepClient._();

  /// Déduit l'URL WHEP d'une URL de flux go2rtc :
  /// `http://h:1984/api/stream.m3u8?src=cam` → `http://h:1984/api/webrtc?src=cam`.
  /// Retourne null si l'URL n'est pas un flux go2rtc (RTSP direct, HLS
  /// externe… → pas de WebRTC, lecture directe).
  static String? deriveWhepUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    if (!uri.path.endsWith('/api/stream.m3u8')) return null;
    final src = uri.queryParameters['src'];
    if (src == null || src.isEmpty) return null;
    final base = uri.path.substring(
      0,
      uri.path.length - '/api/stream.m3u8'.length,
    );
    // Préserve la query brute (encodage d'origine : %20 vs +).
    return uri.replace(path: '$base/api/webrtc', query: uri.query).toString();
  }

  /// Négocie une session WebRTC : envoie l'offre SDP au serveur WHEP et
  /// retourne la réponse SDP à appliquer en `setRemoteDescription`.
  /// Auth Basic automatique si l'URL contient `user:pass@` (api go2rtc).
  static Future<String> negotiate({
    required String whepUrl,
    required String offerSdp,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final target = Uri.tryParse(whepUrl);
    if (target == null || !target.hasScheme) {
      throw WhepException('URL WebRTC invalide.');
    }

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(target)
          .timeout(
            timeout,
            onTimeout: () =>
                throw WhepException('Signaling WebRTC : délai dépassé.'),
          );
      request.headers.contentType = ContentType('application', 'sdp');
      if (target.userInfo.isNotEmpty) {
        final token = base64Encode(
          utf8.encode(Uri.decodeFull(target.userInfo)),
        );
        request.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
      }
      request.write(offerSdp);

      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw WhepException(
          'Serveur WebRTC : HTTP ${response.statusCode} '
          '(go2rtc trop ancien ? WHEP requiert go2rtc >= 1.2).',
        );
      }
      if (!body.contains('v=0')) {
        throw WhepException('Réponse SDP invalide.');
      }
      return body;
    } on SocketException {
      throw WhepException('Serveur WebRTC injoignable.');
    } on TimeoutException {
      throw WhepException('Signaling WebRTC : délai dépassé.');
    } on HttpException {
      throw WhepException('Serveur WebRTC injoignable.');
    } finally {
      client.close();
    }
  }
}
