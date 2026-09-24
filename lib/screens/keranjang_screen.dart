// lib/screens/keranjang_screen.dart
// Keranjang + checkout pembeli — cerminan `frontend/src/app/keranjang/page.tsx`.
//
// Tiga aturan yang menentukan benar/salahnya tagihan, jangan diubah tanpa
// mengubah backend juga:
//
// 1. KEADAAN SERVER MENANG. Keranjang lokal menyimpan harga saat part
//    dimasukkan — bisa basi. `ApiService.cartGudang()` adalah kebenaran:
//    harga yang ditagih, gudang pengirim, dan boleh-tidaknya part dibeli.
// 2. SATU PESANAN = SATU GUDANG. Kurir tak bisa mengirim satu paket dari dua
//    kota. Keranjang boleh lintas gudang, tapi checkout hanya untuk gudang
//    terpilih; sisanya TETAP di keranjang untuk pesanan berikutnya.
// 3. PPN 12% INKLUSIF. Harga Accurate sudah mengandung PPN → total = barang +
//    ongkir. PPN hanya ditampilkan sebagai komponen, bukan tambahan.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../cart.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/voucher_tiket.dart';
import '../widgets/mas_ui.dart';
import 'pilih_lokasi_screen.dart';

class KeranjangScreen extends StatefulWidget {
  const KeranjangScreen({super.key});

  @override
  State<KeranjangScreen> createState() => _KeranjangScreenState();
}

class _KeranjangScreenState extends State<KeranjangScreen> {
  final _cart = CartStore.instance;

  final _nameCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _addressCtl = TextEditingController();
  final _postalCtl = TextEditingController();
  final _noteCtl = TextEditingController();

  /// Alamat tersimpan di Profil (paritas web): alamat utama mengisi form, >1
  /// alamat → pilihan "Kirim ke". Kosong bila fitur profil belum aktif.
  List<Alamat> _alamatList = [];
  int? _alamatId;

  /// Titik peta penerima (dari alamat tersimpan / peta) — ikut dikirim ke cek
  /// Ambil di Toko supaya jarak dihitung dari titik, bukan tebakan kode pos.
  double? _lat;
  double? _lon;

  /// Keadaan server untuk isi keranjang (harga, gudang, bisa dibeli).
  CartGudang? _asal;

  /// Gudang yang dipilih untuk checkout kali ini.
  String _gudangPilih = '';

  int _weightGrams = 0;

  /// Berat dus + isian + bungkus yang ikut ditimbang kurir — ditampilkan
  /// terpisah supaya pembeli tak menyangka beratnya salah hitung.
  int _packingGrams = 0;
  List<ShippingRate> _rates = [];
  ShippingRate? _rate;
  String? _rateErr;
  bool _loadingRates = false;

  /// Ambil di Toko — hanya ditawarkan bila SERVER bilang alamat ini dekat gudang
  /// pemenuh (jarak + izin gudang dihitung di sana, dihitung ULANG saat order).
  PickupInfo? _pickup;
  bool _ambilSendiri = false;

  bool _gatewayOn = false;
  bool _busy = false;
  String? _error;

  Timer? _ongkirDebounce;
  Timer? _pickupDebounce;

  /// Tanda tangan isi keranjang & gudang aktif — dipakai untuk tahu kapan
  /// perlu ambil ulang berat/ongkir, supaya tidak menembak server tiap rebuild.
  String _lastBeliSig = '';

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCartChanged);
    _prefillAddress();
    _loadGateway();
    _refreshServerState();
  }

  @override
  void dispose() {
    _ongkirDebounce?.cancel();
    _pickupDebounce?.cancel();
    _cart.removeListener(_onCartChanged);
    _nameCtl.dispose();
    _phoneCtl.dispose();
    _addressCtl.dispose();
    _postalCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (!mounted) return;
    setState(() {});
    _refreshServerState();
  }

  Future<void> _prefillAddress() async {
    final a = await _cart.loadAddress();
    if (!mounted) return;
    setState(() {
      _nameCtl.text = a.name;
      _phoneCtl.text = a.phone;
      _addressCtl.text = a.address;
      _postalCtl.text = a.postal;
    });
    _scheduleOngkir();
    // Alamat profil menang atas prefill lokal (sumber yang dikelola pembeli
    // sendiri di Profil). Gagal/503 pra-migrasi → diam, pakai prefill.
    try {
      final list = await ApiService.listAlamat();
      if (!mounted) return;
      setState(() => _alamatList = list);
      Alamat? utama;
      for (final x in list) {
        if (x.isDefault) utama = x;
      }
      utama ??= list.isNotEmpty ? list.first : null;
      if (utama != null) _pakaiAlamat(utama);
    } catch (_) {
      /* fitur profil belum aktif / offline */
    }
  }

  void _pakaiAlamat(Alamat a) {
    setState(() {
      _alamatId = a.id;
      _nameCtl.text = a.namaPenerima;
      _phoneCtl.text = a.telepon;
      _addressCtl.text = [a.alamat, a.kecamatan, a.kota, a.provinsi]
          .where((e) => e.isNotEmpty)
          .join(', ');
      _postalCtl.text = a.kodePos;
      _lat = a.lat;
      _lon = a.lng;
      _rates = [];
      _rate = null;
    });
    _scheduleOngkir();
  }

  Future<void> _loadGateway() async {
    try {
      final m = await ApiService.paymentMethods();
      if (mounted) setState(() => _gatewayOn = m.gatewayAvailable);
    } on ApiException {
      if (mounted) setState(() => _gatewayOn = false);
    }
  }

  /// Segarkan keadaan tiap item dari server, lalu hitung ulang berat + ongkir.
  Future<void> _refreshServerState() async {
    final items = _cart.items;
    if (items.isEmpty) {
      setState(() {
        _asal = null;
        _weightGrams = 0;
        _packingGrams = 0;
        _rates = [];
        _rate = null;
      });
      return;
    }
    try {
      final r = await ApiService.cartGudang(
        [for (final i in items) CartLine(partNumber: i.partNumber, qty: i.qty)],
      );
      if (!mounted) return;
      setState(() => _asal = r);
      await _refreshWeight();
      // Batas poin bergantung harga barang keranjang → ikut disegarkan setiap
      // keadaan server berubah (harga/stok/gudang bisa bergeser).
      await _refreshPoin();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Tanpa keadaan server kita tak boleh menebak harga → tampilkan errornya.
      setState(() {
        _asal = null;
        _error = e.isAuth ? e.message : null;
      });
    }
  }

  /// Berat KIRIM hanya untuk item gudang terpilih (yang benar-benar dipesan).
  Future<void> _refreshWeight() async {
    final beli = _itemsBeli;
    if (beli.isEmpty) {
      setState(() {
        _weightGrams = 0;
        _packingGrams = 0;
      });
      return;
    }
    final sig = beli.map((i) => '${i.partNumber}:${i.qty}').join(',');
    if (sig == _lastBeliSig && _weightGrams > 0) return;
    _lastBeliSig = sig;

    // Estimasi sementara (1 kg/item) supaya UI langsung punya angka, lalu
    // dipertajam berat sesungguhnya dari SIMS via backend.
    final perkiraan = beli.fold<int>(0, (n, i) => n + i.qty) * 1000;
    setState(() {
      _weightGrams = perkiraan < 1000 ? 1000 : perkiraan;
      // Angka kemasan keranjang LAMA tak boleh nyangkut di layar sampai jawaban
      // server datang — lebih baik tak tampil daripada tampil salah.
      _packingGrams = 0;
      // Berat berubah → ongkir lama tak berlaku lagi.
      _rates = [];
      _rate = null;
      _rateErr = null;
    });

    try {
      final w = await ApiService.cartWeight(
        [for (final i in beli) CartLine(partNumber: i.partNumber, qty: i.qty)],
      );
      if (!mounted) return;
      setState(() {
        _weightGrams = w.weightGrams;
        _packingGrams = w.packingGrams;
      });
    } on ApiException {
      /* pakai estimasi — pembeli tetap bisa cek ongkir manual */
    }
    _scheduleOngkir();
  }

  /// Ongkir dihitung OTOMATIS begitu alamat (kode pos) & berat siap. Dulu
  /// pembeli harus ingat menekan "Cek Ongkir"; yang lupa membuat order tanpa
  /// kurir. Debounce 900 ms supaya tak menembak tiap ketikan.
  void _scheduleOngkir() {
    _ongkirDebounce?.cancel();
    if (_itemsBeli.isNotEmpty &&
        _weightGrams > 0 &&
        _postalCtl.text.trim().length >= 5) {
      _ongkirDebounce =
          Timer(const Duration(milliseconds: 900), () => _cekOngkir());
    }
    _schedulePickup();
  }

  /// Jadwalkan cek Ambil di Toko saja (dipanggil juga saat alamat diketik —
  /// tanpa ikut mengambil ulang tarif kurir).
  void _schedulePickup() {
    _pickupDebounce?.cancel();
    if (!mounted) return;
    // Ambil di Toko punya syarat SENDIRI (paritas web): cukup titik peta ATAU
    // alamat terisi — kode pos belum 5 digit tak boleh menahan cek jarak.
    // Syarat tak terpenuhi → info lama dibuang, jangan nyangkut di layar.
    final bisaCekPickup = _itemsBeli.isNotEmpty &&
        ((_lat != null && _lon != null) ||
            _postalCtl.text.trim().length >= 5 ||
            _addressCtl.text.trim().isNotEmpty);
    if (!bisaCekPickup) {
      if (_pickup != null || _ambilSendiri) {
        setState(() {
          _pickup = null;
          _ambilSendiri = false;
        });
      }
      return;
    }
    _pickupDebounce =
        Timer(const Duration(milliseconds: 900), () => _cekAmbilSendiri());
  }

  /// Kelayakan ambil di toko: ikut isi keranjang (gudang pemenuh bisa berpindah)
  /// dan ikut kode pos alamat.
  Future<void> _cekAmbilSendiri() async {
    final beli = _itemsBeli;
    if (beli.isEmpty) return;
    try {
      final p = await ApiService.shippingPickup(
        items: [
          for (final i in beli) CartLine(partNumber: i.partNumber, qty: i.qty),
        ],
        destPostal: _postalCtl.text.trim(),
        lat: _lat,
        lon: _lon,
        alamat: _addressCtl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _pickup = p;
        // Pilihan ambil sendiri TAK BOLEH bertahan saat syaratnya hilang (ganti
        // alamat jauh / tambah part dari gudang lain) — kalau dibiarkan,
        // checkout ditolak server dengan alasan yang tak terlihat di layar.
        if (!p.tersedia) _ambilSendiri = false;
      });
    } on ApiException {
      if (mounted) setState(() => _pickup = null);
    }
  }

  Future<void> _cekOngkir() async {
    final beli = _itemsBeli;
    if (beli.isEmpty || _weightGrams <= 0) return;

    setState(() {
      _loadingRates = true;
      _rateErr = null;
      _rates = [];
      _rate = null;
    });

    try {
      final r = await ApiService.shippingRates(
        weightGrams: _weightGrams,
        value: _subtotal.toDouble(),
        destPostal: _postalCtl.text.trim(),
        items: [
          for (final i in beli) CartLine(partNumber: i.partNumber, qty: i.qty),
        ],
      );
      if (!mounted) return;
      final sorted = [...r.rates]..sort((a, b) => a.price.compareTo(b.price));
      setState(() {
        _rateErr = r.error;
        _rates = r.rates;
        // Termurah jadi default supaya pembeli tak checkout tanpa kurir karena
        // lupa memilih; dia tetap bebas mengganti.
        _rate = sorted.isNotEmpty ? sorted.first : null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _rateErr = e.message);
    } finally {
      if (mounted) setState(() => _loadingRates = false);
    }
  }

  // ── Turunan keadaan ─────────────────────────────────────────────────

  CartGudangItem? _srv(String pn) => _asal?.forPn(pn);

  String _gudangOf(String pn) => _srv(pn)?.gudang ?? '';

  /// Harga yang AKAN DITAGIH. Server menang; harga lokal cuma dipakai selagi
  /// keadaan server belum tiba supaya angka tidak berkedip jadi nol.
  int _hargaOf(CartItem i) =>
      _srv(i.partNumber)?.harga.round() ?? priceToNum(i.harga);

  bool _bisaBeli(CartItem i) =>
      _srv(i.partNumber)?.bisaDibeli ??
      (hasPrice(i.harga) && hasWeight(i.berat));

  List<String> get _gudangList => _cart.items
      .map((i) => _gudangOf(i.partNumber))
      .where((g) => g.isNotEmpty)
      .toSet()
      .toList();

  String get _gudangAktif {
    final list = _gudangList;
    if (_gudangPilih.isNotEmpty && list.contains(_gudangPilih)) {
      return _gudangPilih;
    }
    final utama = _asal?.utama ?? '';
    if (utama.isNotEmpty && list.contains(utama)) return utama;
    return list.isNotEmpty ? list.first : '';
  }

  bool get _lintasGudang => _gudangList.length > 1;

  /// Item yang ikut checkout kali ini. Item gudang lain DITAHAN, bukan dihapus.
  List<CartItem> get _itemsBeli {
    final g = _gudangAktif;
    if (g.isEmpty) return _cart.items;
    return _cart.items.where((i) => _gudangOf(i.partNumber) == g).toList();
  }

  /// Part yang tak bisa dibeli (harga/berat/stok) → blokir checkout.
  List<CartItem> get _blokir =>
      _cart.items.where((i) => !_bisaBeli(i)).toList();

  int get _subtotal =>
      _itemsBeli.fold(0, (n, i) => n + _hargaOf(i) * i.qty);

  // ── Voucher ─────────────────────────────────────────────────────────
  // Penilaian (potongan + alasan) datang dari SERVER dengan fungsi hitung yang
  // sama dengan checkout. Voucher terbaik dipasang otomatis (pola Shopee)
  // sampai pembeli memilih sendiri di lembar Pilih Voucher. Paritas web
  // `app/keranjang/page.tsx`.
  List<Voucher> _vItems = [];
  Map<String, String> _vPilih = {};
  bool _vManual = false;
  String _vSigDiminta = '';

  Voucher? _vCari(String? code) {
    if (code == null) return null;
    for (final v in _vItems) {
      if (v.code == code && v.bisa) return v;
    }
    return null;
  }

  int get _vDiskon => _vCari(_vPilih['diskon'])?.potongan ?? 0;
  int get _vOngkir {
    final p = _vCari(_vPilih['ongkir'])?.potongan ?? 0;
    return p > _ongkir ? _ongkir : p;
  }

  List<String> get _vKode => [
        if (_vCari(_vPilih['ongkir']) != null) _vPilih['ongkir']!,
        if (_vCari(_vPilih['diskon']) != null) _vPilih['diskon']!,
      ];

  /// Dipanggil dari build: nilai ulang voucher bila harga barang, ongkir,
  /// atau cara ambil berubah (minimal belanja & potongan ongkir ikut berubah).
  void _jadwalVoucher() {
    // Isi keranjang (PN×qty) ikut: ganti part dengan subtotal kebetulan sama
    // tetap wajib dinilai ulang (paritas web `beliSig`).
    final beliSig =
        _itemsBeli.map((i) => '${i.partNumber}:${i.qty}').join(',');
    final sig = '$beliSig|$_subtotal|$_ongkir|$_ambilSendiri';
    if (sig == _vSigDiminta) return;
    _vSigDiminta = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshVoucher());
  }

  Future<List<Voucher>> _refreshVoucher() async {
    final sub = _subtotal;
    if (sub <= 0) {
      if (mounted) setState(() { _vItems = []; _vPilih = {}; });
      return const [];
    }
    try {
      final r = await ApiService.voucherCheckout(sub, _ongkir, _ambilSendiri);
      if (!mounted) return r.items;
      final bisa = {for (final v in r.items) if (v.bisa) v.code};
      setState(() {
        _vItems = r.items;
        _vPilih = _vManual
            // Pilihan pembeli dipertahankan selama masih memenuhi syarat.
            ? {
                for (final e in _vPilih.entries)
                  if (bisa.contains(e.value)) e.key: e.value,
              }
            : {...r.terbaik};
      });
      // Batas poin dihitung dari harga barang SETELAH voucher diskon.
      _refreshPoin();
      return r.items;
    } catch (_) {
      // Gagal menilai → jangan pasang voucher apa pun.
      if (mounted) setState(() { _vItems = []; _vPilih = {}; });
      return const [];
    }
  }

  Future<void> _bukaVoucher() async {
    final hasil = await showVoucherPicker(
      context,
      items: _vItems,
      pilihan: _vPilih,
      onMuatUlang: _refreshVoucher,
    );
    if (hasil == null || !mounted) return;
    setState(() {
      _vPilih = hasil;
      _vManual = true;
    });
    _refreshPoin();
  }

  // ── Poin ────────────────────────────────────────────────────────────
  // `_poinMaks` datang dari SERVER (saldo x plafon 20% x minimal tukar) supaya
  // angka yang ditawarkan sama persis dengan yang diterima saat checkout —
  // kalau berbeda, pembeli menggeser slider ke angka yang kemudian ditolak.
  int _poinMaks = 0;
  int _poinSaldo = 0;
  int _poinPakai = 0;
  int _poinSigSubtotal = -1;

  int get _potongan => _poinPakai * 100;

  /// Ambil batas poin untuk isi keranjang saat ini. Plafon 20% mengikuti harga
  /// barang, jadi batasnya ikut berubah tiap keranjang berubah.
  Future<void> _refreshPoin() async {
    // Voucher dulu, poin belakangan (sama dengan server): plafon 20% poin
    // dari harga barang SETELAH voucher diskon.
    final sub = _subtotal - _vDiskon < 0 ? 0 : _subtotal - _vDiskon;
    if (sub <= 0) {
      if (mounted) setState(() { _poinMaks = 0; _poinPakai = 0; });
      return;
    }
    if (sub == _poinSigSubtotal) return;
    _poinSigSubtotal = sub;
    try {
      final b = await ApiService.poinBatas(sub);
      if (!mounted) return;
      setState(() {
        _poinMaks = b.maksPoin;
        _poinSaldo = b.saldo;
        // Pilihan lama dipangkas ke batas baru, tak pernah dibiarkan melebihi.
        if (_poinPakai > _poinMaks) _poinPakai = _poinMaks;
      });
    } on ApiException {
      if (!mounted) return;
      // Gagal tahu batasnya → jangan tawarkan sama sekali.
      setState(() { _poinMaks = 0; _poinPakai = 0; });
    }
  }

  /// Ambil sendiri = tak ada ongkir sama sekali (bukan "ongkir belum dipilih").
  int get _ongkir => _ambilSendiri ? 0 : (_rate?.price ?? 0).round();

  // ── Checkout ────────────────────────────────────────────────────────

  Future<void> _process() async {
    final nav = AppNav.of(context);
    final beli = _itemsBeli;
    if (beli.isEmpty) return;

    final blokir = _blokir;
    if (blokir.isNotEmpty) {
      setState(() => _error =
          'Belum bisa dibeli: ${blokir.map((i) => '${i.partNumber} (${_srv(i.partNumber)?.alasan ?? 'data belum lengkap'})').join(', ')}. Hapus dari keranjang dulu.');
      return;
    }
    if (_nameCtl.text.trim().isEmpty ||
        _phoneCtl.text.trim().isEmpty ||
        _addressCtl.text.trim().isEmpty ||
        _postalCtl.text.trim().isEmpty) {
      setState(() => _error =
          'Lengkapi alamat penerima (nama, no. HP, alamat, kode pos) dulu.');
      return;
    }
    if (!_gatewayOn) {
      setState(() =>
          _error = 'Pembayaran online (VA/QRIS) belum aktif. Hubungi admin.');
      return;
    }

    // Tarif tersedia tapi tak ada yang dipilih → pastikan itu disengaja
    // (mis. ambil sendiri di gudang), jangan diam-diam order tanpa ongkir.
    // Mode ambil sendiri memang tak berkurir → jangan tanya apa pun.
    if (!_ambilSendiri && _rates.isNotEmpty && _rate == null) {
      final ok = await _confirm(
        'Belum pilih kurir',
        'Anda belum memilih kurir/ongkir. Lanjut TANPA ongkir?\n\n'
            '(Barang diambil sendiri di gudang atau pengiriman diatur terpisah.)',
      );
      if (ok != true) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await ApiService.createOrder(
        items: [
          for (final i in beli)
            CartLine(partNumber: i.partNumber, qty: i.qty, name: i.name),
        ],
        note: _noteCtl.text.trim(),
        courier: _ambilSendiri ? null : _rate?.courier,
        courierService: _ambilSendiri ? null : _rate?.service,
        shippingCost: _ongkir.toDouble(),
        pointRedeem: _poinPakai,
        voucherCodes: _vKode,
        pickup: _ambilSendiri,
        weightGrams: _weightGrams,
        paymentMethod: 'gateway',
        // Midtrans Snap — semua metode (VA/QRIS/e-wallet/kartu) dipilih di
        // halaman bayar, jadi kanalnya cukup 'snap'.
        paymentChannel: 'snap',
        recipientName: _nameCtl.text.trim(),
        recipientPhone: _phoneCtl.text.trim(),
        recipientAddress: _addressCtl.text.trim(),
        recipientPostal: _postalCtl.text.trim(),
        // Titik peta ikut dikirim — server MENGHITUNG ULANG jarak ambil sendiri
        // dari titik ini (paritas web `recipient_lat/lon`).
        recipientLat: _lat,
        recipientLon: _lon,
      );

      await _cart.saveAddress(SavedAddress(
        name: _nameCtl.text.trim(),
        phone: _phoneCtl.text.trim(),
        address: _addressCtl.text.trim(),
        postal: _postalCtl.text.trim(),
      ));

      // Hanya item yang JADI dipesan yang keluar dari keranjang — part gudang
      // lain tetap tersimpan untuk transaksi berikutnya.
      if (_lintasGudang) {
        await _cart.removeAll(beli.map((i) => i.partNumber));
      } else {
        await _cart.clear();
      }

      if (!mounted) return;
      // LANGSUNG ke pembayaran — jangan biarkan pembeli mencari tombol Bayar.
      nav.go(MasScreen.pesananDetail, part: {
        'order_code': res.orderCode,
        'payment_url': res.payment?.url ?? '',
        'autopay': true,
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 16)),
          content: Text(body, style: const TextStyle(fontSize: 13.5)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Lanjut')),
          ],
        ),
      );

  Future<void> _openMap() async {
    final place = await Navigator.of(context).push<GeoPlace>(
      MaterialPageRoute(builder: (_) => const PilihLokasiPeta()),
    );
    if (place == null || !mounted) return;
    setState(() {
      _addressCtl.text = place.displayName.isNotEmpty
          ? place.displayName
          : place.address;
      if (place.postal.isNotEmpty) _postalCtl.text = place.postal;
      _lat = place.lat;
      _lon = place.lon;
      _rates = [];
      _rate = null;
    });
    _scheduleOngkir();
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);

    if (_cart.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const SizedBox(height: 40),
          const MasEmpty(
            icon: Icons.shopping_cart_outlined,
            title: 'Keranjang kosong',
            subtitle: 'Belum ada part yang dipilih.',
          ),
          const SizedBox(height: 12),
          Center(
            child: MasButton(
              label: 'Belanja Part',
              icon: Icons.storefront_outlined,
              onTap: () => nav.go(MasScreen.toko),
            ),
          ),
        ],
      );
    }

    final blokir = _blokir;
    final beli = _itemsBeli;
    final subtotal = _subtotal;
    // PPN INKLUSIF dihitung dari harga barang SETELAH potongan poin — sama
    // dengan backend (orders.create_order); kalau tidak, angkanya berbeda
    // antara layar dan faktur.
    _jadwalVoucher();
    final barangBersih = subtotal - _vDiskon - _potongan;
    final ppn = ppnOf(barangBersih < 0 ? 0 : barangBersih);
    final totalKotor =
        totalOf(subtotal, _ongkir) - _vDiskon - _potongan - _vOngkir;
    // Total tak pernah negatif (paritas web `Math.max(0, …)`).
    final total = totalKotor < 0 ? 0 : totalKotor;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (_error != null) ...[
          _alert(m, _error!),
          const SizedBox(height: 14),
        ],

        if (blokir.isNotEmpty) ...[
          _alert(
            m,
            'Part berikut tidak bisa dibeli: '
            '${blokir.map((i) => '${i.partNumber} — ${_srv(i.partNumber)?.alasan ?? 'data belum lengkap'}').join('; ')}. '
            'Hapus dari keranjang untuk melanjutkan.',
          ),
          const SizedBox(height: 14),
        ],

        if (_lintasGudang) ...[
          _gudangPicker(m),
          const SizedBox(height: 14),
        ],

        _itemList(m),
        const SizedBox(height: 14),
        _alamat(m),
        const SizedBox(height: 14),
        _ekspedisi(m),
        const SizedBox(height: 14),
        _pembayaran(m),
        const SizedBox(height: 14),
        _catatan(m),
        const SizedBox(height: 14),
        _ringkasan(m, subtotal, ppn, total, beli.length),
      ],
    );
  }

  Widget _alert(MasColors m, String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: m.danger50,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border.all(color: m.dangerBorder),
        ),
        child: Text(msg,
            style: TextStyle(fontSize: 12.5, color: m.danger600, height: 1.45)),
      );

  /// Pemilih gudang saat keranjang lintas gudang. Menjelaskan sekalian KENAPA
  /// harus bergantian — pembeli tidak dibiarkan menebak.
  Widget _gudangPicker(MasColors m) => MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '📦 Keranjang berisi part dari ${_gudangList.length} gudang. '
            'Satu pesanan hanya bisa dari satu gudang, jadi part dari gudang lain '
            'tetap tersimpan dan bisa dipesan setelah ini.',
            style: TextStyle(fontSize: 12.5, color: m.ink700, height: 1.45),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in _gudangList)
              GestureDetector(
                onTap: () {
                  setState(() => _gudangPilih = g);
                  _refreshWeight();
                  _refreshPoin();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: g == _gudangAktif ? m.brand50 : m.paper,
                    borderRadius: BorderRadius.circular(MasRadii.input),
                    border: Border.all(
                        color: g == _gudangAktif ? m.brand600 : m.ink200),
                  ),
                  child: Text(
                    'Gudang $g · ${_cart.items.where((i) => _gudangOf(i.partNumber) == g).length} part'
                    '${g == _gudangAktif ? ' — dipesan sekarang' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: g == _gudangAktif
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: g == _gudangAktif ? m.brand700 : m.ink700,
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      );

  Widget _itemList(MasColors m) {
    final beli = _itemsBeli;
    return MasSectionCard(
      title: 'Part di Keranjang',
      trailing: Text('${_cart.items.length} item',
          style: TextStyle(fontSize: 12, color: m.ink500)),
      children: [
        for (final i in _cart.items)
          Opacity(
            // Item gudang lain diredupkan — masih terlihat, tapi jelas tidak
            // ikut checkout kali ini.
            opacity: beli.contains(i) ? 1 : 0.45,
            child: _itemRow(m, i),
          ),
      ],
    );
  }

  Widget _itemRow(MasColors m, CartItem i) {
    final harga = _hargaOf(i);
    final gudang = _gudangOf(i.partNumber);
    final bisa = _bisaBeli(i);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: m.ink100)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(i.partNumber,
                    style: masMono(
                        size: 12.5,
                        weight: FontWeight.w600,
                        color: m.ink900)),
                const SizedBox(height: 2),
                Text(i.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: m.ink700)),
                if (!bisa) ...[
                  const SizedBox(height: 4),
                  MasPill(
                    label: _srv(i.partNumber)?.alasan ?? 'belum bisa dibeli',
                    tone: MasPillTone.warn,
                    height: 19,
                  ),
                ],
                if (gudang.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('🚚 Dikirim dari gudang $gudang',
                      style: TextStyle(fontSize: 11.5, color: m.ink500)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: m.danger600),
            visualDensity: VisualDensity.compact,
            tooltip: 'Hapus',
            onPressed: () => _cart.remove(i.partNumber),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _qtyStepper(m, i),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(harga > 0 ? formatRupiah(harga) : '—',
                style: masMono(size: 11.5, color: m.ink500)),
            Text(formatRupiah(harga * i.qty),
                style: masMono(
                    size: 13.5, weight: FontWeight.w700, color: m.ink900)),
          ]),
        ]),
      ]),
    );
  }

  Widget _qtyStepper(MasColors m, CartItem i) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MasRadii.input),
          border: Border.all(color: m.ink200),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _stepBtn(m, Icons.remove_rounded,
              i.qty <= 1 ? null : () => _cart.setQty(i.partNumber, i.qty - 1)),
          SizedBox(
            width: 34,
            child: Center(
              child: Text('${i.qty}',
                  style: masMono(
                      size: 13, weight: FontWeight.w700, color: m.ink900)),
            ),
          ),
          _stepBtn(m, Icons.add_rounded,
              () => _cart.setQty(i.partNumber, i.qty + 1)),
        ]),
      );

  Widget _stepBtn(MasColors m, IconData icon, VoidCallback? onTap) => SizedBox(
        width: 32,
        height: 32,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon,
              size: 15, color: onTap == null ? m.ink300 : m.ink700),
        ),
      );

  Widget _alamat(MasColors m) => MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('📍 Alamat Penerima',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: m.ink900)),
            ),
            MasButton(
              label: _alamatList.isEmpty ? 'Simpan' : 'Kelola',
              icon: Icons.person_outline_rounded,
              primary: false,
              height: 34,
              onTap: () => AppNav.of(context).go(MasScreen.profil),
            ),
            const SizedBox(width: 6),
            MasButton(
              label: 'Peta',
              icon: Icons.map_outlined,
              primary: false,
              height: 34,
              onTap: _openMap,
            ),
          ]),
          const SizedBox(height: 12),
          if (_alamatList.length > 1) ...[
            _field(
              m,
              'Kirim ke',
              DropdownButtonFormField<int>(
                key: ValueKey(_alamatId),
                initialValue: _alamatId,
                isExpanded: true,
                items: [
                  for (final a in _alamatList)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.label}${a.isDefault ? ' (utama)' : ''} — ${a.namaPenerima}, '
                        '${[a.kecamatan, a.kota].where((e) => e.isNotEmpty).join(', ')} ${a.kodePos}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: m.ink900),
                      ),
                    ),
                ],
                onChanged: (id) {
                  for (final a in _alamatList) {
                    if (a.id == id) _pakaiAlamat(a);
                  }
                },
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MasRadii.input),
                    borderSide: BorderSide(color: m.ink200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MasRadii.input),
                    borderSide: BorderSide(color: m.ink200),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          _field(m, 'Nama penerima',
              MasInput(controller: _nameCtl, hint: 'Nama lengkap')),
          const SizedBox(height: 10),
          _field(
            m,
            'No. HP',
            MasInput(controller: _phoneCtl, hint: '08xxxxxxxxxx'),
          ),
          const SizedBox(height: 10),
          _field(
            m,
            'Alamat lengkap',
            MasInput(
              controller: _addressCtl,
              hint: 'Jalan, no, RT/RW, kelurahan, kecamatan, kota, provinsi',
              maxLines: 3,
              // Alamat ikut menentukan jarak ke gudang (paritas web).
              onChanged: (_) => _schedulePickup(),
            ),
          ),
          const SizedBox(height: 10),
          _field(
            m,
            'Kode pos',
            SizedBox(
              width: 160,
              child: TextField(
                controller: _postalCtl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 5,
                onChanged: (_) {
                  setState(() {
                    _rates = [];
                    _rate = null;
                  });
                  _scheduleOngkir();
                },
                style: TextStyle(fontSize: 14, color: m.ink900),
                cursorColor: m.brand600,
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  hintText: 'mis. 10110',
                  hintStyle: TextStyle(color: m.ink400),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MasRadii.input),
                    borderSide: BorderSide(color: m.ink200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MasRadii.input),
                    borderSide: BorderSide(color: m.ink200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MasRadii.input),
                    borderSide: BorderSide(color: m.brand600),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('Dipakai untuk hitung ongkir.',
              style: TextStyle(fontSize: 11, color: m.ink400)),
        ]),
      );

  Widget _field(MasColors m, String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: m.ink700)),
          const SizedBox(height: 5),
          child,
        ],
      );

  Widget _ekspedisi(MasColors m) {
    final weightKg = _weightGrams / 1000;
    final p = _pickup;
    return MasCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
                _ambilSendiri ? '🏬 Ambil di Toko' : '🚚 Ekspedisi & Ongkir',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: m.ink900)),
          ),
          if (!_ambilSendiri)
            MasButton(
              label: _loadingRates ? 'Mengecek…' : 'Cek Ongkir',
              primary: false,
              height: 34,
              loading: _loadingRates,
              onTap: _cekOngkir,
            ),
        ]),
        // Pilihan cara terima — hanya muncul bila gudang pemenuh memang melayani
        // ambil sendiri untuk alamat ini (server yang memutuskan).
        if (p != null && p.tersedia) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _caraTerima(m, false, '🚚 Kirim ke alamat',
                    'Dikirim ekspedisi, ongkir sesuai tarif')),
            const SizedBox(width: 8),
            Expanded(
                child: _caraTerima(m, true, '🏬 Ambil di toko',
                    'Gudang ${p.gudang} · ±${_km(p.jarakKm)} km · gratis ongkir')),
          ]),
        ],
        if (_ambilSendiri) ...[
          const SizedBox(height: 10),
          Text(
            'Barang disiapkan di Gudang ${p?.gudang ?? _gudangAktif}'
            '${p?.jarakKm != null ? ' (±${_km(p!.jarakKm)} km dari alamat Anda)' : ''}. '
            'Bayar dulu lewat aplikasi, lalu datang membawa kode pesanan — '
            'tak ada ongkir.'
            '${(p?.pic.isNotEmpty ?? false) ? '\nKontak gudang: ${p!.pic}' : ''}',
            style: TextStyle(fontSize: 12.5, color: m.ink700, height: 1.5),
          ),
          if (p?.lat != null && p?.lon != null) ...[
            const SizedBox(height: 8),
            MasButton(
              label: '🗺️ Lihat lokasi gudang',
              primary: false,
              height: 34,
              onTap: () => _bukaUrl(
                  'https://www.google.com/maps/search/?api=1&query=${p!.lat},${p.lon}'),
            ),
          ],
        ] else ...[
          // Alasan tak bisa ambil sendiri hanya bila menyangkut jarak — pembeli
          // luar kota tak perlu diberi tahu fitur yang tak relevan.
          if (p != null && !p.tersedia && p.jarakKm != null) ...[
            const SizedBox(height: 8),
            Text('🏬 ${p.alasan}',
                style: TextStyle(fontSize: 12, color: m.ink500, height: 1.4)),
          ],
          const SizedBox(height: 8),
          // Berat tertagih = max(berat asli, volumetrik) + kemasan. Barang
          // besar tapi ringan ditagih dari ukurannya, dan dus ikut ditimbang di
          // konter — pembeli berhak tahu dasarnya.
          Text(
            'Berat kirim: ${weightKg.toStringAsFixed(weightKg % 1 == 0 ? 0 : 1)} kg '
            '(yang lebih besar antara berat asli dan volumetrik'
            '${_packingGrams > 0 ? ', termasuk kemasan $_packingGrams g' : ''})',
            style: TextStyle(fontSize: 11.5, color: m.ink500),
          ),
          if (_gudangAktif.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '🚚 Ongkir dihitung dari Gudang $_gudangAktif'
              '${_lintasGudang ? ' — untuk ${_itemsBeli.length} part dari gudang ini saja.' : '.'}',
              style: TextStyle(fontSize: 11.5, color: m.ink500),
            ),
        ],
        if (_rateErr != null) ...[
          const SizedBox(height: 10),
          _alert(m, _rateErr!),
        ],
        const SizedBox(height: 10),
        if (_rates.isEmpty)
          Text(
            _loadingRates
                ? 'Mengambil tarif kurir…'
                : 'Isi kode pos untuk melihat pilihan ekspedisi.',
            style: TextStyle(fontSize: 12.5, color: m.ink500),
          )
        else
          Column(children: [
            for (final r in _rates) _rateRow(m, r),
          ]),
        ],
      ]),
    );
  }

  /// Jarak km apa adanya dari server (mis. 3,2) — bilangan bulat tanpa ",0".
  String _km(double? v) {
    if (v == null) return '?';
    return v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1).replaceAll('.', ',');
  }

  Future<void> _bukaUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) AppNav.of(context).toast('Tidak bisa membuka $url');
    }
  }

  /// Tombol pilihan cara terima barang (kirim ↔ ambil sendiri).
  Widget _caraTerima(MasColors m, bool ambil, String judul, String sub) {
    final active = _ambilSendiri == ambil;
    return GestureDetector(
      onTap: () => setState(() => _ambilSendiri = ambil),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? m.brand50 : m.paper,
          borderRadius: BorderRadius.circular(MasRadii.input),
          border: Border.all(color: active ? m.brand600 : m.ink200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(judul,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: m.ink900)),
            Text(sub, style: TextStyle(fontSize: 11, color: m.ink500)),
          ],
        ),
      ),
    );
  }

  Widget _rateRow(MasColors m, ShippingRate r) {
    final active = _rate?.courier == r.courier && _rate?.service == r.service;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _rate = r),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active ? m.brand50 : m.paper,
            borderRadius: BorderRadius.circular(MasRadii.input),
            border: Border.all(color: active ? m.brand600 : m.ink200),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${r.courierName} · ${r.service}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: m.ink900)),
                  if (r.etd.isNotEmpty)
                    Text('estimasi ${r.etd}',
                        style: TextStyle(fontSize: 11.5, color: m.ink500)),
                ],
              ),
            ),
            Text(formatRupiah(r.price),
                style: masMono(
                    size: 13,
                    weight: FontWeight.w700,
                    color: active ? m.brand700 : m.ink800)),
          ]),
        ),
      ),
    );
  }

  Widget _pembayaran(MasColors m) => MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('💳 Pembayaran Online',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: m.ink900)),
          const SizedBox(height: 8),
          if (_gatewayOn)
            Text(
              'Setelah pesanan dibuat, Anda diarahkan ke halaman pembayaran aman '
              'Midtrans untuk memilih metode — Virtual Account, QRIS, e-wallet, '
              'atau kartu. Pembayaran terverifikasi otomatis.',
              style: TextStyle(fontSize: 12.5, color: m.ink600, height: 1.5),
            )
          else
            _alert(m, 'Pembayaran online belum aktif. Hubungi admin.'),
        ]),
      );

  Widget _catatan(MasColors m) => MasCard(
        child: _field(
          m,
          'Catatan / tujuan pesanan',
          MasInput(
            controller: _noteCtl,
            hint: 'Mis. restok cabang, untuk unit HOWO-7 …',
            maxLines: 3,
          ),
        ),
      );

  /// Baris "Voucher MasPart" — ketuk untuk membuka lembar Pilih Voucher.
  Widget _barisVoucher(MasColors m) {
    final hemat = _vDiskon + _vOngkir;
    final nBisa = _vItems.where((v) => v.bisa).length;
    return Material(
      color: kOranyeVoucher.withValues(alpha: m.isDark ? 0.12 : 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: kOranyeVoucher.withValues(alpha: 0.7)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: _bukaVoucher,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                    colors: [kOranyeVoucher, kOranyeVoucher2]),
              ),
              child: const Icon(Icons.confirmation_number_outlined,
                  size: 17, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Voucher MasPart',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: m.ink900)),
                  Text(
                    hemat > 0
                        ? '${_vKode.length} voucher dipakai · hemat ${formatRupiah(hemat)}'
                        : nBisa > 0
                            ? '$nBisa voucher bisa dipakai'
                            : 'Pilih atau masukkan kode voucher',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            hemat > 0 ? FontWeight.w600 : FontWeight.w400,
                        color: hemat > 0 ? kOranyeVoucher2 : m.ink500),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: m.ink400),
          ]),
        ),
      ),
    );
  }

  Widget _ringkasan(
      MasColors m, int subtotal, int ppn, num total, int jumlahBeli) {
    final blokir = _blokir;
    final label = _busy
        ? 'Memproses…'
        : blokir.isNotEmpty
            ? 'Ada part yang belum bisa dibeli'
            : _lintasGudang
                ? 'Proses Pembelian — Gudang $_gudangAktif ($jumlahBeli part)'
                : 'Proses Pembelian';

    return MasCard(
      child: Column(children: [
        _sumRow(m, 'Subtotal barang', formatRupiah(subtotal)),
        const SizedBox(height: 6),
        // PPN ditampilkan sebagai KOMPONEN, bukan tambahan — sama dengan
        // dokumen Accurate.
        _sumRow(m, 'Termasuk PPN 12%', formatRupiah(ppn), muted: true),
        const SizedBox(height: 6),
        _sumRow(
          m,
          _ambilSendiri
              ? 'Ongkir (ambil sendiri)'
              : 'Ongkir${_rate != null ? ' (${_rate!.courierName})' : ''}',
          _ambilSendiri
              ? 'Gratis'
              : _rate != null
                  ? formatRupiah(_rate!.price)
                  : '—',
        ),
        const SizedBox(height: 10),
        _barisVoucher(m),
        if (_vDiskon > 0) ...[
          const SizedBox(height: 6),
          _sumRow(m, 'Voucher diskon (${_vPilih['diskon']})',
              '−${formatRupiah(_vDiskon)}',
              color: _kWarnaDiskon),
        ],
        if (_vOngkir > 0) ...[
          const SizedBox(height: 6),
          _sumRow(m, 'Gratis ongkir (${_vPilih['ongkir']})',
              '−${formatRupiah(_vOngkir)}',
              color: _kWarnaOngkir),
        ],
        // Tukar poin — hanya muncul bila server memang menawarkan (fitur aktif,
        // penukaran dibuka, saldo & keranjang cukup).
        if (_poinMaks > 0) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Divider(height: 1, color: m.ink100),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text('🎁 Tukar poin',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: m.ink700)),
            ),
            Text('punya ${thousands(_poinSaldo)}',
                style: TextStyle(fontSize: 11.5, color: m.ink500)),
          ]),
          Row(children: [
            Expanded(
              child: Slider(
                // ⛔ JANGAN `.clamp()`: num.clamp mengembalikan `num`, sedangkan
                // Slider.value menuntut `double` → galat tipe saat kompilasi.
                value: (_poinPakai > _poinMaks ? _poinMaks : _poinPakai).toDouble(),
                min: 0,
                max: _poinMaks.toDouble(),
                // Langkah 10 poin (paritas web step=10). Maks yang bukan
                // kelipatan 10 tetap tercapai: pembagian dibulatkan KE ATAS,
                // lalu `_poinLangkah` memangkas ke maks.
                divisions: _poinMaks > 10 ? (_poinMaks + 9) ~/ 10 : null,
                label: '${thousands(_poinPakai)} poin',
                onChanged: (v) => setState(() => _poinPakai = _poinLangkah(v)),
              ),
            ),
            MasButton(
              label: _poinPakai == _poinMaks ? 'Batal' : 'Maks',
              primary: false,
              height: 32,
              onTap: () => setState(
                  () => _poinPakai = _poinPakai == _poinMaks ? 0 : _poinMaks),
            ),
          ]),
          Text(
            'Maksimal ${thousands(_poinMaks)} poin untuk keranjang ini (20% dari harga '
            'barang). Poin tidak bisa membayar ongkir.',
            style: TextStyle(fontSize: 11.5, color: m.ink400, height: 1.4),
          ),
        ],
        if (_potongan > 0) ...[
          const SizedBox(height: 6),
          _sumRow(m, 'Potongan poin (${thousands(_poinPakai)})',
              '−${formatRupiah(_potongan)}',
              color: _kWarnaPoin),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, color: m.ink150),
        ),
        Row(children: [
          Expanded(
            child: Text('Total',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: m.ink900)),
          ),
          Text(formatRupiah(total),
              style: masMono(
                  size: 18, weight: FontWeight.w700, color: m.brand700)),
        ]),
        const SizedBox(height: 12),
        MasButton(
          label: label,
          expand: true,
          height: 48,
          loading: _busy,
          onTap: (blokir.isNotEmpty || jumlahBeli == 0) ? null : _process,
        ),
        const SizedBox(height: 8),
        Text(
          'Harga part dihitung dari sistem saat pesanan dibuat. Ongkir opsional.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: m.ink400),
        ),
      ]),
    );
  }

  /// Nilai slider → kelipatan 10 poin, tak pernah melebihi batas server.
  int _poinLangkah(double v) {
    if (v >= _poinMaks) return _poinMaks;
    final r = (v / 10).round() * 10;
    return r > _poinMaks ? _poinMaks : (r < 0 ? 0 : r);
  }

  // Warna baris potongan — sama dengan web (keranjang/page.tsx).
  static const _kWarnaDiskon = Color(0xFFC9530F);
  static const _kWarnaOngkir = Color(0xFF0B7D6E);
  static const _kWarnaPoin = Color(0xFF167A4A);

  Widget _sumRow(MasColors m, String label, String value,
          {bool muted = false, Color? color}) =>
      Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: muted ? 12.5 : 13,
                  color: color ?? (muted ? m.ink400 : m.ink500))),
        ),
        Text(value,
            style: masMono(
                size: muted ? 12.5 : 13,
                color: color ?? (muted ? m.ink400 : m.ink800))),
      ]);
}
