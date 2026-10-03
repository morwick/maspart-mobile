// lib/screens/keranjang_screen.dart
// Keranjang ala Shopee — cerminan `frontend/src/app/keranjang/page.tsx`.
//
// Masukan pemilik 2026-10-03: layar ini HANYA daftar belanja — centang part,
// ubah jumlah, hapus — lalu tombol Checkout membawa part yang DICENTANG ke
// layar Checkout (checkout_screen: alamat, ekspedisi, voucher, bayar).
//
// Aturan pemilik tetap: SATU pesanan = SATU gudang (kurir tak bisa mengirim satu
// paket dari dua kota). Karena itu part dikelompokkan per gudang (pengganti
// "toko" di Shopee) dan centang hanya boleh dari satu gudang sekaligus —
// mencentang part gudang lain melepas centang gudang sebelumnya, dengan pesan.
//
// Harga, stok, dan gudang yang tampil selalu dari SERVER (`/api/cart/gudang`);
// harga yang tersimpan di perangkat hanya pengisi selagi memuat. Checkout tetap
// menghitung ulang semuanya — angka di sini perkiraan sebelum PPN & ongkir.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../cart.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/alamat_form.dart';
import '../widgets/foto_part.dart';
import '../widgets/mas_ui.dart';
import 'part_detail_screen.dart' show ProdukSerupaSection;

/// Kunci kelompok untuk part yang gudangnya belum diketahui (memuat / tanpa alamat).
const _kTanpaGudang = '';

/// Lebar kolom centang — baris harga/qty/total menjorok sejauh ini.
const double _kLebarCek = 40;

class KeranjangScreen extends StatefulWidget {
  const KeranjangScreen({super.key});

  @override
  State<KeranjangScreen> createState() => _KeranjangScreenState();
}

class _KeranjangScreenState extends State<KeranjangScreen> {
  final _cart = CartStore.instance;

  /// Alamat profil menentukan gudang acuan (harga, stok) — tanpa alamat, server
  /// menolak /cart/gudang (409). Alamat pertama bisa disimpan lewat lembar di sini.
  /// 'gagal' = daftar alamat tak terbaca → tetap coba ambil harga.
  String _alamatStatus = 'muat'; // muat | ok | kosong | gagal
  List<Alamat> _alamatList = [];

  /// Keadaan server untuk SELURUH isi keranjang (harga, gudang, stok, foto).
  CartGudang? _asal;
  String? _asalErr;

  /// Pesan info (mis. centang gudang lain dilepas).
  String? _info;

  /// PN yang strip "Produk Serupa"-nya sedang dibuka.
  String? _serupaBuka;

  // Debounce 400 ms: tombol +/− yang ditekan beruntun cukup satu permintaan
  // (endpoint dibatasi 60/menit).
  Timer? _debounce;
  String _sigDiminta = '';
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCartChanged);
    _muatAlamat();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cart.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() {
    if (!mounted) return;
    setState(() {});
    _jadwalAsal();
  }

  Future<void> _muatAlamat() async {
    try {
      final list = await ApiService.listAlamat();
      if (!mounted) return;
      setState(() {
        _alamatList = list;
        _alamatStatus = list.isEmpty ? 'kosong' : 'ok';
      });
    } catch (_) {
      // Fitur alamat belum aktif / offline → tetap coba harga.
      if (mounted) setState(() => _alamatStatus = 'gagal');
    }
    _jadwalAsal(paksa: true);
  }

  /// Tanda tangan isi keranjang (PN×qty) — centang saja tak memicu permintaan.
  String get _cartSig =>
      _cart.items.map((i) => '${i.partNumber}:${i.qty}').join(',');

  /// Jadwalkan pembacaan keadaan server bila isi keranjang berubah.
  /// [paksa] = abaikan tanda tangan (Coba lagi / alamat baru tersimpan).
  void _jadwalAsal({bool paksa = false}) {
    final sig = _cartSig;
    if (!paksa && sig == _sigDiminta) return;
    _debounce?.cancel();
    if (_cart.isEmpty || _alamatStatus == 'muat' || _alamatStatus == 'kosong') {
      // Belum bisa bertanya ke server — tanda tangan dikosongkan supaya
      // perubahan berikutnya (atau alamat tersimpan) tetap memicu permintaan.
      _sigDiminta = '';
      return;
    }
    _sigDiminta = sig;
    _debounce = Timer(const Duration(milliseconds: 400), _muatAsal);
  }

  Future<void> _muatAsal() async {
    final items = _cart.items;
    if (items.isEmpty || !mounted) return;
    final id = ++_req;
    setState(() => _asalErr = null);
    try {
      final r = await ApiService.cartGudang(
        [for (final i in items) CartLine(partNumber: i.partNumber, qty: i.qty)],
      );
      if (!mounted || id != _req) return;
      setState(() => _asal = r);
    } catch (e) {
      if (!mounted || id != _req) return;
      setState(() => _asalErr = e is ApiException && e.message.isNotEmpty
          ? e.message
          : 'Gagal memuat harga terkini');
    }
  }

  // ── Turunan keadaan ─────────────────────────────────────────────────

  CartGudangItem? _srv(String pn) => _asal?.forPn(pn);

  /// Harga server bila sudah tiba; harga lokal hanya pengisi selagi memuat.
  int _hargaOf(CartItem i) =>
      _srv(i.partNumber)?.harga.round() ?? priceToNum(i.harga);

  String _gudangOf(String pn) => _srv(pn)?.gudang ?? _kTanpaGudang;

  /// Boleh dicentang: belum ada data server (checkout yang memeriksa), atau
  /// server bilang bisa dibeli — termasuk yang hanya bisa lewat Ambil di Toko.
  bool _bisaPilih(CartItem i) {
    final s = _srv(i.partNumber);
    return s == null || s.bisaDibeli || s.hanyaAmbil;
  }

  List<String> _bisaDipilih(List<CartItem> list) =>
      [for (final i in list) if (_bisaPilih(i)) i.partNumber];

  bool _semuaTercentang(List<CartItem> list, Set<String> pilihSet) {
    final b = _bisaDipilih(list);
    return b.isNotEmpty && b.every(pilihSet.contains);
  }

  // ── Aksi ────────────────────────────────────────────────────────────

  /// Ganti centang sekelompok PN. Menambah dari gudang LAIN melepas centang
  /// gudang sebelumnya (satu pesanan = satu gudang) — pembeli diberi tahu,
  /// tak diam-diam.
  void _centang(List<String> pns, bool nyala) {
    final pilih = _cart.pilihan;
    if (!nyala) {
      final buang = pns.toSet();
      _cart.setPilihan(pilih.where((p) => !buang.contains(p)));
      return;
    }
    final gBaru = pns.map(_gudangOf).where((g) => g.isNotEmpty).toSet();
    var dasar = pilih;
    if (gBaru.length == 1) {
      final g = gBaru.first;
      final lepas = pilih.where((p) {
        final gp = _gudangOf(p);
        return gp.isNotEmpty && gp != g;
      }).toList();
      if (lepas.isNotEmpty) {
        final gLama = lepas.map(_gudangOf).toSet().join(', ');
        setState(() => _info =
            'Satu pesanan hanya dari satu gudang — centang Gudang $gLama dilepas, '
            'sekarang memilih Gudang $g. Part gudang lain tetap di keranjang untuk '
            'pesanan berikutnya.');
        final buang = lepas.toSet();
        dasar = pilih.where((p) => !buang.contains(p)).toList();
      } else {
        setState(() => _info = null);
      }
    }
    _cart.setPilihan({...dasar, ...pns});
  }

  /// Jangan lewati stok yang diketahui; kosong/nol/negatif → 1 (normQty).
  void _ubahQty(CartItem i, int q) {
    final stok = _srv(i.partNumber)?.stok ?? 0;
    final n = normQty(q);
    _cart.setQty(i.partNumber, stok > 0 && n > stok ? stok : n);
  }

  Future<void> _hapusTerpilih(List<CartItem> terpilih) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus dari keranjang?'),
        content: Text('Hapus ${terpilih.length} part terpilih dari keranjang?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) await _cart.removeAll(terpilih.map((i) => i.partNumber));
  }

  void _checkout(List<CartItem> terpilih, List<String> gudangTerpilih) {
    if (terpilih.isEmpty) {
      setState(() => _info = 'Centang dulu part yang mau di-checkout.');
      return;
    }
    if (gudangTerpilih.length > 1) {
      setState(() => _info = 'Part yang dicentang berasal dari lebih dari satu '
          'gudang — checkout satu gudang dulu.');
      return;
    }
    // Simpan centang EFEKTIF (yang masih boleh dibeli) — itu yang dibaca Checkout.
    _cart.setPilihan(terpilih.map((i) => i.partNumber));
    AppNav.of(context).go(MasScreen.checkout);
  }

  /// Lembar "Tambah Alamat" yang sama dengan Checkout (alamat pertama otomatis
  /// jadi alamat utama).
  Future<void> _tambahAlamat() async {
    final hasil = await tampilkanTambahAlamat(
      context,
      pertama: _alamatList.isEmpty,
      sebelum: {for (final a in _alamatList) a.id},
    );
    if (hasil == null || !mounted) return;
    setState(() {
      _alamatList = hasil.list;
      _alamatStatus = 'ok';
    });
    // Gudang acuan baru diketahui → harga/stok dihitung ulang.
    _jadwalAsal(paksa: true);
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final items = _cart.items;

    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const SizedBox(height: 40),
          MasEmpty(
            icon: Icons.shopping_cart_outlined,
            title: 'Keranjang belanja Anda kosong.',
            subtitle: 'Cari part di etalase, lalu tekan + Keranjang.',
            action: MasButton(
              label: 'Belanja Part',
              icon: Icons.storefront_outlined,
              onTap: () => nav.go(MasScreen.toko),
            ),
          ),
        ],
      );
    }

    // Kelompok per gudang, urutan = kemunculan pertama di keranjang.
    final kelompok = <String, List<CartItem>>{};
    for (final i in items) {
      kelompok.putIfAbsent(_gudangOf(i.partNumber), () => []).add(i);
    }
    final gudangDikenal = kelompok.keys.where((g) => g.isNotEmpty).toList();
    final multiGudang = gudangDikenal.length > 1;

    // Centang EFEKTIF: part yang masih ada & masih boleh dibeli. Part yang
    // berubah jadi tak bisa dibeli (stok habis dsb.) otomatis lepas dari total.
    final pilihSet = _cart.pilihan.toSet();
    final terpilih = items
        .where((i) => pilihSet.contains(i.partNumber) && _bisaPilih(i))
        .toList();
    final gudangTerpilih = terpilih
        .map((i) => _gudangOf(i.partNumber))
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList();
    final totalBarang =
        terpilih.fold<int>(0, (n, i) => n + _hargaOf(i) * i.qty);
    final totalQty = terpilih.fold<int>(0, (n, i) => n + i.qty);
    final adaHarga0 = terpilih.any((i) => _hargaOf(i) <= 0);

    // "Pilih Semua" hanya bermakna bila semua part dari satu gudang.
    final semuaBisa = _bisaDipilih(items);
    final pilihSemuaAktif = !multiGudang && semuaBisa.isNotEmpty;

    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          children: [
            if (_alamatStatus == 'kosong') ...[
              _banner(
                m,
                'Tambah alamat pengiriman dulu — gudang terdekat, harga, dan stok '
                'dihitung dari alamat itu.',
                aksi: MasButton(
                  label: 'Tambah Alamat',
                  icon: Icons.add_location_alt_outlined,
                  height: 36,
                  onTap: _tambahAlamat,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_asalErr != null) ...[
              _banner(
                m,
                'Gagal memuat harga & stok terkini ($_asalErr). Harga di bawah '
                'bisa sudah berubah.',
                aksi: MasButton(
                  label: 'Coba lagi',
                  icon: Icons.refresh_rounded,
                  primary: false,
                  height: 36,
                  onTap: () => _jadwalAsal(paksa: true),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_info != null) ...[
              _infoBar(m, _info!),
              const SizedBox(height: 12),
            ],
            for (final e in kelompok.entries) ...[
              _grup(m, e.key, e.value, pilihSet),
              const SizedBox(height: 12),
            ],
            if (multiGudang)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(Icons.inventory_2_outlined, size: 14, color: m.ink500),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Keranjang berisi part dari ${gudangDikenal.length} gudang. Satu '
                      'pesanan hanya bisa dari satu gudang — checkout bergantian, part '
                      'gudang lain tetap tersimpan.',
                      style: TextStyle(fontSize: 12, color: m.ink500, height: 1.45),
                    ),
                  ),
                ]),
              ),
          ],
        ),
      ),
      _footer(
        m,
        items: items,
        pilihSet: pilihSet,
        terpilih: terpilih,
        gudangTerpilih: gudangTerpilih,
        totalBarang: totalBarang,
        totalQty: totalQty,
        adaHarga0: adaHarga0,
        multiGudang: multiGudang,
        semuaBisa: semuaBisa,
        pilihSemuaAktif: pilihSemuaAktif,
      ),
    ]);
  }

  Widget _banner(MasColors m, String pesan, {required Widget aksi}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: m.danger50,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border.all(color: m.dangerBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pesan,
              style: TextStyle(fontSize: 12.5, color: m.danger600, height: 1.45)),
          const SizedBox(height: 10),
          aksi,
        ]),
      );

  Widget _infoBar(MasColors m, String pesan) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: m.brand50,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border.all(color: m.brand100),
        ),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, size: 16, color: m.brand700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(pesan,
                style: TextStyle(fontSize: 12.5, color: m.ink700, height: 1.45)),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: m.ink500),
            tooltip: 'Tutup',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _info = null),
          ),
        ]),
      );

  Widget _cek(MasColors m,
          {required bool value, required ValueChanged<bool>? onChanged}) =>
      SizedBox(
        width: _kLebarCek,
        height: 40,
        child: Checkbox(
          value: value,
          onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
          activeColor: m.brand600,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );

  /// Satu kartu gudang: kepala (centang semua + nama gudang) + baris part.
  Widget _grup(MasColors m, String g, List<CartItem> list, Set<String> pilihSet) {
    final b = _bisaDipilih(list);
    final label = g.isNotEmpty
        ? 'Gudang $g'
        : (_asal != null || _asalErr != null || _alamatStatus == 'kosong')
            ? 'Gudang belum tersedia'
            : 'Memuat gudang…';
    return Container(
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.ink150),
        boxShadow: m.shadow1,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: m.ink150)),
          ),
          child: Row(children: [
            _cek(
              m,
              value: _semuaTercentang(list, pilihSet),
              onChanged: b.isEmpty ? null : (v) => _centang(b, v),
            ),
            Icon(Icons.warehouse_outlined, size: 17, color: m.brand700),
            const SizedBox(width: 7),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: m.ink900)),
            ),
            Text('${list.length} part',
                style: TextStyle(fontSize: 12, color: m.ink500)),
          ]),
        ),
        for (var k = 0; k < list.length; k++) ...[
          if (k > 0) Divider(height: 1, thickness: 1, color: m.ink150),
          _baris(m, list[k], pilihSet),
        ],
      ]),
    );
  }

  /// Pil peringatan yang boleh turun baris (alasan server bisa panjang).
  Widget _pilWarn(MasColors m, String teks) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: m.warn50,
          borderRadius: BorderRadius.circular(MasRadii.chip),
          border: Border.all(color: m.warnBorder),
        ),
        child: Text(teks,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: m.warn600)),
      );

  Widget _baris(MasColors m, CartItem i, Set<String> pilihSet) {
    final nav = AppNav.of(context);
    final s = _srv(i.partNumber);
    final boleh = _bisaPilih(i);
    final cek = boleh && pilihSet.contains(i.partNumber);
    final stok = s?.stok ?? 0;
    final harga = _hargaOf(i);
    final redup = boleh ? 1.0 : 0.55;
    final serupa = _serupaBuka == i.partNumber;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 12, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Centang + foto + nama/PN (ketuk → detail part).
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _cek(
                m,
                value: cek,
                onChanged: boleh ? (v) => _centang([i.partNumber], v) : null,
              ),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => nav.go(MasScreen.part, part: {
                  'part_number': i.partNumber,
                  'part_name': i.name,
                }),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Opacity(opacity: redup, child: FotoPart(foto: s?.foto)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Opacity(
                          opacity: redup,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(i.name.isNotEmpty ? i.name : i.partNumber,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      height: 1.35,
                                      color: m.ink900)),
                              const SizedBox(height: 2),
                              Text(i.partNumber,
                                  style: masMono(size: 11.5, color: m.ink500)),
                            ],
                          ),
                        ),
                        if (!boleh)
                          _pilWarn(m, s?.alasan.isNotEmpty == true
                              ? s!.alasan
                              : 'belum bisa dibeli'),
                        if (boleh && (s?.hanyaAmbil ?? false))
                          _pilWarn(m, 'Hanya Ambil di Toko'),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ]),
          // Harga satuan + kuantitas.
          Padding(
            padding: const EdgeInsets.only(left: _kLebarCek, top: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Opacity(
                  opacity: redup,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Harga', style: TextStyle(fontSize: 11, color: m.ink500)),
                      Text(harga > 0 ? formatRupiah(harga) : '—',
                          style: masMono(size: 12.5, color: m.ink700)),
                    ],
                  ),
                ),
              ),
              _qtyKolom(m, i, stok),
            ]),
          ),
          // Total baris + aksi.
          Padding(
            padding: const EdgeInsets.only(left: _kLebarCek, top: 6),
            child: Row(children: [
              Expanded(
                child: Opacity(
                  opacity: redup,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total', style: TextStyle(fontSize: 11, color: m.ink500)),
                      Text(formatRupiah(harga * i.qty),
                          style: masMono(
                              size: 14,
                              weight: FontWeight.w700,
                              color: m.brand700)),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _cart.remove(i.partNumber),
                style: TextButton.styleFrom(
                  foregroundColor: m.ink800,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Hapus', style: TextStyle(fontSize: 12.5)),
              ),
              TextButton(
                onPressed: () => setState(
                    () => _serupaBuka = serupa ? null : i.partNumber),
                style: TextButton.styleFrom(
                  foregroundColor: m.brand700,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Produk Serupa', style: TextStyle(fontSize: 12.5)),
                  Icon(serupa ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18),
                ]),
              ),
            ]),
          ),
        ]),
      ),
      if (serupa)
        Container(
          color: m.ink50,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ProdukSerupaSection(
              key: ValueKey('serupa-krj-${i.partNumber}'), pn: i.partNumber),
        ),
    ]);
  }

  /// Stepper − [ketik] + (KL-14: bilangan bulat 1..99.999, dipangkas ke stok
  /// yang diketahui) + "Jadikan N" bila qty > stok / "Sisa N" bila stok tipis.
  Widget _qtyKolom(MasColors m, CartItem i, int stok) {
    final maks = stok > 0 && stok < kQtyMaks ? stok : kQtyMaks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: m.paper,
            borderRadius: BorderRadius.circular(MasRadii.input),
            border: Border.all(color: m.ink200),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _stepBtn(m, Icons.remove_rounded,
                i.qty <= 1 ? null : () => _ubahQty(i, i.qty - 1)),
            Container(
              width: 52,
              height: 32,
              decoration: BoxDecoration(
                border: Border.symmetric(
                    vertical: BorderSide(color: m.ink200)),
              ),
              child: _QtyInput(
                key: ValueKey('qty-${i.partNumber}'),
                qty: i.qty,
                onChanged: (q) => _ubahQty(i, q),
              ),
            ),
            _stepBtn(m, Icons.add_rounded,
                i.qty >= maks ? null : () => _ubahQty(i, i.qty + 1)),
          ]),
        ),
        if (stok > 0 && i.qty > stok)
          TextButton(
            onPressed: () => _ubahQty(i, stok),
            style: TextButton.styleFrom(
              foregroundColor: m.brand700,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 28),
            ),
            child: Text('Jadikan $stok', style: const TextStyle(fontSize: 12)),
          )
        else if (stok > 0 && stok <= 10)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Sisa $stok',
                style: TextStyle(fontSize: 11.5, color: m.warn600)),
          ),
      ],
    );
  }

  Widget _stepBtn(MasColors m, IconData icon, VoidCallback? onTap) => SizedBox(
        width: 32,
        height: 32,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon, size: 16, color: onTap == null ? m.ink300 : m.ink700),
        ),
      );

  /// Bilah bawah menempel (ala Shopee): Pilih Semua, Hapus, Total, Checkout.
  Widget _footer(
    MasColors m, {
    required List<CartItem> items,
    required Set<String> pilihSet,
    required List<CartItem> terpilih,
    required List<String> gudangTerpilih,
    required int totalBarang,
    required int totalQty,
    required bool adaHarga0,
    required bool multiGudang,
    required List<String> semuaBisa,
    required bool pilihSemuaAktif,
  }) {
    final n = terpilih.length;
    return Container(
      decoration: BoxDecoration(
        color: m.paper,
        border: Border(top: BorderSide(color: m.ink150)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: m.isDark ? 0.3 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(4, 2, 12, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          _cek(
            m,
            value: pilihSemuaAktif && _semuaTercentang(items, pilihSet),
            onChanged: pilihSemuaAktif ? (v) => _centang(semuaBisa, v) : null,
          ),
          Expanded(
            child: Text(
              multiGudang ? 'Pilih per gudang' : 'Pilih Semua (${items.length})',
              style: TextStyle(
                  fontSize: 13,
                  color: pilihSemuaAktif ? m.ink800 : m.ink500),
            ),
          ),
          TextButton(
            onPressed: n == 0 ? null : () => _hapusTerpilih(terpilih),
            style: TextButton.styleFrom(
              foregroundColor: m.danger600,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Hapus', style: TextStyle(fontSize: 13)),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total ($n produk${totalQty != n ? ', $totalQty pcs' : ''})',
                    style: TextStyle(fontSize: 12, color: m.ink600),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(formatRupiah(totalBarang),
                        style: masMono(
                            size: 18,
                            weight: FontWeight.w700,
                            color: m.brand700)),
                  ),
                  Text(
                    adaHarga0
                        ? 'Ada part tanpa harga — dicek saat checkout'
                        : 'Belum termasuk PPN & ongkir',
                    style: TextStyle(fontSize: 11, color: m.ink500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            MasButton(
              label: n > 0 ? 'Checkout ($n)' : 'Checkout',
              icon: Icons.shopping_cart_checkout_rounded,
              onTap: n == 0 ? null : () => _checkout(terpilih, gudangTerpilih),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Kotak angka di tengah stepper qty. Mengetik langsung mengubah keranjang
/// (bila angkanya sah); kotak kosong dibiarkan selama diketik dan kembali ke
/// qty keranjang saat fokus lepas — supaya menghapus angka tak langsung jadi 1.
class _QtyInput extends StatefulWidget {
  final int qty;
  final ValueChanged<int> onChanged;

  const _QtyInput({super.key, required this.qty, required this.onChanged});

  @override
  State<_QtyInput> createState() => _QtyInputState();
}

class _QtyInputState extends State<_QtyInput> {
  late final TextEditingController _ctl =
      TextEditingController(text: '${widget.qty}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _sinkron();
    });
  }

  @override
  void didUpdateWidget(covariant _QtyInput old) {
    super.didUpdateWidget(old);
    // Qty berubah dari luar (+/−, dipangkas stok, "Jadikan N") → kotak ikut.
    // Kotak yang sedang dikosongkan pembeli dibiarkan sampai fokus lepas.
    final n = int.tryParse(_ctl.text);
    if (n != widget.qty && (n != null || !_focus.hasFocus)) _sinkron();
  }

  void _sinkron() {
    final t = '${widget.qty}';
    if (_ctl.text == t) return;
    _ctl.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Center(
      child: TextField(
        controller: _ctl,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        // KL-14: hanya digit (tanpa titik/koma/minus), maks 5 digit = 99.999.
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        style: masMono(size: 13, weight: FontWeight.w700, color: m.ink900),
        cursorColor: m.brand600,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (t) {
          final n = int.tryParse(t);
          if (n != null) widget.onChanged(n);
        },
        onSubmitted: (_) => _sinkron(),
        onTapOutside: (_) => _focus.unfocus(),
      ),
    );
  }
}
