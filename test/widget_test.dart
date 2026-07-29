import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maspart_mobile/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen renders the form', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );

    // Brand + judul layar
    expect(find.text('MasPart'), findsOneWidget);
    expect(find.text('Masuk'), findsWidgets);

    // Dua field input (username + password)
    expect(find.byType(TextField), findsNWidgets(2));

    // Tombol masuk
    expect(find.widgetWithText(FilledButton, 'Masuk'), findsOneWidget);
  });
}
