import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maspart_mobile/screens/login_screen.dart';
import 'package:maspart_mobile/theme/mas_theme.dart';
import 'package:maspart_mobile/widgets/mas_ui.dart';

void main() {
  testWidgets('LoginScreen renders the form', (WidgetTester tester) async {
    // Tema WAJIB dibangun lewat buildMasTheme: seluruh layar membaca palet
    // lewat `context.mas` (ThemeExtension MasColors). MaterialApp polos membuat
    // ekstensi itu null → layar apa pun meledak di baris pertama build-nya.
    await tester.pumpWidget(
      MaterialApp(theme: buildMasTheme(Brightness.light), home: const LoginScreen()),
    );

    // Brand + judul layar
    expect(find.text('MasPart'), findsOneWidget);
    expect(find.text('Masuk'), findsWidgets);

    // Dua field input (username + password)
    expect(find.byType(TextField), findsNWidgets(2));

    // Tombol masuk — layar ini memakai MasButton (komponen bersama), bukan lagi
    // FilledButton bawaan Material seperti saat test ini pertama ditulis.
    expect(find.widgetWithText(MasButton, 'Masuk'), findsOneWidget);
  });
}
