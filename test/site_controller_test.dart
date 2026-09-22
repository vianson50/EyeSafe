import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/data/models.dart';
import 'package:eyesafe/data/onvif.dart';
import 'package:eyesafe/data/site_controller.dart';

void main() {
  group('Mappers Supabase', () {
    test('Equipment.fromDb mappe tous les champs', () {
      final equipment = Equipment.fromDb({
        'id': 'uuid-1',
        'name': 'Caméra test',
        'model': 'Axis P3265-LV',
        'serial': 'AX-123',
        'location': 'Entrepôt',
        'category': 'camera',
        'installed_on': '2026-01-15',
        'warranty_until': '2027-06-30',
        'storage_used_pct': 68.0,
        'storage_total_label': '4 TO',
      });

      expect(equipment.category, EquipmentCategory.camera);
      expect(equipment.storageUsed, closeTo(0.68, 0.0001));
      expect(equipment.storageTotal, '4 TO');
      expect(equipment.underWarranty, isTrue);
      expect(equipment.warrantyExpiringSoon, isFalse);
      expect(equipment.installedAt.year, 2026);
    });

    test('Equipment.fromDb gère les champs null', () {
      final equipment = Equipment.fromDb({
        'id': 'uuid-2',
        'name': 'NVR',
        'model': null,
        'serial': null,
        'location': null,
        'category': 'recorder',
        'installed_on': '2025-03-01',
        'warranty_until': null,
        'storage_used_pct': null,
        'storage_total_label': null,
      });

      expect(equipment.underWarranty, isFalse);
      expect(equipment.storageUsed, isNull);
      expect(equipment.model, '');
    });

    test('MaintenanceVisit.fromDb mappe les tâches et rapport', () {
      final visit = MaintenanceVisit.fromDb({
        'scheduled_on': '2026-10-01',
        'technician_name': 'Karim B.',
        'tasks': ['Nettoyage', 'Contrôle'],
        'report_ref': 'RPT-2026-001',
      });

      expect(visit.isPast, isTrue);
      expect(visit.tasks, hasLength(2));
      expect(visit.technician, 'Karim B.');
    });

    test('NotificationItem.fromDb mappe les champs et l\'état lu', () {
      final unread = NotificationItem.fromDb({
        'id': 'n1',
        'title': 'Nouveau signalement',
        'body': 'Écran noir',
        'created_at': '2026-09-15T10:00:00Z',
        'read_at': null,
        'data': {'type': 'ticket'},
      });
      expect(unread.isUnread, isTrue);
      expect(unread.type, 'ticket');

      final read = NotificationItem.fromDb({
        'id': 'n2',
        'title': 'Ticket mis à jour',
        'body': null,
        'created_at': '2026-09-15T10:00:00Z',
        'read_at': '2026-09-15T11:00:00Z',
        'data': null,
      });
      expect(read.isUnread, isFalse);
      expect(read.type, isNull);
    });

    test('rtspUrlFor génère les URLs Hikvision et Dahua (flux secondaire)', () {
      final hik = SiteController.rtspUrlFor(
        brand: 'Hikvision',
        host: '192.168.1.64',
        port: '554',
        user: 'admin',
        password: 'Pass@123',
        channel: 3,
      );
      expect(
        hik,
        'rtsp://admin:Pass%40123@192.168.1.64:554/Streaming/Channels/302',
      );

      final dahua = SiteController.rtspUrlFor(
        brand: 'Dahua',
        host: '10.0.0.5',
        port: '554',
        user: 'admin',
        password: 'secret',
        channel: 1,
      );
      expect(
        dahua,
        'rtsp://admin:secret@10.0.0.5:554/cam/realmonitor?channel=1&subtype=1',
      );
    });

    test('adaptateurs Axis, Uniview et Imou', () {
      // Axis — VAPIX media.amp, sous-flux via paramètres.
      final axis = SiteController.rtspUrlFor(
        brand: 'Axis',
        host: '192.168.1.10',
        port: '554',
        user: 'root',
        password: 'pass',
        channel: 1,
      );
      expect(
        axis,
        'rtsp://root:pass@192.168.1.10:554/axis-media/media.amp'
        '?camera=1&videocodec=h264&resolution=640x360&fps=15',
      );

      // Uniview — unicast, s1 = flux secondaire.
      final uniview = SiteController.rtspUrlFor(
        brand: 'Uniview',
        host: '172.16.0.20',
        port: '554',
        user: 'admin',
        password: 'pw',
        channel: 4,
      );
      expect(uniview, 'rtsp://admin:pw@172.16.0.20:554/unicast/c4/s1/live');

      // Imou — gamme grand public de Dahua → mêmes chemins.
      final imou = SiteController.rtspUrlFor(
        brand: 'Imou',
        host: '192.168.1.30',
        port: '554',
        user: 'admin',
        password: 'pw',
        channel: 2,
      );
      expect(
        imou,
        'rtsp://admin:pw@192.168.1.30:554/cam/realmonitor?channel=2&subtype=1',
      );
    });

    test('TicketStatus mappe les valeurs base', () {
      expect(TicketStatusX.fromDb('pending'), TicketStatus.pending);
      expect(TicketStatusX.fromDb('en_route'), TicketStatus.enRoute);
      expect(TicketStatusX.fromDb('resolved'), TicketStatus.resolved);
      expect(TicketStatusX.fromDb('inconnu'), TicketStatus.resolved);
    });
  });

  group('SiteController mode démo', () {
    test('les données de démo sont exposées', () {
      final controller = SiteController.demoForTest();

      expect(controller.equipment, isNotEmpty);
      expect(controller.tickets, hasLength(3));
      expect(controller.visits, isNotEmpty);
      expect(controller.alerts, hasLength(3));
      expect(controller.contract?.siteLabel, 'Boutique Cocody Angré');
      expect(controller.isLive, isFalse);
      expect(controller.noSite, isFalse);
      controller.dispose();
    });

    test('respondToTicket met à jour le ticket en mode démo', () async {
      final controller = SiteController.demoForTest();
      final pending = controller.tickets.firstWhere(
        (t) => t.status == TicketStatus.pending,
      );

      final deadline = DateTime.now().add(const Duration(hours: 24));
      final error = await controller.respondToTicket(
        ticket: pending,
        deadline: deadline,
        note: 'Dépannage programmé',
      );

      expect(error, isNull);
      final updated = controller.tickets.firstWhere((t) => t.id == pending.id);
      expect(updated.status, TicketStatus.enRoute);
      expect(updated.interventionAt, deadline);
      expect(updated.technicianNote, 'Dépannage programmé');
      controller.dispose();
    });

    test('createTicket insère le ticket en tête en mode démo', () async {
      final controller = SiteController.demoForTest();
      final initialCount = controller.tickets.length;

      await controller.createTicket(
        title: 'Écran noir',
        equipmentId: 'EQ-002',
        description: 'Plus d\'image.',
      );

      expect(controller.tickets, hasLength(initialCount + 1));
      expect(controller.tickets.first.title, 'Écran noir');
      expect(controller.tickets.first.status, TicketStatus.pending);
      expect(controller.tickets.first.equipment, contains('EQ-002'));
      controller.dispose();
    });

    test('removeEquipment déconnecte une caméra en mode démo', () async {
      final controller = SiteController.demoForTest();

      // Connecte 2 caméras puis en retire une.
      final error = await controller.connectNvr(
        brand: 'Hikvision',
        host: '192.168.1.64',
        port: '554',
        user: 'admin',
        password: 'pass',
        channels: 2,
        namePrefix: 'Test',
      );
      expect(error, isNull);
      final before = controller.equipment.length;
      final target = controller.equipment.last;

      final removeError = await controller.removeEquipment(target);

      expect(removeError, isNull);
      expect(controller.equipment.length, before - 1);
      expect(controller.equipment.where((e) => e.id == target.id), isEmpty);
      // Id inconnu : sans effet, sans erreur.
      expect(await controller.removeEquipment(target), isNull);
      controller.dispose();
    });

    test('authorizedPtzControl autorise en mode démo', () async {
      final controller = SiteController.demoForTest();
      final camera = controller.equipment.firstWhere(
        (e) => e.streamUrl != null,
      );
      // Mode démo : pas de backend → autorisé (pas de tenant à vérifier).
      expect(await controller.authorizedPtzControl(camera), isTrue);
      controller.dispose();
    });

    test('authorizedStreamUrl retourne l\'URL stockée en mode démo', () async {
      final controller = SiteController.demoForTest();
      final camera = controller.equipment.firstWhere(
        (e) => e.streamUrl != null,
      );

      expect(await controller.authorizedStreamUrl(camera), camera.streamUrl);
      // Caméra sans flux → null.
      final noStream = controller.equipment.firstWhere(
        (e) => e.streamUrl == null,
      );
      expect(await controller.authorizedStreamUrl(noStream), isNull);
      controller.dispose();
    });

    test(
      'recordEvent centralise les événements et isMotionActive suit la fenêtre',
      () async {
        final controller = SiteController.demoForTest();
        final camera = Equipment(
          id: 'CAM-X',
          name: 'Test',
          model: '',
          serial: 'S',
          location: '',
          category: EquipmentCategory.camera,
          installedAt: DateTime.now(),
          streamUrl: 'rtsp://a:b@1.2.3.4:554/x',
        );

        // Aucun événement → pas de mouvement.
        expect(controller.isMotionActive('CAM-X'), isFalse);

        final t0 = DateTime.now();

        // Alarme de mouvement fraîche → actif.
        controller.recordEvent(
          camera,
          const OnvifEvent(
            topic: 'tns1:VideoAnalytics/MotionAlarm',
            data: {'State': 'true'},
          ),
          now: t0,
        );
        expect(controller.isMotionActive('CAM-X'), isTrue);
        expect(controller.cameraEvents, hasLength(1));
        expect(controller.cameraEvents.first.cameraName, 'Test');

        // Fin de mouvement APRÈS la fenêtre de dédup (sinon ignorée comme
        // doublon du même topic) → dernier événement = false.
        controller.recordEvent(
          camera,
          const OnvifEvent(
            topic: 'tns1:VideoAnalytics/MotionAlarm',
            data: {'State': 'false'},
          ),
          now: t0.add(const Duration(seconds: 31)),
        );
        expect(controller.isMotionActive('CAM-X'), isFalse);
        expect(controller.cameraEvents, hasLength(2));

        controller.dispose();
      },
    );

    test(
      'recordEvent DÉDUPLIQUE (caméra+topic) sur 30 s et priorise',
      () async {
        final controller = SiteController.demoForTest();
        final camera = Equipment(
          id: 'CAM-X',
          name: 'Test',
          model: '',
          serial: 'S',
          location: '',
          category: EquipmentCategory.camera,
          installedAt: DateTime.now(),
          streamUrl: 'rtsp://a:b@1.2.3.4:554/x',
        );
        final camB = Equipment(
          id: 'CAM-B',
          name: 'B',
          model: '',
          serial: 'S',
          location: '',
          category: EquipmentCategory.camera,
          installedAt: DateTime.now(),
          streamUrl: 'rtsp://a:b@1.2.3.5:554/x',
        );

        final t0 = DateTime(2026, 9, 22, 14, 0, 0);
        final motion = const OnvifEvent(
          topic: 'tns1:VideoAnalytics/MotionAlarm',
          data: {'State': 'true'},
        );

        // Rafale de 5 événements identiques en 10 s → 1 seul retenu.
        var recorded = 0;
        for (var i = 0; i < 5; i++) {
          if (controller.recordEvent(
            camera,
            motion,
            now: t0.add(Duration(seconds: i * 2)),
          )) {
            recorded++;
          }
        }
        expect(recorded, 1, reason: 'les doublons 30 s sont ignorés');
        expect(controller.cameraEvents, hasLength(1));

        // Autre caméra, même topic → PAS un doublon (clé = caméra+topic).
        expect(
          controller.recordEvent(
            camB,
            motion,
            now: t0.add(const Duration(seconds: 3)),
          ),
          isTrue,
        );

        // Autre topic sur la même caméra → pas un doublon non plus.
        expect(
          controller.recordEvent(
            camera,
            const OnvifEvent(topic: 'tns1:AudioAnalytics/AudioDetected'),
            now: t0.add(const Duration(seconds: 4)),
          ),
          isTrue,
        );

        // Même topic APRÈS la fenêtre de 30 s → enregistré.
        expect(
          controller.recordEvent(
            camera,
            motion,
            now: t0.add(const Duration(seconds: 31)),
          ),
          isTrue,
        );
        // 1 (motion dédup) + 1 (camB) + 1 (audio) + 1 (motion >30s) = 4.
        expect(controller.cameraEvents, hasLength(4));

        controller.dispose();
      },
    );

    test(
      'priorisation : tamper/intrusion = critiques, motion = historique',
      () {
        const motion = OnvifEvent(
          topic: 'tns1:VideoAnalytics/MotionAlarm',
          data: {'State': 'true'},
        );
        const tamper = OnvifEvent(
          topic: 'tns1:Device/TamperDetection',
          data: {'State': 'true'},
        );
        const intrusion = OnvifEvent(
          topic: 'tns1:RuleEngine/FieldDetector/ObjectsInside',
        );

        expect(motion.isCritical, isFalse);
        expect(tamper.isCritical, isTrue);
        expect(intrusion.isCritical, isTrue);
      },
    );

    test('résumé multi-caméras : N caméras distinctes sur 60 s', () {
      final controller = SiteController.demoForTest();
      Equipment cam(String id) => Equipment(
        id: id,
        name: id,
        model: '',
        serial: 'S',
        location: '',
        category: EquipmentCategory.camera,
        installedAt: DateTime.now(),
        streamUrl: 'rtsp://a:b@1.2.3.4:554/x',
      );
      final t0 = DateTime.now();
      final motion = const OnvifEvent(
        topic: 'tns1:VideoAnalytics/MotionAlarm',
        data: {'State': 'true'},
      );

      controller.recordEvent(cam('A'), motion, now: t0);
      controller.recordEvent(cam('B'), motion, now: t0);
      controller.recordEvent(cam('C'), motion, now: t0);

      expect(controller.motionCameraCount, 3);
      expect(controller.multiMotionSummary, 'Activité multiple — 3 caméras');
      controller.dispose();
    });

    test(
      'connectNvr distant crée des caméras via IP publique/domaine',
      () async {
        final controller = SiteController.demoForTest();
        final initialCount = controller.equipment.length;

        final error = await controller.connectNvr(
          brand: 'Hikvision',
          host: 'boutique-cocody.ddns.net',
          port: '8554', // port public redirigé → 554 sur le routeur
          user: 'admin',
          password: 'Pass@123',
          channels: 2,
          namePrefix: 'Angré',
          remote: true,
        );

        expect(error, isNull);
        expect(controller.equipment, hasLength(initialCount + 2));
        final cam = controller.equipment.last;
        expect(cam.model, 'NVR Hikvision · distant');
        expect(cam.location, 'Accès distant · Canal 2');
        expect(
          cam.streamUrl,
          'rtsp://admin:Pass%40123@boutique-cocody.ddns.net:8554'
          '/Streaming/Channels/202',
        );
        controller.dispose();
      },
    );
  });

  group('CameraEventPoller — support et cycle de vie', () {
    test('isSupported : RTSP avec identifiants uniquement', () {
      Equipment camWith(String? url) => Equipment(
        id: 'C1',
        name: 'N',
        model: '',
        serial: 'S',
        location: '',
        category: EquipmentCategory.camera,
        installedAt: DateTime.now(),
        streamUrl: url,
      );
      final controller = SiteController.demoForTest();

      // RTSP + creds → supporté.
      expect(
        CameraEventPoller(
          camera: camWith('rtsp://admin:pass@192.168.1.64:554/x'),
          controller: controller,
        ).isSupported,
        isTrue,
      );
      // Relais go2rtc/cloud (http) → non supporté.
      expect(
        CameraEventPoller(
          camera: camWith('http://cloud:1984/api/stream.m3u8?src=cam'),
          controller: controller,
        ).isSupported,
        isFalse,
      );
      // RTSP sans identifiants → non supporté (pas d'ONVIF Digest).
      expect(
        CameraEventPoller(
          camera: camWith('rtsp@192.168.1.64:554/x'.replaceFirst('@', '')),
          controller: controller,
        ).isSupported,
        isFalse,
      );
      // Pas de flux → non supporté.
      expect(
        CameraEventPoller(
          camera: camWith(null),
          controller: controller,
        ).isSupported,
        isFalse,
      );
      controller.dispose();
    });
  });

  group('testEndpoint (accès distant IP directe)', () {
    test('port invalide ou hôte vide → message d\'erreur', () async {
      expect(
        await SiteController.testEndpoint(host: 'site.ddns.net', port: 'abc'),
        isNotNull,
      );
      expect(
        await SiteController.testEndpoint(host: 'site.ddns.net', port: '70000'),
        isNotNull,
      );
      expect(
        await SiteController.testEndpoint(host: '  ', port: '554'),
        isNotNull,
      );
    });

    test(
      'hôte injoignable → message d\'aide redirection de port',
      () async {
        // IP non routée (RFC 5737) + port : le test doit échouer proprement.
        final error = await SiteController.testEndpoint(
          host: '192.0.2.1',
          port: '554',
        );
        expect(error, isNotNull);
        expect(error, contains('redirection'));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });
}
