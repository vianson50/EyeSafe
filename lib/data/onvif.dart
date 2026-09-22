import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

/// Client ONVIF minimal (profil S — streaming), en Dart pur.
///
/// Couvre les briques utiles à EyeSafe :
///  - **WS-Discovery** : découverte des caméras ONVIF sur le réseau local
///    (multicast UDP 239.255.255.250:3702).
///  - **GetProfiles / GetStreamUri** : récupère les profils de flux
///    (main / sub stream) et leur URL RTSP, quelle que soit la marque.
///  - **PTZ** : ContinuousMove / Stop (maintenir un bouton = mouvement).
///
/// Authentification : WS-Security UsernameToken avec digest
/// `base64(SHA1(nonce + created + motdepasse))` — le standard ONVIF
/// (les caméras rejettent le mot de passe en clair).
///
/// Limite connue : ONVIF fonctionne sur le réseau local. Pour un accès
/// distant, passer par l'IP directe (redirection de port) ou un relais.

/// Mode du filtre IR-cut (jour/nuit) — contrôle de base ONVIF Imaging.
enum OnvifIrCutMode {
  /// La caméra bascule seule selon la luminosité.
  auto,

  /// Filtre engagé → image couleur (jour forcé).
  on,

  /// Filtre retiré → image N&B sensible IR (nuit forcée).
  off,
}

extension OnvifIrCutModeX on OnvifIrCutMode {
  String get xmlName => switch (this) {
    OnvifIrCutMode.auto => 'Auto',
    OnvifIrCutMode.on => 'On',
    OnvifIrCutMode.off => 'Off',
  };

  String get label => switch (this) {
    OnvifIrCutMode.auto => 'AUTO',
    OnvifIrCutMode.on => 'JOUR',
    OnvifIrCutMode.off => 'NUIT',
  };

  OnvifIrCutMode get next => switch (this) {
    OnvifIrCutMode.auto => OnvifIrCutMode.on,
    OnvifIrCutMode.on => OnvifIrCutMode.off,
    OnvifIrCutMode.off => OnvifIrCutMode.auto,
  };
}

/// Caméra découverte sur le réseau local via WS-Discovery.
class OnvifDiscovered {
  OnvifDiscovered({required this.address, required this.xaddrs, this.name});

  /// IP:port de l'expéditeur (source UDP).
  final String address;

  /// URLs de service annoncées (ex: http://192.168.1.64:80/onvif/device_service).
  final List<Uri> xaddrs;

  /// Nom convivial extrait des scopes (souvent le modèle ou le hostname).
  final String? name;

  /// Première XAddr http — point d'entrée ONVIF typique.
  Uri get deviceUri => xaddrs.first;

  /// Hôte sans port (pour l'affichage).
  String get host => deviceUri.host;

  @override
  String toString() => 'OnvifDiscovered($address, $xaddrs, $name)';
}

/// Profil média ONVIF (un flux — main ou sub stream).
class OnvifProfile {
  OnvifProfile({
    required this.token,
    required this.name,
    this.width,
    this.height,
    this.hasPtz = false,
    this.hasAudio = false,
    this.videoSourceToken,
  });

  /// Token à passer à GetStreamUri / ContinuousMove.
  final String token;

  /// Nom donné par la caméra (ex: "Profile_1", "mainstream").
  final String name;

  /// Résolution vidéo si annoncée.
  final int? width;
  final int? height;

  /// Le profil embarque une configuration PTZ.
  final bool hasPtz;

  /// Le profil embarque un encodeur audio (une caméra bas de gamme
  /// sans micro → l'app n'affichera pas d'indicateur audio).
  final bool hasAudio;

  /// Token de la source vidéo (VideoSourceConfiguration) — requis pour
  /// le service Imaging (filtre IR jour/nuit). Null si absent.
  final String? videoSourceToken;

  bool get isMainStream =>
      width != null && height != null && width! * height! >= 640 * 480;

  String get resolutionLabel =>
      width != null && height != null ? '$width×$height' : '—';

  @override
  String toString() => 'OnvifProfile($token, $name, $resolutionLabel)';
}

/// Échappe les caractères XML (partagé par les méthodes de la classe et
/// les helpers de test).
String _xmlEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Exceptions ONVIF explicites pour l'UI.
class OnvifException implements Exception {
  OnvifException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Client ONVIF vers un appareil précis (caméra ou NVR).
class OnvifDevice {
  OnvifDevice({
    required this.host,
    this.port = 80,
    this.user = '',
    this.password = '',
    Duration timeout = const Duration(seconds: 6),
  }) : _timeout = timeout; // ignore: prefer_initializing_formals

  final String host;
  final int port;
  final String user;
  final String password;
  final Duration _timeout;

  Uri? _mediaUri;
  Uri? _ptzUri;
  Uri? _imagingUri;

  static const _nsEnv = 'http://www.w3.org/2003/05/soap-envelope';
  static const _nsSchema = 'http://www.onvif.org/ver10/schema';
  static const _nsMedia = 'http://www.onvif.org/ver10/media/wsdl';
  static const _nsPtz = 'http://www.onvif.org/ver20/ptz/wsdl';
  static const _nsImaging = 'http://www.onvif.org/ver10/imaging/wsdl';
  static const _secExt =
      'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd';
  static const _secUtil =
      'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd';

  Uri _deviceUri(String path) => Uri(
    scheme: 'http',
    host: host,
    port: port,
    path: path.isEmpty ? '/onvif/device_service' : path,
  );

  /// En-tête WS-Security UsernameToken (digest SHA-1 standard ONVIF).
  @visibleForTesting
  static String securityHeader({
    required String user,
    required String password,
  }) {
    final nonce = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final created = DateTime.now().toUtc().toIso8601String();
    final digest = sha1.convert([
      ...nonce,
      ...utf8.encode(created),
      ...utf8.encode(password),
    ]).bytes;
    final nonceB64 = base64Encode(nonce);
    final digestB64 = base64Encode(digest);
    return '<Security s:mustUnderstand="1" xmlns="$_secExt">'
        '<UsernameToken>'
        '<Username>${_xmlEscape(user)}</Username>'
        '<Password Type="$_secExt#PasswordDigest">$digestB64</Password>'
        '<Nonce EncodingType="$_secExt#Base64Binary">$nonceB64</Nonce>'
        '<Created xmlns="$_secUtil">$created</Created>'
        '</UsernameToken></Security>';
  }

  /// Enveloppe SOAP prête à envoyer.
  @visibleForTesting
  static String soapEnvelope({
    required String bodyXml,
    String? action,
    required String user,
    required String password,
  }) {
    final headerBuffer = StringBuffer();
    if (action != null) {
      headerBuffer.write(
        '<a:Action s:mustUnderstand="1" xmlns:a='
        '"http://schemas.xmlsoap.org/ws/2004/08/addressing">'
        '$action</a:Action>',
      );
    }
    headerBuffer.write(securityHeader(user: user, password: password));
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<s:Envelope xmlns:s="$_nsEnv">'
        '<s:Header>$headerBuffer</s:Header>'
        '<s:Body>$bodyXml</s:Body>'
        '</s:Envelope>';
  }

  Future<XmlElement> _post({
    required Uri uri,
    required String bodyXml,
    required String soapAction,
    required String user,
    required String password,
  }) async {
    final envelope = soapEnvelope(
      bodyXml: bodyXml,
      action: soapAction,
      user: user,
      password: password,
    );
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client
          .postUrl(uri)
          .timeout(
            _timeout,
            onTimeout: () => throw OnvifException(
              'Délai dépassé — l\'appareil ne répond pas.',
            ),
          );
      request.headers.contentType = ContentType(
        'application',
        'soap+xml',
        charset: 'utf-8',
      );
      request.write(envelope);
      final response = await request.close().timeout(_timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      final doc = XmlDocument.parse(text);

      final fault =
          doc.findAllElements('SOAP-ENV:Fault').firstOrNull ??
          doc.findAllElements('s:Fault').firstOrNull;
      if (fault != null) {
        final textNode =
            fault.findAllElements('SOAP-ENV:Text').firstOrNull?.innerText ??
            fault.findAllElements('s:text').firstOrNull?.innerText ??
            'Erreur ONVIF';
        // 401-ish : mauvais identifiants.
        final subcode = fault.innerText;
        if (subcode.contains('NotAuthorized') ||
            subcode.contains('SenderNotAuthorized')) {
          throw OnvifException(
            'Identifiants refusés par la caméra (authentification ONVIF).',
          );
        }
        throw OnvifException('Caméra ONVIF : $textNode');
      }
      return doc.rootElement;
    } on SocketException {
      throw OnvifException(
        'Appareil injoignable ($host) — vérifiez le réseau.',
      );
    } on TimeoutException {
      throw OnvifException('Délai dépassé — l\'appareil ne répond pas.');
    } on XmlException {
      throw OnvifException('Réponse illisible (pas un appareil ONVIF ?).');
    } finally {
      client.close();
    }
  }

  /// Résout l'URL du service média (GetServices) avec repli standard.
  Future<Uri> mediaUri({required String user, required String password}) async {
    if (_mediaUri != null) return _mediaUri!;
    await _resolveServices(user: user, password: password);
    return _mediaUri!;
  }

  Future<void> _resolveServices({
    required String user,
    required String password,
  }) async {
    Uri? media;
    Uri? ptz;
    Uri? imaging;
    try {
      final root = await _post(
        uri: _deviceUri(''),
        bodyXml:
            '<GetServices xmlns="http://www.onvif.org/ver10/device/wsdl">'
            '<IncludeCapability>false</IncludeCapability>'
            '</GetServices>',
        soapAction: 'http://www.onvif.org/ver10/device/wsdl/GetServices',
        user: user,
        password: password,
      );
      for (final svc in root.findAllElements('tds:Service')) {
        final namespace = svc
            .findElements('tds:Namespace')
            .firstOrNull
            ?.innerText;
        final xaddr = svc.findElements('tds:XAddr').firstOrNull?.innerText;
        if (xaddr == null) continue;
        final uri = Uri.tryParse(xaddr);
        if (uri == null) continue;
        if (namespace?.contains('/ver10/media/') ?? false) {
          media ??= uri;
        } else if (namespace?.contains('/ptz/') ?? false) {
          ptz ??= uri;
        } else if (namespace?.contains('/imaging/') ?? false) {
          imaging ??= uri;
        }
      }
    } on OnvifException {
      // Appareil incapable de GetServices → chemins standard ci-dessous.
    }
    _mediaUri = media ?? _deviceUri('/onvif/Media');
    _ptzUri = ptz ?? _deviceUri('/onvif/PTZ');
    _imagingUri = imaging ?? _deviceUri('/onvif/Imaging');
  }

  /// Récupère les profils de flux de la caméra.
  Future<List<OnvifProfile>> getProfiles({
    required String user,
    required String password,
  }) async {
    final uri = await mediaUri(user: user, password: password);
    final root = await _post(
      uri: uri,
      bodyXml: '<GetProfiles xmlns="$_nsMedia"/>',
      soapAction: '$_nsMedia/GetProfiles',
      user: user,
      password: password,
    );
    return _parseProfiles(root);
  }

  /// URL RTSP du profil (injecte les identifiants si absents).
  Future<String> getStreamUri({
    required String token,
    required String user,
    required String password,
  }) async {
    final uri = await mediaUri(user: user, password: password);
    final root = await _post(
      uri: uri,
      bodyXml:
          '<GetStreamUri xmlns="$_nsMedia">'
          '<StreamSetup>'
          '<Stream xmlns="$_nsSchema">RTP-Unicast</Stream>'
          '<Transport xmlns="$_nsSchema"><Protocol>RTSP</Protocol></Transport>'
          '</StreamSetup>'
          '<ProfileToken>${_xmlEscape(token)}</ProfileToken>'
          '</GetStreamUri>',
      soapAction: '$_nsMedia/GetStreamUri',
      user: user,
      password: password,
    );

    final streamUri =
        root.findAllElements('tt:Uri').firstOrNull?.innerText.trim() ??
        (throw OnvifException('URL de flux absente de la réponse.'));
    final parsed = Uri.parse(streamUri);
    if ((user.isNotEmpty) && parsed.userInfo.isEmpty) {
      return parsed
          .replace(
            userInfo:
                '${Uri.encodeComponent(user)}:${Uri.encodeComponent(password)}',
          )
          .toString();
    }
    return streamUri;
  }

  /// PTZ : mouvement continu (vitesse −1 à 1). Retourne false si l'appareil
  /// n'accepte pas la commande (pas de PTZ).
  Future<bool> ptzContinuousMove({
    required String profileToken,
    required double panX,
    required double tiltY,
    double zoomX = 0,
  }) async {
    if (_ptzUri == null) {
      await _resolveServices(user: user, password: password);
    }
    String fmt(double v) =>
        v == 0 ? '0' : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
    try {
      await _post(
        uri: _ptzUri!,
        bodyXml:
            '<ContinuousMove xmlns="$_nsPtz">'
            '<ProfileToken>${_xmlEscape(profileToken)}</ProfileToken>'
            '<Velocity>'
            '<PanTilt x="${fmt(panX)}" y="${fmt(tiltY)}" '
            'space="http://www.onvif.org/ver10/tptz/PanTiltSpace"/>'
            '<Zoom x="${fmt(zoomX)}" '
            'space="http://www.onvif.org/ver20/tptz/ZoomSpace"/>'
            '</Velocity>'
            '</ContinuousMove>',
        soapAction: '$_nsPtz/ContinuousMove',
        user: user,
        password: password,
      );
      return true;
    } on OnvifException {
      return false;
    }
  }

  /// PTZ : arrête tout mouvement.
  Future<void> ptzStop({required String profileToken}) async {
    if (_ptzUri == null) {
      await _resolveServices(user: user, password: password);
    }
    try {
      await _post(
        uri: _ptzUri!,
        bodyXml:
            '<Stop xmlns="$_nsPtz">'
            '<ProfileToken>${_xmlEscape(profileToken)}</ProfileToken>'
            '<PanTilt>true</PanTilt>'
            '<Zoom>true</Zoom>'
            '</Stop>',
        soapAction: '$_nsPtz/Stop',
        user: user,
        password: password,
      );
    } on OnvifException {
      // Pas de PTZ ou appareil partiel : on ignore.
    }
  }

  // ── Filtre IR-cut (jour/nuit) — service Imaging ──

  /// Lit le mode actuel du filtre IR-cut. Retourne null si l'appareil
  /// n'expose pas d'Imaging settings (caméra bas de gamme → bouton masqué).
  Future<OnvifIrCutMode?> getIrCutMode({
    required String videoSourceToken,
    required String user,
    required String password,
  }) async {
    if (_imagingUri == null) {
      await _resolveServices(user: user, password: password);
    }
    try {
      final root = await _post(
        uri: _imagingUri!,
        bodyXml:
            '<GetImagingSettings xmlns="$_nsImaging">'
            '<VideoSourceToken>${_xmlEscape(videoSourceToken)}</VideoSourceToken>'
            '</GetImagingSettings>',
        soapAction: '$_nsImaging/GetImagingSettings',
        user: user,
        password: password,
      );
      return parseIrCutModeForTest(root.toXmlString());
    } on OnvifException {
      return null;
    }
  }

  /// Force le filtre IR-cut (jour/nuit/auto). Best-effort : certains
  /// firmwares exigent le document complet → retourne false, l'app
  /// masque alors le contrôle.
  Future<bool> setIrCutMode({
    required String videoSourceToken,
    required OnvifIrCutMode mode,
    required String user,
    required String password,
  }) async {
    if (_imagingUri == null) {
      await _resolveServices(user: user, password: password);
    }
    try {
      await _post(
        uri: _imagingUri!,
        bodyXml: buildSetIrCutBodyForTest(
          videoSourceToken: videoSourceToken,
          mode: mode,
        ),
        soapAction: '$_nsImaging/SetImagingSettings',
        user: user,
        password: password,
      );
      return true;
    } on OnvifException {
      return false;
    }
  }
}

/// Parse le mode IR-cut d'une réponse GetImagingSettings. Le schéma ONVIF
/// est une union : enfant Auto (avec délais), On ou Off sous IrCutFilter.
@visibleForTesting
OnvifIrCutMode? parseIrCutModeForTest(String xml) {
  try {
    final doc = XmlDocument.parse(xml);
    final ir = doc.findAllElements('tt:IrCutFilter').firstOrNull;
    if (ir == null) return null;
    for (final child in ir.children.whereType<XmlElement>()) {
      final name = child.name.local;
      if (name == 'Auto') return OnvifIrCutMode.auto;
      if (name == 'On') return OnvifIrCutMode.on;
      if (name == 'Off') return OnvifIrCutMode.off;
    }
    // Variante défensive : <tt:Mode>On</tt:Mode> (firmwares exotiques).
    final text = ir.innerText.trim().toLowerCase();
    if (text == 'auto') return OnvifIrCutMode.auto;
    if (text == 'on') return OnvifIrCutMode.on;
    if (text == 'off') return OnvifIrCutMode.off;
    return null;
  } on XmlException {
    return null;
  }
}

/// Corps SOAP SetImagingSettings pour basculer le filtre IR-cut.
/// Mise à jour partielle (IrCutFilter seul) — acceptée par la plupart des
/// firmwares ; un refus se traduit par un simple échec best-effort.
@visibleForTesting
String buildSetIrCutBodyForTest({
  required String videoSourceToken,
  required OnvifIrCutMode mode,
}) {
  final escaped = _xmlEscape(videoSourceToken);
  final inner = switch (mode) {
    OnvifIrCutMode.auto => '<tt:Auto/>',
    OnvifIrCutMode.on => '<tt:On/>',
    OnvifIrCutMode.off => '<tt:Off/>',
  };
  return '<SetImagingSettings xmlns="$_nsImagingForHelpers">'
      '<VideoSourceToken>$escaped</VideoSourceToken>'
      '<ImagingSettings '
      'xmlns:tt="http://www.onvif.org/ver10/schema">'
      '<tt:IrCutFilter>$inner</tt:IrCutFilter>'
      '</ImagingSettings>'
      '</SetImagingSettings>';
}

const _nsImagingForHelpers = 'http://www.onvif.org/ver10/imaging/wsdl';

/// Extensions de test : expose le parsing XML sans passer par le réseau.
extension OnvifProfileX on OnvifProfile {
  /// Parse une réponse GetProfiles complète (exposé pour les tests).
  static List<OnvifProfile> parseForTest(String xml) {
    final doc = XmlDocument.parse(xml);
    return _parseProfiles(doc.rootElement);
  }
}

List<OnvifProfile> _parseProfiles(XmlElement root) {
  final profiles = <OnvifProfile>[];
  for (final node in root.findAllElements('trt:Profiles')) {
    final token = node.getAttribute('token');
    if (token == null) continue;
    final name =
        node.findElements('tt:Name').firstOrNull?.innerText ?? 'Profil';
    final resolution = node.findAllElements('tt:Resolution').firstOrNull;
    final width = int.tryParse(resolution?.getAttribute('Width') ?? '');
    final height = int.tryParse(resolution?.getAttribute('Height') ?? '');
    final hasPtz = node.findAllElements('tt:PTZConfiguration').isNotEmpty;
    final hasAudio = node
        .findAllElements('tt:AudioEncoderConfiguration')
        .isNotEmpty;
    // Source vidéo (pour le service Imaging / filtre IR).
    final videoSourceToken = node
        .findAllElements('tt:VideoSourceConfiguration')
        .firstOrNull
        ?.findElements('tt:SourceToken')
        .firstOrNull
        ?.innerText;
    profiles.add(
      OnvifProfile(
        token: token,
        name: name,
        width: width,
        height: height,
        hasPtz: hasPtz,
        hasAudio: hasAudio,
        videoSourceToken: videoSourceToken,
      ),
    );
  }
  return profiles;
}

/// Découverte WS-Discovery des caméras ONVIF du réseau local.
Future<List<OnvifDiscovered>> discoverOnvifDevices({
  Duration duration = const Duration(seconds: 3),
}) async {
  final multicast = InternetAddress('239.255.255.250');
  const port = 3702;

  final socket = await RawDatagramSocket.bind(
    InternetAddress.anyIPv4,
    0,
    reuseAddress: true,
    reusePort: false,
  );

  final probe =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" '
      'xmlns:a="http://schemas.xmlsoap.org/ws/2004/08/addressing">'
      '<s:Header>'
      '<a:Action s:mustUnderstand="1">'
      'http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</a:Action>'
      '<a:MessageID>urn:uuid:${_uuidV4()}</a:MessageID>'
      '<a:To s:mustUnderstand="1">'
      'urn:schemas-xmlsoap-org:ws:2005:04:discovery</a:To>'
      '</s:Header>'
      '<s:Body>'
      '<Probe xmlns="http://schemas.xmlsoap.org/ws/2005/04/discovery">'
      '<d:Types xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" '
      'xmlns:dp0="http://www.onvif.org/ver10/network/wsdl">'
      'dp0:NetworkVideoTransmitter</d:Types>'
      '</Probe>'
      '</s:Body>'
      '</s:Envelope>';

  try {
    socket.joinMulticast(multicast);
  } on SocketException {
    // Certains réseaux refusent le join — les réponses unicast suffisent.
    debugPrint('discoverOnvif: joinMulticast refusé, réponse unicast only');
  }

  socket.send(utf8.encode(probe), multicast, port);
  // Deuxième salve après 500 ms capte les appareils lents à répondre.
  await Future<void>.delayed(const Duration(milliseconds: 500));
  socket.send(utf8.encode(probe), multicast, port);

  final found = <String, OnvifDiscovered>{};
  final deadline = DateTime.now().add(duration);
  try {
    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) break;
      final received = socket.receive();
      if (received == null) {
        // Pas encore de paquet : petite pause pour éviter un spin CPU.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }
      final datagram = received;
      final parsed = _parseProbeMatch(
        utf8.decode(datagram.data, allowMalformed: true),
        datagram.address.address,
      );
      if (parsed != null) {
        final key = parsed.xaddrs.first.toString();
        final existing = found[key];
        if (existing == null) {
          found[key] = parsed;
        } else if (existing.name == null && parsed.name != null) {
          found[key] = parsed;
        }
      }
    }
  } finally {
    try {
      socket.leaveMulticast(multicast);
    } on SocketException {
      // ignore
    }
    socket.close();
  }
  return found.values.toList()..sort((a, b) => a.host.compareTo(b.host));
}

@visibleForTesting
OnvifDiscovered? parseProbeMatchForTest(String xml, String source) =>
    _parseProbeMatch(xml, source);

OnvifDiscovered? _parseProbeMatch(String xml, String source) {
  try {
    final doc = XmlDocument.parse(xml);
    if (doc.findAllElements('ProbeMatch').isEmpty) return null;

    final xaddrs = <Uri>[];
    for (final node in doc.findAllElements('d:XAddrs')) {
      for (final part in node.innerText.trim().split(RegExp(r'\s+'))) {
        final uri = Uri.tryParse(part);
        if (uri != null && uri.isScheme('HTTP')) xaddrs.add(uri);
      }
    }
    if (xaddrs.isEmpty) return null;

    String? name;
    final scopes = doc.findAllElements('d:Scopes').firstOrNull?.innerText ?? '';
    for (final scope in scopes.split(' ')) {
      final s = scope.trim();
      if (s.startsWith('onvif://www.onvif.org/name/')) {
        final decoded = Uri.decodeComponent(
          s.substring('onvif://www.onvif.org/name/'.length),
        );
        if (decoded.isNotEmpty) name = decoded;
      }
    }

    return OnvifDiscovered(address: source, xaddrs: xaddrs, name: name);
  } on XmlException {
    return null;
  }
}

String _uuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

// ═══════════════════════════════════════════════════════════
// ÉVÉNEMENTS ONVIF — PullPoint (alertes temps réel)
//
// Cycle de vie WS-BaseNotification (profil ONVIF) :
//   1. createPullPointSubscription → l'appareil réserve un point de
//      retrait et renvoie son URL dédiée (valide ~60 s par défaut).
//   2. pullMessages en boucle (long-poll : l'appel BLOQUE côté serveur
//      jusqu'à un événement ou l'expiration du timeout) → [OnvifEvent].
//   3. renewSubscription périodique pour maintenir la souscription
//      vivante (elle expire sinon — TerminationTime).
//   4. unsubscribe pour libérer proprement.
//
// Événements typiques : tns1:VideoAnalytics/MotionAlarm (détection de
// mouvement, Data/State=true|false), tns1:AudioAnalytics/AudioDetected,
// tns1:RuleEngine/…, tns1:Device/HardwareFailure… — voir [OnvifEvent.topic].
// ═══════════════════════════════════════════════════════════

const _nsEventsWsdl = 'http://www.onvif.org/ver10/events/wsdl';
const _nsWsn = 'http://docs.oasis-open.org/wsn/b-2';

/// Identifiants ONVIF (WS-Security UsernameToken Digest).
class OnvifCredentials {
  const OnvifCredentials({required this.user, required this.password});

  final String user;
  final String password;
}

/// Souscription PullPoint active : [url] est le point de retrait dédié
/// (à passer à [pullMessages] / [renewSubscription] / [unsubscribe]).
class PullPointSubscription {
  const PullPointSubscription({
    required this.url,
    this.currentTime,
    this.terminationTime,
  });

  /// Adresse du pull point (renvoyée par l'appareil, à durée de vie
  /// limitée — renouveler via [renewSubscription]).
  final String url;

  /// Heure appareil au moment de la création.
  final DateTime? currentTime;

  /// Expiration de la souscription — après cette date le pull point
  /// est détruit par l'appareil.
  final DateTime? terminationTime;

  @override
  String toString() => 'PullPointSubscription($url, expire $terminationTime)';
}

/// Notification reçue d'un appareil ONVIF (mouvement, audio, règle…).
class OnvifEvent {
  const OnvifEvent({
    required this.topic,
    this.timestamp,
    this.propertyOperation,
    this.source = const {},
    this.data = const {},
  });

  /// Sujet ONVIF — ex. `tns1:VideoAnalytics/MotionAlarm`,
  /// `tns1:AudioAnalytics/AudioDetected`.
  final String topic;

  /// Horodatage appareil (attribut `UtcTime` du Message).
  final DateTime? timestamp;

  /// `Initialized` / `Changed` / `Deleted`.
  final String? propertyOperation;

  /// Items sources — ex. `{VideoSourceConfiguration: 1}` (quel capteur).
  final Map<String, String> source;

  /// Items données — ex. `{State: true}` (l'état de l'alarme).
  final Map<String, String> data;

  /// Espace de noms du sujet — ex. `tns1:` pour
  /// `tns1:VideoAnalytics/MotionAlarm` (vide si absent).
  String get topicNamespace {
    final i = topic.indexOf(':');
    return i < 0 ? '' : topic.substring(0, i + 1);
  }

  /// Segments hiérarchiques du sujet — ex.
  /// `['VideoAnalytics', 'MotionAlarm']` pour
  /// `tns1:VideoAnalytics/MotionAlarm` (utile au routage UI).
  List<String> get topicSegments {
    var t = topic;
    final i = t.indexOf(':');
    // Ne retire le préfixe que si c'est un namespace (pas un segment).
    if (i >= 0 && !t.substring(0, i).contains('/')) {
      t = t.substring(i + 1);
    }
    return t.split('/').where((s) => s.isNotEmpty).toList();
  }

  /// Événement CRITIQUE — à remonter en alerte (vs mouvement = simple
  /// historique). Sujets concernés : intrusion (LineDetector/
  /// FieldDetector), sabotage/tamper (camera tampering, sabotage),
  /// débranchement (VideoLoss), alarme audio d'agression.
  bool get isCritical {
    final t = topic.toLowerCase();
    return t.contains('intrusion') ||
        t.contains('tamper') ||
        t.contains('sabotage') ||
        t.contains('videoloss') ||
        t.contains('video_loss') ||
        t.contains('linedetector') ||
        t.contains('fielddetector') ||
        t.contains('aggression');
  }

  /// Alarme de mouvement ACTIVE — absorbe la variance des firmwares :
  ///  - sujets : `…/MotionAlarm`, `…/Motion`, `…/CellMotionDetectorAlarm/Motion`
  ///  - items  : `State` (Hikvision), `IsMotion`, `IsActive` (Axis)
  ///  - valeurs : `true`, `yes`, `1`
  bool get isMotionActive {
    if (!topic.contains('Motion')) return false;
    for (final key in const ['State', 'IsMotion', 'IsActive']) {
      final v = data[key]?.toLowerCase();
      if (v == 'true' || v == 'yes' || v == '1') return true;
    }
    return false;
  }

  @override
  String toString() => 'OnvifEvent($topic, $data)';
}

/// Étape 1 — crée une souscription PullPoint sur le service événements
/// de l'appareil (chemin standard `/onvif/event_service`, avec repli sur
/// l'URL fournie pour les appareils atypiques). Durée initiale : 1 min.
Future<PullPointSubscription> createPullPointSubscription(
  String deviceUrl,
  OnvifCredentials creds,
) async {
  final base = Uri.tryParse(deviceUrl);
  if (base == null || !base.hasScheme) {
    throw OnvifException('URL d\'appareil invalide : $deviceUrl');
  }

  const body =
      '<CreatePullPointSubscription xmlns="$_nsEventsWsdl">'
      '<InitialTerminationTime>PT1M</InitialTerminationTime>'
      '</CreatePullPointSubscription>';
  const action = '$_nsEventsWsdl/CreatePullPointSubscription';

  XmlElement root;
  try {
    root = await _eventsPost(
      uri: base.replace(path: '/onvif/event_service'),
      bodyXml: body,
      soapAction: action,
      creds: creds,
    );
  } on OnvifException {
    // Repli : certains firmwares n'exposent pas le chemin standard du
    // service événements — on retente l'URL appareil telle quelle.
    root = await _eventsPost(
      uri: base,
      bodyXml: body,
      soapAction: action,
      creds: creds,
    );
  }
  return parsePullPointSubscriptionForTest(root.toXmlString());
}

/// Étape 2 — retire les événements en attente (long-poll : l'appel
/// bloque côté appareil jusqu'à un événement ou [timeout]).
/// Retourne les notifications reçues (souvent 0 ou 1 par appel).
Future<List<OnvifEvent>> pullMessages(
  String subscriptionUrl,
  OnvifCredentials creds, {
  Duration timeout = const Duration(seconds: 5),
  int messageLimit = 50,
}) async {
  final uri = Uri.tryParse(subscriptionUrl);
  if (uri == null || !uri.hasScheme) {
    throw OnvifException('URL de souscription invalide.');
  }

  final body =
      '<PullMessages xmlns="$_nsEventsWsdl">'
      '<Timeout>${formatXsDuration(timeout)}</Timeout>'
      '<MessageLimit>$messageLimit</MessageLimit>'
      '</PullMessages>';

  // Marge réseau au-dessus du long-poll serveur.
  final httpTimeout = timeout + const Duration(seconds: 10);

  final root = await _eventsPost(
    uri: uri,
    bodyXml: body,
    soapAction: '$_nsEventsWsdl/PullMessages',
    creds: creds,
    timeout: httpTimeout,
  );
  return parseOnvifEventsForTest(root.toXmlString());
}

/// Étape 3 — prolonge la souscription avant son expiration (défaut 1 min).
/// À appeler périodiquement pendant la boucle de pull.
Future<void> renewSubscription(
  String subscriptionUrl,
  OnvifCredentials creds, {
  Duration? terminationTime,
}) async {
  final uri = Uri.tryParse(subscriptionUrl);
  if (uri == null || !uri.hasScheme) {
    throw OnvifException('URL de souscription invalide.');
  }

  final t = formatXsDuration(terminationTime ?? const Duration(minutes: 1));
  final body =
      '<wsnt:Renew xmlns:wsnt="$_nsWsn">'
      '<wsnt:TerminationTime>$t</wsnt:TerminationTime>'
      '</wsnt:Renew>';

  await _eventsPost(
    uri: uri,
    bodyXml: body,
    soapAction: '$_nsWsn/Renew',
    creds: creds,
  );
}

/// Étape 4 — libère le pull point côté appareil.
Future<void> unsubscribe(String subscriptionUrl, OnvifCredentials creds) async {
  final uri = Uri.tryParse(subscriptionUrl);
  if (uri == null || !uri.hasScheme) {
    throw OnvifException('URL de souscription invalide.');
  }

  const body = '<wsnt:Unsubscribe xmlns:wsnt="$_nsWsn"/>';

  await _eventsPost(
    uri: uri,
    bodyXml: body,
    soapAction: '$_nsWsn/Unsubscribe',
    creds: creds,
  );
}

/// Formate une [Duration] en xs:duration (PT5S, PT1M30S…).
String formatXsDuration(Duration d) {
  final s = d.inSeconds;
  if (s == 0) return 'PT0S';
  if (s < 60) return 'PT${s}S';
  final m = s ~/ 60;
  final rest = s % 60;
  return 'PT${m}M${rest > 0 ? '${rest}S' : ''}';
}

/// POST SOAP vers un service événements, avec WS-Security Digest et
/// gestion d'erreurs alignée sur [OnvifDevice].
Future<XmlElement> _eventsPost({
  required Uri uri,
  required String bodyXml,
  required String soapAction,
  required OnvifCredentials creds,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final envelope = OnvifDevice.soapEnvelope(
    bodyXml: bodyXml,
    action: soapAction,
    user: creds.user,
    password: creds.password,
  );

  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client
        .postUrl(uri)
        .timeout(
          timeout,
          onTimeout: () => throw OnvifException(
            'Délai dépassé — l\'appareil ne répond pas.',
          ),
        );
    request.headers.contentType = ContentType(
      'application',
      'soap+xml',
      charset: 'utf-8',
    );
    request.write(envelope);

    final response = await request.close().timeout(timeout);
    final text = await response.transform(utf8.decoder).join().timeout(timeout);
    final doc = XmlDocument.parse(text);

    final fault =
        doc.findAllElements('SOAP-ENV:Fault').firstOrNull ??
        doc.findAllElements('s:Fault').firstOrNull;
    if (fault != null) {
      final textNode =
          fault.findAllElements('SOAP-ENV:Text').firstOrNull?.innerText ??
          fault.findAllElements('s:text').firstOrNull?.innerText ??
          'Erreur ONVIF';
      final subcode = fault.innerText;
      if (subcode.contains('NotAuthorized') ||
          subcode.contains('SenderNotAuthorized')) {
        throw OnvifException(
          'Identifiants refusés par la caméra (authentification ONVIF).',
        );
      }
      throw OnvifException('Caméra ONVIF : $textNode');
    }
    return doc.rootElement;
  } on SocketException {
    throw OnvifException(
      'Appareil injoignable (${uri.host}) — vérifiez le réseau.',
    );
  } on TimeoutException {
    throw OnvifException('Délai dépassé — l\'appareil ne répond pas.');
  } on XmlException {
    throw OnvifException('Réponse illisible (pas un appareil ONVIF ?).');
  } finally {
    client.close();
  }
}

// ═══════════════════════════════════════════════════════
// REPLAY ONVIF — Recording Search + Replay (standard)
//
// Couvre Dahua, Axis, Uniview, Hikvision… d'un coup via le service
// standard `ver10/search.wsdl` : FindRecordings → boucle
// GetRecordingSearchResults → GetReplayUri (URL RTSP prête à lire).
// ═════════════════════════════════════════════════════

const _nsSearchWsdl = 'http://www.onvif.org/ver10/search/wsdl';

/// Segment d'enregistrement trouvé via ONVIF Recording Search.
class RecordingSegment {
  const RecordingSegment({
    required this.recordingToken,
    required this.start,
    required this.end,
    this.sourceToken,
  });

  /// Token de l'enregistrement (pour GetReplayUri).
  final String recordingToken;

  /// Token de la source (caméra/canal) si exposé.
  final String? sourceToken;

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  @override
  String toString() => 'RecordingSegment($sourceToken, $start → $end)';
}

/// Résultat d'une recherche multi-étapes (token de session + segments).
class RecordingSearchResult {
  const RecordingSearchResult({
    required this.searchToken,
    required this.segments,
    this.moreResults = false,
  });

  /// Token de session de recherche (à passer à
  /// [getRecordingSearchResults] / [endSearch]).
  final String searchToken;

  final List<RecordingSegment> segments;

  /// true → d'autres résultats disponibles (pagination).
  final bool moreResults;
}

String _isoUtc(DateTime t) =>
    t.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+'), '');

/// Étape 1 — lance une recherche d'enregistrements sur la période
/// [from]–[to] (optionnellement filtrée sur un canal via [sourceToken]).
/// Retourne le token de session + les premiers segments.
Future<RecordingSearchResult> findRecordings(
  String deviceUrl,
  OnvifCredentials creds, {
  required DateTime from,
  required DateTime to,
  String? sourceToken,
}) async {
  final base = Uri.tryParse(deviceUrl);
  if (base == null || !base.hasScheme) {
    throw OnvifException('URL d\'appareil invalide : $deviceUrl');
  }

  final sourceFilter = sourceToken == null
      ? ''
      : '<tt:Source><tt:Token>$sourceToken</tt:Token></tt:Source>';

  final body =
      '<FindRecordings xmlns="$_nsSearchWsdl">'
      '<MaxResults>100</MaxResults>'
      '<SearchScope>'
      '<tt:RecordingInformationFilter>'
      '<tt:Source>true</tt:Source>'
      '<tt:Extension/>‘'
      '</tt:RecordingInformationFilter>'
      '$sourceFilter'
      '<tt:Extension>'
      '<tt:Time>/</tt:Time>'
      '<tt:TimeFrom>${_isoUtc(from)}</tt:TimeFrom>'
      '<tt:TimeTill>${_isoUtc(to)}</tt:TimeTill>'
      '</tt:Extension>'
      '</SearchScope>'
      '</FindRecordings>';

  final root = await _eventsPost(
    uri: base.replace(path: '/onvif/RecordingSearch'),
    bodyXml: body,
    soapAction: '$_nsSearchWsdl/FindRecordings',
    creds: creds,
  );
  return parseRecordingSearchForTest(root.toXmlString());
}

/// Étape 2 — récupère les résultats suivants d'une recherche en cours
/// (une caméra renvoie souvent par lots de 100).
Future<List<RecordingSegment>> getRecordingSearchResults(
  String searchToken,
  String deviceUrl,
  OnvifCredentials creds,
) async {
  final base = Uri.tryParse(deviceUrl);
  if (base == null) throw OnvifException('URL invalide.');

  final body =
      '<GetRecordingSearchResults xmlns="$_nsSearchWsdl">'
      '<SearchToken>$searchToken</SearchToken>'
      '<MinResults>1</MinResults>'
      '<MaxResults>100</MaxResults>'
      '</GetRecordingSearchResults>';

  final root = await _eventsPost(
    uri: base.replace(path: '/onvif/RecordingSearch'),
    bodyXml: body,
    soapAction: '$_nsSearchWsdl/GetRecordingSearchResults',
    creds: creds,
  );
  return parseRecordingSegmentsForTest(root.toXmlString());
}

/// Termime une session de recherche (libère les ressources appareil).
Future<void> endSearch(
  String searchToken,
  String deviceUrl,
  OnvifCredentials creds,
) async {
  final base = Uri.tryParse(deviceUrl);
  if (base == null) return;
  try {
    await _eventsPost(
      uri: base.replace(path: '/onvif/RecordingSearch'),
      bodyXml:
          '<EndSearch xmlns="$_nsSearchWsdl">'
          '<SearchToken>$searchToken</SearchToken>'
          '</EndSearch>',
      soapAction: '$_nsSearchWsdl/EndSearch',
      creds: creds,
    );
  } on OnvifException {
    // Fin de session best-effort — on ignore.
  }
}

/// Étape 3 — URL RTSP de rejeu d'un enregistrement
/// (protocole par défaut : RTSP).
Future<String> getReplayUri(
  String recordingToken,
  String deviceUrl,
  OnvifCredentials creds, {
  String protocol = 'RTSP',
}) async {
  final base = Uri.tryParse(deviceUrl);
  if (base == null) throw OnvifException('URL invalide.');

  final body =
      '<GetReplayUri xmlns="http://www.onvif.org/ver10/replay/wsdl">'
      '<StreamSetup>'
      '<tt:Stream>RTP-Unicast</tt:Stream>'
      '<tt:Transport><tt:Protocol>$protocol</tt:Protocol></tt:Transport>'
      '</StreamSetup>'
      '<RecordingToken>$recordingToken</RecordingToken>'
      '</GetReplayUri>';

  final root = await _eventsPost(
    uri: base.replace(path: '/onvif/Replay'),
    bodyXml: body,
    soapAction: 'http://www.onvif.org/ver10/replay/wsdl/GetReplayUri',
    creds: creds,
  );

  // URI dans tt:Uri (même forme que GetStreamUri).
  for (final e in root.descendants.whereType<XmlElement>()) {
    if (e.name.local == 'Uri') {
      final raw = e.innerText.trim();
      final parsed = Uri.tryParse(raw);
      if (parsed != null &&
          parsed.isScheme('rtsp') &&
          creds.user.isNotEmpty &&
          parsed.userInfo.isEmpty) {
        return parsed
            .replace(
              userInfo:
                  '${Uri.encodeComponent(creds.user)}:'
                  '${Uri.encodeComponent(creds.password)}',
            )
            .toString();
      }
      return raw;
    }
  }
  throw OnvifException(
    'URL de rejeu absente — enregistrement peut-être purgé.',
  );
}

/// Recherche COMPLÈTE en un appel : Find + pagination des résultats +
/// EndSearch. Retourne des segments avec leur URL de rejeu RTSP prête
/// à jouer (GetReplayUri par segment).
Future<List<({DateTime start, DateTime end, String replayUrl})>>
findReplaySegments(
  String deviceUrl,
  OnvifCredentials creds, {
  required DateTime from,
  required DateTime to,
  String? sourceToken,
}) async {
  final search = await findRecordings(
    deviceUrl,
    creds,
    from: from,
    to: to,
    sourceToken: sourceToken,
  );

  final all = [...search.segments];
  var more = search.moreResults;
  var guard = 0;
  while (more && guard < 10) {
    guard++;
    final next = await getRecordingSearchResults(
      search.searchToken,
      deviceUrl,
      creds,
    );
    all.addAll(next);
    more = next.length >= 100; // lot plein → probablement plus
  }

  await endSearch(search.searchToken, deviceUrl, creds);

  // Résout chaque URL de rejeu (limite le nombre pour éviter les
  // dizaines de secondes sur les gros inventaires).
  final top = all.take(20).toList();
  return [
    for (final seg in top)
      (
        start: seg.start,
        end: seg.end,
        replayUrl: await getReplayUri(seg.recordingToken, deviceUrl, creds),
      ),
  ];
}

/// Parse une réponse FindRecordings (token + segments + More).
@visibleForTesting
RecordingSearchResult parseRecordingSearchForTest(String xml) {
  final doc = XmlDocument.parse(xml);

  String token = '';
  for (final e in doc.descendants.whereType<XmlElement>()) {
    if (e.name.local == 'SearchToken' && token.isEmpty) {
      token = e.innerText.trim();
    }
  }
  if (token.isEmpty) {
    throw OnvifException(
      'Recherche refusée — service Recording Search absent de '
      'cet appareil (repli constructeur utilisé).',
    );
  }

  final segments = parseRecordingSegmentsForTest(xml);
  final more = doc.descendants.whereType<XmlElement>().any(
    (e) => e.name.local == 'MoreUpdates' || e.name.local == 'MoreResults',
  );

  return RecordingSearchResult(
    searchToken: token,
    segments: segments,
    moreResults: more,
  );
}

/// Parse les segments d'une réponse Find/GetRecordingSearchResults.
@visibleForTesting
List<RecordingSegment> parseRecordingSegmentsForTest(String xml) {
  final doc = XmlDocument.parse(xml);
  final segments = <RecordingSegment>[];

  for (final item in doc.descendants.whereType<XmlElement>().where(
    (e) => e.name.local == 'RecordingInformation',
  )) {
    String token = '';
    String? source;
    DateTime? start;
    DateTime? end;

    for (final e in item.descendants.whereType<XmlElement>()) {
      switch (e.name.local) {
        case 'RecordingToken':
          if (token.isEmpty) token = e.innerText.trim();
        case 'SourceToken':
          source ??= e.innerText.trim();
        case 'BeginDateTime':
          start ??= DateTime.tryParse(e.innerText.trim());
        case 'EndDateTime':
          end ??= DateTime.tryParse(e.innerText.trim());
      }
    }

    if (token.isEmpty || start == null || end == null) continue;
    if (!end.isAfter(start)) continue;
    segments.add(
      RecordingSegment(
        recordingToken: token,
        sourceToken: source,
        start: start,
        end: end,
      ),
    );
  }

  segments.sort((a, b) => a.start.compareTo(b.start));
  return segments;
}

/// Parse une réponse CreatePullPointSubscription (exposé aux tests).
@visibleForTesting
PullPointSubscription parsePullPointSubscriptionForTest(String xml) {
  final doc = XmlDocument.parse(xml);

  String url = '';
  DateTime? currentTime;
  DateTime? terminationTime;

  // Les préfixes varient selon les firmwares (wsa:, wsa5:, sans préfixe) :
  // on cible les noms LOCAUX.
  for (final e in doc.descendants.whereType<XmlElement>()) {
    final local = e.name.local;
    if (local == 'Address' && url.isEmpty) {
      url = e.innerText.trim();
    } else if (local == 'CurrentTime' && currentTime == null) {
      currentTime = DateTime.tryParse(e.innerText.trim());
    } else if (local == 'TerminationTime' && terminationTime == null) {
      terminationTime = DateTime.tryParse(e.innerText.trim());
    }
  }

  if (url.isEmpty) {
    throw OnvifException(
      'Souscription refusée — pas d\'adresse de pull point dans la réponse.',
    );
  }
  return PullPointSubscription(
    url: url,
    currentTime: currentTime,
    terminationTime: terminationTime,
  );
}

/// Parse une réponse PullMessages en événements (exposé aux tests).
@visibleForTesting
List<OnvifEvent> parseOnvifEventsForTest(String xml) {
  final doc = XmlDocument.parse(xml);
  final events = <OnvifEvent>[];

  for (final msg in doc.descendants.whereType<XmlElement>().where(
    (e) => e.name.local == 'NotificationMessage',
  )) {
    // Sujet (ex. tns1:VideoAnalytics/MotionAlarm).
    String topic = '';
    for (final t in msg.descendants.whereType<XmlElement>()) {
      if (t.name.local == 'Topic') {
        topic = t.innerText.trim();
        break;
      }
    }

    // Message interne tt:Message (porteur des données) — le wrapper
    // wsnt:Message porte le même nom local : on prend celui qui possède
    // l'attribut UtcTime ou des enfants Source/Data.
    XmlElement? inner;
    final candidates = msg.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'Message')
        .toList();
    for (final c in candidates) {
      final hasUtc = c.attributes.any((a) => a.name.local == 'UtcTime');
      final hasPayload = c.children.whereType<XmlElement>().any(
        (child) => child.name.local == 'Source' || child.name.local == 'Data',
      );
      if (hasUtc || hasPayload) {
        inner = c;
        break;
      }
    }
    inner ??= candidates.isEmpty ? null : candidates.last;

    DateTime? timestamp;
    String? operation;
    final source = <String, String>{};
    final data = <String, String>{};

    if (inner != null) {
      for (final a in inner.attributes) {
        if (a.name.local == 'UtcTime') {
          timestamp = DateTime.tryParse(a.value);
        } else if (a.name.local == 'PropertyOperation') {
          operation = a.value;
        }
      }
      for (final container in inner.children.whereType<XmlElement>()) {
        final isSource = container.name.local == 'Source';
        final isData = container.name.local == 'Data';
        if (!isSource && !isData) continue;
        for (final item in container.descendants.whereType<XmlElement>()) {
          // Deux formes coexistent sur le terrain : le schéma canonique
          // ONVIF (`tt:SimpleItem`, majoritaire — Hikvision/Dahua) et la
          // variante `tt:SimpleItemValue` de certains firmwares. Les deux
          // portent Name/Value en attributs.
          final local = item.name.local;
          if (local != 'SimpleItem' && local != 'SimpleItemValue') continue;
          final name = item.getAttribute('Name');
          final value = item.getAttribute('Value');
          if (name == null) continue;
          (isSource ? source : data)[name] = value ?? '';
        }
      }
    }

    events.add(
      OnvifEvent(
        topic: topic,
        timestamp: timestamp,
        propertyOperation: operation,
        source: source,
        data: data,
      ),
    );
  }
  return events;
}
