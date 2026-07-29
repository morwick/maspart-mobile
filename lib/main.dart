// lib/main.dart — MasPart Mobile. Entry point + tema global (light/dark) + root gate.
// Mengikuti desain "MasPart Mobile.dc": arsitektur Command Center.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/mas_theme.dart';
import 'auth_storage.dart';
import 'app/shell.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const MasPartApp());
}

class MasPartApp extends StatefulWidget {
  const MasPartApp({super.key});
  @override
  State<MasPartApp> createState() => _MasPartAppState();
}

class _MasPartAppState extends State<MasPartApp> {
  final ThemeController _theme = ThemeController();

  @override
  void dispose() {
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      controller: _theme,
      child: AnimatedBuilder(
        animation: _theme,
        builder: (context, _) => MaterialApp(
          title: 'MasPart',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const _MasScrollBehavior(),
          theme: buildMasTheme(Brightness.light),
          darkTheme: buildMasTheme(Brightness.dark),
          themeMode: _theme.mode,
          home: const _RootGate(),
        ),
      ),
    );
  }
}

/// Izinkan drag mouse/trackpad (bukan hanya touch) untuk list horizontal.
class _MasScrollBehavior extends MaterialScrollBehavior {
  const _MasScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

/// Gerbang awal: token tersimpan → shell; jika tidak → login.
class _RootGate extends StatelessWidget {
  const _RootGate();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: AuthStorage.getToken(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: context.mas.canvas,
            body: Center(child: CircularProgressIndicator(color: context.mas.brand600)),
          );
        }
        final token = snap.data;
        if (token != null && token.isNotEmpty) return const AppShell();
        return const LoginScreen();
      },
    );
  }
}
