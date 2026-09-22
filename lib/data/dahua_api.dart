/// Adaptateur Dahua — HTTP API (JSON-RPC `/cgi-bin/…`).
///
/// Dahua expose deux voies : le NetSDK natif (bibliothèque .so/AAR sous
/// licence — non intégrable dans une app Flutter propre) et l'**HTTP API**
/// documentée, recommandée pour les nouvelles intégrations. C'est cette
/// dernière qui est implémentée ici :
///
///  - **Login signé** : `global.login` en deux temps — le premier appel
///    renvoie `realm` + `random` serveur, le second envoie
///    `base64(md5(user:random:base64(md5(user:realm:pass))))`.
///  - **Session** : `?__session=…` sur les appels suivants.
///  - **DeviceInfo** : `magicBox.getSystemInfo` (deviceType, serialNumber,
///    updateSerial = firmware).
///
/// Imou (gamme grand public de Dahua) n'expose PAS cette API localement
/// (cloud uniquement) → RTSP/ONVIF pour Imou.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'isapi.dart' show IsapiDeviceInfo;

/// Erreur Dahua explicite pour l'UI.
class DahuaException implements Exception {
  const DahuaException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dérivation du mot de passe de login Dahua (spécification HTTP API) :
///
/// 1. `loginSignature = base64(md5(user:realm:password))`
/// 2. `loginPassword = base64(md5(user:serverRandom:loginSignature))`
class DahuaAuth {
  DahuaAuth._();

  static String buildLoginPassword({
    required String user,
    required String realm,
    required String serverRandom,
    required String password,
  }) {
    final signature = base64Encode(
      md5.convert(utf8.encode('$user:$realm:$password')).bytes,
    );
    return base64Encode(
      md5.convert(utf8.encode('$user:$serverRandom:$signature')).bytes,
    );
  }
}

/// Client HTTP API vers un appareil Dahua.
class DahuaHttp {
  DahuaHttp({
    required this.host,
    this.httpPort = 80,
    required this.user,
    required this.password,
    this.allowSelfSigned = false,
    Duration timeout = const Duration(seconds: 6),
  }) : _timeout = timeout; // ignore: prefer_initializing_formals

  final String host;
  final int httpPort;
  final String user;
  final String password;
  final bool allowSelfSigned;
  final Duration _timeout;

  String? _session;
  int _id = 0;

  Uri _uri(String method) => Uri(
    scheme: allowSelfSigned ? 'https' : 'http',
    host: host,
    port: httpPort,
    path: '/cgi-bin/$method',
    queryParameters: _session == null ? null : {'__session': _session},
  );

  HttpClient _newClient() {
    final client = HttpClient()..connectionTimeout = _timeout;
    if (allowSelfSigned) {
      client.badCertificateCallback = (_, _, _) => true;
    }
    return client;
  }

  Future<Map<String, dynamic>> _rpc(
    String method,
    Map<String, dynamic> params,
  ) async {
    final client = _newClient();
    try {
      final request = await client
          .postUrl(_uri(method))
          .timeout(
            _timeout,
            onTimeout: () => throw const DahuaException(
              'Délai dépassé — l\'appareil ne répond pas.',
            ),
          );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({'method': method, 'params': params, 'id': ++_id}),
      );
      final response = await request.close().timeout(_timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      return parseRpcResponseForTest(body);
    } on DahuaException {
      rethrow;
    } on SocketException {
      throw DahuaException(
        'Appareil injoignable ($host) — vérifiez l\'IP et le port HTTP.',
      );
    } on TimeoutException {
      throw const DahuaException('Délai dépassé — l\'appareil ne répond pas.');
    } on HttpException {
      throw const DahuaException('Appareil injoignable.');
    } on FormatException {
      throw const DahuaException('Réponse illisible — pas un appareil Dahua ?');
    } finally {
      client.close();
    }
  }

  /// Login en deux temps (realm + random serveur → mot de passe signé).
  Future<void> _login() async {
    final clientRandom = _randomDigits();

    // 1er appel : volontairement sans mot de passe → realm + random serveur.
    final first = await _rpc('global.login', {
      'userName': user,
      'password': '',
      'clientType': 'Web3.0',
      'random': clientRandom,
    });
    if (first['result'] == true) {
      _session = (first['data'] as Map?)?['session'] as String?;
      if (_session != null) return;
    }
    final challenge = first['data'] as Map?;
    final realm = challenge?['realm'] as String? ?? '';
    final serverRandom = challenge?['random'] as String? ?? '';
    if (realm.isEmpty || serverRandom.isEmpty) {
      throw const DahuaException(
        'Authentification Dahua refusée (pas de challenge).',
      );
    }

    // 2e appel : mot de passe dérivé de la signature MD5.
    final second = await _rpc('global.login', {
      'userName': user,
      'password': DahuaAuth.buildLoginPassword(
        user: user,
        realm: realm,
        serverRandom: serverRandom,
        password: password,
      ),
      'clientType': 'Web3.0',
      'random': clientRandom,
    });
    if (second['result'] != true) {
      throw const DahuaException('Identifiants refusés par l\'appareil Dahua.');
    }
    _session = (second['data'] as Map?)?['session'] as String?;
    if (_session == null) {
      throw const DahuaException('Session Dahua non attribuée.');
    }
  }

  static String _randomDigits() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  /// Informations matérielles via `magicBox.getSystemInfo`.
  Future<IsapiDeviceInfo> getDeviceInfo() async {
    if (_session == null) await _login();
    final r = await _rpc('magicBox.getSystemInfo', <String, dynamic>{});
    if (r['result'] != true) {
      throw const DahuaException('getSystemInfo refusé par l\'appareil.');
    }
    return parseSystemInfoForTest(jsonEncode(r));
  }
}

// ── Parsing (exposé pour les tests) ──

/// Parse une réponse JSON-RPC Dahua ; lève si le corps n'est pas du JSON.
@visibleForTesting
Map<String, dynamic> parseRpcResponseForTest(String body) {
  final dynamic data;
  try {
    data = jsonDecode(body);
  } on FormatException {
    throw const DahuaException('Réponse illisible — pas un appareil Dahua ?');
  }
  if (data is! Map<String, dynamic>) {
    throw const DahuaException('Réponse Dahua inattendue.');
  }
  return data;
}

/// Mappe `magicBox.getSystemInfo` vers nos infos neutres.
@visibleForTesting
IsapiDeviceInfo parseSystemInfoForTest(String body) {
  final r = parseRpcResponseForTest(body);
  final data = r['data'];
  if (data is! Map) {
    throw const DahuaException('SystemInfo Dahua absent.');
  }
  String pick(String k) => data[k]?.toString() ?? '';
  return IsapiDeviceInfo(
    model: pick('deviceType'),
    serial: pick('serialNumber'),
    firmware: pick('updateSerial').isNotEmpty
        ? pick('updateSerial')
        : pick('hardwareVersion'),
    mac: '',
  );
}
