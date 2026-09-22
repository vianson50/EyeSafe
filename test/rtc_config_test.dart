import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/data/rtc_config.dart';

void main() {
  group('RtcConfig.buildIceServers', () {
    test('défaut : STUN Google seul', () {
      final servers = RtcConfig.buildIceServers();
      expect(servers, hasLength(1));
      expect(servers.first['urls'], 'stun:stun.l.google.com:19302');
    });

    test('STUN multiples séparés par virgules ou retours ligne', () {
      final servers = RtcConfig.buildIceServers(
        stunUrls: 'stun:a.example:3478, stun:b.example:3478\nstun:c:3478',
      );
      expect(servers, hasLength(3));
      expect(servers[0]['urls'], 'stun:a.example:3478');
      expect(servers[1]['urls'], 'stun:b.example:3478');
      expect(servers[2]['urls'], 'stun:c:3478');
    });

    test('TURN avec identifiants ajouté après les STUN', () {
      final servers = RtcConfig.buildIceServers(
        stunUrls: 'stun:a:3478',
        turnUrl: 'turn:turn.eyesafe.ci:3478',
        turnUser: 'eyesafe',
        turnPass: 'secret',
      );
      expect(servers, hasLength(2));
      final turn = servers.last;
      expect(turn['urls'], 'turn:turn.eyesafe.ci:3478');
      expect(turn['username'], 'eyesafe');
      expect(turn['credential'], 'secret');
    });

    test('TURN sans identifiants : entrée URL seule (TURN ouvert)', () {
      final servers = RtcConfig.buildIceServers(turnUrl: 'turn:open:3478');
      expect(servers, hasLength(2));
      expect(servers.last.containsKey('username'), isFalse);
      expect(servers.last.containsKey('credential'), isFalse);
    });

    test('champ STUN vide ou espaces → repli sur le défaut', () {
      expect(RtcConfig.buildIceServers(stunUrls: '   ,  '), hasLength(1));
      expect(
        RtcConfig.buildIceServers(stunUrls: '  ').first['urls'],
        RtcConfig.defaultStunUrls,
      );
    });
  });
}
