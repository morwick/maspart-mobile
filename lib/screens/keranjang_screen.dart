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
// 3. PPN 12% (DPP 11/12) DITAMBAHKAN. Harga katalog BELUM termasuk PPN →
//    total = neto + PPN + ongkir − potongan ongkir, dengan neto = barang −
//    voucher diskon − potongan poin. Ongkir tidak kena PPN (lihat order_ui).

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../auth_storage.dart';
import '../cart.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/voucher_tiket.dart';
import '../widgets/alamat_form.dart';
import '../widgets/mas_ui.dart';
import '../widgets/pilih_metode_bayar.dart';
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

  /// Masukan penguji 2026-09-29 (paritas web): gudang acuan (harga, stok,
  /// ongkir) diturunkan server dari alamat PROFIL — alamat yang cuma diketik di
  /// keranjang diabaikan, jadi tanpa alamat profil semua permintaan dibalas 409.
  /// Alamat pertama WAJIB disimpan lewat lembar "Tambah Alamat" di sini.
  /// 'gagal' = daftar alamat tak terbaca → perilaku lama (form bebas).
  String _alamatStatus = 'muat'; // muat | ok | gagal
  bool _alamatBusy = false;
  bool get _tanpaAlamat => _alamatStatus == 'ok' && _alamatList.isEmpty;
  bool get _alamatSiap =>
      _alamatStatus == 'gagal' ||
      (_alamatStatus == 'ok' && _alamatList.isNotEmpty);

  /// Titik peta penerima (dari alamat tersimpan / peta) — ikut dikirim ke cek
  /// Ambil di Toko supaya jarak dihitung dari titik, bukan tebakan kode pos.
  double? _lat;
  double? _lon;

  /// Keadaan server untuk isi keranjang (harga, gudang, bisa dibeli).
  CartGudang? _asal;

  /// Gudang yang dipilih untuk checkout kali ini.
  String _gudangPilih = '';

  int _weightGrams = 0;

  List<ShippingRate> _rates = [];
  // Jenis pengiriman ala marketplace: pilih kelompok dulu, lalu kurirnya.
  List<ShippingGroup> _kelompok = [];
  String? _katPilih;
  ShippingRate? _rate;
  String? _rateErr;
  bool _loadingRates = false;

  /// Ambil di Toko — hanya ditawarkan bila SERVER bilang alamat ini dekat gudang
  /// pemenuh (jarak + izin gudang dihitung di sana, dihitung ULANG saat order).
  PickupInfo? _pickup;
  bool _ambilSendiri = false;

  bool _gatewayOn = false;

  /// #11: `/payments/methods` GAGAL dimuat (bukan "gateway mati") — dulu
  /// dianggap belum aktif dan checkout tertutup sampai layar dibuka ulang.
  bool _gatewayGagal = false;

  /// Metode bayar dari server. RajaOngkir: pembeli memilih QRIS / VA bank di
  /// sini (paritas web `kanalPilih`); Midtrans (gateway lama): kanal 'snap',
  /// metode dipilih di halaman Midtrans.
  PaymentMethods? _metode;

  /// Kanal yang DIPILIH pembeli. Null = pakai bawaan ([_kanalEfektif]).
  String? _kanalPilih;

  /// Pembeli memilih "Bayar Tempo" (hanya akun TEMPO, migrasi 048).
  bool _pilihTempo = false;
  bool _busy = false;
  String? _error;

  /// R-5 (KL-15, paritas web `kurirPilihan`): kurir + layanan yang DIPILIH
  /// SENDIRI oleh pembeli. Hitung ulang tarif (ubah qty/alamat) dulu diam-diam
  /// memindahkan pilihan ke yang termurah; kini dipertahankan selama masih
  /// tersedia, dan bila hilang pembeli diberi tahu lewat [_kurirInfo].
  ({String courier, String service, String nama})? _kurirPilihan;
  String? _kurirInfo;

  /// S-16 (audit 2026-09-28): kunci idempotensi percobaan checkout terakhir
  /// yang jawabannya TAK PASTI (koneksi putus / 5xx — server bisa saja sudah
  /// membuat pesanannya). Dipakai ulang hanya bila isi pesanannya persis sama,
  /// sehingga server mengembalikan pesanan yang sama, bukan pesanan & VA kedua.
  ///
  /// QA e2e 2026-09-29 #5: disimpan di SharedPreferences (per akun, ≤24 jam),
  /// bukan cuma di memori — aplikasi yang dimatikan saat "Memproses…" dulu
  /// kehilangan kuncinya, lalu Proses ulang membuat pesanan & VA kedua.
  static const _idemTtl = Duration(hours: 24);

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
      setState(() {
        _alamatList = list;
        _alamatStatus = 'ok';
      });
      Alamat? utama;
      for (final x in list) {
        if (x.isDefault) utama = x;
      }
      utama ??= list.isNotEmpty ? list.first : null;
      if (utama != null) _pakaiAlamat(utama);
    } catch (_) {
      /* fitur profil belum aktif / offline → perilaku lama */
      if (mounted) setState(() => _alamatStatus = 'gagal');
    }
    // Keadaan server baru bisa dibaca setelah status alamat diketahui.
    _refreshServerState();
  }

  /// Lembar "Tambah Alamat" (paritas web): isian keranjang tak hilang karena
  /// tak pindah halaman. Alamat pertama otomatis jadi alamat utama.
  Future<void> _tambahAlamat() async {
    final pertama = _tanpaAlamat;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final m = ctx.mas;
        String? err;
        var tertutup = false;
        return StatefulBuilder(builder: (ctx, setLocal) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.92),
              decoration: BoxDecoration(
                color: m.paper,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(MasRadii.sheet)),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(pertama ? 'Tambah Alamat Pengiriman' : 'Tambah Alamat Baru',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: m.ink900)),
                      if (pertama) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Alamat ini disimpan ke profil sebagai alamat utama — '
                          'lain kali tak perlu diisi lagi.',
                          style: TextStyle(fontSize: 12.5, color: m.ink500),
                        ),
                      ],
                      if (err != null) ...[
                        const SizedBox(height: 8),
                        Text(err ?? '', style: TextStyle(fontSize: 12.5, color: m.danger600)),
                      ],
                      const SizedBox(height: 12),
                      AlamatForm(
                        prefillNama: _nameCtl.text.trim(),
                        prefillTelepon: _phoneCtl.text.trim(),
                        forceDefault: pertama,
                        submitting: _alamatBusy,
                        submitLabel: 'Simpan & pakai alamat ini',
                        onCancel: () => Navigator.pop(ctx),
                        onSubmit: (body) async {
                          setLocal(() => _alamatBusy = true);
                          try {
                            final sebelum = {for (final a in _alamatList) a.id};
                            await ApiService.createAlamat(body);
                            final list = await ApiService.listAlamat();
                            if (!mounted) return;
                            Alamat? baru;
                            for (final a in list) {
                              if (!sebelum.contains(a.id)) baru = a;
                            }
                            setState(() {
                              _alamatList = list;
                              _alamatStatus = 'ok';
                            });
                            if (baru != null) _pakaiAlamat(baru);
                            tertutup = true;
                            if (ctx.mounted) Navigator.pop(ctx);
                            // Gudang acuan baru diketahui → harga/stok/berat dihitung ulang.
                            _lastBeliSig = '';
                            _refreshServerState();
                          } on ApiException catch (e) {
                            if (!tertutup) setLocal(() => err = e.message);
                          } finally {
                            _alamatBusy = false;
                            if (!tertutup && ctx.mounted) setLocal(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
      },
    );
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

  /// [coba] = percobaan ke berapa; galat sesaat diulang otomatis 2× (#11).
  Future<void> _loadGateway({int coba = 0}) async {
    try {
      final m = await ApiService.paymentMethods();
      if (mounted) {
        setState(() {
          _gatewayOn = m.gatewayAvailable;
          _gatewayGagal = false;
          _metode = m;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _gatewayOn = false;
        _gatewayGagal = true;
      });
      if (!e.isAuth && coba < 2) {
        await Future<void>.delayed(Duration(seconds: 2 * (coba + 1)));
        if (mounted && !_gatewayOn) await _loadGateway(coba: coba + 1);
      }
    }
  }

  // ── Kunci idempotensi tersimpan (#5) ────────────────────────────────

  Future<String> _idemPrefKey() async =>
      'maspart_checkout_idem_${await AuthStorage.usernameToken()}';

  /// Kunci tersimpan untuk [sig] yang masih berlaku, atau null.
  Future<String?> _idemAmbil(String sig) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(await _idemPrefKey());
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final at = DateTime.fromMillisecondsSinceEpoch(
          (j['at'] as num?)?.toInt() ?? 0);
      if (DateTime.now().difference(at) > _idemTtl) return null;
      if (j['sig'] != sig) return null;
      final k = (j['key'] ?? '').toString();
      return k.isEmpty ? null : k;
    } catch (_) {
      return null;
    }
  }

  Future<void> _idemSimpan(String sig, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        await _idemPrefKey(),
        jsonEncode({
          'sig': sig,
          'key': key,
          'at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {/* tak fatal: server tetap punya dedupe sidik jari */}
  }

  Future<void> _idemBuang() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(await _idemPrefKey());
    } catch (_) {}
  }

  /// Segarkan keadaan tiap item dari server, lalu hitung ulang berat + ongkir.
  Future<void> _refreshServerState() async {
    final items = _cart.items;
    if (items.isEmpty) {
      setState(() {
        _asal = null;
        _weightGrams = 0;
        _rates = [];
        _rate = null;
      });
      return;
    }
    // Tanpa alamat profil server pasti menjawab 409 — tunggu alamat disimpan.
    if (!_alamatSiap) return;
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
      setState(() => _weightGrams = 0);
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
      setState(() => _weightGrams = w.weightGrams);
    } on ApiException {
      /* pakai estimasi — pembeli tetap bisa cek ongkir manual */
    }
    _scheduleOngkir();
  }

  /// Ongkir dihitung OTOMATIS begitu alamat (kode pos) & berat siap. Dulu
  /// pembeli harus ingat menekan "Cek Ongkir"; yang lupa membuat order tanpa
  /// kurir. Debounce 900 ms supaya tak menembak tiap ketikan.
  void _scheduleOngkir({bool lambat = false}) {
    _ongkirDebounce?.cancel();
    if (!_alamatSiap) return;
    if (_itemsBeli.isNotEmpty &&
        _weightGrams > 0 &&
        _postalCtl.text.trim().length >= 5) {
      _ongkirDebounce = Timer(Duration(milliseconds: lambat ? 1500 : 900), () => _cekOngkir());
    }
    _schedulePickup();
  }

  /// Jadwalkan cek Ambil di Toko saja (tanpa mengambil ulang tarif kurir).
  void _schedulePickup() {
    _pickupDebounce?.cancel();
    if (!mounted) return;
    // Ambil di Toko punya syarat SENDIRI (paritas web): cukup titik peta ATAU
    // alamat terisi — kode pos belum 5 digit tak boleh menahan cek jarak.
    // Syarat tak terpenuhi → info lama dibuang, jangan nyangkut di layar.
    final bisaCekPickup = _itemsBeli.isNotEmpty &&
        _alamatSiap &&
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
    } catch (_) {
      // R-6 (KL-10, paritas web): info pickup gagal dimuat → pilihan Ambil di
      // Toko disembunyikan, jadi modenya WAJIB kembali ke Kirim — dulu hanya
      // `_pickup` yang dikosongkan dan mode ambil sendiri terkunci tanpa tombol
      // untuk keluar (checkout lalu ditolak server).
      if (mounted) {
        setState(() {
          _pickup = null;
          _ambilSendiri = false;
        });
      }
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
        alamat: _addressCtl.text.trim(),
      );
      if (!mounted) return;
      final sorted = [...r.rates]..sort((a, b) => a.price.compareTo(b.price));
      final pilihan = _kurirPilihan;
      ShippingRate? sama;
      if (pilihan != null) {
        for (final x in r.rates) {
          if (x.courier == pilihan.courier && x.service == pilihan.service) {
            sama = x;
            break;
          }
        }
      }
      setState(() {
        _rateErr = r.error;
        _rates = r.rates;
        _kelompok = r.kelompok;
        _katPilih = null;
        // Kurir pilihan pembeli dipertahankan bila masih ada (R-5); selain itu
        // termurah jadi default supaya pembeli tak checkout tanpa kurir karena
        // lupa memilih — dia tetap bebas mengganti.
        _rate = sama ?? (sorted.isNotEmpty ? sorted.first : null);
        _kurirInfo = (pilihan != null && sama == null && sorted.isNotEmpty)
            ? 'Kurir pilihan Anda (${pilihan.nama} · ${pilihan.service}) tidak '
                'tersedia untuk alamat/berat ini — dipilih yang termurah.'
            : null;
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

  /// R-19 (paritas web): barang yang hanya terhalang BERAT tak bisa dikirim,
  /// tapi tetap bisa dibeli dengan Ambil di Toko (ongkirnya tak dihitung).
  bool _bisaBeli(CartItem i) {
    final s = _srv(i.partNumber);
    if (s != null) return s.bisaDibeli || (_ambilSendiri && s.hanyaAmbil);
    return hasPrice(i.harga) && hasWeight(i.berat);
  }

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
  /// QA e2e 2026-09-29 #9: hanya barang yang IKUT dipesan kali ini — barang
  /// gudang lain ditahan untuk transaksi berikutnya, tak boleh menghalangi.
  List<CartItem> get _blokir =>
      _itemsBeli.where((i) => !_bisaBeli(i)).toList();

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
      // #8: gagal → subtotal ini boleh dicoba lagi pada penyegaran berikutnya
      // (dulu tanda tangannya tertinggal dan poin tak pernah ditawarkan lagi).
      _poinSigSubtotal = -1;
      if (!mounted) return;
      // Gagal tahu batasnya → jangan tawarkan sama sekali.
      setState(() { _poinMaks = 0; _poinPakai = 0; });
    }
  }

  /// Ambil sendiri = tak ada ongkir sama sekali (bukan "ongkir belum dipilih").
  int get _ongkir => _ambilSendiri ? 0 : (_rate?.price ?? 0).round();

  /// Total yang TAMPIL (rumus = backend orders.create_order): barang setelah
  /// voucher & poin + PPN + ongkir − potongan ongkir. Dikirim sebagai
  /// expected_total (T-13) — server menolak bila hitungannya berbeda.
  int get _totalTampil {
    final bersih = _subtotal - _vDiskon - _potongan;
    final t = totalOf(bersih < 0 ? 0 : bersih, _ongkir, _vOngkir).round();
    return t < 0 ? 0 : t;
  }

  // ── Metode bayar (RajaOngkir) ───────────────────────────────────────

  /// Ringkasan TEMPO akun ini; null = bukan pelanggan tempo (paritas web).
  TempoAkun? get _tempo => (_metode?.tempo?.aktif ?? false) ? _metode!.tempo : null;
  bool get _pakaiTempo => _pilihTempo && _tempo != null;

  /// Kenapa tempo tak bisa dipakai untuk [total] (null = boleh). Server
  /// mengulang cek ini dengan total final.
  String? _alasanTempo(int total) {
    final t = _tempo;
    if (t == null) return 'Pembayaran tempo tidak aktif.';
    if (!t.boleh) return t.alasan ?? 'Pembayaran tempo sedang tidak bisa dipakai.';
    if (total > t.sisa) {
      return 'Total ${formatRupiah(total)} melebihi sisa limit tempo ${formatRupiah(t.sisa)}.';
    }
    return null;
  }

  bool get _pilihKanal => _metode?.isRajaOngkir ?? false;

  /// Kanal RajaOngkir yang boleh untuk [total] (min/maks per kanal).
  List<PaymentChannel> _kanalBoleh(int total) => [
        for (final c in _metode?.channels ?? const <PaymentChannel>[])
          if (c.code != 'snap' && c.alasanTakBisa(total) == null) c,
      ];

  /// Kanal yang akan dikirim: pilihan pembeli bila masih boleh untuk total
  /// sekarang, selain itu QRIS, selain itu VA pertama. Null = tak ada kanal
  /// yang menerima total ini (mis. di bawah Rp 10.000). Midtrans → 'snap'.
  String? get _kanalEfektif {
    if (!_pilihKanal) return 'snap';
    final boleh = _kanalBoleh(_totalTampil);
    if (boleh.isEmpty) return null;
    if (_kanalPilih != null && boleh.any((c) => c.code == _kanalPilih)) {
      return _kanalPilih;
    }
    return boleh.any((c) => c.isQris) ? 'qris' : boleh.first.code;
  }

  /// Pesan bila tak satu pun kanal menerima total ini.
  String _pesanTanpaKanal(int total) {
    final minimal = (_metode?.channels ?? const <PaymentChannel>[])
        .map((c) => c.minAmount)
        .where((n) => n > 0)
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    if (minimal != null && total < minimal) {
      return 'Minimal pembayaran online ${formatRupiah(minimal)} (total pesanan '
          '${formatRupiah(total)}). Tambah barang ke pesanan ini dulu.';
    }
    return 'Tidak ada metode pembayaran untuk total ${formatRupiah(total)}. '
        'Hubungi admin.';
  }

  // ── Checkout ────────────────────────────────────────────────────────

  /// [buatBaru] = pembeli memilih "Tetap buat pesanan baru" setelah server
  /// menemukan pesanan belum-bayar berisi sama (409 `pesanan_serupa`).
  Future<void> _process({bool buatBaru = false}) async {
    final nav = AppNav.of(context);
    final beli = _itemsBeli;
    if (beli.isEmpty) return;

    if (_tanpaAlamat) {
      _tambahAlamat();
      return;
    }

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
    if (!_pakaiTempo && !_gatewayOn && _gatewayGagal) {
      // #11: galat sesaat saat membuka keranjang — cek sekali lagi dulu.
      await _loadGateway(coba: 2);
      if (!mounted) return;
    }
    if (!_pakaiTempo && !_gatewayOn) {
      setState(() => _error = _gatewayGagal
          ? 'Metode pembayaran belum bisa dicek (koneksi bermasalah). Coba lagi '
              'sebentar.'
          : 'Pembayaran online (VA/QRIS) belum aktif. Hubungi admin.');
      return;
    }

    // R-6: jaring terakhir — mode Ambil di Toko tanpa info pickup yang
    // mengizinkannya (pilihannya tak terlihat di layar) kembali ke Kirim.
    if (_ambilSendiri && !(_pickup?.tersedia ?? false)) {
      setState(() {
        _ambilSendiri = false;
        _error = 'Ambil di Toko tidak tersedia untuk alamat ini — pesanan akan '
            'dikirim. Pilih kurir dulu.';
      });
      _scheduleOngkir();
      return;
    }

    // Kirim ke alamat WAJIB punya ongkir terhitung (paritas web, audit
    // 2026-09-28 KL-13/T-13). Dialog lama "Lanjut TANPA ongkir?" menjanjikan
    // opsi yang tak ada — server selalu menolak pesanan kirim tanpa ongkir.
    if (!_ambilSendiri && (_rate == null || _loadingRates)) {
      setState(() => _error = _loadingRates
          ? 'Ongkir sedang dihitung — tunggu sebentar.'
          : 'Ongkir wajib dihitung sebelum memesan — isi kode pos & alamat '
              'lengkap, lalu pilih kurir.');
      return;
    }
    final tampil = _totalTampil;
    final tempo = _pakaiTempo;
    // Kanal dicek SETELAH ongkir pasti: batas minimal kanal (Rp 10.000) berlaku
    // untuk total akhir, bukan subtotal sebelum ongkir terhitung. TEMPO: tanpa
    // kanal — yang dicek sisa limit.
    final kanal = tempo ? null : _kanalEfektif;
    if (tempo) {
      final alasan = _alasanTempo(tampil);
      if (alasan != null) {
        setState(() => _error = alasan);
        return;
      }
    } else if (kanal == null) {
      setState(() => _error = _pesanTanpaKanal(tampil));
      return;
    }

    // Kunci lama hanya untuk permintaan IDENTIK setelah percobaan tanpa jawaban
    // pasti; selain itu percobaan baru = kunci baru (paritas web).
    final sig = [
      for (final i in beli) '${i.partNumber}x${i.qty}',
      _noteCtl.text.trim(), _ambilSendiri, _rate?.courier, _rate?.service,
      _ongkir, _poinPakai, _vKode.join(','), tampil, tempo ? 'tempo' : kanal,
      _nameCtl.text.trim(), _phoneCtl.text.trim(), _addressCtl.text.trim(),
      _postalCtl.text.trim(), _lat, _lon,
    ].join('|');
    // Kunci disimpan SEBELUM dikirim: aplikasi yang mati di tengah permintaan
    // tetap memakai kunci yang sama saat pembeli menekan Proses lagi (#5).
    final lama = buatBaru ? null : await _idemAmbil(sig);
    final idemKey = lama ?? ApiService.kunciIdempoten();
    await _idemSimpan(sig, idemKey);
    if (!mounted) return;
    final pnDipesan = beli.map((i) => i.partNumber).toList();
    var ulangBaru = false;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await ApiService.createOrder(
        idempotencyKey: idemKey,
        items: [
          for (final i in beli)
            CartLine(partNumber: i.partNumber, qty: i.qty, name: i.name),
        ],
        note: _noteCtl.text.trim(),
        courier: _ambilSendiri ? null : _rate?.courier,
        courierService: _ambilSendiri ? null : _rate?.service,
        shippingCost: _ongkir,
        pointRedeem: _poinPakai,
        voucherCodes: _vKode,
        expectedTotal: tampil,
        pickup: _ambilSendiri,
        weightGrams: _weightGrams,
        paymentMethod: tempo ? 'tempo' : 'gateway',
        // RajaOngkir: QRIS / VA bank pilihan pembeli. Midtrans (gateway lama):
        // 'snap' — metodenya dipilih di halaman Midtrans. Tempo: tanpa kanal.
        paymentChannel: kanal,
        recipientName: _nameCtl.text.trim(),
        recipientPhone: _phoneCtl.text.trim(),
        recipientAddress: _addressCtl.text.trim(),
        recipientPostal: _postalCtl.text.trim(),
        // Titik peta ikut dikirim — server MENGHITUNG ULANG jarak ambil sendiri
        // dari titik ini (paritas web `recipient_lat/lon`).
        recipientLat: _lat,
        recipientLon: _lon,
        buatBaru: buatBaru,
      );
      await _idemBuang();

      await _cart.saveAddress(SavedAddress(
        name: _nameCtl.text.trim(),
        phone: _phoneCtl.text.trim(),
        address: _addressCtl.text.trim(),
        postal: _postalCtl.text.trim(),
      ));

      // Hanya item yang JADI dipesan yang keluar dari keranjang — part gudang
      // lain (dan barang yang ditambahkan sementara itu) tetap tersimpan.
      await _cart.removeAll(pnDipesan);

      // VA: nomornya tampil langsung di detail pesanan (salin → bayar dari
      // m-banking) — tak perlu membuka halaman bayar. QRIS & Snap Midtrans:
      // QR / metode ada di halaman bayar → langsung dibuka.
      final kanalJadi = res.payment?.channel ?? kanal ?? '';
      final ke = {
        'order_code': res.orderCode,
        'payment_url': res.payment?.url ?? '',
        // Tempo: tak ada yang dibayar sekarang — pesanan langsung diproses.
        'autopay': !tempo && !kanalJadi.startsWith('va_'),
      };
      if (!mounted) {
        // #28: pembeli sudah meninggalkan keranjang saat pesanan selesai
        // dibuat — jangan diam; beri jalan ke pembayarannya.
        nav.toast('Pesanan ${res.orderCode} sudah dibuat — segera bayar.',
            actionLabel: 'Bayar',
            onAction: () => nav.go(MasScreen.pesananDetail, part: ke));
        return;
      }
      // LANGSUNG ke pembayaran — jangan biarkan pembeli mencari tombol Bayar.
      nav.go(MasScreen.pesananDetail, part: ke);
    } on ApiException catch (e) {
      // Jawaban pasti (4xx) = pesanan TIDAK dibuat → kunci tak perlu dipakai
      // ulang. Tanpa jawaban pasti (jaringan / 5xx) kunci tetap tersimpan.
      if (!(e.isJaringan || e.statusCode >= 500)) await _idemBuang();
      final kode = '${e.detail?['kode'] ?? ''}';
      final kodePesanan = '${e.detail?['order_code'] ?? ''}';
      if (e.statusCode == 409 &&
          kode == 'pesanan_sudah_dibayar' &&
          kodePesanan.isNotEmpty) {
        // Percobaan checkout ini ternyata sudah jadi pesanan yang LUNAS
        // (mis. dibayar dari layar lain) → barangnya keluar dari keranjang.
        await _cart.removeAll(pnDipesan);
        nav.toast(e.message);
        nav.go(MasScreen.pesananDetail, part: {'order_code': kodePesanan});
        return;
      }
      if (!mounted) return;
      if (e.statusCode == 409 &&
          kode == 'pesanan_serupa' &&
          kodePesanan.isNotEmpty) {
        ulangBaru = await _tawarPesananSerupa(e, kodePesanan, pnDipesan);
        return;
      }
      if (kode.startsWith('tempo_')) {
        // Limit / beku / tak aktif menurut server → pesanan TIDAK dibuat. Muat
        // ulang ringkasan tempo supaya sisa limit di layar sama dengan server.
        setState(() => _error = e.message);
        await _loadGateway();
        return;
      }
      setState(() => _error = e.isJaringan
          ? 'Koneksi terputus sebelum pesanan terkonfirmasi — pesanan mungkin '
              'sudah terbuat. Periksa Pesanan Saya dulu sebelum menekan Proses '
              'Pembelian lagi.'
          : e.message);
      if (e.isJaringan) {
        await _cariPesananTerbuat(tampil, pnDipesan);
        return;
      }
      if (e.statusCode == 409 || e.statusCode == 400) {
        // T-13 / QA e2e 2026-09-29 #8: tagihan berubah, stok kurang, voucher
        // terpakai / tak berlaku, poin tak cukup — pesanan BELUM dibuat.
        // Muat ulang SEMUA komponen tagihan (harga, stok, ongkir, voucher,
        // poin) supaya Proses berikutnya lolos atau alasannya terlihat;
        // dulu batas poin & voucher tertahan tanda tangan lama → galat sama
        // berulang tanpa akhir.
        await _segarkanTagihan();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      // Di finally, bukan sesudah try: cabang `pesanan_serupa` keluar lewat
      // `return` di dalam catch.
      if (ulangBaru && mounted) unawaited(_process(buatBaru: true));
    }
  }

  /// Paksa semua angka tagihan diambil ulang dari server.
  Future<void> _segarkanTagihan() async {
    _poinSigSubtotal = -1;
    _vSigDiminta = '';
    await _refreshServerState();
    if (!mounted) return;
    if (!_ambilSendiri) await _cekOngkir();
    if (!mounted) return;
    await _refreshVoucher();
    if (!mounted) return;
    await _refreshPoin();
  }

  /// 409 `pesanan_serupa`: server menemukan pesanan BELUM DIBAYAR berisi sama
  /// (refresh / app dimatikan / Kembali saat Proses). Tawarkan membukanya;
  /// true = pembeli sengaja ingin pesanan BARU (dikirim ulang `buat_baru`).
  Future<bool> _tawarPesananSerupa(
      ApiException e, String kodePesanan, List<String> pnDipesan) async {
    final total = (e.detail?['total'] as num?)?.round();
    final pilih = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pesanan serupa belum dibayar'),
        content: Text(e.message.isNotEmpty
            ? e.message
            : 'Pesanan $kodePesanan'
                '${total != null ? ' senilai ${formatRupiah(total)}' : ''} berisi '
                'barang yang sama dan belum dibayar.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'baru'),
              child: const Text('Tetap buat pesanan baru')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'buka'),
              child: Text('Buka pesanan $kodePesanan')),
        ],
      ),
    );
    if (!mounted) return false;
    if (pilih == 'baru') return true;
    if (pilih == 'buka') {
      await _cart.removeAll(pnDipesan);
      if (!mounted) return false;
      AppNav.of(context)
          .go(MasScreen.pesananDetail, part: {'order_code': kodePesanan});
    }
    return false;
  }

  /// S-16: setelah koneksi putus, cari pesanan BELUM DIBAYAR yang baru saja
  /// terbuat dengan total yang sama → tawarkan membukanya, supaya pembeli tak
  /// memesan (dan membayar) dua kali. Gagal mencari → cukup pesan galatnya.
  Future<void> _cariPesananTerbuat(int total, List<String> pnDipesan) async {
    List<OrderSummary> daftar;
    try {
      daftar = await ApiService.myOrders();
    } catch (_) {
      return;
    }
    final batas = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    OrderSummary? calon;
    for (final o in daftar) {
      final dibuat = DateTime.tryParse(o.createdAt)?.toUtc();
      if (o.status == 'menunggu_pembayaran' &&
          o.total.round() == total &&
          dibuat != null &&
          dibuat.isAfter(batas)) {
        calon = o;
        break;
      }
    }
    if (calon == null || !mounted) return;
    final kode = calon.orderCode;
    final buka = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pesanan sudah terbuat'),
        content: Text('Pesanan $kode senilai ${formatRupiah(total)} ternyata sudah '
            'tercatat sebelum koneksi terputus. Buka pesanan itu untuk membayar — '
            'jangan memesan lagi supaya tidak tertagih dua kali.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nanti')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Buka Pesanan')),
        ],
      ),
    );
    if (buka != true || !mounted) return;
    await _idemBuang();
    await _cart.removeAll(pnDipesan);
    if (!mounted) return;
    AppNav.of(context).go(MasScreen.pesananDetail, part: {'order_code': kode});
  }

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
    // PPN dihitung dari harga barang SETELAH voucher diskon & potongan poin,
    // lalu DITAMBAHKAN — sama dengan backend (orders.create_order); kalau
    // tidak, angka yang dilihat pembeli berbeda dengan yang ditagih. Minimal
    // belanja voucher & plafon poin tetap memakai harga sebelum pajak
    // (`subtotal`).
    _jadwalVoucher();
    final barangBersih = subtotal - _vDiskon - _potongan;
    final neto = barangBersih < 0 ? 0 : barangBersih;
    final ppn = ppnOf(neto);
    final totalKotor = totalOf(neto, _ongkir, _vOngkir);
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
          _ikonTeks(
            Icons.inventory_2_outlined,
            Text(
              'Keranjang berisi part dari ${_gudangList.length} gudang. '
              'Satu pesanan hanya bisa dari satu gudang, jadi part dari gudang lain '
              'tetap tersimpan dan bisa dipesan setelah ini.',
              style: TextStyle(fontSize: 12.5, color: m.ink700, height: 1.45),
            ),
            color: m.ink700,
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
                  // Teks biasa (bisa turun baris) — alasan seperti "stok tinggal
                  // N — kurangi jumlahnya" terlalu panjang untuk pil satu baris.
                  Text(_srv(i.partNumber)?.alasan ?? 'belum bisa dibeli',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: m.warn600)),
                ],
                // Qty > stok (masukan penguji 2026-09-29) → satu ketukan menyesuaikan.
                if ((_srv(i.partNumber)?.stok ?? 0) > 0 &&
                    i.qty > _srv(i.partNumber)!.stok) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 28,
                    child: OutlinedButton(
                      onPressed: () =>
                          _cart.setQty(i.partNumber, _srv(i.partNumber)!.stok),
                      style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10)),
                      child: Text('Jadikan ${_srv(i.partNumber)!.stok}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
                if (gudang.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  _ikonTeks(
                      Icons.local_shipping_outlined,
                      Text('Dikirim dari gudang $gudang',
                          style: TextStyle(fontSize: 11.5, color: m.ink500)),
                      color: m.ink500),
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
          _stepBtn(
              m,
              Icons.add_rounded,
              // Sisa stok diketahui → tak bisa menambah melebihinya.
              (_srv(i.partNumber)?.stok ?? 0) > 0 && i.qty >= _srv(i.partNumber)!.stok
                  ? null
                  : () => _cart.setQty(i.partNumber, i.qty + 1)),
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

  /// Belum ada alamat profil → tak ada form bebas (server mengabaikannya):
  /// info + tombol Tambah Alamat (masukan penguji 2026-09-29, paritas web).
  Widget _alamatKosong(MasColors m) => MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Alamat Penerima',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: m.ink900)),
          const SizedBox(height: 10),
          _alert(m, 'Lengkapi alamat pengiriman dulu — gudang terdekat, stok, '
              'dan ongkir dipilih dari alamat itu.'),
          const SizedBox(height: 10),
          MasButton(
            label: 'Tambah Alamat',
            icon: Icons.add_location_alt_outlined,
            expand: true,
            onTap: _tambahAlamat,
          ),
        ]),
      );

  Widget _alamat(MasColors m) => _tanpaAlamat ? _alamatKosong(m) : MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Alamat Penerima',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: m.ink900)),
            ),
            if (_alamatList.isNotEmpty)
              MasButton(
                label: 'Kelola',
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
          if (_alamatStatus == 'ok')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _tambahAlamat,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Tambah Alamat Baru'),
              ),
            ),
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
              // Alamat ikut menentukan jarak ke gudang & TUJUAN ongkir (server
              // mencocokkan kota/provinsi alamat — T-1). Audit 2026-09-28 T-13:
              // dulu tarif lama bertahan saat alamat diganti ke kota lain lalu
              // server menagih tarif baru. Kini tarif gugur SEKETIKA dan dihitung
              // ulang 1,5 dtk setelah berhenti mengetik (hemat kuota).
              onChanged: (_) {
                setState(() {
                  _rates = [];
                  _rate = null;
                  // KL-9/S-17 (paritas web): titik peta lama milik alamat lain —
                  // dibuang saat alamat diketik ulang.
                  _lat = null;
                  _lon = null;
                });
                _scheduleOngkir(lambat: true);
              },
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
                    _lat = null;          // KL-9/S-17: titik peta basi dibuang
                    _lon = null;
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
    final p = _pickup;
    return MasCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
                _ambilSendiri ? 'Ambil di Toko' : 'Ekspedisi & Ongkir',
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
                child: _caraTerima(m, false, Icons.local_shipping_outlined, 'Kirim ke alamat',
                    'Dikirim ekspedisi, ongkir sesuai tarif')),
            const SizedBox(width: 8),
            Expanded(
                child: _caraTerima(m, true, Icons.storefront_outlined, 'Ambil di toko',
                    'Gudang ${p.gudang} · ±${_km(p.jarakKm)} km · gratis ongkir')),
          ]),
        ],
        if (_ambilSendiri) ...[
          const SizedBox(height: 10),
          Text(
            'Barang disiapkan di Gudang ${p?.gudang ?? _gudangAktif}'
            '${p?.jarakKm != null ? ' (±${_km(p!.jarakKm)} km dari alamat Anda)' : ''}. '
            'Bayar dulu lewat aplikasi, lalu datang menunjukkan kode ambil '
            '(muncul di detail pesanan) — tak ada ongkir.'
            '${(p?.pic.isNotEmpty ?? false) ? '\nKontak gudang: ${p!.pic}' : ''}',
            style: TextStyle(fontSize: 12.5, color: m.ink700, height: 1.5),
          ),
          if (p != null && p.catatan.isNotEmpty) ...[
            const SizedBox(height: 4),
            _ikonTeks(
                Icons.location_on_outlined,
                Text(p.catatan,
                    style: TextStyle(fontSize: 12, color: m.warn600, height: 1.4)),
                color: m.warn600),
          ],
          if (p?.lat != null && p?.lon != null) ...[
            const SizedBox(height: 8),
            MasButton(
              label: 'Lihat lokasi gudang',
              icon: Icons.map_outlined,
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
            _ikonTeks(
                Icons.storefront_outlined,
                Text(p.alasan,
                    style: TextStyle(fontSize: 12, color: m.ink500, height: 1.4)),
                color: m.ink500),
            // S-17: titik peta diabaikan karena tak cocok dengan kode pos/alamat.
            if (p.catatan.isNotEmpty)
              _ikonTeks(
                  Icons.location_on_outlined,
                  Text(p.catatan,
                      style: TextStyle(fontSize: 12, color: m.warn600, height: 1.4)),
                  color: m.warn600),
          ],
          if (_gudangAktif.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ikonTeks(
              Icons.local_shipping_outlined,
              Text(
                'Ongkir dihitung dari Gudang $_gudangAktif'
                '${_lintasGudang ? ' — untuk ${_itemsBeli.length} part dari gudang ini saja.' : '.'}',
                style: TextStyle(fontSize: 11.5, color: m.ink500),
              ),
              color: m.ink500,
            ),
        ],
        // R-5: kurir pilihan pembeli hilang setelah hitung ulang → beri tahu.
        if (!_ambilSendiri && _kurirInfo != null) ...[
          const SizedBox(height: 10),
          _ikonTeks(
              Icons.warning_amber_rounded,
              Text(_kurirInfo!,
                  style: TextStyle(fontSize: 12, color: m.warn600, height: 1.4)),
              color: m.warn600),
        ],
        if (_rateErr != null) ...[
          const SizedBox(height: 10),
          _alert(m, _rateErr!),
        ],
        const SizedBox(height: 10),
        if (_rates.isEmpty)
          Text(
            _tanpaAlamat
                ? 'Tambah alamat pengiriman dulu — ongkir dihitung dari alamat itu.'
                : _loadingRates
                    ? 'Mengambil tarif kurir…'
                    : 'Isi kode pos untuk melihat pilihan ekspedisi.',
            style: TextStyle(fontSize: 12.5, color: m.ink500),
          )
        else if (_kelompok.isNotEmpty)
          // Ala Shopee/Tokopedia: jenis pengiriman dulu (rentang harga + tanggal
          // tiba), kurir di dalam jenis yang aktif. Termurah terpilih otomatis.
          Column(children: [
            for (final k in _kelompok) ...[
              _kelompokRow(m, k),
              if (k.kode == _katAktif)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Column(children: [
                    for (final r in _rates.where((r) => r.kategori == k.kode))
                      _rateRow(m, r),
                  ]),
                ),
            ],
          ])
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
  /// Ikon kecil + teks sebaris — pengganti emoji di awal teks (emoji tampil
  /// sebagai kotak "?" di sebagian perangkat, mis. simulator iOS 26).
  Widget _ikonTeks(IconData icon, Text text, {required Color color}) {
    final size = (text.style?.fontSize ?? 12) + 2;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: size, color: color),
      ),
      const SizedBox(width: 5),
      Expanded(child: text),
    ]);
  }

  Widget _caraTerima(MasColors m, bool ambil, IconData icon, String judul, String sub) {
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
            _ikonTeks(
                icon,
                Text(judul,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: m.ink900)),
                color: active ? m.brand600 : m.ink700),
            Text(sub, style: TextStyle(fontSize: 11, color: m.ink500)),
          ],
        ),
      ),
    );
  }

  /// "estimasi 4-6 hari · tarif min. 10 kg" — paritas kartu tarif web.
  String _infoTarif(ShippingRate r) => [
        if (r.etd.isNotEmpty) 'estimasi ${r.etd}',
        if (r.minKg > 0) 'tarif min. ${r.minKg} kg',
      ].join(' · ');

  /// Jenis aktif: pilihan pembeli; kalau belum memilih ikut kurir terpilih
  /// (termurah otomatis); kalau belum ada juga, jenis pertama.
  String? get _katAktif =>
      _katPilih ??
      (_rate != null && _rate!.kategori.isNotEmpty ? _rate!.kategori : null) ??
      (_kelompok.isNotEmpty ? _kelompok.first.kode : null);

  void _pilihKelompok(String kode) {
    // Seperti Tokopedia: memilih jenis langsung memilih kurir termurah di dalamnya.
    final isi = _rates.where((r) => r.kategori == kode).toList()
      ..sort((a, b) => a.price.compareTo(b.price));
    setState(() {
      _katPilih = kode;
      if (isi.isNotEmpty && isi.first.kategori != _rate?.kategori) {
        _pilihRateTanpaSetState(isi.first);
      }
    });
  }

  /// Pembeli memilih kurir sendiri → diingat (R-5) supaya hitung ulang tarif
  /// tak menggantinya diam-diam.
  void _pilihRate(ShippingRate r) => setState(() => _pilihRateTanpaSetState(r));

  void _pilihRateTanpaSetState(ShippingRate r) {
    _rate = r;
    _kurirPilihan = (
      courier: r.courier,
      service: r.service,
      nama: r.courierName.isNotEmpty ? r.courierName : r.courier.toUpperCase(),
    );
    _kurirInfo = null;
  }

  static const _bulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  /// "29 Sep – 1 Okt" (atau satu tanggal bila sama) dari tanggal ISO server.
  String _rentangTiba(String a, String b) {
    String f(String iso) {
      final d = DateTime.tryParse(iso);
      return d == null ? iso : '${d.day} ${_bulan[d.month - 1]}';
    }
    return (b.isEmpty || a == b) ? f(a) : '${f(a)} – ${f(b)}';
  }

  Widget _kelompokRow(MasColors m, ShippingGroup k) {
    final aktif = k.kode == _katAktif;
    final harga = k.hargaMax > k.hargaMin
        ? '${formatRupiah(k.hargaMin)} – ${formatRupiah(k.hargaMax)}'
        : formatRupiah(k.hargaMin);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _pilihKelompok(k.kode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: aktif ? m.brand50 : m.paper,
            borderRadius: BorderRadius.circular(MasRadii.input),
            border: Border.all(color: aktif ? m.brand600 : m.ink200),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(k.label,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: m.ink900)),
                      if (k.termurah)
                        const MasPill(
                            label: 'Termurah', tone: MasPillTone.brand, height: 20),
                    ],
                  ),
                  if (k.tibaMin.isNotEmpty)
                    Text('Estimasi tiba ${_rentangTiba(k.tibaMin, k.tibaMax)}',
                        style: TextStyle(fontSize: 12, color: m.ink700)),
                  Text(k.catatan,
                      style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(harga,
                style: masMono(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: aktif ? m.brand700 : m.ink800)),
          ]),
        ),
      ),
    );
  }

  Widget _rateRow(MasColors m, ShippingRate r) {
    final active = _rate?.courier == r.courier && _rate?.service == r.service;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _pilihRate(r),
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
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${r.courierName} · ${r.service}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: m.ink900)),
                      if (r.termurah)
                        const MasPill(
                            label: 'Termurah', tone: MasPillTone.brand, height: 20),
                      if (r.tercepat)
                        const MasPill(
                            label: 'Tercepat', tone: MasPillTone.info, height: 20),
                    ],
                  ),
                  if (_infoTarif(r).isNotEmpty)
                    Text(_infoTarif(r),
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
          Text(_pilihKanal ? 'Metode Pembayaran' : 'Pembayaran Online',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: m.ink900)),
          const SizedBox(height: 12),
          if (_tempo != null) ...[
            ..._pilihanTempo(m),
            const SizedBox(height: 12),
          ],
          if (_pakaiTempo)
            _catatanTempo(m)
          else if (_gatewayOn && _pilihKanal)
            ..._pilihanKanal(m)
          else if (_gatewayOn)
            Text(
              'Setelah pesanan dibuat, Anda diarahkan ke halaman pembayaran aman '
              'Midtrans untuk memilih metode — Virtual Account, QRIS, e-wallet, '
              'atau kartu. Pembayaran terverifikasi otomatis.',
              style: TextStyle(fontSize: 12.5, color: m.ink600, height: 1.5),
            )
          else if (_gatewayGagal) ...[
            _alert(m, 'Metode pembayaran belum bisa dimuat — periksa koneksi.'),
            TextButton(
              onPressed: () => _loadGateway(coba: 2),
              child: const Text('Coba lagi'),
            ),
          ] else
            _alert(m, 'Pembayaran online belum aktif. Hubungi admin.'),
        ]),
      );

  /// Pilihan "Bayar Tempo" / "Bayar Sekarang" (akun TEMPO saja, paritas web).
  List<Widget> _pilihanTempo(MasColors m) {
    final t = _tempo!;
    final alasan = _alasanTempo(_totalTampil);
    Widget kartu({required bool aktif, required String label, required String judul,
        required String ket, bool merah = false, required VoidCallback onTap}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: aktif ? m.brand50 : m.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: aktif ? m.brand600 : m.ink200, width: aktif ? 1.5 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _busy ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1B211D))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(judul,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: m.ink900)),
                    const SizedBox(height: 2),
                    Text(ket,
                        style: TextStyle(fontSize: 11.5, color: merah ? m.danger600 : m.ink500, height: 1.35)),
                  ]),
                ),
                Icon(aktif ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 20, color: aktif ? m.brand600 : m.ink300),
              ]),
            ),
          ),
        ),
      );
    }

    return [
      kartu(
        aktif: _pakaiTempo,
        label: 'TEMPO',
        judul: 'Bayar Tempo (${t.terminHari} hari)',
        ket: alasan ??
            'Sisa limit ${formatRupiah(t.sisa)} · jatuh tempo ${t.terminHari} hari setelah barang dikirim',
        merah: alasan != null,
        onTap: () => setState(() => _pilihTempo = true),
      ),
      kartu(
        aktif: !_pakaiTempo,
        label: 'ONLINE',
        judul: 'Bayar Sekarang',
        ket: 'QRIS atau Virtual Account — dicek otomatis',
        onTap: () => setState(() => _pilihTempo = false),
      ),
    ];
  }

  Widget _catatanTempo(MasColors m) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.receipt_long_outlined, size: 14, color: m.ink500),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Pesanan langsung diproses gudang tanpa bayar dulu. Tagihannya jatuh tempo '
            '${_tempo?.terminHari ?? 30} hari setelah barang dikirim — lihat & bayar di menu '
            'Tagihan Tempo.',
            style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.45),
          ),
        ),
      ]);

  /// QRIS + petak Virtual Account (RajaOngkir) — paritas web `PilihMetodeBayar`.
  List<Widget> _pilihanKanal(MasColors m) {
    final total = _totalTampil;
    final kanal = _kanalEfektif;
    return [
      if (kanal == null) ...[
        _alert(m, _pesanTanpaKanal(total)),
        const SizedBox(height: 8),
      ],
      PilihMetodeBayar(
        kanal: [
          for (final c in _metode?.channels ?? const <PaymentChannel>[])
            if (c.code != 'snap') c,
        ],
        value: kanal,
        total: total,
        enabled: !_busy,
        onChanged: (code) => setState(() => _kanalPilih = code),
      ),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lock_outline_rounded, size: 14, color: m.ink500),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Dibayar lewat RajaOngkir & dicek otomatis. Nomor VA / kode QR muncul '
            'di halaman pesanan setelah pesanan dibuat.',
            style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.45),
          ),
        ),
      ]),
    ];
  }

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
        const SizedBox(height: 10),
        _barisVoucher(m),
        if (_vDiskon > 0) ...[
          const SizedBox(height: 6),
          _sumRow(m, 'Voucher diskon (${_vPilih['diskon']})',
              '−${formatRupiah(_vDiskon)}',
              color: _kWarnaDiskon),
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
              child: _ikonTeks(
                  Icons.card_giftcard_outlined,
                  Text('Tukar poin',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: m.ink700)),
                  color: m.ink700),
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
        // Urutan ala Accurate: potongan barang (voucher diskon & poin) di atas,
        // lalu PPN DITAMBAHKAN atas barang setelah potongan, lalu ongkir & voucher
        // ongkir. Ongkir tidak kena PPN.
        const SizedBox(height: 6),
        _sumRow(m, 'PPN 12% (DPP 11/12)', formatRupiah(ppn)),
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
        if (_vOngkir > 0) ...[
          const SizedBox(height: 6),
          _sumRow(m, 'Gratis ongkir (${_vPilih['ongkir']})',
              '−${formatRupiah(_vOngkir)}',
              color: _kWarnaOngkir),
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
          'Harga, ongkir, dan potongan dihitung ulang sistem saat pesanan dibuat.',
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
