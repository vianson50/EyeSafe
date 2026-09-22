import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/data/go2rtc.dart';
import 'package:eyesafe/data/site_controller.dart';

void main() {
  group('Go2rtcServer.hlsUrl', () {
    test('construit l\'URL HLS avec le flux encodé', () {
      final server = Go2rtcServer(baseUrl: 'http://192.168.100.14:1984');
      expect(
        server.hlsUrl('cocody_entree'),
        'http://192.168.100.14:1984/api/stream.m3u8?src=cocody_entree',
      );
    });

    test('normalise le slash final et encode les noms spéciaux', () {
      final server = Go2rtcServer(baseUrl: 'https://relay.mondomaine.ci/');
      expect(server.normalizedBase, 'https://relay.mondomaine.ci');
      expect(
        server.hlsUrl('cam entrée'),
        'https://relay.mondomaine.ci/api/stream.m3u8'
        '?src=cam%20entr%C3%A9e',
      );
      expect(server.hostLabel, 'relay.mondomaine.ci');
    });
  });

  group('Go2rtcServer.parseStreams', () {
    test('extrait les flux et leur état actif', () {
      const body = '''
{
  "cocody_parking": {"producers": [], "consumers": []},
  "cocody_entree": {
    "producers": [
      {"name": "RTSP", "url": "rtsp://…"}
    ],
    "consumers": []
  }
}
''';
      final streams = Go2rtcServer.parseStreams(body);

      expect(streams, hasLength(2));
      // Trié par nom.
      expect(streams.first.name, 'cocody_entree');
      expect(streams.first.active, isTrue);
      expect(streams.last.name, 'cocody_parking');
      expect(streams.last.active, isFalse);
    });

    test('rejette une réponse non go2rtc (HTML, tableau…)', () {
      expect(
        () => Go2rtcServer.parseStreams('<html>404</html>'),
        throwsA(isA<Go2rtcException>()),
      );
      expect(
        () => Go2rtcServer.parseStreams('[1, 2, 3]'),
        throwsA(isA<Go2rtcException>()),
      );
    });

    test('tolère une valeur sans producteurs', () {
      const body = '{"a": {}, "b": {"producers": null}}';
      final streams = Go2rtcServer.parseStreams(body);
      expect(streams, hasLength(2));
      expect(streams.every((s) => !s.active), isTrue);
    });
  });

  group('CloudPairing (cloud P2P façon Hik-Connect)', () {
    test('normalise codes et noms de flux', () {
      expect(CloudPairing.normalize('eye-7f3k2'), 'EYE7F3K2');
      expect(CloudPairing.normalize('EYE_7F3K.2'), 'EYE7F3K2');
      expect(CloudPairing.normalize('  '), '');
    });

    test('filtre les flux du boîtier par code', () {
      const streams = [
        Go2rtcStream(name: 'EYE7F3K2-1', active: true),
        Go2rtcStream(name: 'EYE7F3K2-2', active: false),
        Go2rtcStream(name: 'EYE9AAAA-1', active: true),
        Go2rtcStream(name: 'autre', active: false),
      ];

      final matched = CloudPairing.filter(streams, 'eye-7F3K2');
      expect(matched, hasLength(2));
      expect(matched.every((s) => s.name.startsWith('EYE7F3K2')), isTrue);

      // Code vide ou inconnu → rien.
      expect(CloudPairing.filter(streams, ''), isEmpty);
      expect(CloudPairing.filter(streams, 'EYE-XXXXX'), isEmpty);
    });

    test('nom de caméra lisible depuis le flux', () {
      expect(CloudPairing.cameraName('EYE7F3K2-3'), 'Caméra 3');
      expect(CloudPairing.cameraName('EYE7F3K212'), 'Caméra 212');
      expect(CloudPairing.cameraName('entree'), 'entree');
    });

    test('addGo2rtcCameras avec libellé Cloud (mode démo)', () async {
      final controller = SiteController.demoForTest();
      final server = Go2rtcServer(baseUrl: 'https://cloud.eyesafe.ci');
      const streams = [Go2rtcStream(name: 'EYE7F3K2-1', active: true)];

      final error = await controller.addGo2rtcCameras(
        server: server,
        streams: streams,
        locationLabel: 'Cloud · EYE7F3K2',
      );

      expect(error, isNull);
      final cam = controller.equipment.last;
      expect(cam.location, 'Cloud · EYE7F3K2');
      expect(
        cam.streamUrl,
        'https://cloud.eyesafe.ci/api/stream.m3u8?src=EYE7F3K2-1',
      );
      controller.dispose();
    });
  });

  group('addGo2rtcCameras (mode démo)', () {
    test('crée une caméra par flux avec URL HLS relais', () async {
      final controller = SiteController.demoForTest();
      final server = Go2rtcServer(baseUrl: 'http://192.168.100.14:1984');
      const streams = [
        Go2rtcStream(name: 'cocody_entree', active: true),
        Go2rtcStream(name: 'cocody_parking', active: false),
      ];

      final error = await controller.addGo2rtcCameras(
        server: server,
        streams: streams,
      );

      expect(error, isNull);
      final created = controller.equipment.where(
        (e) => e.model == 'go2rtc · relais',
      );
      expect(created, hasLength(2));
      final first = created.first;
      expect(first.streamUrl, server.hlsUrl(first.name));
      expect(first.location, 'Relais 192.168.100.14');
      expect(first.isLive, isTrue);
      controller.dispose();
    });

    test('refuse une liste vide', () async {
      final controller = SiteController.demoForTest();
      final error = await controller.addGo2rtcCameras(
        server: Go2rtcServer(baseUrl: 'http://x:1984'),
        streams: const [],
      );
      expect(error, isNotNull);
      controller.dispose();
    });
  });
}
