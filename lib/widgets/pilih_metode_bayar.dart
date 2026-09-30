// lib/widgets/pilih_metode_bayar.dart
// Pemilih metode bayar RajaOngkir — paritas web `components/PilihMetodeBayar.tsx`:
// QRIS satu baris, Virtual Account berupa petak logo bank (bank yang jarang
// dipakai di balik "Bank lainnya"). Kanal yang tak menerima `total` (min/maks)
// tampil redup & tak bisa dipilih. Dipakai keranjang & lembar "Ganti metode".

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../theme/mas_theme.dart';

/// Bank yang tampil tanpa membuka "Bank lainnya" — dipakai sebagian besar pembeli.
const _bankUtama = ['va_bca', 'va_bni', 'va_bri', 'va_mandiri', 'va_bsi', 'va_permata'];

const _namaPetak = {
  'BCA': 'BCA', 'BNI': 'BNI', 'BRI': 'BRI', 'MANDIRI': 'Mandiri',
  'PERMATA': 'Permata', 'BSI': 'BSI', 'CIMB': 'CIMB Niaga', 'BJB': 'BJB',
  'DBS': 'DBS', 'BNC': 'Neo Commerce', 'SAHABAT_SAMPOERNA': 'Sahabat Sampoerna',
};

String _namaBank(PaymentChannel c) {
  final kode = (c.bankCode.isNotEmpty ? c.bankCode : c.code.replaceFirst('va_', ''))
      .toUpperCase();
  return _namaPetak[kode] ??
      (c.label.isNotEmpty ? c.label.replaceFirst(RegExp(r'^Virtual Account\s+'), '') : kode);
}

class PilihMetodeBayar extends StatefulWidget {
  final List<PaymentChannel> kanal;
  final String? value;
  final ValueChanged<String> onChanged;
  final num total;
  final bool enabled;

  const PilihMetodeBayar({
    super.key,
    required this.kanal,
    required this.value,
    required this.onChanged,
    required this.total,
    this.enabled = true,
  });

  @override
  State<PilihMetodeBayar> createState() => _PilihMetodeBayarState();
}

class _PilihMetodeBayarState extends State<PilihMetodeBayar> {
  bool _semua = false;

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    PaymentChannel? qris;
    final va = <PaymentChannel>[];
    for (final c in widget.kanal) {
      if (c.isQris) {
        qris = c;
      } else if (c.isVa) {
        va.add(c);
      }
    }
    final utama = [
      for (final k in _bankUtama)
        for (final c in va)
          if (c.code == k) c,
    ];
    final lain = [for (final c in va) if (!_bankUtama.contains(c.code)) c];
    // Bank "lainnya" yang sedang terpilih tetap terlihat walau daftar diciutkan.
    final tampil = _semua || lain.any((c) => c.code == widget.value) ? [...utama, ...lain] : utama;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (qris != null) _barisQris(m, qris),
        if (va.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('TRANSFER VIRTUAL ACCOUNT',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: m.ink500)),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, box) {
            // Maks 6 kolom, petak minimal ±100 px (HP: 3 kolom).
            const jarak = 8.0;
            final kolom = ((box.maxWidth + jarak) / (100 + jarak)).floor().clamp(2, 6);
            final lebar = (box.maxWidth - jarak * (kolom - 1)) / kolom;
            return Wrap(
              spacing: jarak,
              runSpacing: jarak,
              children: [
                for (final c in tampil)
                  SizedBox(width: lebar, child: _petakBank(m, c)),
              ],
            );
          }),
          if (lain.isNotEmpty && tampil.length < va.length)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _semua = true),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text('+ Bank lainnya (${lain.length})',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: m.brand700)),
              ),
            ),
        ],
      ],
    );
  }

  /// Logo selalu di atas latar putih — PNG RajaOngkir transparan (teks QRIS
  /// hitam) dan tak terbaca di mode gelap tanpa ini. Gagal dimuat → nama teks.
  Widget _logo(String url, String nama, double tinggi) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(6)),
        child: url.isEmpty
            ? _logoTeks(nama)
            : Image.network(url,
                height: tinggi,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => _logoTeks(nama)),
      );

  Widget _logoTeks(String nama) => Text(nama,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1B211D)));

  BoxDecoration _kotak(MasColors m, bool aktif) => BoxDecoration(
        color: aktif ? m.brand50 : m.paper,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: aktif ? m.brand600 : m.ink200, width: aktif ? 1.6 : 1),
      );

  Widget _barisQris(MasColors m, PaymentChannel c) {
    final alasan = c.alasanTakBisa(widget.total);
    final aktif = widget.value == c.code;
    final bisa = alasan == null && widget.enabled;
    return Opacity(
      opacity: alasan == null ? 1 : 0.45,
      child: InkWell(
        onTap: bisa ? () => widget.onChanged(c.code) : null,
        borderRadius: BorderRadius.circular(MasRadii.card),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: _kotak(m, aktif),
          child: Row(children: [
            _logo(c.logoUrl, 'QRIS', 16),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('QRIS',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700, color: m.ink900)),
                  Text(
                    alasan != null
                        ? 'Tidak tersedia untuk total ini ($alasan)'
                        : 'GoPay · OVO · DANA · ShopeePay · semua m-banking',
                    style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(aktif ? Icons.check_circle : Icons.radio_button_off,
                size: 20, color: aktif ? m.brand600 : m.ink300),
          ]),
        ),
      ),
    );
  }

  Widget _petakBank(MasColors m, PaymentChannel c) {
    final alasan = c.alasanTakBisa(widget.total);
    final aktif = widget.value == c.code;
    final bisa = alasan == null && widget.enabled;
    final nama = _namaBank(c);
    return Tooltip(
      message: alasan != null ? 'Tidak tersedia untuk total ini ($alasan)' : 'Virtual Account $nama',
      child: Opacity(
        opacity: alasan == null ? 1 : 0.45,
        child: InkWell(
          onTap: bisa ? () => widget.onChanged(c.code) : null,
          borderRadius: BorderRadius.circular(MasRadii.card),
          child: Container(
            height: 76,
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
            decoration: _kotak(m, aktif),
            child: Stack(children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 32, child: Center(child: _logo(c.logoUrl, nama, 24))),
                    const SizedBox(height: 6),
                    Text(nama,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600, color: m.ink700)),
                  ],
                ),
              ),
              if (aktif)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(Icons.check_circle, size: 16, color: m.brand600),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
