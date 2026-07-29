// lib/order_ui.dart
// Helper tampilan & hitung uang untuk fitur Pesanan — cerminan
// `frontend/src/lib/order-ui.ts`. Angka di sini HARUS sama dengan backend,
// kalau tidak, tagihan ke pembeli tak akan cocok dengan dokumen Accurate.

import 'package:flutter/material.dart';
import 'theme/mas_theme.dart';
import 'widgets/mas_ui.dart';

/// PPN 12% **INKLUSIF** — harga jual Accurate SUDAH mengandung PPN, jadi pajak
/// TIDAK ditambahkan di atas subtotal. Contoh dari Accurate: Sub Total 80.000 →
/// PPN 12% 8.571 → Total tetap 80.000.
///
/// Harus sama dengan backend (`orders.ppn_included`).
const double kPpnRate = 0.12;

/// Komponen PPN yang sudah terkandung di dalam [subtotal].
int ppnOf(num subtotal) => (subtotal * 12 ~/ 112);

/// Total tagihan = barang (sudah termasuk PPN) + ongkir. PPN bukan tambahan.
num totalOf(num subtotal, [num ongkir = 0]) => subtotal + ongkir;

/// Label + warna pill tiap status pesanan.
const Map<String, (String, MasPillTone)> kOrderStatus = {
  'menunggu_pembayaran': ('Menunggu Pembayaran', MasPillTone.warn),
  'menunggu_verifikasi': ('Menunggu Verifikasi', MasPillTone.info),
  'diproses': ('Diproses', MasPillTone.info),
  'dikirim': ('Dikirim', MasPillTone.info),
  'selesai': ('Selesai', MasPillTone.brand),
  'batal': ('Batal', MasPillTone.danger),
};

String orderStatusLabel(String status) => kOrderStatus[status]?.$1 ?? status;

MasPillTone orderStatusTone(String status) =>
    kOrderStatus[status]?.$2 ?? MasPillTone.neutral;

/// Langkah yang boleh dipilih cabang/admin setelah pembayaran terverifikasi.
const List<String> kOrderFlow = ['diproses', 'dikirim', 'selesai'];

/// Tahapan progres pesanan untuk stepper. `done` = milestone sudah tercapai.
List<({String label, bool done})> orderProgress(String status) {
  final paid = ['diproses', 'dikirim', 'selesai'].contains(status);
  return [
    (label: 'Dibayar', done: paid),
    (label: 'Diproses', done: paid),
    (label: 'Dikirim', done: ['dikirim', 'selesai'].contains(status)),
    (label: 'Selesai', done: status == 'selesai'),
  ];
}

/// Format timestamp backend ke waktu lokal yang enak dibaca.
///
/// Supabase mengirim `timestamptz` lengkap dengan offset (`+00:00`), tapi
/// sebagian kolom lain polos tanpa zona. Hanya yang TANPA zona yang perlu
/// ditambahi 'Z' — menambahkannya ke string yang sudah beroffset justru
/// membuatnya tak bisa di-parse.
String fmtDate(String? s) {
  if (s == null || s.isEmpty) return '—';
  final sudahAdaZona =
      RegExp(r'[zZ]$').hasMatch(s) || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
  final d = DateTime.tryParse(sudahAdaZona ? s : '${s}Z');
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}.${two(l.minute)}';
}

/// Stepper progres pesanan (Dibayar → Diproses → Dikirim → Selesai).
class OrderStepper extends StatelessWidget {
  final String status;
  const OrderStepper({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final steps = orderProgress(status);
    final batal = status == 'batal';

    return Row(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: !batal && steps[i].done ? m.brand600 : m.ink150,
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: batal
                      ? m.ink100
                      : (steps[i].done ? m.brand600 : m.paper),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: !batal && steps[i].done ? m.brand600 : m.ink200,
                  ),
                ),
                child: steps[i].done && !batal
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                steps[i].label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: !batal && steps[i].done ? m.brand700 : m.ink500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
