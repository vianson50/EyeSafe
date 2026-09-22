/// Adaptateurs d'API propriétaires par marque — le « SDK HTTP » de chaque
/// constructeur, pour les réglages que l'ONVIF ne couvre pas.
///
/// | Marque    | API     | Auth              | Remarques                       |
/// |-----------|---------|-------------------|---------------------------------|
/// | Hikvision | ISAPI   | Digest MD5 (XML)  | `isapi.dart` — complet          |
/// | Axis      | VAPIX   | Digest MD5 (texte)| `param.cgi` — ce fichier        |
/// | Uniview   | LAPI    | Digest MD5 (JSON) | `/LAPI/V1.0/…` — ce fichier     |
/// | Dahua/Imou| —       | —                 | RTSP/ONVIF uniquement (pas d'API|
/// |           |         |                   | HTTP locale sur Imou : cloud)   |
///
/// Chaque adaptateur gère l'authentification Digest (MD5) et les
/// certificats auto-signés HTTPS, comme ISAPI.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'http_digest.dart';
import 'isapi.dart' show IsapiDeviceInfo;

/// Erreur d'adaptateur explicite pour l'UI.
class BrandApiException implements Exception {
  const BrandApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Signaleur interne : le serveur exige (ou renégocie) le Digest.
class _AuthRequired implements Exception {
  const _AuthRequired();
}

/// Base commune : HTTP + Digest MD5 + certificats auto-signés optionnels.
abstract class BrandHttpClient {
  BrandHttpClient({
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

  String? _realm;
  String? _nonce;
  String? _qop;
  String? _opaque;

  /// Schéma selon l'option certificat auto-signé (HTTPS).
  String get scheme => allowSelfSigned ? 'https' : 'http';

  Uri uriFor(String path) =>
      Uri(scheme: scheme, host: host, port: httpPort, path: path);

  HttpClient _newClient() {
    final client = HttpClient()..connectionTimeout = _timeout;
    if (allowSelfSigned) {
      client.badCertificateCallback = (cert, host, port) {
        debugPrint('BrandApi: certificat auto-signé accepté ($host:$port)');
        return true;
      };
    }
    return client;
  }

  /// GET avec négociation Digest (401 → challenge → retry).
  Future<String> get(String path) async {
    final uri = uriFor(path);
    try {
      return await _attempt(uri, path, negotiate: false);
    } on _AuthRequired {
      return _attempt(uri, path, negotiate: true);
    }
  }

  Future<String> _attempt(
    Uri uri,
    String path, {
    required bool negotiate,
  }) async {
    final client = _newClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(
            _timeout,
            onTimeout: () => throw BrandApiException(
              'Délai dépassé — l\'appareil ne répond pas.',
            ),
          );
      if (negotiate && _nonce != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          HttpDigest.buildDigestHeader(
            method: 'GET',
            uri: path,
            user: user,
            password: password,
            realm: _realm ?? '',
            nonce: _nonce!,
            qop: _qop ?? 'auth',
            opaque: _opaque,
          ),
        );
      }
      final response = await request.close().timeout(_timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);

      if (response.statusCode == 401) {
        final challenge = response.headers.value(
          HttpHeaders.wwwAuthenticateHeader,
        );
        if (challenge == null) {
          throw const BrandApiException('Authentification requise, refusée.');
        }
        try {
          final params = HttpDigest.parseChallenge(challenge);
          _realm = params['realm'] ?? '';
          _nonce = params['nonce'];
          _qop = params['qop'] ?? 'auth';
          _opaque = params['opaque'];
        } on FormatException {
          throw const BrandApiException(
            'Authentification non supportée par l\'appareil.',
          );
        }
        throw const _AuthRequired();
      }
      if (response.statusCode >= 400) {
        throw BrandApiException(
          '$runtimeType : erreur HTTP ${response.statusCode}.',
        );
      }
      return text;
    } on _AuthRequired {
      rethrow;
    } on BrandApiException {
      rethrow;
    } on SocketException {
      throw BrandApiException(
        'Appareil injoignable ($host) — vérifiez l\'IP et le port HTTP.',
      );
    } on TimeoutException {
      throw BrandApiException('Délai dépassé — l\'appareil ne répond pas.');
    } on HandshakeException {
      throw BrandApiException(
        'Échec HTTPS — cochez « certificat auto-signé » ou port 80.',
      );
    } finally {
      client.close();
    }
  }
}

/// ─────────────────────────────────────────────────────────────
/// Axis — VAPIX (`axis-cgi/param.cgi`, réponses texte `clé=valeur`)
/// ─────────────────────────────────────────────────────────────
class AxisVapix extends BrandHttpClient {
  AxisVapix({
    required super.host,
    super.httpPort = 80,
    required super.user,
    required super.password,
    super.allowSelfSigned,
    super.timeout,
  });

  /// Informations matérielles via `param.cgi` (groupes Brand + System).
  Future<IsapiDeviceInfo> getDeviceInfo() async {
    const path =
        '/axis-cgi/param.cgi?action=list'
        '&group=root.Brand,root.Properties.System.SerialNumber,'
        'root.Properties.Firmware.Version';
    final text = await get(path);
    return parseVapixDeviceInfoForTest(text);
  }
}

/// Parse une réponse `param.cgi` :
/// `root.Brand.ProdShortName=P3265-LV` → modèle, etc.
@visibleForTesting
IsapiDeviceInfo parseVapixDeviceInfoForTest(String body) {
  final values = <String, String>{};
  for (final line in body.split('\n')) {
    final trimmed = line.trim();
    final eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    values[trimmed.substring(0, eq)] = trimmed.substring(eq + 1);
  }
  return IsapiDeviceInfo(
    model:
        values['root.Brand.ProdShortName'] ?? values['root.Brand.Brand'] ?? '',
    serial: values['root.Properties.System.SerialNumber'] ?? '',
    firmware: values['root.Properties.Firmware.Version'] ?? '',
    mac: values['root.Properties.System.ID'] ?? '',
  );
}

/// ─────────────────────────────────────────────────────────────
/// Uniview — LAPI (`/LAPI/V1.0/…`, réponses JSON)
/// ─────────────────────────────────────────────────────────────
class UniviewLapi extends BrandHttpClient {
  UniviewLapi({
    required super.host,
    super.httpPort = 80,
    required super.user,
    required super.password,
    super.allowSelfSigned,
    super.timeout,
  });

  /// Informations matérielles via `GET /LAPI/V1.0/System/DeviceInfo`.
  Future<IsapiDeviceInfo> getDeviceInfo() async {
    final text = await get('/LAPI/V1.0/System/DeviceInfo');
    return parseLapiDeviceInfoForTest(text);
  }
}

/// Parse une réponse LAPI :
/// `{"ResponseData":{"DevInfo":{"Model":"IPC212SR3-PF36", …}}}`
@visibleForTesting
IsapiDeviceInfo parseLapiDeviceInfoForTest(String body) {
  final dynamic data;
  try {
    data = jsonDecode(body);
  } on FormatException {
    throw const BrandApiException('Réponse illisible — pas un appareil LAPI ?');
  }
  if (data is! Map) {
    throw const BrandApiException('Réponse LAPI inattendue.');
  }
  final dev = (data['ResponseData'] as Map?)?['DevInfo'];
  if (dev is! Map) {
    throw const BrandApiException(
      'DeviceInfo LAPI absent — firmware trop ancien ? Essayer ONVIF.',
    );
  }

  String pick(List<String> keys) {
    for (final k in keys) {
      final v = dev[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  return IsapiDeviceInfo(
    model: pick(['Model', 'DeviceType']),
    serial: pick(['SerialNumber', 'SN']),
    firmware: pick(['FirmwareVersion', 'Firmware']),
    mac: pick(['MAC', 'MacAddress']),
  );
}
