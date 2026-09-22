import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/data/dahua_api.dart';

void main() {
  group('DahuaAuth — dérivation du mot de passe (spécification HTTP API)', () {
    test(
      'loginPassword = base64(md5(user:random:base64(md5(user:realm:pass))))',
      () {
        // Valeurs déterministes pour le vecteur de contrôle.
        final loginPassword = DahuaAuth.buildLoginPassword(
          user: 'admin',
          realm: 'Dahua.2817',
          serverRandom: '394238',
          password: 'Pass@123',
        );

        final signature = base64Encode(
          md5.convert(utf8.encode('admin:Dahua.2817:Pass@123')).bytes,
        );
        final expected = base64Encode(
          md5.convert(utf8.encode('admin:394238:$signature')).bytes,
        );

        expect(loginPassword, expected);
        // Le mot de passe clair ne fuit jamais.
        expect(loginPassword.contains('Pass@123'), isFalse);
      },
    );
  });

  group('parseRpcResponseForTest', () {
    test('parse un JSON-RPC Dahua valide', () {
      const body = '''
{"result": false, "code": 268632088,
 "error": {"code": 268632088, "message": "Login sequence error"},
 "data": {"realm": "Dahua.2817", "random": "394238", "session": "abc"}}
''';
      final r = parseRpcResponseForTest(body);
      expect(r['result'], isFalse);
      expect((r['data'] as Map)['realm'], 'Dahua.2817');
      expect((r['data'] as Map)['random'], '394238');
    });

    test('rejette un corps non JSON', () {
      expect(
        () => parseRpcResponseForTest('<html>401</html>'),
        throwsA(isA<DahuaException>()),
      );
    });
  });

  group('parseSystemInfoForTest (magicBox.getSystemInfo)', () {
    test('mappe deviceType, serialNumber et firmware', () {
      const body = '''
{"result": true,
 "data": {
   "appAutoStartVersion": "2.610.0000006.38.R",
   "deviceType": "IPC-HFW2441T",
   "hardwareVersion": "1.20",
   "processor": "SSC327DE",
   "serialNumber": "4L08B9DPAG00037",
   "updateSerial": "IPC-HX2X2X2X-X2-2.620.0000010.0.R"
 },
 "id": 2}
''';
      final info = parseSystemInfoForTest(body);
      expect(info.model, 'IPC-HFW2441T');
      expect(info.serial, '4L08B9DPAG00037');
      // updateSerial prioritaire sur hardwareVersion comme version firmware.
      expect(info.firmware, contains('2.620'));
    });

    test('tombe en repli sur hardwareVersion sans updateSerial', () {
      const body = '''
{"result": true,
 "data": {"deviceType": "IPC-HDBW1230E", "serialNumber": "SN1",
          "hardwareVersion": "1.03"}}
''';
      final info = parseSystemInfoForTest(body);
      expect(info.model, 'IPC-HDBW1230E');
      expect(info.firmware, '1.03');
    });

    test('réponse sans data → erreur explicite', () {
      expect(
        () => parseSystemInfoForTest('{"result": true}'),
        throwsA(isA<DahuaException>()),
      );
    });
  });

  group('DahuaHttp — construction des URI', () {
    test('chemins cgi-bin et ports cohérents', () {
      // Le port 80 par défaut est omis par Uri.toString().
      final custom = DahuaHttp(
        host: 'h',
        httpPort: 8080,
        user: 'a',
        password: 'p',
      );
      expect(custom.host, 'h');
      expect(custom.httpPort, 8080);

      final https = DahuaHttp(
        host: 'h',
        user: 'a',
        password: 'p',
        allowSelfSigned: true,
      );
      expect(https.allowSelfSigned, isTrue);
    });
  });
}
