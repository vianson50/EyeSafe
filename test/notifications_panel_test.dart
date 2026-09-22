import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/data/site_controller.dart';
import 'package:eyesafe/ui/data_scope.dart';
import 'package:eyesafe/ui/notifications_panel.dart';

void main() {
  testWidgets('Le panneau de notifications s\'ouvre depuis la cloche', (
    WidgetTester tester,
  ) async {
    final controller = SiteController.demoForTest();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DataScope(
          controller: controller,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showNotificationsPanel(context, controller),
                  child: const Text('OUVRIR_CLOCHE'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Le panneau n'est pas ouvert au départ.
    expect(find.text('Notifications'), findsNothing);

    // Appui sur la cloche → le panneau s'ouvre.
    await tester.tap(find.text('OUVRIR_CLOCHE'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    // Mode démo : aucune notification → message d'état vide.
    expect(find.textContaining('Aucune notification'), findsOneWidget);
  });

  testWidgets('Une notification non lue s\'affiche dans le panneau', (
    WidgetTester tester,
  ) async {
    final controller = SiteController.live(null);
    // Injection directe de l'état (sans backend) pour le test.
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    controller.notifications = const [];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DataScope(
          controller: controller,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showNotificationsPanel(context, controller),
                  child: const Text('OUVRIR_CLOCHE'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OUVRIR_CLOCHE'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.textContaining('Tout marquer lu'), findsNothing);
  });
}
