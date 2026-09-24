// lib/screens/poin_screen.dart
// "Poin Saya" — saldo, poin tertunda, dan riwayat buku besar poin.
// Paritas dengan web `frontend/src/app/poin/page.tsx` (+ poin.css).
//
// Poin TERTUNDA sengaja sejajar dengan saldo: poin baru cair saat pesanan
// diterima, jadi tanpa baris ini pembeli yang baru membayar mengira belanjanya
// tak menghasilkan poin sama sekali lalu mengadu ke gudang.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../models.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/mas_ui.dart';

/// Label yang dibaca pembeli untuk tiap jenis baris. Istilah teknis buku besar
/// (earn/redeem/reversal) tak pernah ditampilkan apa adanya.
const _kJenis = <String, String>{
  'earn': 'Dari belanja',
  'redeem': 'Dipakai belanja',
  'reversal': 'Dikembalikan (pesanan batal)',
  'expire': 'Hangus (lewat masa berlaku)',
  'manual': 'Penyesuaian admin',
};

/// Batas riwayat yang diminta — sama dengan web. Bila tercapai, ringkasan
/// hanya parsial dan keterangannya ikut bilang begitu.
const _kRiwayatLimit = 100;

enum _Nada { masuk, keluar, redup }

String _angka(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return n < 0 ? '-$b' : b.toString();
}

class PoinScreen extends StatefulWidget {
  const PoinScreen({super.key});

  @override
  State<PoinScreen> createState() => _PoinScreenState();
}

class _PoinScreenState extends State<PoinScreen> {
  PoinSaldo _poin = const PoinSaldo();
  List<PoinBaris> _riwayat = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saldo = await ApiService.poin();
      final riwayat = await ApiService.poinRiwayat();
      if (!mounted) return;
      setState(() {
        _poin = saldo;
        _riwayat = riwayat;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      // Putus jaringan dll. — tanpa ini layar berputar selamanya.
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat poin.';
        _loading = false;
      });
    }
  }

  String _tanggal(String iso) {
    if (iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso.length >= 10 ? iso.substring(0, 10) : iso;
    const bulan = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    final l = d.toLocal();
    return '${l.day} ${bulan[l.month - 1]} ${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_error != null)
            // Gagal memuat ≠ program belum aktif — jangan menyamarkan server
            // mati sebagai "belum ada poin".
            MasCard(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              child: Column(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: m.danger50),
                  child: Icon(Icons.error_outline, size: 24, color: m.danger600),
                ),
                const SizedBox(height: 10),
                Text('Poin tidak bisa dimuat',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: m.ink800)),
                const SizedBox(height: 4),
                Text('$_error Periksa koneksi Anda lalu coba lagi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5, color: m.ink500, height: 1.5)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Coba lagi'),
                ),
              ]),
            )
          else if (!_poin.aktif)
            // Migrasi 034 belum jalan — jangan menampilkan saldo 0 seolah pembeli
            // tak punya poin; katakan apa adanya bahwa programnya belum ada.
            MasCard(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: _kosong(m, Icons.toll_outlined, 'Program poin belum aktif',
                  'Program poin belum tersedia di toko ini. Nantikan kabarnya.'),
            )
          else ...[
            _hero(m),
            if (!_poin.bolehTukar) ...[
              const SizedBox(height: 12),
              _catatan(m),
            ],
            const SizedBox(height: 12),
            _ringkasan(m),
            const SizedBox(height: 12),
            _kartuRiwayat(m),
            // Tanpa aturan dari server jangan mengarang angka "cara kerja".
            if (_poin.adaAturan) ...[
              const SizedBox(height: 12),
              _kartuCaraKerja(m),
            ],
          ],
        ],
      ),
    );
  }

  // ── Kartu saldo hijau merek (sama di kedua tema) ──
  Widget _hero(MasColors m) {
    final nav = AppNav.of(context);
    const putih = Colors.white;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF03A318), Color(0xFF028912), Color(0xFF015A0B)],
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x55028912), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          // Lingkaran dekoratif, padanan radial-gradient di web.
          Positioned(
            right: -60,
            top: -90,
            child: _lingkaran(200, 0.14),
          ),
          Positioned(
            right: 40,
            bottom: -110,
            child: _lingkaran(180, 0.08),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.toll_outlined, size: 16, color: putih),
                  const SizedBox(width: 6),
                  Text('Poin MasPart',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: putih.withValues(alpha: 0.9))),
                ]),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(_angka(_poin.saldo),
                        style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            letterSpacing: -1.2,
                            color: putih)),
                    const SizedBox(width: 8),
                    Text('poin',
                        style: TextStyle(
                            fontSize: 15, color: putih.withValues(alpha: 0.8))),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: putih.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(MasRadii.pill),
                  ),
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Setara potongan '),
                      TextSpan(
                          text: formatRupiah(_poin.rupiah),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    style: const TextStyle(fontSize: 13, color: putih),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Material(
                      color: putih,
                      borderRadius: BorderRadius.circular(MasRadii.pill),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(MasRadii.pill),
                        onTap: () => nav.go(MasScreen.toko),
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.shopping_cart_outlined,
                                size: 16, color: Color(0xFF026A0E)),
                            SizedBox(width: 7),
                            Text('Belanja sekarang',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF026A0E))),
                          ]),
                        ),
                      ),
                    ),
                    if (!_poin.bolehTukar)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.info_outline,
                            size: 14, color: putih.withValues(alpha: 0.85)),
                        const SizedBox(width: 5),
                        Text('Penukaran segera dibuka',
                            style: TextStyle(
                                fontSize: 12,
                                color: putih.withValues(alpha: 0.85))),
                      ]),
                  ],
                ),
                if (_poin.tertunda > 0) ...[
                  const SizedBox(height: 16),
                  _tunda(nav),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lingkaran(double d, double alpha) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      );

  Widget _tunda(AppNav nav) {
    const putih = Colors.white;
    return Material(
      color: putih.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(MasRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(MasRadii.card),
        onTap: () => nav.go(MasScreen.pesanan),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MasRadii.card),
            border: Border.all(color: putih.withValues(alpha: 0.22)),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: putih.withValues(alpha: 0.2),
              ),
              child: const Icon(Icons.schedule, size: 18, color: putih),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('+${_angka(_poin.tertunda)} poin menunggu',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: putih)),
                  const SizedBox(height: 2),
                  Text(
                      'Cair setelah pesanan Anda ditandai diterima. '
                      'Lihat pesanan ›',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: putih.withValues(alpha: 0.88))),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _catatan(MasColors m) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: m.warn50,
          borderRadius: BorderRadius.circular(MasRadii.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.info_outline, size: 16, color: m.warn600),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Penukaran poin belum dibuka. Poin Anda tetap terkumpul dan '
                'tidak hangus selama masa berlakunya.',
                style: TextStyle(fontSize: 12.5, height: 1.5, color: m.warn600),
              ),
            ),
          ],
        ),
      );

  // ── Ringkasan: diperoleh / dipakai / menunggu ──
  Widget _ringkasan(MasColors m) {
    var dapat = 0, pakai = 0;
    for (final b in _riwayat) {
      if (b.reason == 'earn') {
        dapat += b.delta;
      } else if (b.reason == 'redeem') {
        pakai += -b.delta;
      }
    }
    final hijau = m.isDark ? m.brand700 : m.brand600;
    Widget tile(IconData ic, Color fg, Color bg, String label, int n) =>
        Expanded(
          child: MasCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: bg, borderRadius: BorderRadius.circular(8)),
                  child: Icon(ic, size: 16, color: fg),
                ),
                const SizedBox(height: 8),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: m.ink500)),
                Text(_angka(n),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: m.ink900)),
              ],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          tile(Icons.arrow_upward, hijau, m.brand50, 'Poin diperoleh', dapat),
          const SizedBox(width: 8),
          tile(Icons.arrow_downward, m.ink700, m.ink100, 'Poin dipakai', pakai),
          const SizedBox(width: 8),
          tile(Icons.schedule, m.warn600, m.warn50, 'Menunggu cair',
              _poin.tertunda),
        ]),
        if (_riwayat.length >= _kRiwayatLimit)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
                'Ringkasan dihitung dari $_kRiwayatLimit transaksi terakhir.',
                style: TextStyle(fontSize: 11.5, color: m.ink500)),
          ),
      ],
    );
  }

  Widget _judul(MasColors m, String t, {int? hitung}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text(t,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: m.ink900)),
          if (hitung != null && hitung > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: m.ink100,
                borderRadius: BorderRadius.circular(MasRadii.pill),
              ),
              child: Text('$hitung',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: m.ink600)),
            ),
          ],
        ]),
      );

  Widget _kosong(MasColors m, IconData ic, String judul, String ket) => Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(shape: BoxShape.circle, color: m.brand50),
            child: Icon(ic,
                size: 24, color: m.isDark ? m.brand700 : m.brand600),
          ),
          const SizedBox(height: 10),
          Text(judul,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: m.ink800)),
          const SizedBox(height: 4),
          Text(ket,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5)),
        ],
      );

  // ── Riwayat ──
  Widget _kartuRiwayat(MasColors m) => MasCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _judul(m, 'Riwayat poin', hitung: _riwayat.length),
            if (_riwayat.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 20),
                child: Center(
                  child: _kosong(m, Icons.inventory_2_outlined,
                      'Belum ada riwayat',
                      'Poin pertama Anda muncul setelah pesanan diterima.'),
                ),
              )
            else
              for (var i = 0; i < _riwayat.length; i++) ...[
                if (i > 0) Divider(height: 1, color: m.ink150),
                _baris(m, _riwayat[i]),
              ],
          ],
        ),
      );

  Widget _baris(MasColors m, PoinBaris b) {
    final (IconData ic, _Nada nada) = switch (b.reason) {
      'earn' => (Icons.arrow_upward, _Nada.masuk),
      'reversal' => (Icons.replay, _Nada.masuk),
      'redeem' => (Icons.arrow_downward, _Nada.keluar),
      'expire' => (Icons.highlight_off, _Nada.redup),
      _ => (Icons.edit_outlined, b.delta >= 0 ? _Nada.masuk : _Nada.keluar),
    };
    final hijau = m.isDark ? m.brand700 : m.brand600;
    final (Color fg, Color bg, Color angka) = switch (nada) {
      _Nada.masuk => (hijau, m.brand50, hijau),
      _Nada.keluar => (m.ink700, m.ink100, m.ink800),
      _Nada.redup => (m.ink400, m.ink100, m.ink400),
    };
    final tgl = _tanggal(b.createdAt);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
            child: Icon(ic, size: 17, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_kJenis[b.reason] ?? b.reason,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: m.ink900)),
                const SizedBox(height: 2),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(tgl,
                        style: TextStyle(fontSize: 11.5, color: m.ink500)),
                    if (b.orderCode.isNotEmpty) ...[
                      if (tgl.isNotEmpty)
                        Text('  ·  ',
                            style: TextStyle(fontSize: 11.5, color: m.ink500)),
                      // Kode pesanan = tautan ke detail pesanan (paritas web).
                      GestureDetector(
                        onTap: () => AppNav.of(context).go(
                            MasScreen.pesananDetail,
                            part: {'order_code': b.orderCode}),
                        child: Text(b.orderCode,
                            style: masMono(
                                size: 11.5,
                                weight: FontWeight.w600,
                                color: m.isDark ? m.brand700 : m.brand600)),
                      ),
                    ],
                  ],
                ),
                if (b.reason == 'earn' && b.expiresAt.isNotEmpty)
                  Text('Berlaku s/d ${_tanggal(b.expiresAt)}',
                      style: TextStyle(fontSize: 11, color: m.ink400)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${b.delta > 0 ? '+' : ''}${_angka(b.delta)}',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: angka,
                  decoration: nada == _Nada.redup
                      ? TextDecoration.lineThrough
                      : null)),
        ],
      ),
    );
  }

  // ── Cara kerja: 3 langkah + ketentuan ──
  Widget _kartuCaraKerja(MasColors m) {
    final hijau = m.isDark ? m.brand700 : m.brand600;
    final langkah = [
      (Icons.shopping_cart_outlined, 'Belanja part',
          'Tiap ${formatRupiah(_poin.rpPerPoin)} harga barang dapat 1 poin.'),
      (Icons.inventory_2_outlined, 'Pesanan diterima',
          'Poin cair setelah pesanan Anda terima, bukan saat membayar.'),
      (Icons.local_offer_outlined, 'Tukar jadi potongan',
          '1 poin = potongan ${formatRupiah(_poin.nilaiPoin)} di belanja berikutnya.'),
    ];
    final ketentuan = [
      if (_poin.minTukar > 0)
        'Penukaran minimal ${_angka(_poin.minTukar)} poin.',
      'Potongan maksimal ${_poin.maksPersen}% dari harga barang per pesanan.',
      'Ongkir tidak menghasilkan poin dan tidak bisa dibayar dengan poin.',
      'Poin berlaku ${(_poin.masaHari / 30).round()} bulan; yang paling lama '
          'dipakai lebih dulu.',
    ];
    return MasCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _judul(m, 'Cara kerjanya'),
          for (var i = 0; i < langkah.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: m.brand50,
                        border: Border.all(color: m.brand100),
                      ),
                      child: Icon(langkah[i].$1, size: 16, color: hijau),
                    ),
                    // Garis penghubung antar-langkah.
                    if (i < langkah.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          color: m.brand100,
                        ),
                      ),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(langkah[i].$2,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: m.ink900)),
                          const SizedBox(height: 2),
                          Text(langkah[i].$3,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.5,
                                  color: m.ink600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            decoration: BoxDecoration(
              color: m.ink50,
              borderRadius: BorderRadius.circular(MasRadii.card),
              border: Border.all(color: m.ink150),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('KETENTUAN',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: m.ink500)),
                const SizedBox(height: 6),
                for (final t in ketentuan)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ',
                            style: TextStyle(fontSize: 12.5, color: m.ink500)),
                        Expanded(
                          child: Text(t,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.5,
                                  color: m.ink700)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
