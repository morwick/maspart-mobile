// lib/widgets/beli_lagi.dart
// "Beli Lagi" (pola Shopee/Tokopedia) — helper bersama untuk tombol Beli Lagi
// di daftar/detail pesanan dan layar riwayat Beli Lagi.
//
// Keranjang tersimpan LOKAL di perangkat (CartStore), jadi server hanya
// MENILAI ULANG barang lama (harga/stok/berat terkini) — klien yang
// memasukkan item `bisa_dibeli` ke keranjang. Keranjang sendiri tetap
// menyegarkan harga dari `/api/cart/gudang` sebelum checkout.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../cart.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import 'mas_ui.dart';

/// Status pesanan yang menampilkan tombol "Beli Lagi" (paritas web).
const Set<String> kStatusBeliLagi = {'selesai', 'batal', 'dikirim'};

/// Item Beli Lagi → baris keranjang. Harga disimpan dalam format TAMPILAN
/// yang sama dengan etalase (`harga_display`, mis. "Rp 600.000").
CartItem cartItemDariBeliLagi(BeliLagiItem it, {int? qty}) => CartItem(
      partNumber: it.partNumber,
      name: it.judul,
      harga: it.hargaDisplay.isNotEmpty
          ? it.hargaDisplay
          : (it.harga > 0 ? formatRupiah(it.harga) : ''),
      berat: it.berat,
      qty: (qty ?? it.qty) < 1 ? 1 : (qty ?? it.qty),
    );

/// Masukkan banyak item Beli Lagi ke keranjang sekaligus. Hanya item
/// [BeliLagiItem.bisaDibeli] yang masuk; qty = [qtyPilihan] (per PN) bila ada,
/// selain itu usulan server (`qty`, sudah dipangkas ke stok). PN yang sudah ada
/// di keranjang qty-nya DITAMBAH — sama dengan tombol "+ Keranjang" biasa.
/// Mengembalikan jumlah baris yang dimasukkan.
Future<int> masukkanBeliLagi(
  Iterable<BeliLagiItem> items, {
  Map<String, int> qtyPilihan = const {},
}) async {
  final baris = [
    for (final it in items)
      if (it.bisaDibeli)
        cartItemDariBeliLagi(it, qty: qtyPilihan[it.partNumber]),
  ];
  if (baris.isEmpty) return 0;
  await CartStore.instance.addMany(baris);
  return baris.length;
}

const _kBulanPendek = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// Tanggal pendek dari ISO: "12 Sep" (tahun ini) / "12 Sep 2025". '' bila
/// tak terbaca. Stempel tanpa zona dianggap UTC — sama dengan `fmtDate`.
String tglPendek(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final ada = RegExp(r'[zZ]$|[+-]\d{2}:?\d{2}$').hasMatch(iso);
  final d = DateTime.tryParse(ada ? iso : '${iso}Z');
  if (d == null) return '';
  final l = d.toLocal();
  final tahun = l.year == DateTime.now().year ? '' : ' ${l.year}';
  return '${l.day} ${_kBulanPendek[l.month - 1]}$tahun';
}

/// "Harga turun Rp 5.000" / "Harga naik Rp 5.000" — '' bila sama.
String labelSelisihHarga(int selisih) {
  if (selisih == 0) return '';
  final nominal = formatRupiah(selisih.abs());
  return selisih < 0 ? 'Harga turun $nominal' : 'Harga naik $nominal';
}

/// Alur tombol "Beli Lagi" satu pesanan:
/// ambil isi pesanan (dinilai ulang server) → masukkan item yang bisa dibeli
/// → ringkasan (yang tak bisa, qty disesuaikan stok, harga berubah) → buka
/// Keranjang. Nol item bisa dibeli → keranjang TIDAK dibuka.
///
/// Pemanggil cukup mengurus tanda sibuk tombolnya sendiri.
Future<void> beliLagiDariPesanan(BuildContext context, String code) async {
  final nav = AppNav.of(context);
  BeliLagiPesanan hasil;
  try {
    hasil = await ApiService.beliLagiPesanan(code);
  } on ApiException catch (e) {
    // 409 = alamat/profil belum lengkap → beri jalan keluar ke Profil.
    if (e.statusCode == 409) {
      nav.toast(e.message,
          actionLabel: 'Lengkapi', onAction: () => nav.go(MasScreen.profil));
    } else {
      nav.toast(e.message.isNotEmpty
          ? e.message
          : 'Gagal memuat isi pesanan. Coba lagi.');
    }
    return;
  } catch (_) {
    nav.toast('Gagal memuat isi pesanan. Periksa koneksi Anda.');
    return;
  }

  final bisa = hasil.items.where((i) => i.bisaDibeli).toList();
  if (bisa.isEmpty) {
    if (!context.mounted) return;
    if (hasil.items.isEmpty) {
      nav.toast('Pesanan ini tidak berisi barang yang bisa dibeli lagi.');
      return;
    }
    await tampilkanRingkasanBeliLagi(context, hasil.items, dimasukkan: 0);
    return;
  }

  final n = await masukkanBeliLagi(bisa);
  final perluRingkasan = hasil.items.any((i) =>
      !i.bisaDibeli || i.qtyDisesuaikan || i.selisihHarga != 0);
  if (perluRingkasan && context.mounted) {
    await tampilkanRingkasanBeliLagi(context, hasil.items, dimasukkan: n);
  } else {
    nav.toast('$n barang dimasukkan ke keranjang');
  }
  nav.go(MasScreen.keranjang);
}

/// Lembar ringkasan hasil Beli Lagi. [dimasukkan] = 0 → mode "semua barang
/// sedang tidak tersedia" (tanpa tombol ke keranjang).
Future<void> tampilkanRingkasanBeliLagi(
  BuildContext context,
  List<BeliLagiItem> items, {
  required int dimasukkan,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RingkasanSheet(items: items, dimasukkan: dimasukkan),
  );
}

class _RingkasanSheet extends StatelessWidget {
  final List<BeliLagiItem> items;
  final int dimasukkan;
  const _RingkasanSheet({required this.items, required this.dimasukkan});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final takBisa = items.where((i) => !i.bisaDibeli).toList();
    final disesuaikan =
        items.where((i) => i.bisaDibeli && i.qtyDisesuaikan).toList();
    final berubah =
        items.where((i) => i.bisaDibeli && i.selisihHarga != 0).toList();
    final kosong = dimasukkan == 0;

    Widget judulBagian(String t, IconData ik, Color c) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Row(children: [
            Icon(ik, size: 16, color: c),
            const SizedBox(width: 6),
            Text(t,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: m.ink900)),
          ]),
        );

    Widget baris(String nama, String ket, {Color? warnaKet}) => Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 22),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: nama,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: m.ink800)),
              TextSpan(
                  text: ': $ket',
                  style: TextStyle(color: warnaKet ?? m.ink600)),
            ]),
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
        );

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(MasRadii.sheet)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: m.ink200, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kosong ? m.warn50 : m.brand50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                      kosong
                          ? Icons.remove_shopping_cart_outlined
                          : Icons.shopping_cart_checkout_rounded,
                      size: 19,
                      color: kosong ? m.warn600 : m.brand700),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    kosong
                        ? 'Semua barang di pesanan ini sedang tidak tersedia'
                        : '$dimasukkan barang dimasukkan ke keranjang',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: m.ink900),
                  ),
                ),
              ]),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (takBisa.isNotEmpty) ...[
                        judulBagian(
                            kosong
                                ? 'Tidak bisa dibeli saat ini'
                                : 'Tidak dimasukkan (${takBisa.length})',
                            Icons.block_rounded,
                            m.danger600),
                        for (final it in takBisa)
                          baris(it.judul,
                              it.alasan.isNotEmpty ? it.alasan : 'tidak tersedia',
                              warnaKet: m.danger600),
                      ],
                      if (disesuaikan.isNotEmpty) ...[
                        judulBagian('Jumlah disesuaikan stok',
                            Icons.inventory_2_outlined, m.warn600),
                        for (final it in disesuaikan)
                          baris(it.judul,
                              'jumlah disesuaikan jadi ${it.qty} (sisa stok)'),
                      ],
                      if (berubah.isNotEmpty) ...[
                        judulBagian('Harga berubah sejak dulu dibeli',
                            Icons.sell_outlined, m.info600),
                        for (final it in berubah)
                          baris(
                              it.judul,
                              '${it.selisihHarga < 0 ? 'turun' : 'naik'} '
                              '${formatRupiah(it.selisihHarga.abs())} '
                              '(kini ${it.hargaDisplay.isNotEmpty ? it.hargaDisplay : formatRupiah(it.harga)})',
                              warnaKet:
                                  it.selisihHarga < 0 ? m.brand700 : m.warn600),
                      ],
                      if (!kosong) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Harga di keranjang akan dicek ulang sebelum checkout.',
                          style: TextStyle(fontSize: 11.5, color: m.ink500),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              MasButton(
                label: kosong ? 'Tutup' : 'Lihat Keranjang',
                icon: kosong ? null : Icons.shopping_cart_outlined,
                primary: !kosong,
                expand: true,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
