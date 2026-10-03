// lib/widgets/flash_sale.dart
// STRIP FLASH SALE — panel promo bertenggat di etalase /toko.
// Kembaran `frontend/src/components/FlashSale.tsx` (web): judul + hitung
// mundur, kartu produk mendatar dengan badge persen, harga coret, harga promo,
// dan bar sisa stok.
//
// Isi strip = GET /api/buyer/flash-sale (kampanye diatur admin di web
// /admin/flash-sale). `harga` tiap kartu SUDAH harga promo dari server —
// dihitung di `harga.price_for_buyer()`, titik yang sama dengan keranjang &
// checkout — jadi yang dipajang = yang ditagih. Aplikasi tak menghitung diskon.

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api_service.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';

/// Stok di bawah/sama dengan angka ini diberi label "Terbatas".
const _ambangTerbatas = 3;

const _merahBadge = Color(0xFFC81E1E);
const _amberTerbatas = Color(0xFFD97706);
const _panahInk = Color(0xFF1B211D);

String _dua(int n) => n.toString().padLeft(2, '0');

class FlashSale extends StatefulWidget {
  /// Kampanye berjalan — ditarik terpisah oleh layar, supaya strip TIDAK ikut
  /// berubah saat pembeli mengetik di cari. null = belum dimuat / gagal.
  final FlashSaleData? data;
  final ValueChanged<TokoProduct> onOpen;

  /// Hitung mundur mencapai nol → layar boleh menarik ulang (strip hilang).
  final VoidCallback? onHabis;

  const FlashSale({
    super.key,
    required this.data,
    required this.onOpen,
    this.onHabis,
  });

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
    _mulaiTimer();
  }

  @override
  void didUpdateWidget(covariant FlashSale old) {
    super.didUpdateWidget(old);
    if (old.data?.berakhir != widget.data?.berakhir ||
        old.data?.aktif != widget.data?.aktif) {
      _mulaiTimer();
    }
  }

  void _mulaiTimer() {
    _timer?.cancel();
    _timer = null;
    _sisa = null;
    final d = widget.data;
    _target = (d != null && d.aktif) ? DateTime.tryParse(d.berakhir) : null;
    if (_target == null) return;
    _hitung();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_hitung);
    });
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
    if (_sisa == Duration.zero) {
      _timer?.cancel();
      // Setelah frame ini: induk menarik ulang → server bilang aktif=false.
      final cb = widget.onHabis;
      if (cb != null) WidgetsBinding.instance.addPostFrameCallback((_) => cb());
    }
  }

  String _teksMundur(Duration s) {
    final d = s.inDays;
    final j = s.inHours % 24;
    final m = s.inMinutes % 60;
    final dt = s.inSeconds % 60;
    final hms = '${_dua(j)}:${_dua(m)}:${_dua(dt)}';
    return d > 0 ? '$d hari $hms' : hms;
  }

  List<TokoProduct> _peserta() {
    final d = widget.data;
    if (d == null || !d.aktif) return const [];
    return [for (final p in d.items) if (p.promo) p];
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
                    Text(
                        (widget.data?.judul ?? '').isNotEmpty
                            ? widget.data!.judul
                            : 'Flash Sale',
                        style: const TextStyle(
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
                      p: peserta[k],
                      onOpen: () => widget.onOpen(peserta[k]),
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
  final VoidCallback onOpen;

  const _KartuPromo({required this.p, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final habis = p.stok <= 0;
    final terbatas = !habis && p.stok <= _ambangTerbatas;
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
                    child: Text('${p.promoPersen}%',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        )),
                  ),
                ),
                if (habis)
                  Container(
                    color: Colors.white.withValues(alpha: 0.6),
                    alignment: Alignment.center,
                    child: Text('Stok habis',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: m.ink700,
                        )),
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
                  Text(formatRupiah(p.hargaNormal),
                      style: TextStyle(
                        fontSize: 11,
                        color: m.ink400,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: m.ink400,
                      )),
                  const SizedBox(height: 3),
                  Text(formatRupiah(p.harga),
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
                    habis
                        ? 'Stok habis'
                        : terbatas
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
