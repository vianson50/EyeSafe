import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/data/go2rtc.dart';
import 'package:eyesafe/data/stream_scheduler.dart';

void main() {
  group('StreamScheduler — quota de flux live', () {
    test('les N premières caméras en live, le reste en snapshot', () {
      final scheduler = StreamScheduler(maxLivePreviews: 4);
      scheduler.updateCameras(['c1', 'c2', 'c3', 'c4', 'c5', 'c6']);

      expect(scheduler.modeFor('c1'), PreviewMode.live);
      expect(scheduler.modeFor('c4'), PreviewMode.live);
      expect(scheduler.modeFor('c5'), PreviewMode.snapshot);
      expect(scheduler.modeFor('c6'), PreviewMode.snapshot);
    });

    test('caméra hors liste → snapshot ; liste vide → snapshot', () {
      final scheduler = StreamScheduler();
      expect(scheduler.modeFor('inconnue'), PreviewMode.snapshot);
      scheduler.updateCameras([]);
      expect(scheduler.modeFor('c1'), PreviewMode.snapshot);
    });

    test('setMaxLivePreviews borne et réapplique immédiatement', () {
      final scheduler = StreamScheduler(maxLivePreviews: 8);
      scheduler.updateCameras(List.generate(10, (i) => 'c${i + 1}'));
      expect(scheduler.modeFor('c7'), PreviewMode.live);

      scheduler.setMaxLivePreviews(2);
      expect(scheduler.activeLimit, 2);
      expect(scheduler.modeFor('c1'), PreviewMode.live);
      expect(scheduler.modeFor('c2'), PreviewMode.live);
      expect(scheduler.modeFor('c3'), PreviewMode.snapshot);

      // Bornes : 0 → 1, 99 → 16.
      scheduler.setMaxLivePreviews(0);
      expect(scheduler.maxLivePreviews, 1);
      scheduler.setMaxLivePreviews(99);
      expect(scheduler.maxLivePreviews, 16);
    });
  });

  group('StreamScheduler — dégradation automatique (congestion)', () {
    test('snapshot lent (>3s) → un flux live de moins, min 1', () {
      var fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
      final scheduler = StreamScheduler(maxLivePreviews: 4, now: () => fakeNow);
      scheduler.updateCameras(List.generate(6, (i) => 'c${i + 1}'));
      expect(scheduler.activeLimit, 4);

      // Première sonde congestionnelle.
      scheduler.reportProbeDuration(const Duration(seconds: 5));
      expect(scheduler.activeLimit, 3);

      // Hystérésis : avant 10 s, rien ne bouge.
      scheduler.reportProbeDuration(const Duration(seconds: 5));
      expect(scheduler.activeLimit, 3);

      // Après 10 s : dégrade encore, jusqu'au plancher 1.
      fakeNow = fakeNow.add(const Duration(seconds: 11));
      scheduler.reportProbeDuration(const Duration(seconds: 4));
      expect(scheduler.activeLimit, 2);
      fakeNow = fakeNow.add(const Duration(seconds: 11));
      scheduler.reportProbeDuration(const Duration(seconds: 4));
      expect(scheduler.activeLimit, 1);
      fakeNow = fakeNow.add(const Duration(seconds: 11));
      scheduler.reportProbeDuration(const Duration(seconds: 4));
      expect(scheduler.activeLimit, 1); // plancher

      // Effet visible sur la mosaïque : seule c1 reste live.
      expect(scheduler.modeFor('c1'), PreviewMode.live);
      expect(scheduler.modeFor('c2'), PreviewMode.snapshot);
    });

    test('snapshot rapide (<1s) → récupération progressive du quota', () {
      var fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
      final scheduler = StreamScheduler(maxLivePreviews: 4, now: () => fakeNow);

      // Congestion puis récupération réseau.
      scheduler.reportProbeDuration(const Duration(seconds: 5));
      expect(scheduler.activeLimit, 3);

      fakeNow = fakeNow.add(const Duration(seconds: 11));
      scheduler.reportProbeDuration(const Duration(milliseconds: 400));
      expect(scheduler.activeLimit, 4);

      // Ne dépasse jamais le maximum configuré.
      fakeNow = fakeNow.add(const Duration(seconds: 11));
      scheduler.reportProbeDuration(const Duration(milliseconds: 400));
      expect(scheduler.activeLimit, 4);
    });

    test('sonde moyenne (1-3s) : aucun changement', () {
      final scheduler = StreamScheduler(maxLivePreviews: 4);
      scheduler.reportProbeDuration(const Duration(seconds: 2));
      expect(scheduler.activeLimit, 4);
    });
  });

  group('deriveGo2rtcSnapshotUrl', () {
    test('dérive /api/frame.jpeg avec cache-buster', () {
      final url = deriveGo2rtcSnapshotUrl(
        'http://192.168.100.14:1984/api/stream.m3u8?src=cocody_entree',
        ts: 123456,
      );
      expect(
        url,
        'http://192.168.100.14:1984/api/frame.jpeg?src=cocody_entree'
        '&ts=123456',
      );
    });

    test('préserve sous-chemin et basic-auth', () {
      final url = deriveGo2rtcSnapshotUrl(
        'https://eyesafe:pw@cloud.eyesafe.ci/video/api/stream.m3u8?src=EYE7-1',
      );
      expect(
        url,
        'https://eyesafe:pw@cloud.eyesafe.ci/video/api/frame.jpeg?src=EYE7-1',
      );
    });

    test('retourne null hors go2rtc (RTSP, HLS externe, sans src)', () {
      expect(
        deriveGo2rtcSnapshotUrl(
          'rtsp://admin:pass@192.168.1.64:554/Streaming/Channels/102',
        ),
        isNull,
      );
      expect(
        deriveGo2rtcSnapshotUrl('https://test-streams.mux.dev/x36xhzz.m3u8'),
        isNull,
      );
      expect(deriveGo2rtcSnapshotUrl('http://h:1984/api/stream.m3u8'), isNull);
    });
  });
}
