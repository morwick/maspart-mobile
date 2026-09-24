// lib/widgets/flash_sale.dart
// STRIP FLASH SALE — panel promo bertenggat di etalase /toko.
// Kembaran `frontend/src/components/FlashSale.tsx` (web): judul + hitung
// mundur, kartu produk mendatar dengan badge persen, harga coret, harga promo,
// dan bar sisa stok.
//
// ⚠️ STATUS: TAMPILAN SAJA. Harga promo BELUM berlaku saat checkout —
// penagihan dihitung ulang di server (`harga.price_for_buyer()`) dari harga
// Accurate apa adanya. Karena itu strip DIKUNCI MATI di build rilis selama
// `FlashSaleKampanye.aktif == false`; di build debug/profile ia tampil sebagai
// PRATINJAU berpita peringatan (padanan NODE_ENV !== 'production' di web).
// ⚠️ Konfigurasi di bawah WAJIB disamakan dengan `KAMPANYE` di FlashSale.tsx.

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import '../api_service.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';

/// ── KONFIGURASI KAMPANYE — samakan dengan `KAMPANYE` di FlashSale.tsx. ──
class FlashSaleKampanye {
  FlashSaleKampanye._();

  /// ⛔ Biarkan false sampai diskon benar-benar berlaku di price_for_buyer().
  static const bool aktif = false;
  static const String judul = 'Flash Sale Part Pilihan';

  /// Waktu berakhir, ISO-8601 dengan zona. Lewat tenggat → strip hilang.
  static const String berakhir = '2026-12-31T23:59:59+07:00';

  /// Peserta promo: part_number → persen diskon. Hanya yang terdaftar ikut.
  static const Map<String, int> diskon = {};

  /// Persen yang dipakai HANYA di pratinjau, saat `diskon` kosong.
  static const int diskonPratinjau = 20;

  /// Stok di bawah/sama dengan angka ini diberi label "Terbatas".
  static const int ambangTerbatas = 3;

  /// Batas kartu yang dipajang.
  static const int maksKartu = 24;

  /// Pratinjau = kampanye belum aktif & bukan build rilis.
  static bool get pratinjau => !aktif && !kReleaseMode;

  /// Strip boleh tampil sama sekali? (dipakai layar untuk tak menarik data
  /// percuma bila strip toh disembunyikan).
  static bool get tampil => aktif || pratinjau;
}

const _merahBadge = Color(0xFFC81E1E);
const _amberTerbatas = Color(0xFFD97706);
const _panahInk = Color(0xFF1B211D);

String _dua(int n) => n.toString().padLeft(2, '0');

class FlashSale extends StatefulWidget {
  /// Kolam produk (ready, berharga, berfoto) — ditarik terpisah oleh layar,
  /// sekali, supaya strip TIDAK ikut berubah saat pembeli mengetik di cari.
  final List<TokoProduct> items;
  final ValueChanged<TokoProduct> onOpen;

  const FlashSale({super.key, required this.items, required this.onOpen});

  @override
  State<FlashSale> createState() => _FlashSaleState();
}

class _FlashSaleState extends State<FlashSale> {
  final _rel = ScrollController();
  Timer? _timer;
  DateTime? _target;
  Duration? _sisa;

  @override
  void initState() {
    super.initState();
    _target = DateTime.tryParse(FlashSaleKampanye.berakhir);
    if (FlashSaleKampanye.tampil && _target != null) {
      _hitung();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(_hitung);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rel.dispose();
    super.dispose();
  }

  void _hitung() {
    final t = _target;
    if (t == null) return;
    final d = t.difference(DateTime.now());
    _sisa = d.isNegative ? Duration.zero : d;
    if (_sisa == Duration.zero) _timer?.cancel();
  }

  String _teksMundur(Duration s) {
    final d = s.inDays;
    final j = s.inHours % 24;
    final m = s.inMinutes % 60;
    final dt = s.inSeconds % 60;
    final hms = '${_dua(j)}:${_dua(m)}:${_dua(dt)}';
    return d > 0 ? '$d hari $hms' : hms;
  }

  List<(TokoProduct, int)> _peserta() {
    // Foto wajib: kartu promo tanpa gambar melemahkan strip.
    final src = widget.items
        .where((p) => p.ready && p.harga > 0 && (p.foto ?? '').isNotEmpty);
    if (FlashSaleKampanye.aktif) {
      return [
        for (final p in src)
          if ((FlashSaleKampanye.diskon[p.partNumber] ?? 0) > 0)
            (p, FlashSaleKampanye.diskon[p.partNumber]!),
      ];
    }
    return [
      for (final p in src.take(FlashSaleKampanye.maksKartu))
        (p, FlashSaleKampanye.diskonPratinjau),
    ];
  }

  void _geser() {
    if (!_rel.hasClients) return;
    final pos = _rel.position;
    final langkah = math.max(240.0, pos.viewportDimension * 0.8);
    _rel.animateTo(
      (pos.pixels + langkah).clamp(0.0, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!FlashSaleKampanye.tampil) return const SizedBox.shrink();
    final peserta = _peserta();
    if (peserta.isEmpty) return const SizedBox.shrink();
    final sisa = _sisa;
    if (sisa != null && sisa == Duration.zero) return const SizedBox.shrink();

    final m = context.mas;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [m.brand700, m.brand500],
          ),
          boxShadow: m.shadow2,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Kepala: judul + hitung mundur + jumlah part
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(FlashSaleKampanye.judul,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.17,
                          color: Colors.white,
                        )),
                    if (sisa != null)
                      Tooltip(
                        message: 'Sisa waktu promo',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.schedule_rounded,
                                size: 13, color: m.brand700),
                            const SizedBox(width: 5),
                            Text(_teksMundur(sisa),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: m.brand700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                )),
                          ]),
                        ),
                      ),
                    if (FlashSaleKampanye.pratinjau)
                      Tooltip(
                        message:
                            'Harga promo belum berlaku saat checkout — strip ini hanya tampil di build debug',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.45)),
                          ),
                          child: const Text(
                            'PRATINJAU · harga promo belum berlaku di checkout',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.44,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text('${peserta.length} part',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.95),
                  )),
            ]),
          ),

          // Carousel kartu
          Stack(children: [
            SingleChildScrollView(
              controller: _rel,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int k = 0; k < peserta.length; k++) ...[
                    if (k > 0) const SizedBox(width: 10),
                    _KartuPromo(
                      p: peserta[k].$1,
                      persen: peserta[k].$2,
                      onOpen: () => widget.onOpen(peserta[k].$1),
                    ),
                  ],
                ],
              ),
            ),
            if (peserta.length > 2)
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Semantics(
                    button: true,
                    label: 'Geser ke kanan',
                    child: GestureDetector(
                      onTap: _geser,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.94),
                          boxShadow: m.shadow2,
                        ),
                        child: const Icon(Icons.chevron_right_rounded,
                            size: 20, color: _panahInk),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _KartuPromo extends StatelessWidget {
  final TokoProduct p;
  final int persen;
  final VoidCallback onOpen;

  const _KartuPromo({
    required this.p,
    required this.persen,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final promo = (p.harga * (100 - persen) / 100).round();
    final terbatas = p.stok <= FlashSaleKampanye.ambangTerbatas;
    // Bar = ilustrasi sisa stok relatif ambang "banyak" (10 pcs); MASPART tak
    // punya kuota promo, jadi ini BUKAN "sudah terjual sekian".
    final isiBar = ((p.stok / 10) * 100).clamp(8.0, 100.0) / 100;
    final foto = p.foto;

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        width: 178,
        decoration: BoxDecoration(
          color: m.paper,
          borderRadius: BorderRadius.circular(12),
          boxShadow: m.shadow1,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 178,
              height: 178,
              child: Stack(fit: StackFit.expand, children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: foto != null && foto.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: ApiService.partImageUrl(foto),
                          fit: BoxFit.contain,
                          placeholder: (_, _) => Container(color: m.ink50),
                          errorWidget: (_, _, _) => _tanpaFoto(m),
                        )
                      : _tanpaFoto(m),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: const BoxDecoration(
                      color: _merahBadge,
                      borderRadius:
                          BorderRadius.only(bottomRight: Radius.circular(8)),
                    ),
                    child: Text('$persen%',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        )),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 30,
                    child: Text(p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: m.ink800,
                        )),
                  ),
                  const SizedBox(height: 3),
                  Text(formatRupiah(p.harga),
                      style: TextStyle(
                        fontSize: 11,
                        color: m.ink400,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: m.ink400,
                      )),
                  const SizedBox(height: 3),
                  Text(formatRupiah(promo),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: m.brand700,
                      )),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 6,
                      color: m.ink150,
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: isiBar,
                        heightFactor: 1,
                        child: Container(
                          // Stok menipis tetap berwarna hangat — itu
                          // peringatan, bukan hiasan.
                          color: terbatas ? _amberTerbatas : m.brand500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    terbatas
                        ? 'Terbatas · sisa ${thousands(p.stok)}'
                        : 'Tersedia · ${thousands(p.stok)}',
                    style: TextStyle(fontSize: 10.5, color: m.ink500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tanpaFoto(MasColors m) => Center(
        child: Text('Belum ada foto',
            style: TextStyle(fontSize: 11, color: m.ink400)),
      );
}
