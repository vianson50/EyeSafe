import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/data/site_controller.dart';
import 'package:eyesafe/pages/cameras_page.dart';
import 'package:eyesafe/pages/dashboard_page.dart';
import 'package:eyesafe/pages/equipment_page.dart';
import 'package:eyesafe/pages/maintenance_page.dart';
import 'package:eyesafe/pages/support_page.dart';
import 'package:eyesafe/ui/data_scope.dart';
import 'package:eyesafe/ui/theme.dart';

void main() {
  /// Les pages signalées (dashboard, caméras, équipements, support) doivent
  /// s'afficher sans le moindre débordement de layout, y compris sur un
  /// viewport mobile étroit (360×720) où les en-têtes compriment le texte.
  Future<void> pumpPage(WidgetTester tester, Size size, Widget page) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: DataScope(
          controller: SiteController.demoForTest(),
          child: Scaffold(body: page),
        ),
      ),
    );
  }

  final sizes = [
    const Size(360, 720), // mobile
    const Size(760, 1024), // tablette
    const Size(1440, 900), // desktop
  ];

  for (final size in sizes) {
    group('${size.width}x${size.height}', () {
      testWidgets('Dashboard sans overflow', (tester) async {
        await pumpPage(
          tester,
          size,
          DashboardPage(
            onOpenEquipment: () {},
            onOpenSupport: () {},
            onOpenMaintenance: () {},
            onReportIncident: () {},
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Vue d\'ensemble'), findsOneWidget);
      });

      testWidgets('Caméras sans overflow', (tester) async {
        await pumpPage(tester, size, const CamerasPage());
        expect(tester.takeException(), isNull);
        expect(find.text('Caméras en direct'), findsOneWidget);
      });

      testWidgets('Équipements sans overflow', (tester) async {
        await pumpPage(tester, size, const EquipmentPage());
        expect(tester.takeException(), isNull);
        expect(find.text('Mes équipements'), findsOneWidget);
      });

      testWidgets('Support sans overflow', (tester) async {
        await pumpPage(tester, size, const SupportPage());
        expect(tester.takeException(), isNull);
        expect(find.text('Alertes & support'), findsOneWidget);
      });

      testWidgets('Maintenance sans overflow ni texte vertical', (
        tester,
      ) async {
        await pumpPage(tester, size, const MaintenancePage());
        expect(tester.takeException(), isNull);
        expect(find.text('Entretiens & maintenance'), findsOneWidget);

        // Les rapports d'intervention doivent tenir sur une ou deux lignes :
        // si le texte se coupe lettre par lettre (design « vertical »), la
        // hauteur du rendu explose.
        final firstPastVisit = SiteController.demoForTest().visits
            .where((v) => v.isPast)
            .first;
        final dateRender = tester.renderObject<RenderBox>(
          find.text(firstPastVisit.dateLabel),
        );
        expect(dateRender.size.height, lessThan(60));
      });
    });
  }
}
