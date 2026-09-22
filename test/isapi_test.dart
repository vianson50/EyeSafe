import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:eyesafe/data/g711.dart';
import 'package:eyesafe/data/isapi.dart';

void main() {
  group('IsapiDevice.buildDigestHeader (Digest MD5)', () {
    test('vecteur RFC 2617 (qop=auth)', () {
      // Valeurs de référence de la RFC 2617 — déterministes via cnonce fixé.
      final header = IsapiDevice.buildDigestHeader(
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

      expect(header, contains('Digest'));
      expect(header, contains('username="Mufasa"'));
      expect(header, contains('realm="testrealm@host.com"'));
      expect(header, contains('nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093"'));
      expect(header, contains('uri="/dir/index.html"'));
      expect(header, contains('algorithm=MD5'));
      // response = md5(HA1:nonce:nc:cnonce:qop:HA2) du vecteur RFC.
      expect(header, contains('response="6629fae49393a05397450978507c4ef1"'));
      expect(header, contains('qop=auth'));
      expect(header, contains('nc=00000001'));
      expect(header, contains('cnonce="0a4f113b"'));
    });

    test('sans qop (compat anciens firmwares)', () {
      final header = IsapiDevice.buildDigestHeader(
        method: 'GET',
        uri: '/ISAPI/System/deviceInfo',
        user: 'admin',
        password: 'pass',
        realm: 'IP Camera',
        nonce: 'abc123',
        qop: '',
        cnonce: '0a4f113b',
      );
      expect(header, contains('response='));
      expect(header, isNot(contains('qop')));
    });
  });

  group('IsapiDevice.parseChallenge', () {
    test('extrait les paramètres du WWW-Authenticate Hikvision', () {
      const challenge =
          'Digest realm="IP Camera(1234567890)", nonce="4f3a2b", '
          'qop="auth", stale="FALSE"';
      final params = IsapiDevice.parseChallenge(challenge);
      expect(params['realm'], 'IP Camera(1234567890)');
      expect(params['nonce'], '4f3a2b');
      expect(params['qop'], 'auth');
    });

    test('rejete un challenge non Digest ou sans nonce', () {
      // Depuis la factorisation dans HttpDigest, l'échec de parsing lève
      // FormatException (convertie en IsapiException par le client réseau).
      expect(
        () => IsapiDevice.parseChallenge('Basic realm="x"'),
        throwsFormatException,
      );
    });
  });

  group('parseDeviceInfoForTest', () {
    test('extrait modèle, série, firmware', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<DeviceInfo xmlns="http://www.hikvision.com/ver20/XMLSchema" version="2.0">
  <deviceName>IP Camera</deviceName>
  <deviceID>1</deviceID>
  <model>DS-2CD2143G2-I</model>
  <serialNumber>DS-2CD2143G2-I20210901CCWR123456789</serialNumber>
  <macAddress>c0:56:e3:12:34:56</macAddress>
  <firmwareVersion>V5.7.3</firmwareVersion>
</DeviceInfo>
''';
      final info = parseDeviceInfoForTest(xml);
      expect(info.model, 'DS-2CD2143G2-I');
      expect(info.serial, contains('CCWR'));
      expect(info.firmware, 'V5.7.3');
      expect(info.mac, 'c0:56:e3:12:34:56');
    });
  });

  group('parseChannelsForTest', () {
    test('canal 101 = caméra 1 principal, 102 = secondaire', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<StreamingChannelList>
  <StreamingChannel>
    <id>101</id>
    <ChannelName>Camera 01</ChannelName>
    <Video>
      <maxResolution><width>2304</width><height>1296</height></maxResolution>
    </Video>
  </StreamingChannel>
  <StreamingChannel>
    <id>102</id>
    <ChannelName>Camera 01</ChannelName>
    <Video>
      <maxResolution><width>640</width><height>360</height></maxResolution>
    </Video>
  </StreamingChannel>
  <StreamingChannel>
    <id>201</id>
    <ChannelName>Camera 02</ChannelName>
  </StreamingChannel>
</StreamingChannelList>
''';
      final channels = parseChannelsForTest(xml);
      expect(channels, hasLength(3));

      final main = channels.first;
      expect(main.id, 101);
      expect(main.cameraNumber, 1);
      expect(main.isMainStream, isTrue);
      expect(main.resolutionLabel, '2304×1296');

      final sub = channels[1];
      expect(sub.isMainStream, isFalse);
      expect(sub.cameraNumber, 1);

      final cam2 = channels.last;
      expect(cam2.id, 201);
      expect(cam2.cameraNumber, 2);
      expect(cam2.resolutionLabel, '—');
    });

    test('ignore les ids invalides', () {
      const xml = '''
<StreamingChannelList>
  <StreamingChannel><id>x</id></StreamingChannel>
  <StreamingChannel><id>7</id></StreamingChannel>
</StreamingChannelList>
''';
      expect(parseChannelsForTest(xml), isEmpty);
    });
  });

  group('flipMotionEnabledForTest', () {
    test('bascule enabled sans toucher au reste', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<MotionDetection xmlns="http://www.hikvision.com/ver20/XMLSchema">
  <enabled>false</enabled>
  <sensitivityLevel>50</sensitivityLevel>
  <targetLevel>5</targetLevel>
</MotionDetection>
''';
      final enabled = flipMotionEnabledForTest(xml, true);
      expect(enabled, contains('<enabled>true</enabled>'));
      expect(enabled, contains('<sensitivityLevel>50</sensitivityLevel>'));

      final back = flipMotionEnabledForTest(enabled, false);
      expect(back, contains('<enabled>false</enabled>'));
    });

    test('document sans enabled → erreur explicite', () {
      expect(
        () => flipMotionEnabledForTest('<MotionDetection/>', true),
        throwsA(isA<IsapiException>()),
      );
    });
  });

  group('G.711 (talk-back)', () {
    test('μ-law et A-law : valeurs de référence du portage CCITT', () {
      // Silence (0) — traces de l'algorithme de référence g711.c.
      expect(G711.linearToUlaw(0), 0xCF);
      expect(G711.linearToAlaw(0), 0xD5);
      // Négatif minimal.
      expect(G711.linearToAlaw(-1), 0x55);
    });

    test('bornes extrêmes sans crash', () {
      // Le codec émet toujours un octet valide, quel que soit le PCM.
      for (final s in [-32768, -8192, 0, 8191, 32760]) {
        expect(G711.linearToUlaw(s), inInclusiveRange(0, 255));
        expect(G711.linearToAlaw(s), inInclusiveRange(0, 255));
      }
    });

    test('encodage d\'un tampon PCM16 LE mono', () {
      // 2 échantillons : silence + max positif.
      final bytes = [0x00, 0x00, 0xF8, 0x7F];
      final g711 = G711.encodePcm16Le(bytes);
      expect(g711, hasLength(2));
      expect(g711[0], 0xCF);
    });
  });

  group('Replay ISAPI', () {
    test('parse une réponse CMSSearchResult', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CMSearchResult>
  <searchID>C0-1</searchID>
  <responseStatus>true</responseStatus>
  <numOfMatches>2</numOfMatches>
  <matchList>
    <searchMatchItem>
      <trackID>101</trackID>
      <timeSpan>
        <startTime>2026-09-19T01:00:00Z</startTime>
        <endTime>2026-09-19T01:45:00Z</endTime>
      </timeSpan>
    </searchMatchItem>
    <searchMatchItem>
      <trackID>101</trackID>
      <timeSpan>
        <startTime>2026-09-19T08:00:00Z</startTime>
        <endTime>2026-09-19T08:30:00Z</endTime>
      </timeSpan>
    </searchMatchItem>
  </matchList>
</CMSearchResult>
''';
      final recordings = parseRecordingsForTest(xml);
      expect(recordings, hasLength(2));
      expect(recordings.first.trackId, 101);
      expect(recordings.first.duration, const Duration(minutes: 45));
      expect(recordings.last.start.hour, 8);
    });

    test('ignore les segments invalides (fin <= début)', () {
      const xml = '''
<CMSearchResult><matchList>
  <searchMatchItem>
    <trackID>101</trackID>
    <timeSpan>
      <startTime>2026-09-19T10:00:00Z</startTime>
      <endTime>2026-09-19T10:00:00Z</endTime>
    </timeSpan>
  </searchMatchItem>
</matchList></CMSearchResult>
''';
      expect(parseRecordingsForTest(xml), isEmpty);
    });

    test('URL de lecture : piste + fenêtre ISO 8601 basique', () {
      final url = IsapiDevice.playbackUrl(
        host: '192.168.1.64',
        rtspPort: '554',
        user: 'admin',
        password: 'Pass@123',
        trackId: 101,
        start: DateTime.utc(2026, 9, 19, 1, 0, 0),
        end: DateTime.utc(2026, 9, 19, 1, 45, 0),
      );
      expect(
        url,
        'rtsp://admin:Pass%40123@192.168.1.64:554/Streaming/tracks/101'
        '?starttime=20260919T010000Z&endtime=20260919T014500Z',
      );
    });
  });

  group('Gestion des capacités PTZ', () {
    test('réponse PTZCtrl capabilities exposant PTZCapability → PTZ', () {
      // Structure renvoyée par /ISAPI/PTZCtrl/channels/n/capabilities :
      // la présence de PTZCapability signale un appareil motorisé.
      const xml = '''
<PTZCaps xmlns="http://www.hikvision.com/ver20/XMLSchema">
  <PTZCapability><ptzProxy>false</ptzProxy></PTZCapability>
  <MotionDetectionCapabilityRange/>
</PTZCaps>
''';
      final doc = XmlDocument.parse(xml);
      expect(doc.findAllElements('PTZCapability').isNotEmpty, isTrue);

      // Une caméra bas de gamme renvoie 404/400 → pas de PTZCapability.
      const basic = '<DeviceCaps><VideoCapability/></DeviceCaps>';
      expect(
        XmlDocument.parse(basic).findAllElements('PTZCapability').isNotEmpty,
        isFalse,
      );
    });
  });
}
