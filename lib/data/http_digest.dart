/// Authentification HTTP Digest (MD5) partagée entre les adaptateurs de
/// marque (ISAPI Hikvision, VAPIX Axis, LAPI Uniview).
///
/// Flux standard : requête anonyme → 401 + en-tête `WWW-Authenticate` →
/// [parseChallenge] → [buildDigestHeader] → requête authentifiée.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class HttpDigest {
  HttpDigest._();

  /// Construit l'en-tête `Authorization: Digest …` (MD5, qop=auth).
  ///
  /// `response = md5(HA1:nonce:nc:cnonce:qop:HA2)` avec
  /// `HA1 = md5(user:realm:pass)` et `HA2 = md5(method:uri)`.
  static String buildDigestHeader({
    required String method,
    required String uri,
    required String user,
    required String password,
    required String realm,
    required String nonce,
    String qop = 'auth',
    String? opaque,
    String nc = '00000001',
    String? cnonce,
  }) {
    final cn = cnonce ?? randomCnonce();
    final ha1 = md5.convert(utf8.encode('$user:$realm:$password')).toString();
    final ha2 = md5.convert(utf8.encode('$method:$uri')).toString();
    final response = qop.isEmpty
        ? md5.convert(utf8.encode('$ha1:$nonce:$ha2')).toString()
        : md5.convert(utf8.encode('$ha1:$nonce:$nc:$cn:$qop:$ha2')).toString();
    final buffer = StringBuffer()
      ..write('Digest username="$user", realm="$realm", nonce="$nonce"')
      ..write(', uri="$uri", algorithm=MD5')
      ..write(', response="$response"');
    if (qop.isNotEmpty) {
      buffer.write(', qop=$qop, nc=$nc, cnonce="$cn"');
    }
    if (opaque != null && opaque.isNotEmpty) {
      buffer.write(', opaque="$opaque"');
    }
    return buffer.toString();
  }

  /// Extrait realm/nonce/qop/opaque d'un en-tête `WWW-Authenticate`.
  /// Format typique caméra :
  /// `Digest realm="IP Camera(12345)", nonce="…", qop="auth"`.
  static Map<String, String> parseChallenge(String wwwAuthenticate) {
    final params = <String, String>{};
    final isDigest = wwwAuthenticate.trim().toLowerCase().startsWith('digest');
    final body = wwwAuthenticate.substring(wwwAuthenticate.indexOf(' ') + 1);
    for (final match in RegExp(r'([a-zA-Z]+)=?"([^"]*)"').allMatches(body)) {
      params[match.group(1)!] = match.group(2)!;
    }
    if (!isDigest || params['nonce'] == null) {
      throw const FormatException('Challenge non-Digest ou sans nonce');
    }
    return params;
  }

  /// cnonce hexadécimal aléatoire.
  static String randomCnonce() {
    final rng = Random.secure();
    return List<int>.generate(
      8,
      (_) => rng.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
