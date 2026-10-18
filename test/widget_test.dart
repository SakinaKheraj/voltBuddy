import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:voltbuddy/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // VisibilityDetector batches updates on a timer; tests must flush them
    // immediately (see the visibility_detector package docs).
    VisibilityDetectorController.instance.updateInterval = Duration.zero;

    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // Verify that the main app screen is loaded by finding the rank badge
    expect(find.text('NPC'), findsOneWidget);
  });
}
