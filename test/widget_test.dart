import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/main.dart';

void main() {
  // Smoke test du démarrage en mode démo (backend non configuré).
  //
  // La navigation vers le shell complet est couverte par
  // `responsive_layout_test.dart` (dashboard, caméras, équipements,
  // support — y compris viewports mobiles 360px).
  testWidgets('L\'app démarre et affiche le splash', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const EyeSafeApp());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('EYESAFE'), findsOneWidget);
    expect(find.text('VIDÉOSURVEILLANCE INTELLIGENTE'), findsOneWidget);
  });
}
