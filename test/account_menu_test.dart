import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/data/site_controller.dart';
import 'package:eyesafe/ui/app_shell.dart';
import 'package:eyesafe/ui/data_scope.dart';

void main() {
  testWidgets('Menu compte : déconnexion visible et fonctionnelle', (
    WidgetTester tester,
  ) async {
    final controller = SiteController.demoForTest();
    addTearDown(controller.dispose);

    var signedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DataScope(
          controller: controller,
          child: AppShell(
            onLogout: () => signedOut = true,
            userEmail: 'technicien@eyesafe.ci',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Le bouton compte est présent dans le header.
    final accountButton = find.byIcon(Icons.person_outline);
    expect(accountButton, findsOneWidget);

    // Ouverture du menu compte.
    await tester.tap(accountButton);
    await tester.pumpAndSettle();

    expect(find.text('Se déconnecter'), findsWidgets);
    expect(find.text('Client Pro'), findsOneWidget);
    expect(find.text('technicien@eyesafe.ci'), findsOneWidget);

    // Confirmation.
    await tester.tap(find.text('Se déconnecter').last);
    await tester.pumpAndSettle();

    // Dialogue de confirmation ouvert ; Annuler ne déconnecte pas.
    expect(find.text('Se déconnecter ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(signedOut, isFalse);

    // Re-ouverture puis confirmation réelle.
    await tester.tap(accountButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Se déconnecter').last);
    await tester.pumpAndSettle();
    // Le bouton du dialogue garde la casse naturelle (uppercase: false).
    // Seul le bouton correspond exactement — le titre porte un « ? ».
    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
  });

  testWidgets('Mode démo sans compte : pas de bouton compte', (
    WidgetTester tester,
  ) async {
    final controller = SiteController.demoForTest();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DataScope(controller: controller, child: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person_outline), findsNothing);
    expect(find.text('Se déconnecter'), findsNothing);
  });

  testWidgets('La page Paramètres s\'ouvre sans écran blanc (DataScope)', (
    WidgetTester tester,
  ) async {
    final controller = SiteController.demoForTest();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DataScope(controller: controller, child: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    // Le ⚙ du header ouvre la page Paramètres (route au-dessus du
    // DataScope — régression : écran blanc en release si non enveloppée).
    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Le thème n'est plus réglable dans l'app (suit le système) — on
    // vérifie les sections restantes.
    expect(find.text('LECTURE DIRECT'), findsOneWidget);
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(find.text('À PROPOS'), findsOneWidget);
    expect(find.text('APPARENCE'), findsNothing);
  });
}
