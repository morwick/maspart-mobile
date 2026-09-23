// lib/screens/poin_screen.dart
// "Poin Saya" — saldo, poin tertunda, dan riwayat buku besar poin.
// Paritas dengan web `frontend/src/app/poin/page.tsx`.
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
    return '${d.day} ${bulan[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: m.danger50,
                borderRadius: BorderRadius.circular(MasRadii.card),
                border: Border.all(color: m.dangerBorder),
              ),
              child: Text(_error!,
                  style: TextStyle(fontSize: 12.5, color: m.danger600)),
            ),
            const SizedBox(height: 14),
          ],

          if (!_poin.aktif)
            // Migrasi 034 belum jalan — jangan menampilkan saldo 0 seolah pembeli
            // tak punya poin; katakan apa adanya bahwa programnya belum ada.
            MasCard(
              child: Text('Program poin belum aktif di toko ini.',
                  style: TextStyle(fontSize: 13.5, color: m.ink600)),
            )
          else ...[
            MasCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Poin bisa dipakai',
                      style: TextStyle(fontSize: 12.5, color: m.ink500)),
                  const SizedBox(height: 2),
                  Text('${_poin.saldo}',
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          color: m.ink900)),
                  Text('setara potongan ${formatRupiah(_poin.rupiah)}',
                      style: TextStyle(fontSize: 13.5, color: m.ink600)),
                  if (_poin.tertunda > 0) ...[
                    const SizedBox(height: 10),
                    Divider(height: 1, color: m.ink100),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => nav.go(MasScreen.pesanan),
                      child: Text(
                        '⏳ ${_poin.tertunda} poin menunggu — cair setelah pesanan '
                        'Anda ditandai diterima. Lihat pesanan ›',
                        style: TextStyle(
                            fontSize: 12.5, color: m.ink600, height: 1.5),
                      ),
                    ),
                  ],
                  if (!_poin.bolehTukar) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Penukaran poin belum dibuka. Poin Anda tetap terkumpul dan '
                      'tidak hangus selama masa berlakunya.',
                      style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            MasCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cara kerjanya',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: m.ink900)),
                  const SizedBox(height: 8),
                  ..._aturan().map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('•  $t',
                            style: TextStyle(
                                fontSize: 13, color: m.ink700, height: 1.5)),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),

            MasCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Riwayat',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: m.ink900)),
                  const SizedBox(height: 8),
                  if (_riwayat.isEmpty)
                    Text(
                      'Belum ada riwayat poin. Poin pertama Anda muncul setelah '
                      'pesanan diterima.',
                      style: TextStyle(fontSize: 13, color: m.ink500, height: 1.5),
                    )
                  else
                    ..._riwayat.map((b) => _baris(m, b)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<String> _aturan() => [
        'Tiap belanja ${formatRupiah(_poin.rpPerPoin)} barang dapat 1 poin.',
        '1 poin = potongan ${formatRupiah(_poin.nilaiPoin)} di belanja berikutnya.',
        'Poin cair setelah pesanan Anda terima, bukan saat membayar.',
        'Potongan maksimal ${_poin.maksPersen}% dari harga barang per pesanan.',
        'Ongkir tidak menghasilkan poin dan tidak bisa dibayar dengan poin.',
        'Poin berlaku ${(_poin.masaHari / 30).round()} bulan; yang paling lama '
            'dipakai lebih dulu.',
      ];

  Widget _baris(MasColors m, PoinBaris b) {
    final masuk = b.delta > 0;
    final warna = masuk ? m.brand600 : m.ink700;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_kJenis[b.reason] ?? b.reason,
                    style: TextStyle(fontSize: 13, color: m.ink800)),
                const SizedBox(height: 2),
                Text(
                  [
                    _tanggal(b.createdAt),
                    if (b.orderCode.isNotEmpty) b.orderCode,
                    if (b.reason == 'earn' && b.expiresAt.isNotEmpty)
                      's/d ${_tanggal(b.expiresAt)}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 11.5, color: m.ink500),
                ),
              ],
            ),
          ),
          Text('${masuk ? '+' : ''}${b.delta}',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: warna)),
        ],
      ),
    );
  }
}
