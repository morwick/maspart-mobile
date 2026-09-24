// lib/widgets/promo_banner.dart
// BANNER PROMO ETALASE — carousel geser otomatis di atas etalase /toko.
// Kembaran `frontend/src/components/PromoBanner.tsx` (web). Slide = DATA
// (kPromoSlides di bawah): mengganti promo = mengedit satu list, bukan
// menyentuh logika carousel. ⚠️ Isi list WAJIB disamakan dengan `SLIDES` web.
//
// Slide `plain` = materi desain jadi (teks/logo sudah tercetak di gambar) →
// ditampilkan apa adanya, tanpa lapisan gelap & tanpa teks di atasnya.
// Gambar web ditaruh di `frontend/public/promo/`; aplikasi MEMBUNDEL salinan
// yang sama di `assets/promo/` (terdaftar di pubspec.yaml) → banner tampil
// tanpa bergantung web ter-deploy. ⚠️ Ganti gambar = salin ulang ke dua tempat.

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app/nav.dart';
import '../theme/mas_theme.dart';

class PromoSlide {
  final String id;

  /// Baris kecil di atas judul (opsional).
  final String? eyebrow;

  /// Wajib — juga dipakai sebagai label aksesibilitas slide `plain`.
  final String title;

  /// Penegas besar di kanan (opsional), disembunyikan di layar < 640 px.
  final String? highlight;
  final String? subtitle;
  final String? cta;

  /// Layar tujuan saat slide diketuk (padanan `href` web). null = tak bisa
  /// diketuk. Tujuan = layar yang sedang dibuka → diabaikan (seperti tautan
  /// web ke halaman yang sama).
  final MasScreen? tujuan;

  /// Dua warna gradien latar (dipakai juga sebagai warna dasar bila gambar
  /// gagal dimuat).
  final (Color, Color) tone;

  /// Gambar latar (opsional): "assets/…" = aset bundel aplikasi, selain itu
  /// URL http(s) (dimuat dari jaringan).
  final String? image;
  final bool plain;

  /// Teks syarat/periode kecil di pojok kanan bawah (opsional).
  final String? footnote;

  const PromoSlide({
    required this.id,
    required this.title,
    required this.tone,
    this.eyebrow,
    this.highlight,
    this.subtitle,
    this.cta,
    this.tujuan,
    this.image,
    this.plain = false,
    this.footnote,
  });
}

/// ── ISI BANNER — samakan dengan `SLIDES` di PromoBanner.tsx (web). ──
/// Semua teks harus menggambarkan fitur yang MEMANG ada — jangan menaruh klaim
/// promo yang tak berlaku.
const List<PromoSlide> kPromoSlides = [
  PromoSlide(
    id: 'sinotruk-howo',
    title:
        'Sparepart truck Sinotruk HOWO berkualitas & terpercaya — OEM, ready stock',
    tujuan: MasScreen.toko,
    tone: (Color(0xFF0B1A2E), Color(0xFF123A63)),
    image: 'assets/promo/sparepart-truck.webp',
    plain: true,
  ),
  PromoSlide(
    id: 'harga-murah',
    title:
        'Belanja sparepart truck Sinotruk HOWO, harga lebih murah dan mudah dicari di MasPart',
    tujuan: MasScreen.toko,
    tone: (Color(0xFFD7D7D8), Color(0xFFF2F4F6)),
    image: 'assets/promo/harga-lebih-murah.webp',
    plain: true,
  ),
];

const _autoplay = Duration(seconds: 5);
const _geserDurasi = Duration(milliseconds: 450);

/// Warna tombol panah — tetap gelap di atas lingkaran putih di tema apa pun.
const _panahInk = Color(0xFF1B211D);

/// Gambar slide — aset bundel ("assets/…") atau URL jaringan. Gagal muat →
/// kosong, sehingga warna dasar tone di belakangnya yang tampil.
Widget _gambar(
  String u, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) {
  if (u.startsWith('assets/')) {
    return Image.asset(
      u,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
  return CachedNetworkImage(
    imageUrl: u,
    fit: fit,
    width: width,
    height: height,
    fadeInDuration: const Duration(milliseconds: 200),
    placeholder: (_, _) => const SizedBox.shrink(),
    errorWidget: (_, _, _) => const SizedBox.shrink(),
  );
}

class PromoBanner extends StatefulWidget {
  final List<PromoSlide> slides;

  const PromoBanner({super.key, this.slides = kPromoSlides});

  @override
  State<PromoBanner> createState() => _PromoBannerState();
}

class _PromoBannerState extends State<PromoBanner> {
  final _ctl = PageController();
  Timer? _timer;
  int _i = 0;

  int get _n => widget.slides.length;

  @override
  void initState() {
    super.initState();
    _mulai();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  /// Autoplay — dijeda selama jari menyentuh banner (padanan hover di web) dan
  /// dilewati saat aplikasi tak di layar depan (padanan `document.hidden`).
  void _mulai() {
    _timer?.cancel();
    if (_n < 2) return;
    _timer = Timer.periodic(_autoplay, (_) {
      if (!mounted) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      _ke(_i + 1);
    });
  }

  void _jeda() => _timer?.cancel();

  void _ke(int idx) {
    if (_n == 0 || !_ctl.hasClients) return;
    final t = ((idx % _n) + _n) % _n;
    // Reduced motion (setelan aksesibilitas) TIDAK menghentikan pergantian —
    // hanya animasinya yang dimatikan, persis web.
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctl.jumpToPage(t);
    } else {
      _ctl.animateToPage(t,
          duration: _geserDurasi, curve: const Cubic(.4, 0, .2, 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_n == 0) return const SizedBox.shrink();
    final m = context.mas;
    final layar = MediaQuery.sizeOf(context).width;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        // Rasio materi 4:1, lantai 168 px (sama dengan web).
        final h = math.max(w / 4, 168.0);
        return Container(
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: m.shadow2,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Listener(
              onPointerDown: (_) => _jeda(),
              onPointerUp: (_) => _mulai(),
              onPointerCancel: (_) => _mulai(),
              child: Stack(children: [
                Positioned.fill(
                  child: PageView.builder(
                    controller: _ctl,
                    itemCount: _n,
                    onPageChanged: (v) => setState(() => _i = v),
                    itemBuilder: (context, idx) => _Slide(
                      s: widget.slides[idx],
                      w: w,
                      h: h,
                      layar: layar,
                    ),
                  ),
                ),
                if (_n > 1) ...[
                  Positioned(
                    left: 10,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _NavBtn(
                        icon: Icons.chevron_left_rounded,
                        label: 'Banner sebelumnya',
                        onTap: () => _ke(_i - 1),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _NavBtn(
                        icon: Icons.chevron_right_rounded,
                        label: 'Banner berikutnya',
                        onTap: () => _ke(_i + 1),
                      ),
                    ),
                  ),
                  // Titik indikator — yang aktif memanjang.
                  Positioned(
                    left: 15,
                    bottom: 10,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (int idx = 0; idx < _n; idx++)
                        Semantics(
                          button: true,
                          selected: idx == _i,
                          label:
                              'Ke banner ${idx + 1}: ${widget.slides[idx].title}',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _ke(idx),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 3, vertical: 4),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                width: idx == _i ? 22 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: idx == _i
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ],
              ]),
            ),
          ),
        );
      }),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.92),
            border: Border.all(color: const Color(0x140F1411)),
            boxShadow: m.shadow2,
          ),
          child: Icon(icon, size: 20, color: _panahInk),
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  final PromoSlide s;
  final double w, h;

  /// Lebar layar (padanan media query web: 640 / 900 px).
  final double layar;

  const _Slide({
    required this.s,
    required this.w,
    required this.h,
    required this.layar,
  });

  @override
  Widget build(BuildContext context) {
    final nav = AppNav.of(context);
    final img = s.image;
    final (c0, c1) = s.tone;

    Widget badan;
    if (img != null && s.plain) {
      // Materi jadi: tone = warna dasar (tak berkedip putih selagi dimuat /
      // bila gagal). Di layar < 900 px materi 4:1 dibuat `contain` supaya
      // judul yang tercetak di paruh kiri tak terpotong (lihat globals.css).
      badan = Container(
        color: c0,
        child: _gambar(
          img,
          fit: layar < 900 ? BoxFit.contain : BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    } else {
      badan = Stack(fit: StackFit.expand, children: [
        if (img != null) ...[
          Container(color: c0),
          _gambar(img),
          // Lapisan gelap agar teks terbaca di atas foto.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Color(0xB8000000), // rgba(0,0,0,.72)
                Color(0x47000000), // rgba(0,0,0,.28)
              ]),
            ),
          ),
        ] else ...[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c0, c1],
              ),
            ),
          ),
          // Bentuk dekoratif — senada lingkaran di hero etalase.
          Positioned(
            right: -0.06 * w,
            top: -0.40 * h,
            child: _bulat(280, 0.09),
          ),
          Positioned(
            right: 0.14 * w,
            bottom: -0.55 * h,
            child: _bulat(200, 0.07),
          ),
        ],
        _isi(),
        if (s.footnote != null)
          Positioned(
            right: 16,
            bottom: 12,
            child: Text(s.footnote!,
                style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white.withValues(alpha: 0.75))),
          ),
      ]);
    }

    final dapatDiketuk = s.tujuan != null && s.tujuan != nav.screen;
    return Semantics(
      label: s.plain ? s.title : null,
      image: s.plain && s.tujuan == null,
      link: s.tujuan != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: dapatDiketuk ? () => nav.go(s.tujuan!) : null,
        child: badan,
      ),
    );
  }

  Widget _bulat(double d, double a) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: a),
        ),
      );

  Widget _isi() {
    final padH = (layar * 0.04).clamp(18.0, 44.0);
    final judul = (layar * 0.03).clamp(19.0, 30.0);
    final sub = (layar * 0.0135).clamp(12.0, 14.0);
    final pegas = (layar * 0.05).clamp(28.0, 60.0);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padH),
      child: Row(children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (s.eyebrow != null)
                Text(s.eyebrow!.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 12 * .08,
                      color: Colors.white.withValues(alpha: 0.85),
                    )),
              const SizedBox(height: 6),
              Text(s.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: judul,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -.02 * judul,
                    color: Colors.white,
                  )),
              if (s.subtitle != null) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Text(s.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: sub,
                        color: Colors.white.withValues(alpha: 0.9),
                      )),
                ),
              ],
              if (s.cta != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(s.cta!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F1411),
                      )),
                ),
              ],
            ],
          ),
        ),
        if (s.highlight != null && layar > 640) ...[
          const SizedBox(width: 18),
          Text(s.highlight!,
              style: TextStyle(
                fontSize: pegas,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: -.04 * pegas,
                color: Colors.white.withValues(alpha: 0.22),
              )),
        ],
      ]),
    );
  }
}
