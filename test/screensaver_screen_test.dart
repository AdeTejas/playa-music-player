import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/screens/screensaver_screen.dart';

void main() {
  testWidgets('ScreensaverScreen renders its background and exit hint', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ScreensaverScreen()));
    await tester.pump();

    expect(find.text('Tap anywhere to exit'), findsOneWidget);
  });
}
