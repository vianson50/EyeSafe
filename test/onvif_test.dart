import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/data/onvif.dart';

void main() {
  group('OnvifDevice.soapEnvelope', () {
    test('contient le UsernameToken digest WS-Security', () {
      final xml = OnvifDevice.soapEnvelope(
        bodyXml: '<GetProfiles xmlns="http://www.onvif.org/ver10/media/wsdl"/>',
        action: 'http://www.onvif.org/ver10/media/wsdl/GetProfiles',
        user: 'admin',
        password: 'Pass@123',
      );

      expect(xml, contains('PasswordDigest'));
      expect(xml, contains('<Username>admin</Username>'));
      expect(xml, contains('<Nonce'));
      expect(xml, contains('<Created'));
      expect(xml, contains('GetProfiles'));
      // Le mot de passe ne doit JAMAIS apparaître en clair.
      expect(xml.contains('Pass@123'), isFalse);
    });

    test('échappe les caractères XML dans le nom d\'utilisateur', () {
      final xml = OnvifDevice.soapEnvelope(
        bodyXml: '<x/>',
        user: 'ad<min>&co',
        password: 'p',
      );
      expect(xml, contains('<Username>ad&lt;min&gt;&amp;co</Username>'));
    });
  });

  group('OnvifProfile', () {
    test('main stream selon la résolution', () {
      final main = OnvifProfile(
        token: 'main',
        name: 'Profile_1',
        width: 2688,
        height: 1520,
      );
      final sub = OnvifProfile(
        token: 'sub',
        name: 'Profile_2',
        width: 640,
        height: 360,
      );

      expect(main.isMainStream, isTrue);
      expect(main.resolutionLabel, '2688×1520');
      expect(sub.isMainStream, isFalse);
    });
  });

  group('parsing GetProfiles (XML caméra)', () {
    test('extrait token, nom, résolution et PTZ', () {
      const response = '''
<?xml version="1.0" encoding="UTF-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Body>
    <GetProfilesResponse xmlns="http://www.onvif.org/ver10/media/wsdl">
      <trt:Profiles token="Profile_1" fixed="true">
        <tt:Name>mainstream</tt:Name>
        <tt:VideoSourceConfiguration token="vsc1">
          <tt:SourceToken>VideoSource_1</tt:SourceToken>
        </tt:VideoSourceConfiguration>
        <tt:VideoEncoderConfiguration>
          <tt:Resolution Width="1920" Height="1080"/>
        </tt:VideoEncoderConfiguration>
      </trt:Profiles>
      <trt:Profiles token="Profile_2">
        <tt:Name>substream</tt:Name>
        <tt:VideoEncoderConfiguration>
          <tt:Resolution Width="640" Height="360"/>
        </tt:VideoEncoderConfiguration>
        <tt:AudioEncoderConfiguration>
          <tt:Name>AAC</tt:Name>
        </tt:AudioEncoderConfiguration>
        <tt:PTZConfiguration token="PTZToken">
          <tt:Name>PTZ</tt:Name>
        </tt:PTZConfiguration>
      </trt:Profiles>
    </GetProfilesResponse>
  </s:Body>
</s:Envelope>
''';

      final doc = OnvifProfileX.parseForTest(response);
      expect(doc, hasLength(2));

      final main = doc.first;
      expect(main.token, 'Profile_1');
      expect(main.name, 'mainstream');
      expect(main.width, 1920);
      expect(main.height, 1080);
      expect(main.hasPtz, isFalse);
      // Source vidéo exposée → service Imaging (filtre IR) disponible.
      expect(main.videoSourceToken, 'VideoSource_1');

      final sub = doc.last;
      expect(sub.token, 'Profile_2');
      expect(sub.hasPtz, isTrue);
      expect(sub.hasAudio, isTrue);
      expect(sub.isMainStream, isFalse);
      // Le flux secondaire n'a pas de config source ici.
      expect(doc.last.videoSourceToken, isNull);
    });
  });

  group('Filtre IR-cut (service Imaging)', () {
    test(
      'parse les modes Auto / On / Off d\'une réponse GetImagingSettings',
      () {
        const auto = '''
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
 <s:Body><timg:GetImagingSettingsResponse>
  <tt:ImagingSettings xmlns:tt="http://www.onvif.org/ver10/schema">
   <tt:IrCutFilter>
    <tt:Auto><tt:DayDelay>2</tt:DayDelay></tt:Auto>
   </tt:IrCutFilter>
  </tt:ImagingSettings>
 </timg:GetImagingSettingsResponse></s:Body>
</s:Envelope>
''';
        expect(parseIrCutModeForTest(auto), OnvifIrCutMode.auto);

        const jour = '''
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
 <s:Body><timg:GetImagingSettingsResponse>
  <tt:ImagingSettings xmlns:tt="http://www.onvif.org/ver10/schema">
   <tt:IrCutFilter><tt:On/></tt:IrCutFilter>
  </tt:ImagingSettings>
 </timg:GetImagingSettingsResponse></s:Body>
</s:Envelope>
''';
        expect(parseIrCutModeForTest(jour), OnvifIrCutMode.on);

        const nuit = '''
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
 <s:Body><timg:GetImagingSettingsResponse>
  <tt:ImagingSettings xmlns:tt="http://www.onvif.org/ver10/schema">
   <tt:IrCutFilter><tt:Off/></tt:IrCutFilter>
  </tt:ImagingSettings>
 </timg:GetImagingSettingsResponse></s:Body>
</s:Envelope>
''';
        expect(parseIrCutModeForTest(nuit), OnvifIrCutMode.off);

        // Sans IrCutFilter → caméra sans imaging : null (bouton masqué).
        const none = '<s:Envelope/>';
        expect(parseIrCutModeForTest(none), isNull);
      },
    );

    test('corps SetImagingSettings avec token échappé et mode demandé', () {
      final body = buildSetIrCutBodyForTest(
        videoSourceToken: 'VideoSource 1&2',
        mode: OnvifIrCutMode.off,
      );
      expect(body, contains('SetImagingSettings'));
      expect(body, contains('VideoSource 1&amp;2'));
      expect(body, contains('<tt:Off/>'));

      final auto = buildSetIrCutBodyForTest(
        videoSourceToken: 'vs',
        mode: OnvifIrCutMode.auto,
      );
      expect(auto, contains('<tt:Auto/>'));
    });

    test('cycle AUTO → JOUR → NUIT → AUTO', () {
      expect(OnvifIrCutMode.auto.next, OnvifIrCutMode.on);
      expect(OnvifIrCutMode.on.next, OnvifIrCutMode.off);
      expect(OnvifIrCutMode.off.next, OnvifIrCutMode.auto);
      expect(OnvifIrCutMode.off.label, 'NUIT');
      expect(OnvifIrCutMode.on.label, 'JOUR');
    });
  });

  group('parsing WS-Discovery ProbeMatch', () {
    test('extrait XAddrs et le nom depuis les scopes', () {
      const probeMatch = '''
<?xml version="1.0" encoding="UTF-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
            xmlns:a="http://schemas.xmlsoap.org/ws/2004/08/addressing"
            xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery">
  <s:Header>
    <a:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/ProbeMatches</a:Action>
  </s:Header>
  <s:Body>
    <ProbeMatches>
      <ProbeMatch>
        <a:EndpointReference>
          <a:Address>urn:uuid:abc-123</a:Address>
        </a:EndpointReference>
        <d:Types>dp0:NetworkVideoTransmitter</d:Types>
        <d:Scopes>onvif://www.onvif.org/type/video_encoder
 onvif://www.onvif.org/name/IPC%20Color%20Dome
 onvif://www.onvif.org/hardware/HW1</d:Scopes>
        <d:XAddrs>http://192.168.1.108:80/onvif/device_service</d:XAddrs>
      </ProbeMatch>
    </ProbeMatches>
  </s:Body>
</s:Envelope>
''';

      final device = parseProbeMatchForTest(probeMatch, '192.168.1.108:3702');
      expect(device, isNotNull);
      expect(device!.host, '192.168.1.108');
      expect(device.xaddrs.first.port, 80);
      expect(device.xaddrs.first.path, '/onvif/device_service');
      expect(device.name, 'IPC Color Dome');
    });

    test('ignore les messages sans ProbeMatch ni XAddrs', () {
      const bye = '''
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Body><Bye xmlns="http://schemas.xmlsoap.org/ws/2005/04/discovery"/></s:Body>
</s:Envelope>
''';
      expect(parseProbeMatchForTest(bye, '1.2.3.4:5'), isNull);

      const noXaddrs = '''
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Body><ProbeMatches><ProbeMatch>
    <d:XAddrs xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"/>
  </ProbeMatch></ProbeMatches></s:Body>
</s:Envelope>
''';
      expect(parseProbeMatchForTest(noXaddrs, '1.2.3.4:5'), isNull);
    });
  });

  group('digest WS-Security (RFC ONVIF)', () {
    test('base64(SHA1(nonce + created + password))', () {
      // Le digest ne doit jamais exposer le mot de passe en clair.
      final header = OnvifDevice.securityHeader(
        user: 'admin',
        password: 'secret',
      );
      expect(header, contains('PasswordDigest'));
      expect(header, isNot(contains('secret')));
    });
  });
}
