// lib/theme/mas_theme.dart
// Sistem token MasPart — port 1:1 dari CSS variables desain "MasPart Mobile.dc".
// Mendukung light + dark. Diakses lewat `context.mas`.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ThemeExtension berisi seluruh palet desain (light & dark).
@immutable
class MasColors extends ThemeExtension<MasColors> {
  final bool isDark;

  // Brand
  final Color brand600, brand700, brand500, brand50, brand100;
  // Ink scale (900 = paling gelap di light, paling terang di dark)
  final Color ink900, ink800, ink700, ink600, ink500, ink400, ink300, ink200, ink150, ink100, ink50;
  // Permukaan
  final Color paper, canvas;
  // Status
  final Color warn600, warn50, danger600, danger50, info600, info50;
  // Border kontekstual pill status (nilai literal dari desain)
  final Color warnBorder, infoBorder, dangerBorder;

  const MasColors({
    required this.isDark,
    required this.brand600,
    required this.brand700,
    required this.brand500,
    required this.brand50,
    required this.brand100,
    required this.ink900,
    required this.ink800,
    required this.ink700,
    required this.ink600,
    required this.ink500,
    required this.ink400,
    required this.ink300,
    required this.ink200,
    required this.ink150,
    required this.ink100,
    required this.ink50,
    required this.paper,
    required this.canvas,
    required this.warn600,
    required this.warn50,
    required this.danger600,
    required this.danger50,
    required this.info600,
    required this.info50,
    required this.warnBorder,
    required this.infoBorder,
    required this.dangerBorder,
  });

  static const MasColors light = MasColors(
    isDark: false,
    brand600: Color(0xFF028912),
    brand700: Color(0xFF026A0E),
    brand500: Color(0xFF1EA83A),
    brand50: Color(0xFFEAF6EC),
    brand100: Color(0xFFD3EDD7),
    ink900: Color(0xFF0F1411),
    ink800: Color(0xFF1B211D),
    ink700: Color(0xFF353C37),
    ink600: Color(0xFF535B56),
    ink500: Color(0xFF767E79),
    ink400: Color(0xFF9EA5A0),
    ink300: Color(0xFFC5CAC6),
    ink200: Color(0xFFE1E4E1),
    ink150: Color(0xFFECEFEC),
    ink100: Color(0xFFF3F5F3),
    ink50: Color(0xFFF8F9F7),
    paper: Color(0xFFFFFFFF),
    canvas: Color(0xFFFAF9F5),
    warn600: Color(0xFFB35C00),
    warn50: Color(0xFFFFF3E2),
    danger600: Color(0xFFC0392B),
    danger50: Color(0xFFFDECEA),
    info600: Color(0xFF1A73A8),
    info50: Color(0xFFE6F2F8),
    warnBorder: Color(0xFFF6D9A8),
    infoBorder: Color(0xFFC4DCEB),
    dangerBorder: Color(0xFFF4C4BE),
  );

  static const MasColors dark = MasColors(
    isDark: true,
    brand600: Color(0xFF028912),
    brand700: Color(0xFF4ECB6B),
    brand500: Color(0xFF1EA83A),
    brand50: Color(0xFF14301C),
    brand100: Color(0xFF1E4527),
    ink900: Color(0xFFF1F4F1),
    ink800: Color(0xFFDFE4E0),
    ink700: Color(0xFFC2C9C4),
    ink600: Color(0xFFA2AAA4),
    ink500: Color(0xFF8B938D),
    ink400: Color(0xFF6D756F),
    ink300: Color(0xFF4A524C),
    ink200: Color(0xFF303832),
    ink150: Color(0xFF262D28),
    ink100: Color(0xFF1D241F),
    ink50: Color(0xFF1B211C),
    paper: Color(0xFF161C18),
    canvas: Color(0xFF0E130F),
    warn600: Color(0xFFE5A355),
    warn50: Color(0xFF33250E),
    danger600: Color(0xFFE88377),
    danger50: Color(0xFF331714),
    info600: Color(0xFF6CB8E6),
    info50: Color(0xFF122733),
    warnBorder: Color(0xFF5A4212),
    infoBorder: Color(0xFF1E3A4A),
    dangerBorder: Color(0xFF5A2820),
  );

  /// Gradien hijau premium (header login, avatar asisten).
  LinearGradient get brandGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1EA83A), Color(0xFF028912), Color(0xFF026A0E)],
        stops: [0.0, 0.45, 1.0],
      );

  List<BoxShadow> get shadow1 => isDark
      ? const [
          BoxShadow(color: Color(0x4D000000), blurRadius: 0, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x4D000000), blurRadius: 2, offset: Offset(0, 1)),
        ]
      : const [
          BoxShadow(color: Color(0x0A0F1411), blurRadius: 0, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0A0F1411), blurRadius: 2, offset: Offset(0, 1)),
        ];

  List<BoxShadow> get shadow2 => isDark
      ? const [
          BoxShadow(color: Color(0x4D000000), blurRadius: 0, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 4)),
        ]
      : const [
          BoxShadow(color: Color(0x0A0F1411), blurRadius: 0, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0F0F1411), blurRadius: 14, offset: Offset(0, 4)),
        ];

  List<BoxShadow> get shadow3 => isDark
      ? const [
          BoxShadow(color: Color(0x99000000), blurRadius: 30, spreadRadius: -8, offset: Offset(0, 12)),
          BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 4)),
        ]
      : const [
          BoxShadow(color: Color(0x2E0F1411), blurRadius: 30, spreadRadius: -8, offset: Offset(0, 12)),
          BoxShadow(color: Color(0x0F0F1411), blurRadius: 10, offset: Offset(0, 4)),
        ];

  @override
  MasColors copyWith({bool? isDark}) => this;

  @override
  MasColors lerp(ThemeExtension<MasColors>? other, double t) {
    if (other is! MasColors) return this;
    return t < 0.5 ? this : other;
  }
}

/// Radius standar (px) sesuai desain.
class MasRadii {
  static const double input = 6;
  static const double card = 10;
  static const double sheet = 20;
  static const double pill = 999;
  static const double chip = 7;
}

/// Akses cepat token dari BuildContext.
extension MasContext on BuildContext {
  MasColors get mas => Theme.of(this).extension<MasColors>()!;
}

/// Font monospace (part number, nilai numerik) — JetBrains Mono.
TextStyle masMono({
  double size = 13,
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? height,
  double letterSpacing = 0,
}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

/// Membangun ThemeData lengkap untuk mode tertentu.
ThemeData buildMasTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final mas = isDark ? MasColors.dark : MasColors.light;

  final base = ColorScheme.fromSeed(
    seedColor: mas.brand600,
    brightness: brightness,
  ).copyWith(
    primary: mas.brand600,
    surface: mas.canvas,
    onSurface: mas.ink900,
    surfaceContainerHighest: mas.ink100,
    outlineVariant: mas.ink150,
    error: mas.danger600,
  );

  final textTheme = GoogleFonts.geistTextTheme(
    (isDark ? Typography.whiteMountainView : Typography.blackMountainView).apply(
      bodyColor: mas.ink900,
      displayColor: mas.ink900,
    ),
  ).apply(bodyColor: mas.ink900, displayColor: mas.ink900);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: base,
    scaffoldBackgroundColor: mas.canvas,
    textTheme: textTheme,
    splashFactory: InkRipple.splashFactory,
    // -0.005em letter-spacing global seperti desain (font-family .mp)
    fontFamily: GoogleFonts.geist().fontFamily,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: mas.ink800,
      contentTextStyle: TextStyle(color: mas.ink50, fontWeight: FontWeight.w600),
    ),
    extensions: [mas],
  );
}

/// Controller tema global — toggle light/dark dari header.
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  void toggle() {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  void set(ThemeMode m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }
}

/// Inherited access ke ThemeController.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({super.key, required ThemeController controller, required super.child})
      : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope tidak ditemukan di atas widget ini');
    return scope!.notifier!;
  }
}
