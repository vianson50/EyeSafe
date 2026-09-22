import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/data/whep.dart';

void main() {
  group('WhepClient.deriveWhepUrl', () {
    test('dérive /api/webrtc depuis un flux go2rtc HLS', () {
      expect(
        WhepClient.deriveWhepUrl(
          'http://192.168.100.14:1984/api/stream.m3u8?src=cocody_entree',
        ),
        'http://192.168.100.14:1984/api/webrtc?src=cocody_entree',
      );

      // Avec sous-chemin (cloud derrière reverse-proxy).
      expect(
        WhepClient.deriveWhepUrl(
          'https://cloud.eyesafe.ci/video/api/stream.m3u8?src=EYE7F3K2-1',
        ),
        'https://cloud.eyesafe.ci/video/api/webrtc?src=EYE7F3K2-1',
      );

      // Identifiants basic-auth conservés (api go2rtc protégée).
      expect(
        WhepClient.deriveWhepUrl(
          'http://eyesafe:secret@serveur:1984/api/stream.m3u8?src=cam',
        ),
        'http://eyesafe:secret@serveur:1984/api/webrtc?src=cam',
      );
    });

    test("retourne null pour tout ce qui n'est pas go2rtc", () {
      // RTSP direct (NVR/ONVIF/ISAPI) → media_kit, pas de WebRTC.
      expect(
        WhepClient.deriveWhepUrl(
          'rtsp://admin:pass@192.168.1.64:554/Streaming/Channels/102',
        ),
        isNull,
      );
      // HLS externe (mux.dev…) → pas un serveur go2rtc.
      expect(
        WhepClient.deriveWhepUrl(
          'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
        ),
        isNull,
      );
      // go2rtc sans paramètre src → WHEP impossible.
      expect(
        WhepClient.deriveWhepUrl('http://serveur:1984/api/stream.m3u8'),
        isNull,
      );
      // URL vide/invalide.
      expect(WhepClient.deriveWhepUrl(''), isNull);
    });

    test('src avec caractères spéciaux est préservé tel quel', () {
      final derived = WhepClient.deriveWhepUrl(
        'http://h:1984/api/stream.m3u8?src=cam%20entr%C3%A9e',
      );
      expect(derived, isNotNull);
      expect(derived, contains('src=cam%20entr%C3%A9e'));
    });
  });
}
