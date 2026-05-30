import 'package:flutter_test/flutter_test.dart';

import 'package:voltbuddy/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // Verify that the main app screen is loaded by finding the rank badge
    expect(find.text('NPC'), findsOneWidget);
  });
}
