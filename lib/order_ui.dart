// lib/order_ui.dart
// Helper tampilan & hitung uang untuk fitur Pesanan — cerminan
// `frontend/src/lib/order-ui.ts`. Angka di sini HARUS sama dengan backend,
// kalau tidak, tagihan ke pembeli tak akan cocok dengan dokumen Accurate.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'theme/mas_theme.dart';
import 'utils.dart';
import 'widgets/mas_ui.dart';

/// PPN 12% **DITAMBAHKAN** di atas harga barang — harga katalog/Accurate BELUM
/// termasuk PPN. Bukti: penawaran Accurate asli milik pemilik — Sub Total
/// 5.400.000 → PPN (12%) 594.000 → Total 5.994.000, yaitu 12% × DPP 11/12 =
/// efektif 11%. Aturan (harus SAMA PERSIS dengan backend `orders.create_order`):
///   neto  = subtotal − voucher diskon − potongan poin   (potongan SEBELUM pajak)
///   PPN   = floor(neto × 11 / 100)
///   total = neto + PPN + ongkir − potongan ongkir       (ongkir TIDAK kena PPN)
///
/// Catatan sejarah: sejak 2026-07-12 aplikasi sempat menganggap harga INKLUSIF
/// (PPN = x × 12/112, total = barang + ongkir). Dasarnya penawaran yang dibuat
/// aplikasi SENDIRI dengan inclusiveTax=true — bukan bukti harga jual
/// sebenarnya. Pesanan dari masa itu tetap tampil apa adanya (lihat
/// [ppnDitambahkan]); totalnya SELALU dibaca dari `o.total`, tak dihitung ulang.
const double kPpnRate = 0.12;

/// PPN 12% (DPP 11/12) yang DITAMBAHKAN di atas [neto] (barang setelah voucher
/// diskon & potongan poin). Pembulatan integer ke bawah.
int ppnOf(num neto) => neto <= 0 ? 0 : neto * 11 ~/ 100;

/// Total tagihan = neto + PPN + ongkir − potongan ongkir. [neto] = barang
/// setelah voucher diskon & potongan poin.
num totalOf(num neto, [num ongkir = 0, num potonganOngkir = 0]) {
  final n = neto < 0 ? 0 : neto;
  return n + ppnOf(n) + ongkir - potonganOngkir;
}

/// LEGACY — komponen PPN yang terkandung di harga INKLUSIF (rumus lama 12/112).
/// Hanya untuk menampilkan pesanan lama yang kolom `tax`-nya kosong.
int ppnInklusifLama(num amount) => amount <= 0 ? 0 : amount * 12 ~/ 112;

/// Harga barang pesanan setelah voucher diskon & potongan poin (dasar PPN).
num netoOf(OrderDetail o) {
  final n = o.subtotal - o.voucherDiscount - o.pointDiscount;
  return n < 0 ? 0 : n;
}

/// true = pesanan aturan BARU: PPN ditambahkan di atas barang (total tersimpan
/// = neto + PPN + ongkir − potongan ongkir). false = pesanan lama (harga
/// dianggap inklusif, PPN hanya komponen) → tampil "Termasuk PPN 12%" seperti
/// dulu. Dibaca dari angka yang TERSIMPAN (tak ada kolom penanda aturan) —
/// sama dengan backend `orders.ppn_ditambahkan`. Dibulatkan karena kolom uang
/// datang sebagai double.
bool ppnDitambahkan(OrderDetail o) {
  final tax = (o.tax ?? 0).round();
  if (tax <= 0) return false;
  final ongkir = o.shippingCost - o.shippingDiscount;
  return o.total.round() ==
      netoOf(o).round() + tax + (ongkir < 0 ? 0 : ongkir).round();
}

/// Baris PPN di ringkasan pesanan, sadar aturan. `ditambahkan` false = pesanan
/// lama → tampilkan abu-abu sebagai komponen ("Termasuk PPN 12%"), persis
/// tampilan lama.
({String label, int nilai, bool ditambahkan}) barisPpn(OrderDetail o) {
  if (ppnDitambahkan(o)) {
    return (
      label: 'PPN 12% (DPP 11/12)',
      nilai: o.tax!.round(),
      ditambahkan: true,
    );
  }
  return (
    label: 'Termasuk PPN 12%',
    nilai: o.tax?.round() ?? ppnInklusifLama(o.subtotal),
    ditambahkan: false,
  );
}

/// Label + warna pill tiap status pesanan.
const Map<String, (String, MasPillTone)> kOrderStatus = {
  'menunggu_pembayaran': ('Menunggu Pembayaran', MasPillTone.warn),
  'menunggu_verifikasi': ('Menunggu Verifikasi', MasPillTone.info),
  'diproses': ('Diproses', MasPillTone.info),
  'dikirim': ('Dikirim', MasPillTone.info),
  'selesai': ('Selesai', MasPillTone.brand),
  'batal': ('Batal', MasPillTone.danger),
};

/// Label status. Untuk pesanan AMBIL DI TOKO, status 'dikirim' berarti barangnya
/// sudah siap di konter, bukan sedang di jalan — statusnya sendiri sengaja tidak
/// ditambah, hanya kata yang dibaca pembeli yang berbeda. Dipakai di layar yang
/// memang tahu pesanannya ambil sendiri (daftar pesanan hanya memuat ringkasan).
String orderStatusLabel(String status, {bool pickup = false}) {
  if (pickup && status == 'dikirim') return 'Siap Diambil';
  return kOrderStatus[status]?.$1 ?? status;
}

MasPillTone orderStatusTone(String status) =>
    kOrderStatus[status]?.$2 ?? MasPillTone.neutral;

/// Langkah yang boleh dipilih cabang/admin setelah pembayaran terverifikasi.
const List<String> kOrderFlow = ['diproses', 'dikirim', 'selesai'];

/// Tahapan progres pesanan untuk stepper. `done` = milestone sudah tercapai.
List<({String label, bool done})> orderProgress(String status,
    {bool pickup = false}) {
  final paid = ['diproses', 'dikirim', 'selesai'].contains(status);
  return [
    (label: 'Dibayar', done: paid),
    (label: 'Diproses', done: paid),
    (
      label: pickup ? 'Siap Diambil' : 'Dikirim',
      done: ['dikirim', 'selesai'].contains(status)
    ),
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

  /// Pesanan diambil sendiri → langkah ketiga berbunyi "Siap Diambil".
  final bool pickup;
  const OrderStepper({super.key, required this.status, this.pickup = false});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final steps = orderProgress(status, pickup: pickup);
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

/// Warna baris potongan — sama dengan web (`OrderPotongan.tsx`, keranjang).
const Color kWarnaVoucherDiskon = Color(0xFFC9530F);
const Color kWarnaVoucherOngkir = Color(0xFF0B7D6E);

/// Baris potongan pesanan (voucher diskon, voucher ongkir, poin) + kode voucher.
/// Cerminan `components/OrderPotongan.tsx` — dipakai detail pesanan pembeli,
/// admin, dan cabang. Tanpa baris ini Subtotal + Ongkir ≠ Total dan orang
/// mengira sistem salah hitung.
///
/// [bagian] memecah tampilan mengikuti urutan Accurate untuk pesanan aturan
/// PPN baru ([ppnDitambahkan]): [PotonganBagian.barang] (voucher diskon + poin)
/// tampil SEBELUM baris PPN, [PotonganBagian.ongkir] (voucher gratis ongkir +
/// kode voucher) setelah baris Ongkir. Default [PotonganBagian.semua] = tata
/// letak lama (pesanan lama).
enum PotonganBagian { semua, barang, ongkir }

class OrderPotongan extends StatelessWidget {
  final OrderDetail order;
  final PotonganBagian bagian;
  const OrderPotongan(
      {super.key, required this.order, this.bagian = PotonganBagian.semua});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final o = order;
    final semua = bagian == PotonganBagian.semua;
    final barang = semua || bagian == PotonganBagian.barang;
    final ongkir = semua || bagian == PotonganBagian.ongkir;
    final baris = <(String, num, Color)>[
      if (barang && o.voucherDiscount > 0)
        ('Voucher diskon', o.voucherDiscount, kWarnaVoucherDiskon),
      if (ongkir && o.shippingDiscount > 0)
        ('Voucher gratis ongkir', o.shippingDiscount, kWarnaVoucherOngkir),
      if (barang && o.pointDiscount > 0)
        ('Potongan poin (${thousands(o.pointRedeemed)})', o.pointDiscount,
            m.brand700),
    ];
    // Kode voucher (bisa voucher barang maupun ongkir) selalu paling akhir.
    final kode = ongkir ? (o.voucherCodes ?? '').trim() : '';
    if (baris.isEmpty && kode.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (label, n, warna) in baris)
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 13, color: warna))),
            Text('−${formatRupiah(n)}',
                style: masMono(size: 13, color: warna)),
          ]),
        ),
      if (kode.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
              'Kode voucher: ${kode.split(',').map((e) => e.trim()).join(', ')}',
              style: TextStyle(fontSize: 11.5, color: m.ink400)),
        ),
    ]);
  }
}

/// Bukti serah terima pesanan Ambil di Toko (migrasi 043): foto orang yang
/// mengambil barang + nama & waktu ambil. Dipakai TIGA layar (pembeli, gudang,
/// admin) — bukti yang sama dibaca bila ada sengketa "barang belum diambil".
/// Kosong (SizedBox) bila pesanan belum punya foto serah terima.
class BuktiSerahTerima extends StatelessWidget {
  final OrderDetail order;
  const BuktiSerahTerima({super.key, required this.order});

  void _buka(BuildContext context, String url) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      pageBuilder: (ctx, _, _) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.black54,
          foregroundColor: Colors.white,
          title: const Text('Bukti serah terima'),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 6,
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final url = (order.pickupProofUrl ?? '').trim();
    if (url.isEmpty) return const SizedBox.shrink();
    final m = context.mas;
    final nama = (order.pickedUpBy ?? '').trim();
    final kapan = order.pickedUpAt ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Bukti Serah Terima',
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: m.ink800)),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () => _buka(context, url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MasRadii.card),
          child: Container(
            width: double.infinity,
            height: 180,
            color: m.ink100,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, _) => Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: m.brand600),
              ),
              errorWidget: (_, _, _) =>
                  const Center(child: HatchBox(label: 'foto gagal dimuat')),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Diambil oleh ${nama.isNotEmpty ? nama : '(nama tidak dicatat)'}'
        '${kapan.isNotEmpty ? ' · ${fmtDate(kapan)}' : ''}',
        style: TextStyle(fontSize: 12, color: m.ink600, height: 1.4),
      ),
      Text('Ketuk foto untuk memperbesar.',
          style: TextStyle(fontSize: 11, color: m.ink400)),
    ]);
  }
}
