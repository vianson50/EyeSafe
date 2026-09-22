import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/data/brand_api.dart';
import 'package:eyesafe/data/http_digest.dart';

void main() {
  group('HttpDigest (partagé ISAPI/VAPIX/LAPI)', () {
    test('vecteur RFC 2617 — réponse déterministe', () {
      final header = HttpDigest.buildDigestHeader(
        method: 'GET',
        uri: '/dir/index.html',
        user: 'Mufasa',
        password: 'Circle Of Life',
        realm: 'testrealm@host.com',
        nonce: 'dcd98b7102dd2f0e8b11d0f600bfb0c093',
        qop: 'auth',
        nc: '00000001',
        cnonce: '0a4f113b',
      );
      expect(header, contains('response="6629fae49393a05397450978507c4ef1"'));
      expect(header, contains('algorithm=MD5'));
    });

    test('parse les challenges des 3 constructeurs', () {
      // Hikvision
      final hik = HttpDigest.parseChallenge(
        'Digest realm="IP Camera(12345)", nonce="abc", qop="auth"',
      );
      expect(hik['realm'], 'IP Camera(12345)');

      // Axis (realm avec espaces)
      final axis = HttpDigest.parseChallenge(
        'Digest realm="AXIS:ACCC8E123456", nonce="xyz", stale=FALSE',
      );
      expect(axis['realm'], 'AXIS:ACCC8E123456');

      // Uniview
      final unv = HttpDigest.parseChallenge(
        'Digest realm="uniview", nonce="n1", qop="auth"',
      );
      expect(unv['nonce'], 'n1');

      // Non-Digest → erreur
      expect(
        () => HttpDigest.parseChallenge('Basic realm="x"'),
        throwsFormatException,
      );
    });
  });

  group('VAPIX (Axis) — parsing param.cgi', () {
    test('extrait modèle, série et firmware du texte clé=valeur', () {
      const body = '''
root.Brand.Brand=AXIS
root.Brand.ProdShortName=P3265-LV
root.Brand.WebURL=http://www.axis.com
root.Properties.System.SerialNumber=ACCC8E123456
root.Properties.Firmware.Version=10.12.0
root.Properties.System.ID=ACCC8E123456
''';
      final info = parseVapixDeviceInfoForTest(body);
      expect(info.model, 'P3265-LV');
      expect(info.serial, 'ACCC8E123456');
      expect(info.firmware, '10.12.0');
    });

    test('tombe en repli sur le nom de marque si pas de ProdShortName', () {
      const body = 'root.Brand.Brand=AXIS\n';
      final info = parseVapixDeviceInfoForTest(body);
      expect(info.model, 'AXIS');
      expect(info.serial, isEmpty);
    });

    test('texte illisible → champs vides sans crash', () {
      final info = parseVapixDeviceInfoForTest('<html>401</html>');
      expect(info.model, isEmpty);
    });
  });

  group('LAPI (Uniview) — parsing JSON', () {
    test('extrait DevInfo standard', () {
      const body = '''
{
  "ResponseData": {
    "DevInfo": {
      "Model": "IPC212SR3-PF36",
      "SerialNumber": "C12345678",
      "FirmwareVersion": "V5.2.1",
      "MACAddress": "74:8e:12:34:56:78"
    }
  },
  "ResponseString": "",
  "StatusCode": 1
}
''';
      final info = parseLapiDeviceInfoForTest(body);
      expect(info.model, 'IPC212SR3-PF36');
      expect(info.serial, 'C12345678');
      expect(info.firmware, 'V5.2.1');
    });

    test('accepte les variantes de clés (SN, DeviceType)', () {
      const body = '''
{"ResponseData":{"DevInfo":{"DeviceType":"IPC-D","SN":"X99","FW":"1.0"}}}
''';
      final info = parseLapiDeviceInfoForTest(body);
      expect(info.model, 'IPC-D');
      expect(info.serial, 'X99');
      expect(info.firmware, isEmpty); // ni FirmwareVersion ni Firmware
    });

    test('réponse sans DevInfo → erreur explicite', () {
      expect(
        () => parseLapiDeviceInfoForTest('{"ResponseData":{}}'),
        throwsA(isA<BrandApiException>()),
      );
      expect(
        () => parseLapiDeviceInfoForTest('pas du tout json'),
        throwsA(isA<BrandApiException>()),
      );
    });
  });

  group('AxisVapix / UniviewLapi — URLs', () {
    test('construit les URI http/https selon certificat auto-signé', () {
      final http = AxisVapix(host: '192.168.1.10', user: 'root', password: 'p');
      // Le port 80 par défaut est omis par Uri.toString() — équivalent.
      final httpUri = http.uriFor('/axis-cgi/param.cgi');
      expect(httpUri.scheme, 'http');
      expect(httpUri.host, '192.168.1.10');
      expect(httpUri.port, 80);

      final https = UniviewLapi(
        host: '172.16.0.20',
        user: 'admin',
        password: 'p',
        allowSelfSigned: true,
      );
      expect(https.scheme, 'https');
      expect(
        https.uriFor('/LAPI/V1.0/System/DeviceInfo').path,
        '/LAPI/V1.0/System/DeviceInfo',
      );

      // Port non standard conservé tel quel.
      final custom = AxisVapix(
        host: 'h',
        httpPort: 8080,
        user: 'root',
        password: 'p',
      );
      expect(custom.uriFor('/x').toString(), 'http://h:8080/x');
    });
  });
}
