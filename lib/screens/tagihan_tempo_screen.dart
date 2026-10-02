// lib/screens/tagihan_tempo_screen.dart
// "Tagihan Tempo" — pembeli TOP (migrasi 048): limit kredit, tagihan yang belum
// lunas dikelompokkan menurut jatuh tempo, riwayat pelunasan 90 hari.
// Paritas web `frontend/src/app/tagihan-tempo/page.tsx`. Pembayarannya sendiri
// ada di detail pesanan (VA/QRIS untuk sisa tagihan) — satu alur bayar.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/mas_ui.dart';

class TagihanTempoScreen extends StatefulWidget {
  const TagihanTempoScreen({super.key});

  @override
  State<TagihanTempoScreen> createState() => _TagihanTempoScreenState();
}

class _Kelompok {
  final String judul;
  final bool Function(TagihanTempo t) cocok;
  final bool merah;
  const _Kelompok(this.judul, this.cocok, {this.merah = false});
}

final _kelompok = <_Kelompok>[
  _Kelompok('Lewat jatuh tempo', (t) => t.tempo.tahap == 'lewat', merah: true),
  _Kelompok(
      'Jatuh tempo ≤ 7 hari',
      (t) =>
          t.tempo.tahap == 'jatuh_tempo_hari_ini' ||
          (t.tempo.tahap == 'berjalan' && t.tempo.hariLagi <= 7)),
  _Kelompok('Berjalan', (t) => t.tempo.tahap == 'berjalan' && t.tempo.hariLagi > 7),
  _Kelompok('Belum dikirim', (t) => t.tempo.tahap == 'belum_kirim'),
];

class _TagihanTempoScreenState extends State<TagihanTempoScreen> {
  TempoSaya? _data;
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
      final d = await ApiService.tempoSaya();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Tagihan tempo gagal dimuat.';
        _loading = false;
      });
    }
  }

  String _ketJatuhTempo(TempoOrderInfo t) {
    switch (t.tahap) {
      case 'belum_kirim':
        return 'Jatuh tempo dihitung saat barang dikirim';
      case 'lewat':
        return 'Jatuh tempo ${tglJatuhTempo(t.jatuhTempo)} · lewat ${t.hariLewat} hari';
      case 'jatuh_tempo_hari_ini':
        return 'Jatuh tempo hari ini';
    }
    return 'Jatuh tempo ${tglJatuhTempo(t.jatuhTempo)} · ${t.hariLagi} hari lagi';
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final d = _data;
    if (d == null) {
      return MasErrorState(message: _error ?? 'Tagihan tempo gagal dimuat.', onRetry: _load);
    }
    final a = d.akun;
    if (!d.tersedia || (!a.aktif && d.tagihan.isEmpty)) {
      return const MasEmpty(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Pembayaran tempo belum aktif',
        subtitle: 'Pembayaran tempo (bayar belakangan) tersedia untuk pelanggan korporat '
            'yang sudah disetujui — hubungi admin MasPart bila ingin mengajukan.',
      );
    }
    final persen = a.limit > 0 ? (a.terpakai / a.limit).clamp(0.0, 1.0) : 0.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          if (_error != null) ...[
            Text(_error!, style: TextStyle(fontSize: 12.5, color: m.danger600)),
            const SizedBox(height: 10),
          ],
          MasCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _stat(m, 'Sisa limit', formatRupiah(a.sisa), warna: m.brand700)),
                Expanded(child: _stat(m, 'Terpakai', formatRupiah(a.terpakai))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _stat(m, 'Limit kredit', formatRupiah(a.limit))),
                Expanded(child: _stat(m, 'Termin', '${a.terminHari} hari')),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: persen,
                  minHeight: 8,
                  backgroundColor: m.ink100,
                  color: persen >= 0.9 ? m.danger600 : m.brand600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Jatuh tempo dihitung ${a.terminHari} hari sejak barang dikirim. Limit pulih '
                'setiap kali tagihan dilunasi.',
                style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.4),
              ),
              if (a.beku) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: m.danger50, borderRadius: BorderRadius.circular(MasRadii.input)),
                  child: Text(a.alasan ?? 'Pembayaran tempo sedang dibekukan.',
                      style: TextStyle(fontSize: 12.5, color: m.danger600, height: 1.4)),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          if (d.tagihan.isEmpty)
            MasCard(
              child: Text('Tidak ada tagihan tempo yang belum dibayar. 🎉',
                  style: TextStyle(fontSize: 13.5, color: m.ink600)),
            ),
          for (final k in _kelompok)
            if (d.tagihan.any(k.cocok)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
                child: Row(children: [
                  Expanded(
                    child: Text(k.judul,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: k.merah ? m.danger600 : m.ink800)),
                  ),
                  Text(
                      formatRupiah(d.tagihan
                          .where(k.cocok)
                          .fold<int>(0, (n, t) => n + t.tempo.sisaTagihan)),
                      style: masMono(size: 13, color: m.ink600)),
                ]),
              ),
              for (final t in d.tagihan.where(k.cocok))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: MasCard(
                    onTap: () => nav.go(MasScreen.pesananDetail, part: {'order_code': t.orderCode}),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(t.orderCode,
                              style: masMono(size: 13, weight: FontWeight.w700, color: m.ink900)),
                        ),
                        MasPill(
                            label: orderStatusLabel(t.status, pickup: t.pickup),
                            tone: orderStatusTone(t.status),
                            height: 20),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: Text(_ketJatuhTempo(t.tempo),
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: t.tempo.tahap == 'lewat' ? m.danger600 : m.ink600)),
                        ),
                        Text(formatRupiah(t.tempo.sisaTagihan),
                            style: masMono(size: 14, weight: FontWeight.w700, color: m.ink900)),
                      ]),
                      if (t.tempo.potonganRetur > 0)
                        Text('dari ${formatRupiah(t.total)} (dipotong retur)',
                            style: TextStyle(fontSize: 11, color: m.ink500)),
                      const SizedBox(height: 8),
                      MasButton(
                        label: t.adaTagihanOnline ? 'Lihat tagihan' : 'Bayar',
                        primary: t.tempo.tahap == 'lewat',
                        height: 36,
                        expand: true,
                        onTap: () =>
                            nav.go(MasScreen.pesananDetail, part: {'order_code': t.orderCode}),
                      ),
                    ]),
                  ),
                ),
            ],
          if (!d.bayarOnline && d.tagihan.isNotEmpty)
            Text(
              'Pembayaran online tagihan tempo sedang tidak tersedia — transfer ke rekening '
              'perusahaan, lalu kabari admin lewat chat pesanan.',
              style: TextStyle(fontSize: 12, color: m.info600, height: 1.4),
            ),
          if (d.lunas.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Sudah lunas (90 hari terakhir)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: m.ink800)),
            const SizedBox(height: 8),
            MasCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final l in d.lunas)
                  InkWell(
                    onTap: () => nav.go(MasScreen.pesananDetail, part: {'order_code': l.orderCode}),
                    child: MasKeyValue(
                      label: '${l.orderCode} · ${fmtDate(l.paidAt)}',
                      value: formatRupiah(l.total),
                      mono: true,
                      divider: l != d.lunas.last,
                    ),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(MasColors m, String label, String nilai, {Color? warna}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: m.ink500)),
        const SizedBox(height: 2),
        Text(nilai, style: masMono(size: 15, weight: FontWeight.w700, color: warna ?? m.ink900)),
      ]);
}
