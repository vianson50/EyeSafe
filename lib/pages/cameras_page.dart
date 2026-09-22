import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:record/record.dart';

import '../data/g711.dart';
import '../data/models.dart';
import '../data/brand_api.dart';
import '../data/dahua_api.dart';
import '../data/go2rtc.dart';
import '../data/isapi.dart';
import '../data/onvif.dart';
import '../data/site_controller.dart';
import '../data/stream_scheduler.dart';
import '../data/rtc_config.dart';
import '../data/whep.dart';
import '../ui/data_scope.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/network_settings.dart';

/// Mosaïque des caméras du site actif + lecture en direct plein écran.
class CamerasPage extends StatelessWidget {
  const CamerasPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = DataScope.of(context);
    final cameras = data.equipment
        .where((e) => e.category == EquipmentCategory.camera)
        .toList();
    final liveCount = cameras.where((c) => c.isLive).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final columns = constraints.maxWidth >= 1400
            ? 4
            : constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final padding = EdgeInsets.all(wide ? 32.0 : 20);

        return SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Caméras en direct',
                subtitle:
                    'Surveillance temps réel de votre installation — '
                    '${cameras.length} caméra${cameras.length > 1 ? 's' : ''} '
                    'référencée${cameras.length > 1 ? 's' : ''}, '
                    '$liveCount en direct.',
                actions: [
                  if (liveCount > 0)
                    TechBadge(
                      '$liveCount FLUX ACTIFS',
                      color: AppColors.tertiary,
                      background: AppColors.tertiaryContainer,
                    ),
                  if (data.isTechnician)
                    CircleIconButton(
                      icon: Icons.tune_outlined,
                      size: 38,
                      iconSize: 18,
                      onTap: () => showNetworkSettingsDialog(context, data),
                    ),
                  if (data.isTechnician)
                    PrimaryButton(
                      label: 'Connecter un NVR',
                      icon: Icons.add_circle_outline,
                      height: 40,
                      onTap: () => _openConnectDialog(context, data),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (cameras.isEmpty) ...[
                Text(
                  data.isTechnician
                      ? 'Aucune caméra sur ce site — connectez le NVR du client '
                            'avec le bouton « Connecter un NVR ».'
                      : 'Aucune caméra référencée sur ce site. Votre installateur '
                            'peut les connecter en quelques secondes.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                if (data.isTechnician) ...[
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Connecter un NVR',
                    icon: Icons.add_circle_outline,
                    onTap: () => _openConnectDialog(context, data),
                  ),
                ],
              ] else
                Builder(
                  builder: (context) {
                    // Alimente l'ordonnanceur de bande passante avec
                    // l'ordre d'affichage (les N premières = aperçu live,
                    // les autres = snapshots 5 s).
                    data.streams.updateCameras(
                      cameras.map((c) => c.id).toList(),
                    );
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 16 / 10,
                      ),
                      itemCount: cameras.length,
                      itemBuilder: (context, i) => _CameraTile(
                        camera: cameras[i],
                        onTap: () => _openLive(context, cameras[i]),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _openConnectDialog(BuildContext context, SiteController data) {
    showDialog(
      context: context,
      builder: (dialogContext) => _ConnectNvrDialog(
        onTestEndpoint: (host, port) =>
            SiteController.testEndpoint(host: host, port: port),
        onAddOnvif: (device, profiles) async {
          Navigator.of(dialogContext).pop();
          final error = await data.addOnvifCameras(
            device: device,
            profiles: profiles,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.onSurface,
                  content: Text(
                    error ??
                        '✔ ${profiles.length} caméra'
                            '${profiles.length > 1 ? 's' : ''} ONVIF '
                            'créée${profiles.length > 1 ? 's' : ''} — testez le direct !',
                  ),
                ),
              );
          }
        },
        onAddRelay: (server, streams) async {
          Navigator.of(dialogContext).pop();
          final error = await data.addGo2rtcCameras(
            server: server,
            streams: streams,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.onSurface,
                  content: Text(
                    error ??
                        '✔ ${streams.length} caméra'
                            '${streams.length > 1 ? 's' : ''} relais créée'
                            '${streams.length > 1 ? 's' : ''} — testez le direct !',
                  ),
                ),
              );
          }
        },
        onPairCloud: (server, pairingCode, streams) async {
          Navigator.of(dialogContext).pop();
          final error = await data.addGo2rtcCameras(
            server: server,
            streams: streams,
            locationLabel: 'Cloud · ${CloudPairing.normalize(pairingCode)}',
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.onSurface,
                  content: Text(
                    error ??
                        '✔ Boîtier ${CloudPairing.normalize(pairingCode)} '
                            'appairé — ${streams.length} caméra'
                            '${streams.length > 1 ? 's' : ''} disponible'
                            '${streams.length > 1 ? 's' : ''} !',
                  ),
                ),
              );
          }
        },
        onLoadCloudUrl: data.loadCloudUrl,
        onSaveCloudUrl: data.saveCloudUrl,
        onAddBrandCameras:
            ({
              required brand,
              required host,
              required httpPort,
              required rtspPort,
              required user,
              required password,
              required allowSelfSigned,
              required info,
              required channels,
              required motionDetection,
            }) async {
              Navigator.of(dialogContext).pop();
              final error = await data.addBrandCameras(
                brand: brand,
                host: host,
                httpPort: httpPort,
                rtspPort: rtspPort,
                user: user,
                password: password,
                allowSelfSigned: allowSelfSigned,
                info: info,
                channels: channels,
                motionDetection: motionDetection,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: AppColors.onSurface,
                      content: Text(
                        error ??
                            '✔ ${channels.length} caméra'
                                '${channels.length > 1 ? 's' : ''} $brand créée'
                                '${channels.length > 1 ? 's' : ''}'
                                '${motionDetection ? ' · intrusion activée' : ''} !',
                      ),
                    ),
                  );
              }
            },
        onSubmitNvr:
            (
              brand,
              host,
              port,
              user,
              password,
              channels,
              prefix,
              remote,
            ) async {
              Navigator.of(dialogContext).pop();
              final error = await data.connectNvr(
                brand: brand,
                host: host,
                port: port,
                user: user,
                password: password,
                channels: channels,
                namePrefix: prefix,
                remote: remote,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: AppColors.onSurface,
                      content: Text(
                        error ??
                            '✔ $channels caméra${channels > 1 ? 's' : ''} créée${channels > 1 ? 's' : ''}'
                                '${remote ? ' (accès distant)' : ''} — testez le direct !',
                      ),
                    ),
                  );
              }
            },
        onSubmitUrl: (name, url) async {
          Navigator.of(dialogContext).pop();
          final error = await data.addCameraByUrl(name: name, url: url);
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.onSurface,
                  content: Text(
                    error ?? '✔ Caméra « $name » ajoutée — testez le direct !',
                  ),
                ),
              );
          }
        },
      ),
    );
  }

  Future<void> _openLive(BuildContext context, Equipment camera) async {
    if (camera.streamUrl == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.onSurface,
            content: Text(
              'Flux non configuré pour « ${camera.name} » '
              '(votre installateur doit l\'activer).',
            ),
          ),
        );
      return;
    }

    // Autorisation d'accès au flux vérifiée côté SERVEUR (tenant + rôle)
    // à chaque ouverture de direct — jamais confiance au client.
    final data = DataScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final authorizedUrl = await data.authorizedStreamUrl(camera);
    if (authorizedUrl == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
            content: Text(
              'Accès au flux refusé — votre compte n\'est plus rattaché à ce '
              'site.',
            ),
          ),
        );
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 250),
        // DataScope : la route vit au-dessus du scope de la page —
        // on l'enveloppe pour le PTZ/IR (authorizedPtzControl) qui y
        // accède depuis _LiveViewState.
        pageBuilder: (_, _, _) => DataScope(
          controller: data,
          child: _LiveView(camera: camera, streamUrl: authorizedUrl),
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

/// Assistant de connexion des caméras existantes du client.
/// Mode 1 : NVR Hikvision/Dahua → création automatique par canal.
/// Mode 2 : URL de flux directe (marque exotique, go2rtc…).
/// Mode de connexion choisi dans le dialogue.
enum _ConnectMode {
  /// NVR sur le réseau local du site (téléphone sur le WiFi client).
  nvr,

  /// IP publique / domaine (redirection de port) — méthode « IP directe »
  /// type iDMSS / tinyCam.
  remote,

  /// ONVIF : découverte et profils standard, multi-marques.
  onvif,

  /// Relais go2rtc : le serveur du site tire le RTSP en local et
  /// rediffuse en HLS via une seule adresse — aucune redirection de port.
  relay,

  /// Cloud P2P EyeSafe : appairage par code boîtier, le flux passe par
  /// TON cloud go2rtc — plug-and-play côté client (façon Hik-Connect).
  cloud,

  /// ISAPI (Hikvision) : contrôle total — deviceInfo réel, canaux de flux
  /// déclarés par l'appareil, alerte intrusion (motion detection).
  isapi,

  /// URL de flux exacte (go2rtc, marque exotique…).
  url,
}

class _ConnectNvrDialog extends StatefulWidget {
  const _ConnectNvrDialog({
    required this.onSubmitNvr,
    required this.onSubmitUrl,
    required this.onTestEndpoint,
    required this.onAddOnvif,
    required this.onAddRelay,
    required this.onPairCloud,
    required this.onLoadCloudUrl,
    required this.onSaveCloudUrl,
    required this.onAddBrandCameras,
  });

  final Future<void> Function(
    String brand,
    String host,
    String port,
    String user,
    String password,
    int channels,
    String prefix,
    bool remote,
  )
  onSubmitNvr;
  final Future<void> Function(String name, String url) onSubmitUrl;

  /// Test TCP host:port — retourne null si joignable, sinon un message.
  final Future<String?> Function(String host, String port) onTestEndpoint;

  /// Ajout de caméras ONVIF (profils déjà résolus côté dialogue).
  final Future<void> Function(OnvifDevice device, List<OnvifProfile> profiles)
  onAddOnvif;

  /// Ajout de caméras relayées par go2rtc.
  final Future<void> Function(Go2rtcServer server, List<Go2rtcStream> streams)
  onAddRelay;

  /// Appairage cloud P2P : (serveur, code d'appairage, flux filtrés).
  final Future<void> Function(
    Go2rtcServer server,
    String pairingCode,
    List<Go2rtcStream> streams,
  )
  onPairCloud;

  /// Ajout de caméras via l'API propriétaire de la marque
  /// (ISAPI Hikvision / VAPIX Axis / LAPI Uniview).
  final Future<void> Function({
    required String brand,
    required String host,
    required int httpPort,
    required int rtspPort,
    required String user,
    required String password,
    required bool allowSelfSigned,
    required IsapiDeviceInfo info,
    required List<IsapiChannel> channels,
    required bool motionDetection,
  })
  onAddBrandCameras;

  /// Charge l'URL du cloud mémorisée sur l'appareil.
  final Future<String> Function() onLoadCloudUrl;

  /// Mémorise l'URL du cloud.
  final Future<void> Function(String url) onSaveCloudUrl;

  @override
  State<_ConnectNvrDialog> createState() => _ConnectNvrDialogState();
}

class _ConnectNvrDialogState extends State<_ConnectNvrDialog> {
  _ConnectMode _mode = _ConnectMode.nvr;
  bool _submitting = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  // ── ONVIF ──
  bool _discovering = false;
  List<OnvifDiscovered> _discovered = [];
  bool _loadingProfiles = false;
  List<OnvifProfile> _profiles = [];
  final Set<String> _selectedProfiles = {};
  String? _onvifError;
  OnvifDiscovered? _selectedDevice;
  final _onvifPortController = TextEditingController(text: '80');

  // ── Relais go2rtc ──
  final _relayUrl = TextEditingController();
  final _relayUser = TextEditingController();
  final _relayPassword = TextEditingController();
  bool _loadingRelay = false;
  List<Go2rtcStream> _relayStreams = [];
  final Set<String> _selectedRelay = {};
  String? _relayError;
  Go2rtcServer? _relayServer;

  // ── Cloud P2P ──
  final _cloudUrl = TextEditingController();
  final _cloudCode = TextEditingController();
  bool _pairing = false;
  bool _cloudUrlLoaded = false;
  List<Go2rtcStream> _cloudStreams = [];
  final Set<String> _selectedCloud = {};
  String? _cloudError;
  Go2rtcServer? _cloudServer;
  String? _pairedCode;

  // ── API MARQUE (ISAPI / VAPIX / LAPI / Dahua HTTP) ──
  String _apiBrand = 'Hikvision';
  static const _apiBrands = ['Hikvision', 'Dahua', 'Axis', 'Uniview'];
  final _isapiPortController = TextEditingController(text: '80');
  final _rtspPortController = TextEditingController(text: '554');
  bool _selfSigned = false;
  bool _interrogating = false;
  IsapiDeviceInfo? _deviceInfo;
  List<IsapiChannel> _isapiChannels = [];
  final Set<int> _selectedIsapi = {};
  String? _isapiError;
  bool _motionDetection = true;

  final _host = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _prefix = TextEditingController(text: 'Caméra');
  final _url = TextEditingController();
  final _urlName = TextEditingController(text: 'Caméra externe');
  final _portController = TextEditingController(text: '554');

  String _brand = 'Hikvision';
  String _port = '554';
  int _channels = 4;
  bool _obscure = true;

  /// Marques supportées par l'adaptateur RTSP (chemins documentés dans
  /// SiteController.rtspUrlFor). Imou = Dahua (marque grand public).
  /// Pour toute autre marque : onglet ONVIF (standard) ou URL SIMPLE.
  static const _brands = ['Hikvision', 'Dahua', 'Axis', 'Uniview', 'Imou'];

  /// Hôte nettoyé : tolère un collé « rtsp://user:pass@host/… » ou un
  /// domaine avec chemin — on ne garde que host (le port se saisit à part).
  String get _cleanHost {
    var h = _host.text.trim();
    for (final scheme in ['rtsp://', 'http://', 'https://']) {
      if (h.startsWith(scheme)) {
        h = h.substring(scheme.length);
        break;
      }
    }
    // Retire un éventuel userInfo (user:pass@) et le chemin.
    final at = h.indexOf('@');
    if (at >= 0) h = h.substring(at + 1);
    final slash = h.indexOf('/');
    if (slash >= 0) h = h.substring(0, slash);
    return h;
  }

  bool get _isNvrLike => _mode != _ConnectMode.url;

  bool get _nvrValid =>
      _cleanHost.isNotEmpty &&
      _user.text.trim().isNotEmpty &&
      _password.text.isNotEmpty;

  /// Validation selon le mode actif.
  bool get _formValid => switch (_mode) {
    _ConnectMode.url => _url.text.trim().isNotEmpty,
    _ConnectMode.onvif => _onvifReady && _selectedProfiles.isNotEmpty,
    _ConnectMode.relay => _selectedRelay.isNotEmpty,
    _ConnectMode.cloud => _selectedCloud.isNotEmpty,
    _ConnectMode.isapi => _selectedIsapi.isNotEmpty,
    _ => _nvrValid,
  };

  String get _effectivePort => _port.trim().isEmpty ? '554' : _port.trim();

  int get _onvifPort {
    final p = int.tryParse(_onvifPortController.text.trim());
    return (p != null && p > 0 && p < 65536) ? p : 80;
  }

  OnvifDevice _buildOnvifDevice() => OnvifDevice(
    host:
        _selectedDevice?.host ??
        (_host.text.trim().isNotEmpty ? _host.text.trim() : ''),
    port: _selectedDevice?.deviceUri.hasPort ?? false
        ? _selectedDevice!.deviceUri.port
        : _onvifPort,
    user: _user.text.trim(),
    password: _password.text,
  );

  bool get _onvifReady =>
      (_selectedDevice != null || _host.text.trim().isNotEmpty) &&
      _user.text.trim().isNotEmpty;

  Future<void> _switchMode(_ConnectMode mode) {
    setState(() {
      _mode = mode;
      _testResult = null;
    });
    // Pré-remplit l'URL du cloud mémorisée (une seule fois par ouverture).
    if (mode == _ConnectMode.cloud && !_cloudUrlLoaded) {
      _cloudUrlLoaded = true;
      widget.onLoadCloudUrl().then((url) {
        if (mounted && _cloudUrl.text.isEmpty) {
          setState(() => _cloudUrl.text = url);
        }
      });
    }
    return Future.value();
  }

  int get _isapiHttpPort {
    final p = int.tryParse(_isapiPortController.text.trim());
    return (p != null && p > 0 && p < 65536) ? p : 80;
  }

  int get _rtspPort {
    final p = int.tryParse(_rtspPortController.text.trim());
    return (p != null && p > 0 && p < 65536) ? p : 554;
  }

  IsapiDevice _buildIsapiDevice() => IsapiDevice(
    host: _cleanHost,
    httpPort: _isapiHttpPort,
    user: _user.text.trim(),
    password: _password.text,
    allowSelfSigned: _selfSigned,
  );

  Future<void> _interrogateIsapi() async {
    if (_interrogating) return;
    if (_cleanHost.isEmpty || _user.text.trim().isEmpty) {
      setState(
        () => _isapiError =
            'Renseignez l\'IP, l\'utilisateur et le mot de passe de l\'appareil.',
      );
      return;
    }
    setState(() {
      _interrogating = true;
      _isapiError = null;
    });

    try {
      final IsapiDeviceInfo info;
      final List<IsapiChannel> channels;
      switch (_apiBrand) {
        case 'Dahua':
          final dahua = DahuaHttp(
            host: _cleanHost,
            httpPort: _isapiHttpPort,
            user: _user.text.trim(),
            password: _password.text,
            allowSelfSigned: _selfSigned,
          );
          info = await dahua.getDeviceInfo();
          channels = const [IsapiChannel(id: 101, name: 'Camera 1')];
        case 'Axis':
          final vapix = AxisVapix(
            host: _cleanHost,
            httpPort: _isapiHttpPort,
            user: _user.text.trim(),
            password: _password.text,
            allowSelfSigned: _selfSigned,
          );
          info = await vapix.getDeviceInfo();
          // VAPIX : une caméra Axis = 1 canal (multi-capteurs → ONVIF).
          channels = const [IsapiChannel(id: 101, name: 'Camera 1')];
        case 'Uniview':
          final lapi = UniviewLapi(
            host: _cleanHost,
            httpPort: _isapiHttpPort,
            user: _user.text.trim(),
            password: _password.text,
            allowSelfSigned: _selfSigned,
          );
          info = await lapi.getDeviceInfo();
          channels = const [IsapiChannel(id: 101, name: 'Camera 1')];
        default:
          final device = _buildIsapiDevice();
          info = await device.getDeviceInfo();
          channels = await device.listChannels();
      }

      if (!mounted) return;
      setState(() {
        _interrogating = false;
        _deviceInfo = info;
        _isapiChannels = channels;
        // Pré-sélection : un flux par caméra (le principal si présent).
        _selectedIsapi
          ..clear()
          ..addAll(channels.where((c) => c.isMainStream).map((c) => c.id));
        if (channels.isEmpty) {
          _isapiError = 'Aucun canal de flux exposé par cet appareil.';
        }
      });
    } on IsapiException catch (e) {
      if (!mounted) return;
      setState(() {
        _interrogating = false;
        _isapiError = e.message;
      });
    } on BrandApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _interrogating = false;
        _isapiError = e.message;
      });
    } on DahuaException catch (e) {
      if (!mounted) return;
      setState(() {
        _interrogating = false;
        _isapiError = e.message;
      });
    }
  }

  Future<void> _pairCloud() async {
    if (_pairing) return;
    final code = _cloudCode.text.trim();
    if (code.isEmpty) {
      setState(() => _cloudError = 'Renseignez le code d\'appairage.');
      return;
    }
    if (_cloudUrl.text.trim().isEmpty) {
      setState(() => _cloudError = 'Renseignez l\'URL du cloud EyeSafe.');
      return;
    }
    setState(() {
      _pairing = true;
      _cloudError = null;
    });

    // Mémorise l'URL du cloud pour la prochaine fois.
    try {
      await widget.onSaveCloudUrl(_cloudUrl.text.trim());
    } catch (_) {
      // Mémoire indisponible : la saisie restera volatile.
    }

    final server = Go2rtcServer(baseUrl: _cloudUrl.text.trim());
    try {
      final all = await server.listStreams();
      final matched = CloudPairing.filter(all, code);
      if (!mounted) return;
      setState(() {
        _pairing = false;
        if (matched.isEmpty) {
          _cloudStreams = [];
          _selectedCloud.clear();
          _cloudError = all.isEmpty
              ? 'Aucun flux sur ce cloud — vérifiez l\'URL.'
              : 'Aucun flux pour le code ${CloudPairing.normalize(code)} '
                    'sur ce cloud (${all.length} flux d\'autres boîtiers). '
                    'Vérifiez le code sur l\'étiquette du boîtier.';
          return;
        }
        _cloudServer = server;
        _pairedCode = code;
        _cloudStreams = matched;
        _selectedCloud
          ..clear()
          ..addAll(matched.map((s) => s.name));
      });
    } on Go2rtcException catch (e) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _cloudError = e.message;
      });
    }
  }

  Future<void> _loadRelayStreams() async {
    if (_loadingRelay) return;
    final url = _relayUrl.text.trim();
    if (url.isEmpty) {
      setState(() => _relayError = 'Renseignez l\'URL du serveur go2rtc.');
      return;
    }
    setState(() {
      _loadingRelay = true;
      _relayError = null;
    });
    final server = Go2rtcServer(
      baseUrl: url,
      username: _relayUser.text.trim().isEmpty ? null : _relayUser.text.trim(),
      password: _relayPassword.text,
    );
    try {
      final streams = await server.listStreams();
      if (!mounted) return;
      setState(() {
        _relayServer = server;
        _relayStreams = streams;
        _loadingRelay = false;
        _selectedRelay
          ..clear()
          ..addAll(streams.map((s) => s.name));
        if (streams.isEmpty) {
          _relayError =
              'Aucun flux configuré sur ce serveur go2rtc\n'
              '(ajoutez-les dans go2rtc.yaml, section streams:).';
        }
      });
    } on Go2rtcException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRelay = false;
        _relayError = e.message;
      });
    }
  }

  Future<void> _discoverOnvif() async {
    if (_discovering) return;
    setState(() {
      _discovering = true;
      _onvifError = null;
      _discovered = [];
    });
    try {
      final devices = await discoverOnvifDevices(
        duration: const Duration(seconds: 3),
      );
      if (!mounted) return;
      setState(() {
        _discovered = devices;
        _discovering = false;
        if (devices.isEmpty) {
          _onvifError =
              'Aucune caméra ONVIF trouvée sur ce réseau.\n'
              'Vérifiez que le téléphone est sur le WiFi du site.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _discovering = false;
        _onvifError = 'Découverte impossible : $e';
      });
    }
  }

  Future<void> _loadOnvifProfiles() async {
    if (_loadingProfiles || !_onvifReady) return;
    setState(() {
      _loadingProfiles = true;
      _onvifError = null;
    });
    final device = _buildOnvifDevice();
    try {
      final profiles = await device.getProfiles(
        user: device.user,
        password: device.password,
      );
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _loadingProfiles = false;
        // Pré-sélection : tous les profils PTZ + le premier profil sans PTZ
        // (le main stream typiquement).
        _selectedProfiles
          ..clear()
          ..addAll(profiles.where((p) => p.hasPtz).map((p) => p.token));
        final firstNoPtz = profiles.where((p) => !p.hasPtz).firstOrNull;
        if (firstNoPtz != null) _selectedProfiles.add(firstNoPtz.token);
        if (profiles.isEmpty) {
          _onvifError = 'Aucun profil de flux exposé par cet appareil.';
        }
      });
    } on OnvifException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProfiles = false;
        _onvifError = e.message;
      });
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _password.dispose();
    _prefix.dispose();
    _url.dispose();
    _urlName.dispose();
    _portController.dispose();
    _onvifPortController.dispose();
    _relayUrl.dispose();
    _relayUser.dispose();
    _relayPassword.dispose();
    _cloudUrl.dispose();
    _cloudCode.dispose();
    _isapiPortController.dispose();
    _rtspPortController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {bool obscure = false}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
      filled: true,
      fillColor: AppColors.surfaceLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.outline),
      ),
      suffixIcon: obscure
          ? IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 19,
                color: AppColors.onSurfaceFaint,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            )
          : null,
    );
  }

  Future<void> _testConnection() async {
    if (_testing || !_nvrValid) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final error = await widget.onTestEndpoint(_cleanHost, _effectivePort);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = error == null;
      _testResult = error ?? '✓ Hôte joignable — port ouvert.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Connecter les caméras',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: AppColors.onSurface,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              switch (_mode) {
                _ConnectMode.nvr =>
                  'Récupère les caméras DÉJÀ installées chez le client '
                      '(téléphone sur le WiFi du site).',
                _ConnectMode.remote =>
                  'Connexion directe à l\'IP publique ou au domaine du site '
                      '(redirection de port sur le routeur) — comme iDMSS ou '
                      'tinyCam.',
                _ConnectMode.onvif =>
                  'Standard multi-marques : découverte automatique des caméras '
                      'du réseau, profils de flux et PTZ (Hikvision, Dahua, '
                      'Axis…).',
                _ConnectMode.relay =>
                  'Via votre serveur go2rtc (chez le client ou dans le cloud) : '
                      'les flux sont relayés en HLS depuis une seule adresse, '
                      'sans exposer le RTSP ni ouvrir de port par caméra.',
                _ConnectMode.cloud =>
                  'Plug-and-play façon Hik-Connect, mais sur VOTRE cloud : le '
                      'boîtier du site établit la connexion sortante — aucun '
                      'port à ouvrir. Entrez simplement le code du boîtier.',
                _ConnectMode.isapi =>
                  'Contrôle total via l\'API propriétaire : ISAPI (Hikvision), '
                      'VAPIX (Axis), LAPI (Uniview) — modèle, n° série, firmware '
                      'réels, canaux de flux, alerte intrusion (Hikvision).',
                _ConnectMode.url =>
                  'Une seule caméra via son URL de flux exacte.',
              },
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            // Sélecteur de mode (grille 2×2)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _modeTab(_ConnectMode.nvr, 'NVR LOCAL'),
                      _modeTab(_ConnectMode.remote, 'IP / DOMAINE'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _modeTab(_ConnectMode.onvif, 'ONVIF'),
                      _modeTab(_ConnectMode.relay, 'RELAI GO2RTC'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _modeTab(_ConnectMode.cloud, 'CLOUD (P2P)'),
                      _modeTab(_ConnectMode.isapi, 'API MARQUE'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(children: [_modeTab(_ConnectMode.url, 'URL SIMPLE')]),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_mode == _ConnectMode.onvif) ...[
              _onvifSection(),
            ] else if (_mode == _ConnectMode.relay) ...[
              _relaySection(),
            ] else if (_mode == _ConnectMode.cloud) ...[
              _cloudSection(),
            ] else if (_mode == _ConnectMode.isapi) ...[
              _isapiSection(),
            ] else if (_isNvrLike) ...[
              DropdownButtonFormField<String>(
                initialValue: _brand,
                decoration: _decoration('Marque du NVR'),
                items: [
                  for (final b in _brands)
                    DropdownMenuItem(
                      value: b,
                      child: Text(b, style: const TextStyle(fontSize: 14)),
                    ),
                ],
                onChanged: (v) => setState(() => _brand = v ?? _brand),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _host,
                      keyboardType: TextInputType.url,
                      onChanged: (_) => setState(() {}),
                      decoration: _decoration(
                        _mode == _ConnectMode.remote
                            ? 'IP publique ou domaine (ex: site.ddns.net)'
                            : 'IP du NVR (ex 192.168.1.64)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _port = v,
                      decoration: _decoration(
                        _mode == _ConnectMode.remote ? 'Port public' : 'Port',
                      ),
                    ),
                  ),
                ],
              ),
              if (_mode == _ConnectMode.remote) ...[
                const SizedBox(height: 8),
                Text(
                  'Port externe ouvert sur le routeur (554, 8554, 37778…) '
                  'redirigé vers le 554 du NVR.',
                  style: monoStyle(
                    10,
                    color: AppColors.onSurfaceFaint,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _user,
                      onChanged: (_) => setState(() {}),
                      decoration: _decoration('Utilisateur'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _password,
                      obscureText: _obscure,
                      onChanged: (_) => setState(() {}),
                      decoration: _decoration('Mot de passe', obscure: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _channels,
                      decoration: _decoration('Canaux'),
                      items: [
                        for (final n in [1, 2, 4, 8, 16, 32])
                          DropdownMenuItem(
                            value: n,
                            child: Text('$n canal${n > 1 ? 'x' : ''}'),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _channels = v ?? _channels),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _prefix,
                      decoration: _decoration('Préfixe nom'),
                    ),
                  ),
                ],
              ),
              if (_mode == _ConnectMode.remote) ...[
                const SizedBox(height: 16),
                _portForwardingHint(),
                const SizedBox(height: 12),
                _testConnectionRow(),
              ],
            ] else ...[
              TextField(
                controller: _urlName,
                decoration: _decoration('Nom de la caméra'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                decoration: _decoration(
                  'URL du flux (rtsp://… ou http://…m3u8)',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        PrimaryButton(
          label: _submitting
              ? 'Création…'
              : switch (_mode) {
                  _ConnectMode.url => 'Ajouter la caméra',
                  _ConnectMode.onvif => 'Créer les caméras ONVIF',
                  _ConnectMode.relay => 'Créer les caméras du relais',
                  _ConnectMode.cloud => 'Appairer les caméras',
                  _ConnectMode.isapi => 'Créer les caméras',
                  _ => 'Créer les caméras',
                },
          icon: Icons.videocam_outlined,
          height: 42,
          onTap: _submitting || !_formValid
              ? null
              : () async {
                  setState(() => _submitting = true);
                  if (_mode == _ConnectMode.onvif) {
                    final selected = _profiles
                        .where((p) => _selectedProfiles.contains(p.token))
                        .toList();
                    if (selected.isEmpty) {
                      setState(() {
                        _submitting = false;
                        _onvifError = 'Sélectionnez au moins un profil.';
                      });
                      return;
                    }
                    await widget.onAddOnvif(_buildOnvifDevice(), selected);
                  } else if (_mode == _ConnectMode.relay) {
                    final server = _relayServer;
                    if (server == null) {
                      setState(() {
                        _submitting = false;
                        _relayError = 'Chargez d\'abord les flux du serveur.';
                      });
                      return;
                    }
                    final selectedStreams = _relayStreams
                        .where((s) => _selectedRelay.contains(s.name))
                        .toList();
                    await widget.onAddRelay(server, selectedStreams);
                  } else if (_mode == _ConnectMode.cloud) {
                    final server = _cloudServer;
                    final code = _pairedCode;
                    if (server == null || code == null) {
                      setState(() {
                        _submitting = false;
                        _cloudError = 'Appairez d\'abord le boîtier (code).';
                      });
                      return;
                    }
                    final selectedStreams = _cloudStreams
                        .where((s) => _selectedCloud.contains(s.name))
                        .toList();
                    await widget.onPairCloud(server, code, selectedStreams);
                  } else if (_mode == _ConnectMode.isapi) {
                    if (_deviceInfo == null) {
                      setState(() {
                        _submitting = false;
                        _isapiError = 'Interrogez d\'abord l\'appareil.';
                      });
                      return;
                    }
                    final selectedChannels = _isapiChannels
                        .where((c) => _selectedIsapi.contains(c.id))
                        .toList();
                    await widget.onAddBrandCameras(
                      brand: _apiBrand,
                      host: _cleanHost,
                      httpPort: _isapiHttpPort,
                      rtspPort: _rtspPort,
                      user: _user.text.trim(),
                      password: _password.text,
                      allowSelfSigned: _selfSigned,
                      info: _deviceInfo!,
                      channels: selectedChannels,
                      motionDetection:
                          _motionDetection && _apiBrand == 'Hikvision',
                    );
                  } else if (_isNvrLike) {
                    await widget.onSubmitNvr(
                      _brand,
                      _cleanHost,
                      _effectivePort,
                      _user.text.trim(),
                      _password.text,
                      _channels,
                      _prefix.text.trim().isEmpty
                          ? 'Caméra'
                          : _prefix.text.trim(),
                      _mode == _ConnectMode.remote,
                    );
                  } else {
                    await widget.onSubmitUrl(
                      _urlName.text.trim().isEmpty
                          ? 'Caméra externe'
                          : _urlName.text.trim(),
                      _url.text,
                    );
                  }
                },
        ),
      ],
    );
  }

  Widget _modeTab(_ConnectMode mode, String label) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(
              9,
              weight: FontWeight.w700,
              color: selected ? AppColors.primary : AppColors.onSurfaceFaint,
            ),
          ),
        ),
      ),
    );
  }

  /// Aide « redirection de port » pour l'accès distant (IP directe).
  Widget _portForwardingHint() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.router_outlined,
                size: 14,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'REDIRECTION DE PORT REQUISE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(
                    9.5,
                    weight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: const Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Sur le routeur du site, redirigez le port TCP externe choisi '
            'vers le port 554 (RTSP) du NVR. Ex. : 8554 → 554.\n'
            'RTSP = 554 chez Hikvision et Dahua — les ports 8000 / 37777 '
            'sont les ports web, pas les flux vidéo.\n'
            'RTSP n\'étant pas chiffré, préférez un mot de passe fort et un '
            'nom de domaine (DynDNS) plutôt qu\'une IP qui change.',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: const Color(0xFF92400E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _testConnectionRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GhostButton(
          label: _testing ? 'Test en cours…' : 'Tester la connexion',
          icon: Icons.wifi_tethering,
          height: 38,
          onTap: _testing || !_nvrValid ? null : _testConnection,
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 8),
          Text(
            _testResult!,
            style: monoStyle(
              10.5,
              height: 1.4,
              color: _testOk ? AppColors.tertiary : AppColors.error,
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // Section RELAI GO2RTC : serveur → flux → sélection
  // ═════════════════════════════════════════════════════

  Widget _relaySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _relayUrl,
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {
            _relayServer = null;
            _relayStreams = [];
            _selectedRelay.clear();
          }),
          decoration: _decoration(
            'URL du serveur (ex: http://192.168.100.14:1984)',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Le serveur go2rtc installé chez le client tire le RTSP en local '
          'et rediffuse en HLS — une seule adresse à exposer sur le routeur.',
          style: monoStyle(10, height: 1.4, color: AppColors.onSurfaceFaint),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _relayUser,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Utilisateur (optionnel)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _relayPassword,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Mot de passe', obscure: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: _loadingRelay ? 'Chargement…' : 'Charger les flux du serveur',
          icon: Icons.dns_outlined,
          height: 40,
          onTap: _loadingRelay || _relayUrl.text.trim().isEmpty
              ? null
              : _loadRelayStreams,
        ),
        if (_loadingRelay)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: AppColors.surfaceHigh,
            ),
          ),
        if (_relayError != null) ...[
          const SizedBox(height: 8),
          Text(
            _relayError!,
            style: monoStyle(10.5, height: 1.4, color: AppColors.error),
          ),
        ],

        // Flux du serveur
        if (_relayStreams.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'FLUX DISPONIBLES',
                  style: monoStyle(
                    10,
                    weight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.onSurfaceFaint,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  if (_selectedRelay.length == _relayStreams.length) {
                    _selectedRelay.clear();
                  } else {
                    _selectedRelay
                      ..clear()
                      ..addAll(_relayStreams.map((s) => s.name));
                  }
                }),
                child: Text(
                  _selectedRelay.length == _relayStreams.length
                      ? 'Tout décocher'
                      : 'Tout cocher',
                  style: monoStyle(
                    10,
                    weight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final s in _relayStreams)
            GestureDetector(
              onTap: () => setState(() {
                if (!_selectedRelay.remove(s.name)) {
                  _selectedRelay.add(s.name);
                }
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _selectedRelay.contains(s.name)
                      ? AppColors.secondaryContainer
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedRelay.contains(s.name)
                        ? AppColors.secondary
                        : AppColors.outline,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedRelay.contains(s.name)
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 17,
                      color: _selectedRelay.contains(s.name)
                          ? AppColors.secondary
                          : AppColors.onSurfaceFaint,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: s.active
                            ? AppColors.tertiaryContainer
                            : AppColors.surfaceLow,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.active ? 'ACTIF' : 'VEILLE',
                        style: monoStyle(
                          9,
                          weight: FontWeight.w700,
                          color: s.active
                              ? AppColors.tertiary
                              : AppColors.onSurfaceFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // Section CLOUD (P2P) : code boîtier → flux appariés
  // ═══════════════════════════════════════════════════

  Widget _cloudSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _cloudCode,
          keyboardType: TextInputType.visiblePassword,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {
            // Nouveau code → invalide l'appairage précédent.
            _cloudServer = null;
            _pairedCode = null;
            _cloudStreams = [];
            _selectedCloud.clear();
            _cloudError = null;
          }),
          decoration: _decoration(
            'Code d\'appairage (étiquette du boîtier, ex: EYE-7F3K2)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _cloudUrl,
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {
            _cloudServer = null;
            _pairedCode = null;
          }),
          decoration: _decoration(
            'URL du cloud EyeSafe (saisie une fois, mémorisée)',
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.secondaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.secondary.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cloud_done_outlined,
                    size: 14,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'AUCUN PORT À OUVRIR CHEZ LE CLIENT',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(
                        9.5,
                        weight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Le boîtier du site établit lui-même la connexion sortante vers '
                'le cloud EyeSafe (go2rtc). Les clouds fabricants type '
                'Hik-Connect/DMSS imposent leur SDK — ici, c\'est VOTRE cloud '
                'qui relaie les flux HLS.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: _pairing ? 'Appairage…' : 'Appairer le boîtier',
          icon: Icons.cloud_sync_outlined,
          height: 40,
          onTap: _pairing || _cloudCode.text.trim().isEmpty ? null : _pairCloud,
        ),
        if (_pairing)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: AppColors.surfaceHigh,
            ),
          ),
        if (_cloudError != null) ...[
          const SizedBox(height: 8),
          Text(
            _cloudError!,
            style: monoStyle(10.5, height: 1.4, color: AppColors.error),
          ),
        ],

        // Flux appariés
        if (_cloudStreams.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'CAMÉRAS DU BOÎTIER ${CloudPairing.normalize(_pairedCode ?? '')}',
            style: monoStyle(
              10,
              weight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.onSurfaceFaint,
            ),
          ),
          const SizedBox(height: 8),
          for (final s in _cloudStreams)
            GestureDetector(
              onTap: () => setState(() {
                if (!_selectedCloud.remove(s.name)) {
                  _selectedCloud.add(s.name);
                }
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _selectedCloud.contains(s.name)
                      ? AppColors.secondaryContainer
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedCloud.contains(s.name)
                        ? AppColors.secondary
                        : AppColors.outline,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedCloud.contains(s.name)
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 17,
                      color: _selectedCloud.contains(s.name)
                          ? AppColors.secondary
                          : AppColors.onSurfaceFaint,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            CloudPairing.cameraName(s.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          Text(
                            '${s.name}${s.active ? ' · ACTIF' : ' · VEILLE'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle(
                              9.5,
                              color: AppColors.onSurfaceFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════
  // Section ISAPI (Hikvision) : appareil → canaux
  // ═══════════════════════════════════════════

  Widget _isapiSection() {
    final info = _deviceInfo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _apiBrand,
          decoration: _decoration('Marque (API propriétaire)'),
          items: [
            for (final b in _apiBrands)
              DropdownMenuItem(
                value: b,
                child: Text(
                  '$b — ${switch (b) {
                    'Hikvision' => 'ISAPI',
                    'Dahua' => 'HTTP API',
                    'Axis' => 'VAPIX',
                    _ => 'LAPI',
                  }}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
          ],
          onChanged: (v) => setState(() {
            _apiBrand = v ?? _apiBrand;
            _deviceInfo = null;
            _isapiChannels = [];
            _selectedIsapi.clear();
            _isapiError = null;
          }),
        ),
        const SizedBox(height: 8),
        Text(
          "Imou (Dahua grand public) n'expose pas d'API HTTP locale — "
          'utilisez NVR LOCAL ou ONVIF. Les SDK natifs HCNetSDK/NetSDK '
          '(bibliothèques natives sous licence) ne sont pas intégrés : les '
          'API HTTP sont la voie recommandée.',
          style: monoStyle(9.5, height: 1.4, color: AppColors.onSurfaceFaint),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _host,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {
                  _deviceInfo = null;
                  _isapiChannels = [];
                  _selectedIsapi.clear();
                }),
                decoration: _decoration('IP de l\'appareil (ex 192.168.1.64)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 1,
              child: TextField(
                controller: _isapiPortController,
                keyboardType: TextInputType.number,
                decoration: _decoration('Port HTTP'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _user,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Utilisateur'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _password,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Mot de passe', obscure: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Certificat auto-signé + port RTSP
        Row(
          children: [
            Flexible(
              child: GestureDetector(
                onTap: () => setState(() => _selfSigned = !_selfSigned),
                child: Row(
                  children: [
                    Icon(
                      _selfSigned
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 17,
                      color: _selfSigned
                          ? AppColors.primary
                          : AppColors.onSurfaceFaint,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'HTTPS + certificat auto-signé',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _rtspPortController,
                keyboardType: TextInputType.number,
                decoration: _decoration('Port RTSP'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: _interrogating ? 'Interrogation…' : 'Interroger l\'appareil',
          icon: Icons.memory_outlined,
          height: 40,
          onTap: _interrogating ? null : _interrogateIsapi,
        ),
        if (_interrogating)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: AppColors.surfaceHigh,
            ),
          ),
        if (_isapiError != null) ...[
          const SizedBox(height: 8),
          Text(
            _isapiError!,
            style: monoStyle(10.5, height: 1.4, color: AppColors.error),
          ),
        ],

        // Carte deviceInfo
        if (info != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.model.isEmpty ? 'Appareil Hikvision' : info.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'S/N ${info.serial.isEmpty ? '—' : info.serial}'
                  '${info.firmware.isEmpty ? '' : ' · FW ${info.firmware}'}'
                  '${info.mac.isEmpty ? '' : ' · MAC ${info.mac}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(10, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],

        // Canaux de flux
        if (_isapiChannels.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'CANAUX DE FLUX',
            style: monoStyle(
              10,
              weight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.onSurfaceFaint,
            ),
          ),
          const SizedBox(height: 8),
          for (final c in _isapiChannels)
            GestureDetector(
              onTap: () => setState(() {
                if (!_selectedIsapi.remove(c.id)) {
                  _selectedIsapi.add(c.id);
                }
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _selectedIsapi.contains(c.id)
                      ? AppColors.primaryContainer
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedIsapi.contains(c.id)
                        ? AppColors.primary
                        : AppColors.outline,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedIsapi.contains(c.id)
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 17,
                      color: _selectedIsapi.contains(c.id)
                          ? AppColors.primary
                          : AppColors.onSurfaceFaint,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          Text(
                            '${c.id} · ${c.resolutionLabel} · '
                            '${c.isMainStream ? 'FLUX PRINCIPAL' : 'FLUX SECONDAIRE'}',
                            style: monoStyle(
                              9.5,
                              color: AppColors.onSurfaceFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          // Alerte intrusion (motion detection) — ISAPI Hikvision uniquement
          // (VAPIX/LAPI : configuration via l'interface constructeur).
          if (_apiBrand == 'Hikvision')
            GestureDetector(
              onTap: () => setState(() => _motionDetection = !_motionDetection),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _motionDetection
                      ? AppColors.tertiaryContainer.withValues(alpha: 0.6)
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _motionDetection
                        ? AppColors.tertiary
                        : AppColors.outline,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _motionDetection
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      size: 17,
                      color: _motionDetection
                          ? AppColors.tertiary
                          : AppColors.onSurfaceFaint,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Activer la détection de mouvement (alerte intrusion)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _motionDetection
                              ? AppColors.onSurface
                              : AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════
  // Section ONVIF : découverte → identifiants → profils
  // ═════════════════════════════════════════════════════

  Widget _onvifSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Découverte réseau
        GhostButton(
          label: _discovering
              ? 'Découverte en cours…'
              : 'Découvrir les caméras du réseau',
          icon: Icons.wifi_find_outlined,
          onTap: _discovering ? null : _discoverOnvif,
        ),
        if (_discovering)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: AppColors.surfaceHigh,
            ),
          ),
        if (_discovered.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '${_discovered.length} caméra${_discovered.length > 1 ? 's' : ''} '
            'détectée${_discovered.length > 1 ? 's' : ''} — tapez pour sélectionner :',
            style: monoStyle(10, color: AppColors.onSurfaceFaint),
          ),
          const SizedBox(height: 6),
          for (final d in _discovered)
            GestureDetector(
              onTap: () => setState(() {
                _selectedDevice = d;
                _host.text = d.host;
                _profiles = [];
                _selectedProfiles.clear();
                _onvifError = null;
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _selectedDevice == d
                      ? AppColors.primaryContainer
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedDevice == d
                        ? AppColors.primary
                        : AppColors.outline,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.videocam_outlined,
                      size: 16,
                      color: _selectedDevice == d
                          ? AppColors.primary
                          : AppColors.onSurfaceFaint,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.name ?? 'Caméra ONVIF',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          Text(
                            '${d.host}:${d.deviceUri.hasPort ? d.deviceUri.port : 80}',
                            style: monoStyle(
                              10,
                              color: AppColors.onSurfaceFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),

        // Saisie manuelle si pas de découverte (ou IP hors réseau local)
        TextField(
          controller: _host,
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {
            _selectedDevice = null;
          }),
          decoration: _decoration('IP de la caméra (ou sélection ci-dessus)'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: TextField(
                controller: _onvifPortController,
                keyboardType: TextInputType.number,
                decoration: _decoration('Port HTTP'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _user,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Utilisateur'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _obscure,
          onChanged: (_) => setState(() {}),
          decoration: _decoration('Mot de passe', obscure: true),
        ),
        const SizedBox(height: 14),

        // Chargement des profils
        PrimaryButton(
          label: _loadingProfiles ? 'Chargement…' : 'Charger les profils',
          icon: Icons.video_library_outlined,
          height: 40,
          onTap: _loadingProfiles || !_onvifReady ? null : _loadOnvifProfiles,
        ),
        if (_onvifError != null) ...[
          const SizedBox(height: 8),
          Text(
            _onvifError!,
            style: monoStyle(10.5, height: 1.4, color: AppColors.error),
          ),
        ],

        // Profils trouvés
        if (_profiles.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'PROFILS DE FLUX',
            style: monoStyle(
              10,
              weight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.onSurfaceFaint,
            ),
          ),
          const SizedBox(height: 8),
          for (final p in _profiles)
            GestureDetector(
              onTap: () => setState(() {
                if (!_selectedProfiles.remove(p.token)) {
                  _selectedProfiles.add(p.token);
                }
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _selectedProfiles.contains(p.token)
                      ? AppColors.tertiaryContainer
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedProfiles.contains(p.token)
                        ? AppColors.tertiary
                        : AppColors.outline,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedProfiles.contains(p.token)
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 17,
                      color: _selectedProfiles.contains(p.token)
                          ? AppColors.tertiary
                          : AppColors.onSurfaceFaint,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          Text(
                            '${p.resolutionLabel} · '
                            '${p.isMainStream ? 'FLUX PRINCIPAL' : 'FLUX SECONDAIRE'}'
                            '${p.hasPtz ? ' · PTZ' : ''}',
                            style: monoStyle(
                              9.5,
                              color: AppColors.onSurfaceFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Vignette d'une caméra (état direct / non configuré).
class _CameraTile extends StatefulWidget {
  const _CameraTile({required this.camera, this.onTap});

  final Equipment camera;
  final VoidCallback? onTap;

  @override
  State<_CameraTile> createState() => _CameraTileState();
}

/// Pavé PTZ ONVIF : maintenir une direction = mouvement continu,
/// relâcher = arrêt. Zoom +/- en maintien également.
class _PtzPad extends StatelessWidget {
  const _PtzPad({required this.onMove, required this.onStop});

  final Future<void> Function(double x, double y, {double zoom}) onMove;
  final Future<void> Function() onStop;

  Widget _dirButton({
    required IconData icon,
    required double x,
    required double y,
    double zoom = 0,
  }) {
    return Listener(
      onPointerDown: (_) => onMove(x, y, zoom: zoom),
      onPointerUp: (_) => onStop(),
      onPointerCancel: (_) => onStop(),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, size: 19, color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 42, height: 42),
              _dirButton(icon: Icons.keyboard_arrow_up, x: 0, y: 0.5),
              const SizedBox(width: 42, height: 42),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dirButton(icon: Icons.keyboard_arrow_left, x: -0.5, y: 0),
              _dirButton(icon: Icons.my_location, x: 0, y: 0),
              _dirButton(icon: Icons.keyboard_arrow_right, x: 0.5, y: 0),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 42, height: 42),
              _dirButton(icon: Icons.keyboard_arrow_down, x: 0, y: -0.5),
              const SizedBox(width: 42, height: 42),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dirButton(icon: Icons.add, x: 0, y: 0, zoom: 0.5),
              const SizedBox(width: 6),
              _dirButton(icon: Icons.remove, x: 0, y: 0, zoom: -0.5),
            ],
          ),
        ],
      ),
    );
  }
}

class _CameraTileState extends State<_CameraTile> {
  bool _hover = false;

  // Mode « offline » : sonde TCP légère à l'affichage (une fois).
  // null = sonde en cours, true = joignable, false = injoignable.
  bool? _reachable;

  // ── Bande passante mosaïque ──
  // Snapshot périodique (5 s) pour les tuiles hors quota live.
  Timer? _snapshotTimer;
  Uint8List? _snapshot;
  DateTime? _snapshotAt;
  bool _livePreviewFailed = false;

  // ── Autorisation serveur (tenant + rôle) ──
  // Les aperçus (snapshot comme WebRTC) passent par get_stream_url,
  // comme le plein écran — jamais confiance au client.
  String? _authorizedUrl;
  bool _accessRefused = false;

  static const _navy = Color(0xFF0D1727);
  static const _navyDeep = Color(0xFF0A1220);
  static const _cyan = Color(0xFF22D3EE);

  @override
  void initState() {
    super.initState();
    _probe();
    _resolveAuthorization();
  }

  /// Vérifie l'accès au flux côté SERVEUR avant tout aperçu.
  Future<void> _resolveAuthorization() async {
    final data = DataScope.of(context);
    final url = await data.authorizedStreamUrl(widget.camera);
    if (!mounted) return;
    setState(() {
      if (url == null) {
        _accessRefused = widget.camera.streamUrl != null;
      } else {
        _authorizedUrl = url;
      }
    });
    if (url != null) _applyPreviewMode();
  }

  @override
  void didUpdateWidget(covariant _CameraTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // L'ordre/quota de la mosaïque a pu changer → réévalue le mode.
    if (oldWidget.camera.streamUrl != widget.camera.streamUrl) {
      _applyPreviewMode();
    }
  }

  @override
  void dispose() {
    _snapshotTimer?.cancel();
    super.dispose();
  }

  /// Applique le mode décidé par l'ordonnanceur : aperçu live (WebRTC,
  /// flux go2rtc uniquement) ou snapshot périodique 5 s.
  void _applyPreviewMode() {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    final url = _authorizedUrl;
    if (url == null || _probeDisabled) return;

    final data = DataScope.of(context);
    final mode = data.streams.modeFor(widget.camera.id);
    final whepUrl = WhepClient.deriveWhepUrl(url);

    if (mode == PreviewMode.live && whepUrl != null && !_livePreviewFailed) {
      return; // aperçu WebRTC rendu dans build (_TileWebrtcPreview)
    }
    if (deriveGo2rtcSnapshotUrl(url) != null) {
      // Snapshot immédiat puis toutes les 5 s (sonde de congestion incluse).
      unawaited(_refreshSnapshot());
      _snapshotTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_refreshSnapshot()),
      );
    }
  }

  Future<void> _refreshSnapshot() async {
    final url = _authorizedUrl;
    if (url == null) return;
    final snapshotUrl = deriveGo2rtcSnapshotUrl(
      url,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    if (snapshotUrl == null) return;

    final watch = Stopwatch()..start();
    final bytes = await fetchGo2rtcSnapshot(snapshotUrl);
    watch.stop();

    if (!mounted) return;
    // Sonde de congestion → l'ordonnanceur ajuste le quota live.
    DataScope.of(context).streams.reportProbeDuration(watch.elapsed);
    setState(() {
      _snapshot = bytes;
      _snapshotAt = DateTime.now();
      if (bytes != null) {
        _reachable = true;
      } else if (_snapshot == null) {
        _reachable = false;
      }
    });
  }

  /// Aperçu WebRTC si la caméra est dans le quota live ET que son flux
  /// est servi par go2rtc (relais/cloud). Les flux RTSP directs restent
  /// en placeholder (lecture plein écran au tap) — leur URL cible déjà
  /// le sous-flux.
  Widget? get _livePreviewWidget {
    if (_probeDisabled || _livePreviewFailed || _accessRefused) return null;
    final url = _authorizedUrl;
    if (url == null) return null;
    final data = DataScope.of(context);
    if (data.streams.modeFor(widget.camera.id) != PreviewMode.live) {
      return null;
    }
    final whepUrl = WhepClient.deriveWhepUrl(url);
    if (whepUrl == null) return null;
    return _TileWebrtcPreview(
      whepUrl: whepUrl,
      onFailed: () {
        // Dégradation par tuile : WebRTC impossible → snapshots.
        if (mounted) {
          setState(() => _livePreviewFailed = true);
          _applyPreviewMode();
        }
      },
    );
  }

  /// Environnement de test widget → sonde désactivée (les timers de
  /// timeout resteraient pendants après la disposition du widget).
  static bool get _probeDisabled =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// Sonde l'hôte du flux (RTSP 554 / HLS 80-443) sans bloquer l'UI —
  /// l'état « hors ligne » s'affiche proprement, sans plantage.
  Future<void> _probe() async {
    if (_probeDisabled) return;
    final url = Uri.tryParse(widget.camera.streamUrl ?? '');
    if (url == null ||
        !url.hasScheme ||
        url.host.isEmpty ||
        url.host == 'localhost') {
      return;
    }
    final defaultPort = url.isScheme('rtsp')
        ? 554
        : (url.isScheme('https') ? 443 : 80);
    final port = url.hasPort ? url.port : defaultPort;
    final error = await SiteController.testEndpoint(
      host: url.host,
      port: '$port',
    );
    if (mounted) setState(() => _reachable = error == null);
  }

  Future<void> _disconnect(BuildContext context) async {
    final data = DataScope.of(context);
    final confirmed = await confirmRemoveEquipment(
      context,
      name: widget.camera.name,
    );
    if (!confirmed) return;
    final error = await data.removeEquipment(widget.camera);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.onSurface,
            content: Text(
              error ??
                  'Caméra « ${widget.camera.name} » déconnectée. '
                      'Reconnectez-la à tout moment via « Connecter un NVR ».',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cam = widget.camera;
    final live = cam.isLive;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            gradient: const RadialGradient(
              center: Alignment.topCenter,
              radius: 1.5,
              colors: [_navy, _navyDeep],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover
                  ? _cyan.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.08),
              width: _hover ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hover ? 0.25 : 0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Contenu : aperçu live WebRTC / snapshot / placeholder ──
                if (_livePreviewWidget != null)
                  _livePreviewWidget!
                else if (_snapshot != null)
                  Image.memory(
                    _snapshot!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    color: Colors.white.withValues(alpha: 0.92),
                    colorBlendMode: BlendMode.modulate,
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: live
                                ? _cyan.withValues(alpha: 0.14)
                                : Colors.white.withValues(alpha: 0.06),
                            border: Border.all(
                              color: live
                                  ? _cyan.withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Icon(
                            _accessRefused
                                ? Icons.lock_outline
                                : !live
                                ? Icons.videocam_off_outlined
                                : _reachable == false
                                ? Icons.wifi_off_outlined
                                : Icons.videocam_outlined,
                            size: 26,
                            color: live ? _cyan : Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _accessRefused
                              ? 'ACCÈS REFUSÉ'
                              : !live
                              ? 'FLUX NON CONFIGURÉ'
                              : _reachable == false
                              ? 'HORS LIGNE'
                              : 'VOIR LE DIRECT',
                          style: monoStyle(
                            9,
                            weight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: live ? _cyan : Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Bandeau infos
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.65),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cam.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.card,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cam.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: monoStyle(
                            9.5,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                        if (_snapshotAt != null && _snapshot != null)
                          Text(
                            'IMG '
                            '${_snapshotAt!.hour.toString().padLeft(2, '0')}:'
                            '${_snapshotAt!.minute.toString().padLeft(2, '0')}:'
                            '${_snapshotAt!.second.toString().padLeft(2, '0')}',
                            style: monoStyle(
                              8.5,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Bouton déconnexion
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => _disconnect(context),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _hover
                              ? AppColors.error.withValues(alpha: 0.9)
                              : Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Icon(
                        Icons.link_off_outlined,
                        size: 14,
                        color: _hover
                            ? AppColors.error
                            : Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
                // Badge LIVE
                if (live)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF34D399).withValues(alpha: 0.7),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _livePreviewWidget != null
                                  ? const Color(0xFF34D399)
                                  : Colors.white38,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _livePreviewWidget != null
                                ? 'LIVE'
                                : _snapshot != null
                                ? 'SNAPSHOT 5S'
                                : 'FLUX',
                            style: monoStyle(
                              8.5,
                              weight: FontWeight.w800,
                              letterSpacing: 1,
                              color: _livePreviewWidget != null
                                  ? const Color(0xFF34D399)
                                  : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Aperçu WebRTC compact pour une tuile de la mosaïque (quota live).
/// En cas d'échec (NAT, serveur), prévient le parent → repli snapshot.
class _TileWebrtcPreview extends StatefulWidget {
  const _TileWebrtcPreview({required this.whepUrl, this.onFailed});

  final String whepUrl;
  final VoidCallback? onFailed;

  @override
  State<_TileWebrtcPreview> createState() => _TileWebrtcPreviewState();
}

class _TileWebrtcPreviewState extends State<_TileWebrtcPreview> {
  RTCVideoRenderer? _renderer;
  RTCPeerConnection? _pc;
  Timer? _watchdog;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    unawaited(_disposeWebrtc());
    super.dispose();
  }

  Future<void> _start() async {
    RTCVideoRenderer? renderer;
    RTCPeerConnection? pc;
    try {
      renderer = RTCVideoRenderer();
      await renderer.initialize();
      final iceServers = await RtcConfig.loadIceServers();
      pc = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': iceServers,
      });
      pc.onTrack = (event) {
        if (!mounted || event.streams.isEmpty) return;
        _watchdog?.cancel();
        renderer!.srcObject = event.streams.first;
        if (mounted) setState(() {});
      };
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      final answer = await WhepClient.negotiate(
        whepUrl: widget.whepUrl,
        offerSdp: offer.sdp ?? '',
      );
      await pc.setRemoteDescription(RTCSessionDescription(answer, 'answer'));
      _pc = pc;
      _renderer = renderer;
      _watchdog = Timer(const Duration(seconds: 6), () {
        if (mounted && _renderer?.srcObject == null) _fail();
      });
    } catch (_) {
      await renderer?.dispose();
      await pc?.dispose();
      _fail();
    }
  }

  void _fail() {
    if (_failed) return;
    _failed = true;
    widget.onFailed?.call();
  }

  Future<void> _disposeWebrtc() async {
    final pc = _pc;
    final renderer = _renderer;
    _pc = null;
    _renderer = null;
    try {
      await pc?.close();
      await pc?.dispose();
    } catch (_) {}
    try {
      await renderer?.dispose();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    if (renderer == null || renderer.srcObject == null) {
      return Container(color: const Color(0xFF0A1220));
    }
    return RTCVideoView(
      renderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

/// Navigateur d'enregistrements (replay) : choix de date → segments du
/// jour sur l'appareil/NVR → tap pour rejouer.
class _ReplaySheet extends StatefulWidget {
  const _ReplaySheet({required this.device, required this.channel});

  final IsapiDevice device;
  final int channel;

  @override
  State<_ReplaySheet> createState() => _ReplaySheetState();
}

class _ReplaySheetState extends State<_ReplaySheet> {
  DateTime _day = DateTime.now();
  bool _loading = false;
  List<IsapiRecording> _recordings = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final start = DateTime(_day.year, _day.month, _day.day);
    final end = start.add(const Duration(days: 1));
    try {
      final found = await widget.device.searchRecordings(
        channel: widget.channel,
        start: start,
        end: end,
      );
      if (!mounted) return;
      setState(() {
        _recordings = found;
        _loading = false;
        if (found.isEmpty) {
          _error = 'Aucun enregistrement ce jour-là.';
        }
      });
    } on IsapiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _day = picked);
    _search();
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.history, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Rejouer les enregistrements',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _pickDay,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_day.day.toString().padLeft(2, '0')}/'
                          '${_day.month.toString().padLeft(2, '0')}',
                          style: monoStyle(
                            11.5,
                            weight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in _recordings)
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(r),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.play_circle_outline,
                                size: 22,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${_hhmm(r.start)} – ${_hhmm(r.end)}',
                                style: monoStyle(
                                  13,
                                  weight: FontWeight.w700,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${r.duration.inMinutes} min',
                                style: monoStyle(
                                  10.5,
                                  color: AppColors.onSurfaceFaint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lecteur plein écran du flux en direct.
class _LiveView extends StatefulWidget {
  const _LiveView({required this.camera, this.streamUrl});

  final Equipment camera;

  /// URL autorisée côté serveur (peut différer de camera.streamUrl).
  final String? streamUrl;

  @override
  State<_LiveView> createState() => _LiveViewState();
}

/// Transport de lecture du direct. WebRTC (WHEP) en priorité pour la
/// latence < 1 s ; HLS en repli ; RTSP direct quand l'URL l'exige.
enum _StreamMode { initializing, webrtc, hls, rtsp, error }

class _LiveViewState extends State<_LiveView> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(
    _player,
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: true,
    ),
  );
  String? _error;
  _StreamMode _mode = _StreamMode.initializing;

  // ── WebRTC (WHEP go2rtc) ──
  RTCPeerConnection? _pc;
  RTCVideoRenderer? _webrtcRenderer;
  Timer? _webrtcWatchdog;
  bool _webrtcFailed = false; // un échec → ne pas retenter en boucle

  String? get _url => widget.streamUrl ?? widget.camera.streamUrl;

  /// Stratégie de lecture : WebRTC (WHEP) si l'URL est un flux go2rtc,
  /// sinon media_kit (RTSP direct ou HLS externe). Repli HLS automatique
  /// si le WebRTC échoue (NAT restrictif, serveur ancien).
  void _start() {
    final url = _url;
    if (url == null) {
      setState(() {
        _error = 'Flux non configuré pour cette caméra.';
        _mode = _StreamMode.error;
      });
      return;
    }
    final whepUrl = _webrtcFailed ? null : WhepClient.deriveWhepUrl(url);
    if (whepUrl != null) {
      unawaited(_startWebrtc(url, whepUrl));
    } else {
      setState(
        () => _mode = url.startsWith('rtsp://')
            ? _StreamMode.rtsp
            : _StreamMode.hls,
      );
      _open();
    }
  }

  /// Lecture media_kit (RTSP direct / HLS go2rtc ou externe).
  void _open() {
    final url = _url;
    if (url == null) {
      setState(() => _error = 'Flux non configuré pour cette caméra.');
      return;
    }
    _player
        .open(Media(url))
        .then(
          (_) {},
          onError: (Object e) {
            if (mounted) {
              setState(
                () => _error =
                    'Impossible de lire le flux — caméra '
                    'hors ligne ou réseau coupé.',
              );
            }
          },
        );
  }

  /// Mode « offline » : nouvelle tentative (WebRTC d'abord s'il n'a pas
  /// déjà échoué, sinon HLS/RTSP).
  void _retry() {
    setState(() {
      _error = null;
      _mode = _StreamMode.initializing;
    });
    unawaited(_disposeWebrtc());
    _start();
  }

  // ── WebRTC (WHEP) — latence < 1 s ──

  Future<void> _startWebrtc(String url, String whepUrl) async {
    RTCVideoRenderer? renderer;
    RTCPeerConnection? pc;
    try {
      renderer = RTCVideoRenderer();
      await renderer.initialize();
      // STUN/TURN configurable (hole punching d'abord, relais TURN en
      // repli avant de retomber sur HLS).
      final iceServers = await RtcConfig.loadIceServers();
      pc = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': iceServers,
      });

      pc.onTrack = (event) {
        if (!mounted || event.streams.isEmpty) return;
        _webrtcWatchdog?.cancel();
        renderer!.srcObject = event.streams.first;
        setState(() => _mode = _StreamMode.webrtc);
      };
      pc.onConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _fallbackToHls('connexion WebRTC échouée');
        }
      };

      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      final answer = await WhepClient.negotiate(
        whepUrl: whepUrl,
        offerSdp: offer.sdp ?? '',
      );
      await pc.setRemoteDescription(RTCSessionDescription(answer, 'answer'));

      _pc = pc;
      _webrtcRenderer = renderer;

      // Aucune image reçue après négociation → repli HLS sans bloquer.
      _webrtcWatchdog = Timer(const Duration(seconds: 7), () {
        if (mounted && _mode != _StreamMode.webrtc) {
          _fallbackToHls('aucun flux WebRTC reçu');
        }
      });
    } catch (e) {
      debugPrint('WHEP: $e');
      await renderer?.dispose();
      await pc?.dispose();
      if (mounted) _fallbackToHls('négociation WHEP impossible');
    }
  }

  /// WebRTC impossible (NAT restrictif, go2rtc ancien…) → HLS media_kit.
  void _fallbackToHls(String reason) {
    debugPrint('WebRTC → repli HLS ($reason)');
    _webrtcFailed = true;
    unawaited(
      _disposeWebrtc().then((_) {
        if (!mounted) return;
        setState(() => _mode = _StreamMode.hls);
        _open();
      }),
    );
  }

  Future<void> _disposeWebrtc() async {
    _webrtcWatchdog?.cancel();
    _webrtcWatchdog = null;
    final pc = _pc;
    final renderer = _webrtcRenderer;
    _pc = null;
    _webrtcRenderer = null;
    try {
      await pc?.close();
      await pc?.dispose();
    } catch (_) {}
    try {
      await renderer?.dispose();
    } catch (_) {}
  }

  // ── PTZ ONVIF (si la caméra le supporte) ──
  OnvifDevice? _ptzDevice;
  String? _ptzProfileToken;
  bool _ptzUnavailable = false;

  // ── Filtre IR-cut (jour/nuit) — même autorisation serveur que le PTZ ──
  OnvifDevice? _irDevice;
  String? _videoSourceToken;
  OnvifIrCutMode? _irMode;
  bool _irBusy = false;

  // ── Replay (enregistrements ISAPI Hikvision) ──
  String? _replayLabel;

  // ── Talk-back (micro → haut-parleur caméra) ──
  final AudioRecorder _recorder = AudioRecorder();
  IsapiTalkSession? _talkSession;
  StreamSubscription<Uint8List>? _micStream;
  bool _talking = false;

  /// Caméra Hikvision joignable en ISAPI depuis l'URL RTSP ?
  bool get _isHikvisionRtsp {
    final url = Uri.tryParse(_url ?? '');
    if (url == null || !url.isScheme('rtsp')) return false;
    final m = widget.camera.model;
    return m.contains('Hikvision') || m.contains('ISAPI') || m.contains('NVR');
  }

  IsapiDevice? _hikDeviceCache;

  IsapiDevice _hikDevice() {
    final cached = _hikDeviceCache;
    if (cached != null) return cached;
    final url = Uri.tryParse(_url ?? '')!;
    final creds = url.userInfo.split(':');
    return _hikDeviceCache = IsapiDevice(
      host: url.host,
      user: creds.isNotEmpty ? Uri.decodeComponent(creds[0]) : '',
      password: creds.length > 1
          ? Uri.decodeComponent(creds.sublist(1).join(':'))
          : '',
      timeout: const Duration(seconds: 5),
    );
  }

  /// Canal caméra (NVR « Canal 3 » → 3, sinon 1).
  int get _cameraChannel {
    final m = RegExp(r'Canal (\d+)').firstMatch(widget.camera.location);
    return m != null ? int.parse(m.group(1)!) : 1;
  }

  /// Ouvre le navigateur d'enregistrements (replay).
  Future<void> _openReplay() async {
    if (!_isHikvisionRtsp) return;
    final segment = await showModalBottomSheet<IsapiRecording>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) =>
          _ReplaySheet(device: _hikDevice(), channel: _cameraChannel),
    );
    if (segment == null || !mounted) return;
    final url = Uri.tryParse(_url ?? '');
    if (url == null) return;
    final creds = url.userInfo.split(':');
    final port = url.hasPort ? '${url.port}' : '554';
    final playback = IsapiDevice.playbackUrl(
      host: url.host,
      rtspPort: port,
      user: creds.isNotEmpty ? Uri.decodeComponent(creds[0]) : '',
      password: creds.length > 1
          ? Uri.decodeComponent(creds.sublist(1).join(':'))
          : '',
      trackId: segment.trackId,
      start: segment.start,
      end: segment.end,
    );
    setState(() {
      _replayLabel =
          'REPLAY ${segment.start.hour.toString().padLeft(2, '0')}:'
          '${segment.start.minute.toString().padLeft(2, '0')}';
      _mode = _StreamMode.rtsp;
      _error = null;
    });
    unawaited(_disposeWebrtc());
    _player.open(Media(playback));
  }

  /// Retour au direct depuis un replay.
  void _backToLive() {
    setState(() => _replayLabel = null);
    _start();
  }

  /// Talk-back : maintenir le bouton → le micro est diffusé sur la
  /// caméra (G.711 μ-law 8 kHz). Relâcher = fin.
  Future<void> _startTalk() async {
    if (_talking || !_isHikvisionRtsp) return;
    try {
      if (!await _recorder.hasPermission()) return;
      final session = await _hikDevice().openTalk();
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 8000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _micStream = stream.listen((pcm) {
        final g711 = G711.encodePcm16Le(pcm);
        unawaited(session.send(g711));
      });
      _talkSession = session;
      if (mounted) setState(() => _talking = true);
    } catch (e) {
      debugPrint('talk: $e');
      await _stopTalk();
    }
  }

  Future<void> _stopTalk() async {
    try {
      await _micStream?.cancel();
    } catch (_) {}
    _micStream = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      await _talkSession?.close();
    } catch (_) {}
    _talkSession = null;
    if (mounted) setState(() => _talking = false);
  }

  /// Bascule le filtre IR : AUTO → JOUR → NUIT → AUTO.
  Future<void> _cycleIrMode() async {
    final device = _irDevice;
    final token = _videoSourceToken;
    final current = _irMode;
    if (device == null || token == null || current == null || _irBusy) return;
    final next = current.next;
    setState(() => _irBusy = true);
    final ok = await device.setIrCutMode(
      videoSourceToken: token,
      mode: next,
      user: device.user,
      password: device.password,
    );
    if (!mounted) return;
    setState(() {
      _irBusy = false;
      if (ok) _irMode = next;
    });
  }

  @override
  void initState() {
    super.initState();
    _start();
    _detectPtz();
  }

  @override
  void dispose() {
    unawaited(_stopTalk());
    unawaited(_disposeWebrtc());
    _player.dispose();
    super.dispose();
  }

  /// Détecte si le flux provient d'une caméra ONVIF avec PTZ : on repeuple
  /// les identifiants depuis l'URL RTSP (user:pass@host) et on interroge
  /// GetProfiles. Silencieux en cas d'échec (caméra non ONVIF, réseau
  /// distant sans redirection HTTP…).
  ///
  /// Gestion des capacités : seules les caméras créées via ONVIF/ISAPI
  /// portent le marqueur « · PTZ » fiable (capacité sondée à la création).
  /// VAPIX/LAPI/DAHUA ne sondent pas → détection ONVIF à l'ouverture.
  Future<void> _detectPtz() async {
    // Capturé AVANT les awaits : le contexte reste valide ainsi.
    final data = DataScope.of(context);
    final model = widget.camera.model;
    final createdViaDiscovery =
        model.contains('ONVIF') || model.contains('ISAPI');
    final ptzHint = model.contains('PTZ');
    if (createdViaDiscovery && !ptzHint) {
      // Capacité connue à la connexion : pas de PTZ → pas de pavé.
      setState(() => _ptzUnavailable = true);
      return;
    }
    final url = Uri.tryParse(_url ?? '');
    if (url == null || !url.isScheme('rtsp')) {
      setState(() => _ptzUnavailable = true);
      return;
    }
    final creds = url.userInfo.split(':');
    final device = OnvifDevice(
      host: url.host,
      port: url.hasPort ? 80 : 80, // ONVIF passe par HTTP (80 en général)
      user: creds.isNotEmpty ? Uri.decodeComponent(creds[0]) : '',
      password: creds.length > 1
          ? Uri.decodeComponent(creds.sublist(1).join(':'))
          : '',
      timeout: const Duration(seconds: 4),
    );
    try {
      final profiles = await device.getProfiles(
        user: device.user,
        password: device.password,
      );
      final ptzProfile = profiles.where((p) => p.hasPtz).firstOrNull;
      // Source vidéo du premier profil qui en déclare une → filtre IR.
      final sourceProfile = profiles
          .where((p) => p.videoSourceToken != null)
          .firstOrNull;
      final irMode = sourceProfile == null
          ? null
          : await device.getIrCutMode(
              videoSourceToken: sourceProfile.videoSourceToken!,
              user: device.user,
              password: device.password,
            );

      final needsDeviceControl = ptzProfile != null || irMode != null;
      if (!needsDeviceControl) {
        if (mounted) {
          setState(() {
            _ptzUnavailable = true;
            _irMode = null;
          });
        }
        return;
      }

      // Contrôle physique (PTZ / IR) autorisé côté SERVEUR pour chaque
      // session — tenant + rôle, journalisé (action 'ptz').
      final allowed = await data.authorizedPtzControl(widget.camera);
      if (!mounted) return;
      setState(() {
        if (allowed) {
          if (ptzProfile != null) {
            _ptzDevice = device;
            _ptzProfileToken = ptzProfile.token;
          } else {
            _ptzUnavailable = true;
          }
          if (irMode != null && sourceProfile != null) {
            _irMode = irMode;
            _videoSourceToken = sourceProfile.videoSourceToken;
            _irDevice = device;
          }
        } else {
          _ptzUnavailable = true; // refusé : pavé ET IR masqués
        }
      });
    } catch (_) {
      if (mounted) setState(() => _ptzUnavailable = true);
    }
  }

  /// Boutons flottants du direct : replay (Hikvision), talk-back
  /// (maintenir pour parler), retour au direct pendant un replay.
  Widget _liveControlsOverlay() {
    return Positioned(
      top: 12,
      right: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replayLabel != null)
            GestureDetector(
              onTap: _backToLive,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF22D3EE).withValues(alpha: 0.6),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.play_circle_outline,
                      size: 15,
                      color: Color(0xFF22D3EE),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'RETOUR DIRECT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF22D3EE),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_isHikvisionRtsp)
            GestureDetector(
              onTap: _replayLabel == null ? _openReplay : null,
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.history,
                  size: 17,
                  color: Colors.white70,
                ),
              ),
            ),
          if (_isHikvisionRtsp)
            GestureDetector(
              onLongPressStart: (_) => unawaited(_startTalk()),
              onLongPressEnd: (_) => unawaited(_stopTalk()),
              onLongPressCancel: () => unawaited(_stopTalk()),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _talking
                      ? const Color(0xFF34D399).withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _talking
                        ? const Color(0xFF34D399)
                        : Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Icon(
                  _talking ? Icons.mic : Icons.mic_none_outlined,
                  size: 17,
                  color: _talking ? const Color(0xFF34D399) : Colors.white70,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _ptzMove(double x, double y, {double zoom = 0}) async {
    final device = _ptzDevice;
    final token = _ptzProfileToken;
    if (device == null || token == null) return;
    final ok = await device.ptzContinuousMove(
      profileToken: token,
      panX: x,
      tiltY: y,
      zoomX: zoom,
    );
    if (!ok && mounted) setState(() => _ptzUnavailable = true);
  }

  Future<void> _ptzStopAll() async {
    final device = _ptzDevice;
    final token = _ptzProfileToken;
    if (device == null || token == null) return;
    await device.ptzStop(profileToken: token);
  }

  @override
  Widget build(BuildContext context) {
    final cam = widget.camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Barre supérieure
            Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
              color: Colors.black,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cam.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.card,
                          ),
                        ),
                        Text(
                          '${cam.location} · ${cam.model}',
                          style: monoStyle(
                            10,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Filtre IR (jour/nuit) — contrôle de base ONVIF Imaging,
                  // même autorisation serveur que le PTZ.
                  if (_irMode != null) ...[
                    GestureDetector(
                      onTap: _cycleIrMode,
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _irMode == OnvifIrCutMode.off
                                  ? Icons.nightlight_round
                                  : _irMode == OnvifIrCutMode.on
                                  ? Icons.wb_sunny_outlined
                                  : Icons.contrast_outlined,
                              size: 14,
                              color: _irMode == OnvifIrCutMode.off
                                  ? const Color(0xFF22D3EE)
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _irBusy ? '…' : _irMode!.label,
                              style: monoStyle(
                                9.5,
                                weight: FontWeight.w800,
                                letterSpacing: 1,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34D399).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF34D399).withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      _replayLabel ??
                          switch (_mode) {
                            _StreamMode.webrtc => '● LIVE · WEBRTC <1S',
                            _StreamMode.hls => '● LIVE · HLS',
                            _StreamMode.rtsp => '● LIVE · RTSP',
                            _StreamMode.error => 'HORS LIGNE',
                            _StreamMode.initializing => 'CONNEXION…',
                          },
                      style: monoStyle(
                        10,
                        weight: FontWeight.w800,
                        letterSpacing: 1,
                        color: _mode == _StreamMode.error
                            ? Colors.white54
                            : const Color(0xFF34D399),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Flux vidéo + pad PTZ si disponible
            Expanded(
              child: _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wifi_off_outlined,
                            size: 44,
                            color: Colors.white38,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Vérifiez votre connexion ou contactez votre installateur.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                          const SizedBox(height: 18),
                          GhostButton(
                            label: 'Réessayer',
                            icon: Icons.refresh,
                            height: 40,
                            color: AppColors.card,
                            onTap: _retry,
                          ),
                        ],
                      ),
                    )
                  : _mode == _StreamMode.webrtc && _webrtcRenderer != null
                  ? Stack(
                      children: [
                        RTCVideoView(
                          _webrtcRenderer!,
                          objectFit: RTCVideoViewObjectFit
                              .RTCVideoViewObjectFitContain,
                        ),
                        _liveControlsOverlay(),
                        if (_ptzDevice != null && _ptzProfileToken != null)
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: _PtzPad(
                              onMove: (x, y, {zoom = 0}) =>
                                  _ptzMove(x, y, zoom: zoom),
                              onStop: _ptzStopAll,
                            ),
                          ),
                      ],
                    )
                  : _mode == _StreamMode.initializing
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white54,
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        Video(
                          controller: _controller,
                          controls: AdaptiveVideoControls,
                        ),
                        _liveControlsOverlay(),
                        if (_ptzDevice != null && _ptzProfileToken != null)
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: _PtzPad(
                              onMove: (x, y, {zoom = 0}) =>
                                  _ptzMove(x, y, zoom: zoom),
                              onStop: _ptzStopAll,
                            ),
                          ),
                        if (_ptzDevice == null &&
                            !_ptzUnavailable &&
                            widget.camera.model.contains('PTZ'))
                          const Positioned(
                            right: 16,
                            bottom: 16,
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
