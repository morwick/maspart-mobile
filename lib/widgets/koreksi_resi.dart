// lib/widgets/koreksi_resi.dart
//
// Audit 2026-09-28 T-11 (KL-7): resi salah ketik dulu tak bisa dikoreksi dari UI
// mana pun, dan 'dikirim' ulang menggantinya diam-diam. Dialog ini dipakai layar
// gudang & admin — padanan web components/KoreksiResi.tsx.

import 'package:flutter/material.dart';

import '../theme/mas_theme.dart';
import 'mas_ui.dart';

/// Tanya resi baru + alasan. Null bila dibatalkan.
Future<(String, String)?> tanyaKoreksiResi(BuildContext context, String? resiLama) async {
  final resiCtl = TextEditingController();
  final alasanCtl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final m = ctx.mas;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Koreksi resi', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resi sekarang: ${resiLama ?? '-'}. Pembeli langsung dikabari '
                  'nomor resi baru & perubahan tercatat di riwayat pesanan.',
                  style: TextStyle(fontSize: 12.5, color: m.ink600, height: 1.45),
                ),
                const SizedBox(height: 8),
                MasInput(
                  controller: resiCtl,
                  hint: 'Nomor resi yang benar',
                  mono: true,
                  height: 40,
                  onChanged: (_) => setLocal(() {}),
                ),
                const SizedBox(height: 8),
                MasInput(
                  controller: alasanCtl,
                  hint: 'Alasan, mis. salah ketik digit terakhir',
                  height: 40,
                  onChanged: (_) => setLocal(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            TextButton(
              onPressed: resiCtl.text.trim().length >= 8 && alasanCtl.text.trim().length >= 5
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Simpan resi'),
            ),
          ],
        ),
      );
    },
  );
  final resi = resiCtl.text.trim();
  final alasan = alasanCtl.text.trim();
  resiCtl.dispose();
  alasanCtl.dispose();
  if (ok != true) return null;
  return (resi, alasan);
}

/// Tanya resi saat admin menandai 'dikirim' pesanan kurir. Null bila dibatalkan.
Future<String?> tanyaResiKirim(BuildContext context, String kode) async {
  final ctl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Nomor resi', style: TextStyle(fontSize: 16)),
        content: MasInput(
          controller: ctl,
          hint: 'Resi $kode (dari struk ekspedisi)',
          mono: true,
          height: 40,
          onChanged: (_) => setLocal(() {}),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
            onPressed: ctl.text.trim().length >= 8 ? () => Navigator.pop(ctx, true) : null,
            child: const Text('Lanjut'),
          ),
        ],
      ),
    ),
  );
  final resi = ctl.text.trim();
  ctl.dispose();
  return ok == true ? resi : null;
}

/// S-19: admin menyelesaikan pesanan Ambil di Toko TANPA serah terima gudang
/// (tanpa kode ambil & foto) — alasan wajib (min. 10 karakter), dicatat di
/// pesanan. Null = dibatalkan. Padanan web: prompt alasan di admin/orders.
Future<String?> tanyaAlasanSelesaiPickup(BuildContext context, String kode) async {
  final ctl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Selesai tanpa serah terima',
            style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pesanan $kode biasanya diselesaikan gudang lewat "Serahkan & '
              'Selesai" (kode ambil + foto pengambil). Tulis alasan menyelesaikan '
              'dari sini — dicatat di pesanan.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            MasInput(
              controller: ctl,
              hint: 'Alasan (min. 10 karakter)',
              maxLines: 3,
              onChanged: (_) => setLocal(() {}),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
            onPressed: ctl.text.trim().length >= 10 ? () => Navigator.pop(ctx, true) : null,
            child: const Text('Lanjut'),
          ),
        ],
      ),
    ),
  );
  final alasan = ctl.text.trim();
  ctl.dispose();
  return ok == true ? alasan : null;
}
