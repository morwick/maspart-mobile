// lib/main.dart — MasPart Mobile. Entry point + tema global (light/dark/system)
// + root gate. Mengikuti desain "MasPart Mobile.dc": arsitektur Command Center.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/mas_theme.dart';
import 'auth_storage.dart';
import 'push.dart';
import 'app/shell.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge: konten menggambar sampai di bawah status & navigation bar,
  // warnanya diatur per-tema lewat AnnotatedRegion (lihat MasPartApp).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Aplikasi lapangan dipegang satu tangan — kunci potret supaya tabel & kartu
  // tak melompat saat HP miring di dalam kabin.
  await SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );

  // Preferensi tema dibaca SEBELUM frame pertama agar layar tak berkedip
  // terang → gelap saat aplikasi dibuka.
  final theme = ThemeController();
  await theme.load();

  // Push notifikasi sistem (FCM). Tanpa google-services.json → tidur diam-diam.
  await Push.init();

  // Satu widget yang gagal dibangun tak boleh memunculkan kotak merah "RED
  // SCREEN OF DEATH" berisi jejak tumpukan di layar pengguna lapangan.
  ErrorWidget.builder = (details) => _FriendlyError(details: details);

  runApp(MasPartApp(theme: theme));
}

/// Pengganti kotak galat bawaan Flutter — memberi tahu apa yang harus dilakukan
/// (muat ulang layar) alih-alih menampilkan jejak tumpukan.
class _FriendlyError extends StatelessWidget {
  final FlutterErrorDetails details;
  const _FriendlyError({required this.details});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFDECEA),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 30, color: Color(0xFFC0392B)),
            const SizedBox(height: 8),
            const Text(
              'Bagian ini gagal ditampilkan',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFFC0392B)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Coba buka ulang layar ini. Bila terus terjadi, laporkan ke admin.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Color(0xFF8A4038), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class MasPartApp extends StatefulWidget {
  final ThemeController theme;
  const MasPartApp({super.key, required this.theme});
  @override
  State<MasPartApp> createState() => _MasPartAppState();
}

class _MasPartAppState extends State<MasPartApp> {
  ThemeController get _theme => widget.theme;

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
          // Skala teks HP bisa disetel sampai 2× di Setelan Android; tabel part
          // & kartu stok pecah total di atas 1.3×. Dibatasi, bukan dimatikan —
          // pengguna yang butuh huruf besar tetap terlayani.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final brightness = Theme.of(context).brightness;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: masOverlayStyle(brightness),
              child: MediaQuery(
                data: mq.copyWith(
                  textScaler: mq.textScaler.clamp(
                    minScaleFactor: 0.85,
                    maxScaleFactor: 1.3,
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
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
          return const MasSplash();
        }
        final token = snap.data;
        if (token != null && token.isNotEmpty) return const AppShell();
        return const LoginScreen();
      },
    );
  }
}

/// Layar tunggu bermerek — menggantikan spinner telanjang di atas kanvas
/// kosong, yang di HP lambat terlihat seperti aplikasi gagal terbuka.
class MasSplash extends StatelessWidget {
  const MasSplash({super.key});
  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Scaffold(
      backgroundColor: m.canvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: m.brand600,
                borderRadius: BorderRadius.circular(14),
                boxShadow: m.shadow2,
              ),
              child: Text('M',
                  style: masMono(size: 26, weight: FontWeight.w700, color: Colors.white)),
            ),
            const SizedBox(height: 18),
            Text('MASPART',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: m.ink500,
                )),
            const SizedBox(height: 22),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: m.brand600),
            ),
          ],
        ),
      ),
    );
  }
}
