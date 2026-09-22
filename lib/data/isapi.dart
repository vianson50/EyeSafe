/// Client ISAPI (Hikvision) — API HTTP propriétaire des caméras/NVR.
///
/// Couvre les briques utiles à EyeSafe :
///  - **Authentification Digest (MD5)** — ISAPI refuse Basic par défaut.
///  - **Certificats auto-signés** — les caméras servent HTTPS avec un
///    certificat self-signed ; option [IsapiDevice.allowSelfSigned].
///  - **DeviceInfo** : modèle, n° série, firmware réels de l'appareil.
///  - **Streaming/channels** : canaux de flux déclarés par l'appareil
///    lui-même (ex: 101 = caméra 1 flux principal, 102 = secondaire).
///  - **MotionDetection** : active/désactive l'alerte intrusion par
///    caméra — configuration précise inaccessible via ONVIF simple.
///
/// Limite : un adaptateur par marque (ISAPI = Hikvision ; Dahua expose
/// une API CGI proche). Ce fichier structure le patron ISAPI.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'http_digest.dart';

/// Erreur ISAPI explicite pour l'UI.
class IsapiException implements Exception {
  IsapiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Informations matérielles lues via /ISAPI/System/deviceInfo.
class IsapiDeviceInfo {
  const IsapiDeviceInfo({
    this.model = '',
    this.serial = '',
    this.firmware = '',
    this.mac = '',
  });

  final String model;
  final String serial;
  final String firmware;
  final String mac;
}

/// Canal de flux ISAPI (id 101 = caméra 1 / flux principal, 102 = secondaire).
class IsapiChannel {
  const IsapiChannel({
    required this.id,
    required this.name,
    this.width,
    this.height,
  });

  final int id;
  final String name;
  final int? width;
  final int? height;

  /// Caméra à laquelle appartient le canal (101 → 1).
  int get cameraNumber => id ~/ 100;

  /// 101/201… = flux principal, 102/202… = secondaire.
  bool get isMainStream => id % 100 == 1;

  String get resolutionLabel =>
      width != null && height != null ? '$width×$height' : '—';

  @override
  String toString() => 'IsapiChannel($id, $name)';
}

/// Segment d'enregistrement trouvé sur l'appareil (replay).
class IsapiRecording {
  const IsapiRecording({
    required this.trackId,
    required this.start,
    required this.end,
  });

  final int trackId;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  @override
  String toString() => 'IsapiRecording($trackId, $start → $end)';
}

/// Client vers un appareil Hikvision via ISAPI.
class IsapiDevice {
  IsapiDevice({
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

  /// Accepte les certificats HTTPS auto-signés (caméras sur le LAN).
  final bool allowSelfSigned;
  final Duration _timeout;

  // ── Authentification Digest (cache realm/nonce du 401) ──
  String? _realm;
  String? _nonce;
  String? _qop;
  String? _opaque;

  Uri _uri(String path) => Uri(
    scheme: allowSelfSigned ? 'https' : 'http',
    host: host,
    port: httpPort,
    path: path,
  );

  HttpClient _newClient() {
    final client = HttpClient()..connectionTimeout = _timeout;
    if (allowSelfSigned) {
      client.badCertificateCallback = (cert, host, port) {
        debugPrint('ISAPI: certificat auto-signé accepté ($host:$port)');
        return true;
      };
    }
    return client;
  }

  /// Construit l'en-tête Authorization Digest (MD5, qop=auth).
  /// Délègue au helper partagé [HttpDigest] (utilisé aussi par VAPIX/LAPI).
  @visibleForTesting
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
  }) => HttpDigest.buildDigestHeader(
    method: method,
    uri: uri,
    user: user,
    password: password,
    realm: realm,
    nonce: nonce,
    qop: qop,
    opaque: opaque,
    nc: nc,
    cnonce: cnonce,
  );

  /// Extrait realm/nonce/qop/opaque d'un en-tête WWW-Authenticate Digest.
  @visibleForTesting
  static Map<String, String> parseChallenge(String wwwAuthenticate) =>
      HttpDigest.parseChallenge(wwwAuthenticate);

  Future<String> _request(String method, String path, {String? body}) async {
    final uri = _uri(path);
    if (_nonce != null) {
      // Retry avec les identifiants déjà négociés.
      try {
        return await _attempt(uri, method, path, body);
      } on IsapiAuthRequired {
        // nonce expiré → renégocie.
      }
    }
    return _attempt(uri, method, path, body, negotiate: true);
  }

  Future<String> _attempt(
    Uri uri,
    String method,
    String path,
    String? body, {
    bool negotiate = false,
  }) async {
    final client = _newClient();
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(
            _timeout,
            onTimeout: () => throw IsapiException(
              'Délai dépassé — l\'appareil ne répond pas.',
            ),
          );
      request.headers.contentType = ContentType(
        'application',
        'xml',
        charset: 'utf-8',
      );
      if (negotiate && _nonce != null) {
        _applyAuth(request, method, uri);
      }
      if (body != null) request.write(body);
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
          throw IsapiException('Authentification requise mais refusée.');
        }
        final params = parseChallenge(challenge);
        _realm = params['realm'] ?? '';
        _nonce = params['nonce'];
        _qop = params['qop'] ?? 'auth';
        _opaque = params['opaque'];
        throw const IsapiAuthRequired();
      }
      if (response.statusCode >= 400) {
        throw IsapiException(
          'Appareil ISAPI : erreur HTTP '
          '${response.statusCode}.',
        );
      }
      return text;
    } on IsapiAuthRequired {
      if (_nonce == null) rethrow;
      // deuxième passage avec le digest fraîchement négocié
      return _attempt(uri, method, path, body, negotiate: true);
    } on SocketException {
      throw IsapiException(
        'Appareil injoignable ($host) — vérifiez l\'IP et le port HTTP.',
      );
    } on HandshakeException {
      throw IsapiException(
        'Échec HTTPS — cochez « certificat auto-signé » ou utilisez le port '
        'HTTP 80.',
      );
    } on XmlException {
      throw IsapiException('Réponse illisible — pas un appareil ISAPI ?');
    } finally {
      client.close();
    }
  }

  void _applyAuth(HttpClientRequest request, String method, Uri uri) {
    request.headers.set(
      HttpHeaders.authorizationHeader,
      buildDigestHeader(
        method: method,
        uri: uri.path,
        user: user,
        password: password,
        realm: _realm ?? '',
        nonce: _nonce!,
        qop: _qop ?? 'auth',
        opaque: _opaque,
      ),
    );
  }

  Future<String> get(String path) => _request('GET', path);
  Future<String> put(String path, String body) =>
      _request('PUT', path, body: body);

  /// URI d'un endpoint ISAPI (réutilisé par la session talk-back).
  Uri uriFor(String path) => _uri(path);

  /// Applique l'authentification Digest déjà négociée à une requête
  /// externe (session talk-back).
  void applyAuth(HttpClientRequest request, String method, String path) {
    if (_nonce == null) return;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      HttpDigest.buildDigestHeader(
        method: method,
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

  // ── Endpoints ISAPI ──

  /// /ISAPI/System/deviceInfo
  Future<IsapiDeviceInfo> getDeviceInfo() async {
    final xml = await get('/ISAPI/System/deviceInfo');
    return parseDeviceInfoForTest(xml);
  }

  /// /ISAPI/Streaming/channels — canaux déclarés par l'appareil.
  Future<List<IsapiChannel>> listChannels() async {
    final xml = await get('/ISAPI/Streaming/channels');
    return parseChannelsForTest(xml);
  }

  // ── Replay : recherche d'enregistrements sur l'appareil/NVR ──

  /// POST /ISAPI/ContentMgmt/search — segments enregistrés d'un canal
  /// sur une période (max 40 résultats par requête, pagination non gérée).
  Future<List<IsapiRecording>> searchRecordings({
    required int channel,
    required DateTime start,
    required DateTime end,
  }) async {
    final body =
        '<CMSSearchDescription>'
        '<searchID>${DateTime.now().microsecondsSinceEpoch}</searchID>'
        '<trackList><trackID>${channel}01</trackID></trackList>'
        '<timeSpanList><timeSpan>'
        '<startTime>${_isapiTime(start)}</startTime>'
        '<endTime>${_isapiTime(end)}</endTime>'
        '</timeSpan></timeSpanList>'
        '<maxResults>40</maxResults>'
        '</CMSSearchDescription>';
    final xml = await _request('POST', '/ISAPI/ContentMgmt/search', body: body);
    return parseRecordingsForTest(xml);
  }

  /// URL RTSP de lecture d'un segment (piste + fenêtre temporelle).
  /// Format Hikvision : /Streaming/tracks/{id}?starttime=…Z&endtime=…Z
  static String playbackUrl({
    required String host,
    required String rtspPort,
    required String user,
    required String password,
    required int trackId,
    required DateTime start,
    required DateTime end,
  }) {
    final creds =
        '${Uri.encodeComponent(user)}:${Uri.encodeComponent(password)}';
    return 'rtsp://$creds@$host:$rtspPort/Streaming/tracks/$trackId'
        '?starttime=${_basicIsoTime(start)}'
        '&endtime=${_basicIsoTime(end)}';
  }

  static String _isapiTime(DateTime t) {
    final iso = t.toUtc().toIso8601String();
    // 2026-09-19T01:00:00.000Z → 2026-09-19T01:00:00Z
    return iso.replaceFirst(RegExp(r'\.\d+'), '');
  }

  /// 2026-09-19T08:00:00Z → 20260919T080000Z (ISO 8601 basique Hikvision).
  static String _basicIsoTime(DateTime t) {
    final iso = _isapiTime(t);
    return iso.replaceAll(RegExp(r'[-:]'), '');
  }

  // ── Talk-back : audio du téléphone vers le haut-parleur caméra ──

  /// Ouvre une session d'interphonie (POST openTalk avec descripteur
  /// G.711) puis retourne le flux d'envoi. Fermeture via [IsapiTalkSession.close].
  Future<IsapiTalkSession> openTalk({
    int channel = 1,
    bool aLaw = false,
  }) async {
    final audioType = aLaw ? 'G.711alaw' : 'G.711ulaw';
    // Négocie le Digest au passage (401 → challenge → retry géré).
    await _request(
      'POST',
      '/ISAPI/System/Audio/channels/$channel/openTalk',
      body:
          '<TalkDescription>'
          '<audioType>$audioType</audioType>'
          '<audioBitRate>64</audioBitRate>'
          '<sampleRate>8000</sampleRate>'
          '</TalkDescription>',
    );
    return IsapiTalkSession._(this, channel);
  }

  Future<void> closeTalk(int channel) async {
    try {
      await _request(
        'DELETE',
        '/ISAPI/System/Audio/channels/$channel/openTalk',
      );
    } on IsapiException {
      // Déjà fermée ou non supportée : on ignore.
    }
  }

  /// /ISAPI/PTZCtrl/channels/{n}/capabilities — la caméra gère-t-elle le
  /// PTZ ? (capacités : une caméra bas de gamme ne l'expose pas → l'app
  /// masque le pavé PTZ).
  Future<bool> hasPtzChannel(int cameraNumber) async {
    final paths = [
      '/ISAPI/PTZCtrl/channels/$cameraNumber/capabilities',
      '/ISAPI/PTZCtrl/channels/$cameraNumber',
    ];
    for (final path in paths) {
      try {
        final xml = await get(path);
        final doc = XmlDocument.parse(xml);
        // Toute réponse PTZ valide expose PTZCapability(e)
        return doc.findAllElements('PTZCapability').isNotEmpty ||
            doc.findAllElements('PTZStatus').isNotEmpty;
      } on IsapiException {
        continue;
      } on XmlException {
        continue;
      }
    }
    return false;
  }

  /// /ISAPI/System/Video/inputs/channels/{n}/motionDetection (caméra) puis
  /// variante NVR en repli. Retourne false si l'appareil ne l'expose pas.
  Future<bool> setMotionDetection(int cameraNumber, bool enabled) async {
    final paths = [
      '/ISAPI/System/Video/inputs/channels/$cameraNumber/motionDetection',
      '/ISAPI/ContentMgmt/InputProxy/channels/$cameraNumber/video/'
          'motionDetection',
    ];
    for (final path in paths) {
      try {
        final current = await get(path);
        final updated = flipMotionEnabledForTest(current, enabled);
        await put(path, updated);
        return true;
      } on IsapiException {
        continue;
      }
    }
    return false;
  }
}

/// Session de talk-back ouverte : flux G.711 continu vers le haut-parleur
/// de la caméra (PUT chunked sur /talk-data). Fermer impérativement via
/// [close] pour libérer la connexion et couper l'interphonie.
class IsapiTalkSession {
  IsapiTalkSession._(this._device, this._channel);

  final IsapiDevice _device;
  final int _channel;
  HttpClient? _client;
  HttpClientRequest? _request;
  bool _closed = false;

  bool get isClosed => _closed;

  /// Ouvre le flux d'envoi (une seule fois) avec l'authentification
  /// Digest déjà négociée par openTalk.
  Future<void> _openStream() async {
    if (_closed) return;
    final path = '/ISAPI/System/Audio/channels/$_channel/talk-data';
    _client = HttpClient();
    final request = await _client!.postUrl(_device.uriFor(path));
    request.headers.contentType = ContentType('audio', 'G.711');
    _device.applyAuth(request, 'POST', path);
    _request = request;
  }

  /// Envoie un bloc G.711 brut (ouvre le flux au premier appel).
  Future<void> send(List<int> g711Bytes) async {
    if (_closed) return;
    if (_request == null) await _openStream();
    _request?.add(g711Bytes);
    await _request?.flush();
  }

  /// Termine la session : ferme le flux puis DELETE openTalk.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _request?.close();
    } catch (_) {}
    _request = null;
    _client?.close();
    _client = null;
    await _device.closeTalk(_channel);
  }
}

/// Signal interne : le serveur exige (ou renégocie) le Digest.
class IsapiAuthRequired implements Exception {
  const IsapiAuthRequired();
}

/// Challenge WWW-Authenticate inutilisable (pas Digest / pas de nonce).
class IsapiExceptionFormat extends IsapiException {
  IsapiExceptionFormat()
    : super('Authentification non supportée par l\'appareil.');
}

// ── Parsing XML (exposé pour les tests) ──

@visibleForTesting
List<IsapiRecording> parseRecordingsForTest(String xml) {
  final doc = XmlDocument.parse(xml);
  final recordings = <IsapiRecording>[];
  for (final item in doc.findAllElements('searchMatchItem')) {
    final trackId = int.tryParse(
      item.findElements('trackID').firstOrNull?.innerText.trim() ?? '',
    );
    final timeSpan = item.findElements('timeSpan').firstOrNull;
    final start = DateTime.tryParse(
      timeSpan?.findElements('startTime').firstOrNull?.innerText ?? '',
    );
    final end = DateTime.tryParse(
      timeSpan?.findElements('endTime').firstOrNull?.innerText ?? '',
    );
    if (trackId == null || start == null || end == null) continue;
    if (!end.isAfter(start)) continue;
    recordings.add(IsapiRecording(trackId: trackId, start: start, end: end));
  }
  recordings.sort((a, b) => a.start.compareTo(b.start));
  return recordings;
}

@visibleForTesting
IsapiDeviceInfo parseDeviceInfoForTest(String xml) {
  final doc = XmlDocument.parse(xml);
  String tag(String name) =>
      doc.findAllElements(name).firstOrNull?.innerText.trim() ?? '';
  return IsapiDeviceInfo(
    model: tag('model'),
    serial: tag('serialNumber'),
    firmware: tag('firmwareVersion'),
    mac: tag('macAddress'),
  );
}

@visibleForTesting
List<IsapiChannel> parseChannelsForTest(String xml) {
  final doc = XmlDocument.parse(xml);
  final channels = <IsapiChannel>[];
  for (final node in doc.findAllElements('StreamingChannel')) {
    final id = int.tryParse(
      node.findElements('id').firstOrNull?.innerText.trim() ?? '',
    );
    if (id == null || id < 100) continue;
    final name =
        node.findElements('ChannelName').firstOrNull?.innerText.trim() ??
        'Canal $id';
    final width = int.tryParse(
      node.findAllElements('width').firstOrNull?.innerText.trim() ?? '',
    );
    final height = int.tryParse(
      node.findAllElements('height').firstOrNull?.innerText.trim() ?? '',
    );
    channels.add(
      IsapiChannel(id: id, name: name, width: width, height: height),
    );
  }
  channels.sort((a, b) => a.id.compareTo(b.id));
  return channels;
}

/// Bascule l'élément `enabled` d'un document motionDetection sans toucher
/// au reste.
@visibleForTesting
String flipMotionEnabledForTest(String xml, bool enabled) {
  final doc = XmlDocument.parse(xml);
  final node = doc.findAllElements('enabled').firstOrNull;
  if (node == null) {
    throw IsapiException(
      'Configuration de détection introuvable sur cet appareil.',
    );
  }
  node.innerText = enabled ? 'true' : 'false';
  return doc.toXmlString(pretty: true);
}
