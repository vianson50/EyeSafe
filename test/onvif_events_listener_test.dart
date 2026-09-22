import 'package:flutter_test/flutter_test.dart';

import 'package:eyesafe/data/onvif.dart';
import 'package:eyesafe/data/onvif_events_listener.dart';

class _FakeListener extends OnvifEventsListener {
  _FakeListener({required super.onEvent})
    : super(
        deviceUrl: 'http://x',
        credentials: const OnvifCredentials(user: 'a', password: 'b'),
      );

  void emitForTest(OnvifEvent e) => onEvent?.call(e);
}

void main() {
  test('le callback reçoit les événements émis', () {
    final received = <OnvifEvent>[];
    final listener = _FakeListener(onEvent: received.add);

    listener.emitForTest(
      const OnvifEvent(
        topic: 'tns1:VideoAnalytics/MotionAlarm',
        data: {'State': 'true'},
      ),
    );

    expect(received, hasLength(1));
    expect(received.first.isMotionActive, isTrue);
    listener.dispose();
  });

  test('formatXsDuration (helper partagé)', () {
    expect(formatXsDuration(const Duration(seconds: 5)), 'PT5S');
    expect(formatXsDuration(const Duration(seconds: 90)), 'PT1M30S');
  });
}
