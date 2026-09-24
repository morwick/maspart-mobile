// lib/screens/part_detail_screen.dart — detail part: foto SIMS, stok Accurate,
// harga, spesifikasi fisik, keranjang (pembeli) & cek kecocokan di unit (EPC).
//
// Tiap kartu memuat datanya SENDIRI (foto / stok / spesifikasi / cek-unit):
// gagalnya satu sumber tidak boleh mengosongkan seluruh layar.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard + Uint8List (PNG exploded view)
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';
import '../widgets/penilaian.dart';
import '../widgets/rak_editor.dart';
import '../utils.dart';
import '../api_service.dart';
import '../app/nav.dart';
import '../cart.dart';

/// Nomor rangka terakhir yang dipakai — pembeli umumnya punya 1-2 unit saja,
/// jadi lebih baik diingat daripada diketik ulang tiap membuka part.
const _kRangkaKey = 'maspart_rangka_terakhir';

class PartDetailScreen extends StatefulWidget {
  final Map<String, dynamic> part;
  const PartDetailScreen({super.key, required this.part});
  @override
  State<PartDetailScreen> createState() => _PartDetailScreenState();
}

class _PartDetailScreenState extends State<PartDetailScreen> {
  final _cart = CartStore.instance;

  /// Data baris part yang dipakai layar. Disalin dari argumen navigasi lalu
  /// DILENGKAPI dari katalog by-PN bila argumennya "tipis" (mis. dibuka dari
  /// kandidat foto Asisten yang hanya mengoper part_number) — persis web yang
  /// selalu fetch baris katalog by PN.
  late Map<String, dynamic> _part = Map<String, dynamic>.from(widget.part);

  List<String> _photos = [];
  int _fotoIdx = 0;                       // foto aktif di galeri
  final PageController _fotoCtl = PageController();
  bool _loadingPhotos = true;

  /// Foto yang DISEMBUNYIKAN daftar-hitam karena terbukti bukan part ini
  /// (SIMS kadang menempelkan foto part saudara). Hanya dipakai admin: sebagai
  /// penanda + jalan memulihkan. `_fotoBusy` mengunci tombol saat request jalan.
  int _fotoTersembunyi = 0;
  bool _fotoBusy = false;

  /// Semua unit yang memakai PN ini (nama model dari kolom `file` katalog).
  List<String> _units = [];

  AccurateStock? _stock;
  bool _loadingStock = true;
  String? _stockErr; // panggilan API gagal (jaringan / server), bukan stok 0

  PartSpecResponse? _spec;
  bool _loadingSpec = true;
  String? _specErr;

  /// Lokasi rak per gudang (label PENUH Accurate → baris). Dimuat TERPISAH dari
  /// stok: rak yang gagal terbaca tak boleh ikut menghilangkan angka stoknya.
  Map<String, RakInfo> _rak = const {};
  bool _loadingRak = false;
  bool _rakDiminta = false; // didChangeDependencies bisa dipanggil berkali-kali

  /// Baris gudang yang sedang dibentangkan (hanya satu, biar kartunya pendek).
  String? _bukaGudang;

  /// Keluarga varian pemasok — part fisik yang SAMA dipecah jadi beberapa kartu
  /// barang Accurate per pemasok (PN dasar + '/SN' + '/SH' dst), stok DAN harga
  /// beda tiap kartu. null = bukan keluarga varian / gagal / tak dikonfigurasi
  /// → seluruh tampilan lama dipakai apa adanya.
  PartVarian? _varianData;

  /// Kode varian yang sedang dilihat; '' = "Semua varian" (gabungan).
  String _tabVarian = '';

  String get _pn => '${_part['part_number'] ?? ''}';
  String get _name => '${_part['part_name'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCartChanged);
    _backfillFromCatalog();
    _loadPhotos();
    _loadStock();
    _loadVarian();
    _loadSpec();
  }

  /// Muat ulang SEMUA kartu (tarik-ke-bawah). Stok Accurate berubah sepanjang
  /// hari; sebelumnya satu-satunya cara menyegarkannya adalah keluar dari layar
  /// lalu membuka partnya lagi.
  Future<void> _reloadAll() async {
    setState(() {
      _loadingPhotos = true;
      _loadingStock = true;
      _stockErr = null;
      _loadingSpec = true;
      _specErr = null;
    });
    await Future.wait<void>([
      _backfillFromCatalog(),
      _loadPhotos(),
      _loadStock(),
      _loadVarian(),
      _loadSpec(),
      if (_rakDiminta) _loadRak(),
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppNav baru bisa dibaca di sini, bukan di initState. Rak hanya relevan
    // untuk staf internal yang boleh melihat stok — pembeli malah ditolak 403
    // di pintu server, jadi panggilannya jangan dibuang percuma.
    if (_rakDiminta) return;
    final nav = AppNav.of(context);
    if (nav.isBuyer || !nav.showStok) return;
    _rakDiminta = true;
    _loadingRak = true; // build menyusul; setState di sini tak diperlukan
    _loadRak();
  }

  /// Rak & kartu stok part ini di semua gudang. Ini fitur PELENGKAP: server
  /// lama / migrasi belum jalan → diamkan saja, kartu stok tetap tampil utuh.
  Future<void> _loadRak() async {
    final pn = _pn;
    if (pn.isEmpty) {
      _loadingRak = false;
      return;
    }
    try {
      final r = await ApiService.rakForPart(pn);
      if (!mounted) return;
      setState(() {
        _rak = r;
        _loadingRak = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRak = false);
    }
  }

  /// Ambil baris katalog by PN. Dua kegunaan, itulah kenapa fetch ini SELALU
  /// jalan (dulu dilewati bila nama sudah ada):
  ///   1. melengkapi field yang kosong pada argumen navigasi (mis. dibuka dari
  ///      kandidat foto Asisten yang cuma mengoper part_number);
  ///   2. mengumpulkan SEMUA unit tempat PN ini dipakai — persis web yang
  ///      menampilkan "Ditemukan di N unit".
  /// Kegagalan diabaikan diam-diam (layar tetap jalan).
  Future<void> _backfillFromCatalog() async {
    final pn = _pn;
    if (pn.isEmpty) return;
    try {
      final rows = await ApiService.searchPart(query: pn, byName: false, limit: 20);
      // Web: pakai baris yang PN-nya PERSIS sama; kalau tak ada, pakai semua
      // hasil (substring) supaya layar tidak kosong melompong.
      final exact = [
        for (final r in rows)
          if ('${r['part_number'] ?? ''}'.trim().toUpperCase() ==
              pn.trim().toUpperCase())
            r,
      ];
      final dipakai = exact.isNotEmpty ? exact : rows;
      if (!mounted) return;

      // Nama unit dari kolom `file`, tanpa duplikat & urutan katalog dijaga.
      final unit = <String>[];
      for (final r in dipakai) {
        final u = modelFromFile(r['file'] as String?);
        if (u.isNotEmpty && !unit.contains(u)) unit.add(u);
      }

      final merged = Map<String, dynamic>.from(_part);
      if (exact.isNotEmpty) {
        // Baris ber-PN PERSIS sama = data OTORITATIF: server sudah men-scope
        // stok ke daerah pembeli (+ fallback gudang terdekat) & menerapkan izin
        // kolom. Field stok/harga SELALU diambil dari sini.
        // ⛔ Dulu seluruh merge dilewati begitu `part_name` terisi — padahal
        // nama ada tak berarti stok ikut ada. Pintu masuk selain Cari Part
        // (Cari by Foto, Toko, Harga) tak membawa `gudang`, jadi kartu "Stok
        // tersedia" SELALU '—' padahal stoknya ada.
        for (final k in const ['stok', 'gudang', 'harga']) {
          if (exact.first.containsKey(k)) merged[k] = exact.first[k];
        }
        exact.first.forEach((k, v) {
          final cur = merged[k];
          final kosong = cur == null ||
              (cur is String && cur.trim().isEmpty) ||
              (cur is Map && cur.isEmpty);
          if (kosong && v != null) merged[k] = v;
        });
      } else if (dipakai.isNotEmpty && _name.trim().isEmpty) {
        // Tak ada PN yang persis sama — hasil substring itu PART LAIN. Hanya
        // field deskriptif yang boleh dipinjam; ⛔ JANGAN stok/harga/gudang.
        for (final k in const ['part_name', 'file', 'sims_url', 'photo_url']) {
          final cur = merged[k];
          final kosong = cur == null || (cur is String && cur.trim().isEmpty);
          if (kosong && dipakai.first[k] != null) merged[k] = dipakai.first[k];
        }
      }
      setState(() {
        _part = merged;
        _units = unit;
      });
    } catch (_) {
      /* katalog tak terjangkau — pakai apa adanya dari argumen navigasi */
    }
  }

  @override
  void dispose() {
    _cart.removeListener(_onCartChanged);
    _fotoCtl.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPhotos() async {
    try {
      final res = _pn.isEmpty ? const PartPhotos() : await ApiService.partPhotos(_pn);
      if (!mounted) return;
      setState(() {
        _photos = res.photos;
        _fotoIdx = 0;
        _fotoTersembunyi = res.tersembunyi;
        _loadingPhotos = false;
      });
      if (_fotoCtl.hasClients) _fotoCtl.jumpToPage(0);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _photos = [];
        _loadingPhotos = false;
      });
    }
  }

  /// Admin menandai satu foto SALAH — hilang dari layar ini, dari etalase, dan
  /// berhenti memberi suara di "Cari by Foto". Baris galeri tak dihapus, jadi
  /// bisa dipulihkan lewat tautan "Pulihkan" di bawah kartu foto.
  Future<void> _tandaiFotoSalah(String url) async {
    if (_fotoBusy) return;
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Foto ini salah?'),
        content: Text('Sembunyikan foto ini dari $_pn.\n\n'
            'Foto juga berhenti dipakai "Cari by Foto". Bisa dipulihkan lagi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sembunyikan')),
        ],
      ),
    );
    if (ya != true) return;
    setState(() => _fotoBusy = true);
    try {
      await ApiService.fotoSalah(_pn, url);
      await _loadPhotos();
      if (mounted) AppNav.of(context).toast('Foto disembunyikan');
    } catch (e) {
      if (mounted) AppNav.of(context).toast('Gagal menandai foto: $e');
    } finally {
      if (mounted) setState(() => _fotoBusy = false);
    }
  }

  Future<void> _pulihkanFoto() async {
    if (_fotoBusy) return;
    setState(() => _fotoBusy = true);
    try {
      await ApiService.fotoPulihkan(_pn);
      await _loadPhotos();
    } catch (e) {
      if (mounted) AppNav.of(context).toast('Gagal memulihkan foto: $e');
    } finally {
      if (mounted) setState(() => _fotoBusy = false);
    }
  }

  /// Stok per gudang dari indeks Accurate (ERP) — BUKAN live per-PN: server
  /// menariknya 3× sehari pada jam WIB tetap 07/12/19. Kegagalan di sini TIDAK
  /// boleh diterjemahkan jadi angka 0 — 0 berarti habis, gagal berarti tidak tahu.
  Future<void> _loadStock() async {
    if (_pn.isEmpty) {
      setState(() => _loadingStock = false);
      return;
    }
    try {
      final s = await ApiService.accurateStock(_pn);
      if (!mounted) return;
      setState(() {
        _stock = s;
        _loadingStock = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stockErr = e.message;
        _loadingStock = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stockErr = 'Gagal menghubungi server.';
        _loadingStock = false;
      });
    }
  }

  /// Keluarga varian pemasok. Fitur PELENGKAP: `ApiService.partVarian` sudah
  /// menelan galatnya jadi null, dan hasil yang bukan keluarga (1 kartu saja)
  /// sengaja TIDAK disimpan — supaya `_varian` cukup dicek null untuk memilih
  /// antara tampilan varian dan tampilan lama.
  Future<void> _loadVarian() async {
    if (_pn.isEmpty) return;
    final v = await ApiService.partVarian(_pn);
    if (!mounted || v == null || !v.keluarga) return;
    setState(() => _varianData = v);
  }

  // Exploded view TANPA nomor rangka. SENGAJA tidak dimuat saat layar dibuka:
  // panggilan pertama bisa 10-60 dtk (PN umum dipakai belasan ribu model), dan
  // gambar hanya tampil bila user memang meminta.
  PartExplodedFigure? _exploded;

  /// Ringkasan penilaian (dari UlasanProdukSection) → baris ★ di bawah judul.
  double _rataUlasan = 0;
  int _jumlahUlasan = 0;
  bool _explodedBusy = false;
  String? _explodedErr;

  // Stok PEMASOK Weichai — diambil LIVE saat staf menekan tombol (bukan tiap
  // buka layar: portal lambat & di balik Cloudflare). Non-fatal, internal-only.
  WeichaiStock? _weichai;
  bool _weichaiBusy = false;
  String? _weichaiErr;

  Future<void> _cekWeichai() async {
    if (_weichaiBusy || _pn.isEmpty) return;
    setState(() {
      _weichaiBusy = true;
      _weichaiErr = null;
    });
    try {
      final d = await ApiService.weichaiStock(_pn);
      if (!mounted) return;
      setState(() {
        _weichai = d;
        _weichaiBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weichaiBusy = false;
        _weichaiErr = e is ApiException ? e.message : 'Gagal menghubungi portal Weichai.';
      });
    }
  }

  Future<void> _loadExploded() async {
    if (_explodedBusy || _exploded != null || _pn.isEmpty) return;
    setState(() {
      _explodedBusy = true;
      _explodedErr = null;
    });
    try {
      final d = await ApiService.partExplodedFigure(_pn);
      if (!mounted) return;
      setState(() {
        _exploded = d;
        _explodedBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _explodedBusy = false;
        _explodedErr = e is ApiException ? e.message : 'Gagal memuat exploded view.';
      });
    }
  }

  /// Spesifikasi fisik resmi SIMS — sumber berat untuk hitung ongkir.
  Future<void> _loadSpec() async {
    if (_pn.isEmpty) {
      setState(() => _loadingSpec = false);
      return;
    }
    try {
      final s = await ApiService.partSpec(_pn);
      if (!mounted) return;
      setState(() {
        _spec = s;
        _loadingSpec = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _specErr = e.message;
        _loadingSpec = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _specErr = 'Gagal menghubungi server.';
        _loadingSpec = false;
      });
    }
  }

  void _copyPn(String pn) {
    Clipboard.setData(ClipboardData(text: pn));
    AppNav.of(context).toast('Nomor part "$pn" disalin');
  }

  void _openGallery(int index) {
    if (_photos.isEmpty) return;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      pageBuilder: (_, _, _) => _FullscreenGallery(photos: _photos, initial: index),
    ));
  }

  // ── Turunan data ────────────────────────────────────────────────────

  /// Rincian stok Accurate — hanya bila PN benar-benar ketemu di sana.
  AccurateStockDetail? get _acc =>
      (_stock?.found ?? false) ? _stock!.stock : null;

  /// True bila stok live TIDAK bisa dipastikan (belum dikonfigurasi, sesi
  /// Accurate mati, error server, atau panggilan API gagal).
  bool get _stokGagal =>
      _stockErr != null ||
      (_stock != null &&
          (!_stock!.configured || _stock!.sessionExpired || _stock!.error));

  /// Pesan kegagalan yang jujur: jelaskan penyebabnya, dan tegaskan bahwa ini
  /// bukan berarti barangnya habis.
  String get _stokGagalPesan {
    if (_stockErr != null) {
      return 'Stok live gagal diambil: $_stockErr. Ini bukan berarti stok habis — '
          'jumlahnya belum bisa dipastikan.';
    }
    final s = _stock!;
    final r = (s.reason ?? '').trim();
    final ekor = r.isEmpty ? '' : ' — $r';
    if (!s.configured) {
      return 'Integrasi Accurate belum dikonfigurasi$ekor. Stok live tidak tersedia; '
          'angka di bawah (bila ada) berasal dari katalog dan bisa basi.';
    }
    if (s.sessionExpired) {
      return 'Sesi Accurate kedaluwarsa$ekor. Stok live tidak bisa diambil — '
          'bukan berarti stok habis.';
    }
    return 'Gagal mengambil stok dari Accurate$ekor. Ini bukan berarti stok habis — '
        'jumlahnya belum bisa dipastikan.';
  }

  /// Stok per gudang dari katalog lokal (Excel hasil export Accurate) — cadangan
  /// saat stok live gagal diambil.
  List<(String, String)> get _gudangLokal {
    final out = <(String, String)>[];
    final g = _part['gudang'];
    if (g is Map) g.forEach((k, v) => out.add(('$k', thousands(asInt(v)))));
    return out;
  }

  /// Stok yang benar-benar DIKETAHUI. null = tidak diketahui (jangan diperlakukan
  /// sebagai habis).
  int? get _stokDiketahui {
    final acc = _acc;
    if (acc != null) return acc.availableToSell;
    // Server memasang topeng '—' bila izin Kolom Stok dimatikan untuk akun ini;
    // parser menolaknya jadi angka, sehingga dirahasiakan ≠ habis.
    return _stokAngka(_part['stok']);
  }

  /// Angka stok dari string server. Server mengirim '1.500' untuk seribu lima
  /// ratus (titik = pemisah RIBUAN) dan '—' bila ditutupi izin kolom.
  /// ⛔ JANGAN pakai asNum(): titik dianggap desimal → '1.500' terbaca 1,5 → 1.
  int? _stokAngka(dynamic v) {
    if (v is num) return v.toInt();
    if (v is! String) return null;
    final digit = v.replaceAll(RegExp(r'[^0-9-]'), '');
    return digit.isEmpty ? null : int.tryParse(digit);
  }

  /// Stok TERSCOPE untuk pembeli — hanya daerahnya sendiri (backend sudah
  /// men-scope kolom `stok`), TIDAK memakai stok company-wide Accurate. null =
  /// tidak diketahui. Dipakai untuk tampilan & logika beli pembeli.
  int? get _stokBuyer {
    // JUMLAH rincian gudang terscope — persis web (`buyerStock`). Server sudah
    // memfilter ke daerah pembeli + fallback gudang terdekat.
    // ⛔ JANGAN memakai `stok`: itu total SEMUA cabang (company-wide Accurate) —
    // angkanya salah untuk pembeli DAN membocorkan stok cabang lain, padahal
    // kartunya tertulis "di <kota>".
    final g = _part['gudang'];
    if (g is Map && g.isNotEmpty) {
      var n = 0;
      g.forEach((_, v) => n += asInt(v));
      return n;
    }
    return null;
  }

  /// Nama lokasi stok pembeli (gudang pertama pada katalog terscope).
  String? get _lokasiBuyer {
    final g = _gudangLokal;
    return g.isNotEmpty ? g.first.$1 : null;
  }

  /// Buang awalan nomor Accurate: "1. Jakarta" → "Jakarta" (= `locName` web).
  static String _locName(String s) {
    final t = s.replaceFirst(RegExp(r'^\s*\d+\s*\.\s*'), '').trim();
    return t.isNotEmpty ? t : s;
  }

  bool _bukaChat = false;

  /// Tombol "Chat Gudang" → layar chat dengan KEY gudang (bukan nama mentah
  /// "1. Jakarta" — backend menolak key tak dikenal dengan 404). Sama dengan
  /// web `chatKey`: cocokkan nama lokasi stok ke label `/api/buyer/locations`,
  /// fallback ke gudang milik pembeli.
  Future<void> _chatGudang(AppNav nav) async {
    if (_bukaChat) return;
    setState(() => _bukaChat = true);
    String? key;
    try {
      final loc = _lokasiBuyer;
      if (loc != null) {
        final nama = _locName(loc).toLowerCase();
        final locs = await ApiService.buyerLocations();
        for (final l in locs) {
          if (l.label.trim().toLowerCase() == nama) {
            key = l.key;
            break;
          }
        }
      }
      key ??= (await ApiService.buyerLocation()).key;
    } catch (_) {
      /* gagal memetakan → buka daftar percakapan tanpa gudang terpilih */
    }
    if (!mounted) return;
    setState(() => _bukaChat = false);
    nav.go(MasScreen.chat,
        part: {if (key != null && key.isNotEmpty) 'gudang': key});
  }

  // ── Varian pemasok ──────────────────────────────────────────────────
  //
  // UI varian hanya hidup bila keluarganya memang > 1 kartu Accurate (dijaga
  // saat `_loadVarian` menyimpan). ⛔ Aturan pemilik: harga TIDAK PERNAH
  // dirata-rata — rentang hanya LABEL, dan keranjang selalu menunjuk `kode`
  // varian yang dipilih user secara eksplisit.

  List<PartVarianItem>? get _varian => _varianData?.varian;

  /// Varian yang sedang dipilih; null = tab gabungan "Semua varian".
  PartVarianItem? get _varianAktif {
    final v = _varian;
    if (v == null || _tabVarian.isEmpty) return null;
    for (final x in v) {
      if (x.kode == _tabVarian) return x;
    }
    return null;
  }

  /// Label pendek untuk chip & rincian: `<base>/SN` → "/SN", kartu dasar →
  /// "base". Kode utuh tetap dipakai di tempat yang menentukan pesanan.
  String _labelVarian(String kode) {
    final b = (_varianData?.base ?? '').toUpperCase();
    final k = kode.toUpperCase();
    if (b.isEmpty) return kode;
    if (k == b) return 'base';
    return k.startsWith(b) ? kode.substring(b.length) : kode;
  }

  /// Harga satu varian sebagai teks. Harga yang HILANG (gerbang kolom server)
  /// jadi '—', bukan 'Rp 0' — dirahasiakan ≠ gratis.
  String _hargaVarian(PartVarianItem v) =>
      (v.harga ?? 0) > 0 ? formatRupiah(v.harga) : '—';

  /// LABEL rentang harga keluarga — tidak pernah dirata-rata.
  String? get _rentangHarga {
    final lo = _varianData?.hargaMin;
    final hi = _varianData?.hargaMax;
    if (lo == null || hi == null || lo <= 0 || hi <= 0) return null;
    return lo == hi ? formatRupiah(lo) : '${formatRupiah(lo)} – ${thousands(hi)}';
  }

  /// Harga tampilan. Accurate = sumber utama (juga mengisi part yang harga
  /// lokalnya kosong); katalog lokal = cadangan.
  String get _hargaStr {
    final accHarga = _acc?.harga ?? 0;
    if (accHarga > 0) return formatRupiah(accHarga);
    final lokal = asNum(_part['harga']);
    return (lokal != null && lokal > 0) ? formatRupiah(lokal) : '—';
  }

  bool get _hargaLive => (_acc?.harga ?? 0) > 0;

  /// Berat satuan (gram): katalog dulu, lalu spesifikasi SIMS.
  int get _beratGram {
    final lokal = asInt(_part['berat']);
    return lokal > 0 ? lokal : (_spec?.beratGram ?? 0);
  }

  int _qtyDiKeranjang(String pn) {
    for (final i in _cart.items) {
      if (i.partNumber == pn) return i.qty;
    }
    return 0;
  }

  void _tambahKeKeranjang() {
    final nav = AppNav.of(context);
    _cart.add(CartItem(
      partNumber: _pn,
      name: _name,
      harga: _hargaStr,
      berat: _beratGram,
    ));
    nav.toast('$_pn masuk keranjang',
        actionLabel: 'Lihat', onAction: () => nav.go(MasScreen.keranjang));
  }

  /// Keranjang untuk SATU varian pemasok. `part_number` = kode varian apa
  /// adanya (suffix ikut) supaya server bisa mengunci kartu barang yang persis
  /// itu — harga tiap pemasok beda, jadi tak boleh diwakili PN dasar.
  void _tambahVarian(PartVarianItem v) {
    final nav = AppNav.of(context);
    _cart.add(CartItem(
      partNumber: v.kode,
      name: v.nama.isNotEmpty ? v.nama : _name,
      harga: _hargaVarian(v),
      // Berat part FISIK sama untuk semua varian — yang beda hanya pemasoknya.
      berat: _beratGram,
    ));
    nav.toast('${v.kode} masuk keranjang',
        actionLabel: 'Lihat', onAction: () => nav.go(MasScreen.keranjang));
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final item = _part;
    final pn = _pn;
    final name = _name;
    final model = modelFromFile(item['file'] as String?);
    // Daftar unit dari katalog; selagi fetch berjalan pakai unit baris terpilih.
    final unitList =
        _units.isNotEmpty ? _units : [if (model.isNotEmpty) model];

    // Gating kolom stok/harga — persis web. Pembeli: stok hanya daerahnya sendiri
    // (bukan stok company-wide Accurate) + harga selalu tampil.
    final isBuyer = nav.isBuyer;
    final showStok = nav.showStok;   // pembeli → selalu false di sini
    final showHarga = nav.showHarga;

    return RefreshIndicator(
      onRefresh: _reloadAll,
      color: m.brand600,
      backgroundColor: m.paper,
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _backButton(m),
        const SizedBox(height: 14),
        InkWell(
          onTap: pn.isEmpty ? null : () => _copyPn(pn),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(pn, style: masMono(size: 22, weight: FontWeight.w600, color: m.ink900)),
                  // Part yang sama dipecah jadi beberapa kartu barang Accurate —
                  // beda pemasok, beda harga.
                  if (_varian != null)
                    MasPill(
                        label: '${_varian!.length} varian pemasok',
                        tone: MasPillTone.warn,
                        height: 20),
                ]),
                if (name.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(name, style: TextStyle(fontSize: 13.5, color: m.ink600)),
                ],
                // Baris ala Shopee: "4,8 ★★★★★ | 12 Penilaian".
                if (_jumlahUlasan > 0) ...[
                  const SizedBox(height: 4),
                  RatingRingkas(rata: _rataUlasan, jumlah: _jumlahUlasan),
                ],
              ]),
            ),
            Icon(Icons.copy_rounded, size: 18, color: m.brand600),
          ]),
        ),
        const SizedBox(height: 16),
        _imageCard(m),
        // Pembeli: kartu ringkas stok (daerah sendiri) + harga.
        // Internal: kartu ringkas hanya sejauh izin kolom mengizinkan.
        // Keluarga varian pemasok MENGGANTI kartu-kartu itu (jangan dobel):
        // pembeli dapat daftar varian + keranjang per varian, internal dapat
        // pemilih varian + angka yang mengikuti pilihannya.
        if (isBuyer) ...[
          const SizedBox(height: 14),
          if (_varian != null) _buyerVarianCard(m) else _buyerStatRow(m),
        ] else if (showStok || showHarga) ...[
          const SizedBox(height: 14),
          if (_varian != null) ...[
            _varianChips(m, showStok, showHarga),
            const SizedBox(height: 12),
            _statRowVarian(m, showStok, showHarga),
          ] else
            _statRow(m, showStok, showHarga),
        ],
        // Tombol beli hanya untuk pembeli — peran internal tidak berbelanja.
        if (isBuyer) ...[
          const SizedBox(height: 14),
          _cartCard(m, nav),
        ],
        // Rincian stok per gudang (Accurate/company-wide) — hanya internal yang
        // berizin stok. Pembeli tidak boleh melihat stok gudang lain.
        if (!isBuyer && showStok) ...[
          const SizedBox(height: 14),
          _stokCard(m),
          // Stok PEMASOK Weichai — diambil LIVE saat diminta (tombol). Terpisah
          // dari stok Accurate: beda makna (stok KITA vs ketersediaan PEMASOK).
          // Fitur elevated: DEFAULT hanya admin & akun 'mas', selebihnya harus
          // dicentang admin di Menu Control tab "Fitur" (aturan pemilik 2026-08-25).
          if (nav.showWeichaiStock) ...[
            const SizedBox(height: 14),
            _weichaiCard(m),
          ],
        ],
        const SizedBox(height: 14),
        _specCard(m),
        const SizedBox(height: 14),
        _explodedCard(m),
        // Semua unit yang memakai PN ini (web: "Ditemukan di N unit"). Sebelum
        // katalog terjawab, tampilkan dulu unit dari argumen navigasi supaya
        // bagian ini tidak berkedip muncul-hilang.
        // Daftar model unit = katalog internal; pembeli cukup "Cocok di unit saya?".
        if (!isBuyer && unitList.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
              unitList.length > 1
                  ? 'Ditemukan di ${unitList.length} unit'
                  : 'Ditemukan di unit',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: m.ink700)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final u in unitList)
              MasPill(label: u, tone: MasPillTone.neutral),
          ]),
        ],
        if (pn.isNotEmpty) ...[
          const SizedBox(height: 16),
          _CekUnitCard(pn: pn),
          // Penilaian pembeli ala Shopee — rata-rata, sebaran, filter, ulasan.
          const SizedBox(height: 16),
          UlasanProdukSection(
            key: ValueKey('ulasan-$pn'),
            pn: pn,
            onRingkas: (rata, jumlah) {
              if (!mounted) return;
              if (rata == _rataUlasan && jumlah == _jumlahUlasan) return;
              setState(() {
                _rataUlasan = rata;
                _jumlahUlasan = jumlah;
              });
            },
          ),
        ],
      ],
      ),
    );
  }

  // ── Kartu ringkas: stok total & harga (internal, sesuai izin kolom) ──

  Widget _statRow(MasColors m, bool showStok, bool showHarga) {
    final acc = _acc;
    final stokTotal = acc != null
        ? '${thousands(acc.availableToSell)}${acc.unit.isEmpty ? '' : ' ${acc.unit}'}'
        : (_stokDiketahui != null ? thousands(_stokDiketahui) : '—');

    final stokCard = MasCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          MasEyebrow('Stok total'),
          if (acc != null) const MasPill(label: 'Accurate', tone: MasPillTone.brand, height: 18),
        ]),
        const SizedBox(height: 6),
        if (_loadingStock)
          const MasSkeleton(height: 24)
        else ...[
          Text(stokTotal,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: m.ink900)),
          // Jangan biarkan "—" tanpa penjelasan: user harus tahu bedanya
          // "habis" dan "tidak terbaca".
          if (_stokDiketahui == null)
            Text(_stokGagal ? 'stok live tidak terambil' : 'tidak ada data stok',
                style: TextStyle(fontSize: 11.5, color: m.ink500)),
        ],
      ]),
    );

    final hargaCard = MasCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          MasEyebrow('Harga'),
          if (_hargaLive) const MasPill(label: 'Accurate', tone: MasPillTone.brand, height: 18),
        ]),
        const SizedBox(height: 8),
        Text(_hargaStr, style: masMono(size: 17, weight: FontWeight.w600, color: m.brand700)),
      ]),
    );

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (showStok) Expanded(child: stokCard),
        if (showStok && showHarga) const SizedBox(width: 12),
        if (showHarga) Expanded(child: hargaCard),
      ]),
    );
  }

  // ── Pemilih varian pemasok (internal) ───────────────────────────────

  /// Chip mendatar yang MENGGESER — sengaja bukan `MasSegmentTabs` (lebarnya
  /// dibagi rata & tak bisa digeser): kode varian panjang dan jumlahnya bisa
  /// beberapa, di lebar HP pasti meluber. Default "Semua varian".
  Widget _varianChips(MasColors m, bool showStok, bool showHarga) {
    final varian = _varian!;
    final total = _varianData?.totalAvailable;
    final aktif = _varianAktif;

    Widget chip({
      required String label,
      required String sub,
      required bool dipilih,
      required VoidCallback onTap,
      bool mono = false,
    }) {
      final fg = dipilih ? Colors.white : m.ink700;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dipilih ? m.brand700 : m.paper,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: dipilih ? m.brand700 : m.ink200),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                label,
                style: mono
                    ? masMono(size: 12, weight: FontWeight.w600, color: fg)
                    : TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(sub,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: dipilih ? Colors.white.withValues(alpha: 0.75) : m.ink500,
                    )),
              ],
            ]),
          ),
        ),
      );
    }

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip(
            label: 'Semua varian',
            sub: showStok && total != null ? thousands(total) : '',
            dipilih: aktif == null,
            onTap: () => setState(() => _tabVarian = ''),
          ),
          for (final v in varian)
            chip(
              label: v.kode,
              mono: true,
              // Angka yang dicabut gerbang kolom cukup dihilangkan dari chip —
              // jangan diganti 0 (itu terbaca "habis"/"gratis").
              sub: [
                if (showStok && v.stok != null) thousands(v.stok),
                if (showHarga && (v.harga ?? 0) > 0) formatRupiah(v.harga),
              ].join(' · '),
              dipilih: aktif?.kode == v.kode,
              onTap: () => setState(() => _tabVarian = v.kode),
            ),
        ],
      ),
    );
  }

  // ── Kartu ringkas versi VARIAN (internal) ───────────────────────────

  /// Menggantikan `_statRow` (jangan dirender dobel). Tab "Semua" = total
  /// keluarga + LABEL rentang harga; tab satu varian = angka PASTI kartu itu
  /// plus kode Accurate-nya. Ditumpuk ke bawah, bukan dua kolom: teks rentang
  /// ("Rp 285.000 – 455.000") tak muat di setengah lebar HP.
  Widget _statRowVarian(MasColors m, bool showStok, bool showHarga) {
    final varian = _varian!;
    final aktif = _varianAktif;
    final total = _varianData?.totalAvailable;
    final unit = aktif?.unit ?? (varian.isNotEmpty ? varian.first.unit : '');

    String satuan(String s) => unit.isEmpty ? s : '$s $unit';
    final stokTeks = aktif != null
        ? (aktif.stok != null ? satuan(thousands(aktif.stok)) : '—')
        : (total != null ? satuan(thousands(total)) : '—');

    final kartu = <Widget>[];

    if (showStok) {
      kartu.add(MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            MasEyebrow(aktif != null ? 'Stok varian ini' : 'Stok total'),
            const MasPill(label: 'Accurate', tone: MasPillTone.brand, height: 18),
          ]),
          const SizedBox(height: 6),
          Text(stokTeks,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: m.ink900)),
          const SizedBox(height: 6),
          if (aktif != null)
            Text(aktif.nama, style: TextStyle(fontSize: 11.5, color: m.ink500))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final v in varian)
                MasPill(
                  label: '${_labelVarian(v.kode)} ${v.stok != null ? thousands(v.stok) : '—'}',
                  tone: MasPillTone.neutral,
                  height: 20,
                ),
            ]),
        ]),
      ));
    }

    if (showHarga) {
      kartu.add(MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            MasEyebrow('Harga'),
            const MasPill(label: 'Accurate', tone: MasPillTone.brand, height: 18),
          ]),
          const SizedBox(height: 8),
          Text(aktif != null ? _hargaVarian(aktif) : (_rentangHarga ?? '—'),
              style: masMono(size: 17, weight: FontWeight.w600, color: m.brand700)),
          const SizedBox(height: 4),
          Text(
            aktif != null
                ? 'harga pasti varian ini — dipakai keranjang & penawaran'
                : 'beda per pemasok — pilih varian untuk harga pasti',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: m.ink500),
          ),
        ]),
      ));
    }

    kartu.add(MasCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        MasEyebrow('Kode Accurate'),
        const SizedBox(height: 6),
        Text(aktif != null ? aktif.kode : '${varian.length} kartu barang',
            style: masMono(size: 14, weight: FontWeight.w600, color: m.ink900)),
        const SizedBox(height: 4),
        Text(
          aktif != null
              ? (aktif.no.isEmpty ? '—' : aktif.no)
              : [for (final v in varian) v.kode].join(' · '),
          style: masMono(size: 11.5, color: m.ink500),
        ),
      ]),
    ));

    return Column(children: [
      for (int i = 0; i < kartu.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        kartu[i],
      ],
    ]);
  }

  // ── Pembeli: pilih varian pemasok ───────────────────────────────────

  /// SATU BARIS per kartu Accurate — harga & stok wilayah PASTI milik varian
  /// itu, dan tombol keranjang menunjuk `kode` spesifik (tak ada penjualan
  /// atas nama "gabungan"). Tetap TANPA sebaran antar-gudang: pembeli tidak
  /// berhak melihat stok cabang lain.
  Widget _buyerVarianCard(MasColors m) {
    final varian = _varian!;
    final berat = _beratGram;
    final baris = <Widget>[];

    for (int i = 0; i < varian.length; i++) {
      final v = varian[i];
      final harga = _hargaVarian(v);
      final stok = v.stokWilayah; // null = TIDAK DIKETAHUI, bukan habis
      final qty = _qtyDiKeranjang(v.kode);

      Widget aksi;
      if (stok != null && stok <= 0) {
        // Tombol hanya ditutup bila stok BENAR-BENAR diketahui nol; stok yang
        // tak terbaca dibiarkan lewat — server memvalidasi ulang saat checkout.
        aksi = _alertBox(m, 'Stok habis di wilayahmu.', danger: true);
      } else if (!hasPrice(harga)) {
        aksi = _alertBox(m, 'Harga varian ini belum tersedia, jadi belum bisa dibeli.');
      } else if (!hasWeight(berat)) {
        // Tanpa berat, ongkir tak bisa dihitung → checkout pasti ditolak server.
        aksi = _alertBox(m,
            'Berat part belum ditetapkan, jadi ongkir tidak bisa dihitung dan varian ini belum bisa dibeli.');
      } else if (qty > 0) {
        aksi = Row(children: [
          _stepBtn(m, Icons.remove_rounded,
              () => qty <= 1 ? _cart.remove(v.kode) : _cart.setQty(v.kode, qty - 1)),
          SizedBox(
            width: 46,
            child: Center(
              child: Text('$qty', style: masMono(size: 14, weight: FontWeight.w700, color: m.ink900)),
            ),
          ),
          _stepBtn(m, Icons.add_rounded, () => _cart.setQty(v.kode, qty + 1)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('sudah di keranjang',
                style: TextStyle(fontSize: 11.5, color: m.ink500)),
          ),
        ]);
      } else {
        aksi = MasButton(
          label: '+ Keranjang',
          icon: Icons.shopping_cart_outlined,
          height: 38,
          expand: true,
          onTap: () => _tambahVarian(v),
        );
      }

      baris.add(Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: m.ink100)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(v.kode, style: masMono(size: 13, weight: FontWeight.w600, color: m.ink900)),
                if ((v.nama.isNotEmpty ? v.nama : _name).isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(v.nama.isNotEmpty ? v.nama : _name,
                      style: TextStyle(fontSize: 11.5, color: m.ink500)),
                ],
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Text(harga, style: masMono(size: 14, weight: FontWeight.w600, color: m.brand700)),
              const SizedBox(height: 2),
              // Stok yang tak terbaca ditulis '—': dirahasiakan ≠ habis.
              Text('stok wilayahmu: ${stok != null ? thousands(stok) : '—'}',
                  style: TextStyle(fontSize: 11.5, color: m.ink500)),
            ]),
          ]),
          const SizedBox(height: 10),
          aksi,
        ]),
      ));
    }

    baris.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Text('Part fisik sama, pemasok berbeda — harga mengikuti varian yang dipilih.',
          style: TextStyle(fontSize: 11.5, height: 1.45, color: m.ink400)),
    ));

    return MasSectionCard(
      title: 'Pilih varian pemasok',
      trailing: MasPill(label: '${varian.length} pilihan', tone: MasPillTone.warn, height: 20),
      children: baris,
    );
  }

  // ── Kartu ringkas pembeli: stok daerah sendiri + harga (selalu) ─────

  Widget _buyerStatRow(MasColors m) {
    final stok = _stokBuyer;
    final loc = _lokasiBuyer;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: MasCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              MasEyebrow('Stok tersedia'),
              const SizedBox(height: 6),
              if (_loadingStock)
                const MasSkeleton(height: 24)
              else ...[
                Text(stok == null ? '—' : thousands(stok),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: m.ink900)),
                Text(stok != null && loc != null ? 'di $loc' : 'stok tidak tersedia',
                    style: TextStyle(fontSize: 11.5, color: m.ink500)),
              ],
            ]),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MasCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                MasEyebrow('Harga'),
                if (_hargaLive) const MasPill(label: 'Accurate', tone: MasPillTone.brand, height: 18),
              ]),
              const SizedBox(height: 8),
              Text(_hargaStr, style: masMono(size: 17, weight: FontWeight.w600, color: m.brand700)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Keranjang (pembeli) ─────────────────────────────────────────────

  Widget _cartCard(MasColors m, AppNav nav) {
    final pn = _pn;
    // Pembeli memakai stok TERSCOPE daerahnya, bukan stok company-wide Accurate.
    final stok = _stokBuyer;
    final berat = _beratGram;
    final qty = _qtyDiKeranjang(pn);

    final varian = _varian;

    Widget aksi;
    if (varian != null) {
      // Keluarga varian pemasok: harga & stok BEDA tiap kartu, jadi tak ada
      // tombol beli "gabungan" di sini — keranjang diisi dari kartu "Pilih
      // varian pemasok" di atas supaya pesanan selalu menunjuk kode spesifik.
      aksi = _alertBox(m,
          'Part ini punya ${varian.length} varian pemasok dengan harga berbeda — pilih salah satunya di kartu di atas.');
    } else if (stok != null && stok <= 0) {
      // Hanya menutup tombol bila stok BENAR-BENAR diketahui nol. Stok yang gagal
      // diambil dibiarkan lewat — server tetap memvalidasi ulang saat checkout.
      aksi = _alertBox(m, 'Stok habis — part ini belum bisa dibeli.', danger: true);
    } else if (!hasPrice(_hargaStr)) {
      aksi = _alertBox(m, 'Harga belum tersedia untuk part ini, jadi belum bisa dibeli.');
    } else if (!hasWeight(berat)) {
      // Tanpa berat, ongkir tidak bisa dihitung → checkout pasti ditolak server.
      aksi = _alertBox(m,
          'Berat part belum ditetapkan, jadi ongkir tidak bisa dihitung dan part ini belum bisa dibeli.');
    } else if (qty > 0) {
      aksi = Row(children: [
        _stepBtn(m, Icons.remove_rounded,
            () => qty <= 1 ? _cart.remove(pn) : _cart.setQty(pn, qty - 1)),
        SizedBox(
          width: 46,
          child: Center(
            child: Text('$qty', style: masMono(size: 14, weight: FontWeight.w700, color: m.ink900)),
          ),
        ),
        _stepBtn(m, Icons.add_rounded, () => _cart.setQty(pn, qty + 1)),
        const SizedBox(width: 10),
        Expanded(
          child: MasButton(
            label: 'Lihat keranjang',
            primary: false,
            height: 38,
            expand: true,
            onTap: () => nav.go(MasScreen.keranjang),
          ),
        ),
      ]);
    } else {
      aksi = MasButton(
        label: '+ Keranjang',
        icon: Icons.shopping_cart_outlined,
        height: 40,
        expand: true,
        onTap: _tambahKeKeranjang,
      );
    }

    return MasCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: MasEyebrow('Beli part ini')),
          if (berat > 0)
            Text('${thousands(berat)} g / pcs', style: TextStyle(fontSize: 11.5, color: m.ink500)),
        ]),
        const SizedBox(height: 10),
        aksi,
        // Ikut web: pembeli bisa langsung menanyakan ketersediaan ke gudang.
        // Berguna justru saat tombol beli tertutup (stok habis / harga & berat
        // belum ada), jadi selalu ditampilkan — bukan hanya saat bisa dibeli.
        const SizedBox(height: 8),
        MasButton(
          label: 'Chat Gudang',
          icon: Icons.chat_bubble_outline_rounded,
          primary: false,
          height: 38,
          expand: true,
          loading: _bukaChat,
          onTap: () => _chatGudang(nav),
        ),
      ]),
    );
  }

  Widget _stepBtn(MasColors m, IconData icon, VoidCallback onTap) => SizedBox(
        width: 38,
        height: 38,
        child: Material(
          color: m.paper,
          borderRadius: BorderRadius.circular(MasRadii.input),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(MasRadii.input),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(MasRadii.input),
                border: Border.all(color: m.ink200),
              ),
              child: Icon(icon, size: 16, color: m.ink700),
            ),
          ),
        ),
      );

  // ── Stok per gudang (Accurate) ──────────────────────────────────────

  Widget _stokCard(MasColors m) {
    if (_loadingStock) return const MasSkeleton(height: 120);

    final acc = _acc;
    final varian = _varian;
    final aktif = _varianAktif;
    final lokal = _gudangLokal;
    final children = <Widget>[];

    // Angka stok benar-benar terbaca hanya bila Accurate menjawab & tidak gagal.
    // Membedakan ini penting: gudang tanpa angka boleh ditulis '0' saat datanya
    // lengkap, tapi harus '—' saat stok live-nya memang tak diketahui.
    // Di mode varian sumbernya endpoint varian (Accurate juga) yang SUDAH
    // menjawab, jadi 0 di sana memang berarti kosong.
    final stokTerbaca = varian != null || (acc != null && !_stokGagal);

    // Baris = gabungan gudang ber-STOK (Accurate) dan gudang ber-RAK. Gudang
    // yang stoknya 0 tapi punya rak TETAP ditampilkan: justru saat barang habis
    // orang paling butuh tahu rak lamanya (buat dicek ulang / diisi kembali).
    final labels = <String>[];
    final qty = <String, int>{};
    final display = <String, String>{};
    // Mode gabungan: gudang → rincian per varian, dipakai sebagai sub-chip.
    final rincian = <String, List<(String, int)>>{};

    if (varian == null) {
      for (final g in acc?.perGudang ?? const <GudangQty>[]) {
        // ⚠️ Kunci rak WAJIB label PENUH Accurate (`gudang`); `deskripsi` hanya
        // untuk dibaca manusia dan tak pernah cocok dengan baris rak.
        final key = g.gudang;
        if (key.isEmpty) continue;
        if (!labels.contains(key)) labels.add(key);
        qty[key] = g.qty;
        display[key] = g.deskripsi.isNotEmpty ? g.deskripsi : g.gudang;
      }
    } else {
      // Satu varian terpilih → sebaran kartu itu saja; tab "Semua" → jumlah
      // seluruh varian per gudang + rincian siapa menyumbang berapa.
      for (final v in aktif != null ? [aktif] : varian) {
        for (final g in v.perGudang) {
          final key = g.gudang;
          if (key.isEmpty) continue;
          if (!labels.contains(key)) labels.add(key);
          qty[key] = (qty[key] ?? 0) + g.qty;
          if (aktif == null) {
            (rincian[key] ??= <(String, int)>[]).add((_labelVarian(v.kode), g.qty));
          }
        }
      }
    }
    for (final key in _rak.keys) {
      if (!labels.contains(key)) labels.add(key);
    }
    if (varian != null) {
      // Endpoint varian tak menjanjikan urutan gudang — urutkan terbanyak dulu
      // (persis web) supaya gudang yang paling berisi ada di atas.
      labels.sort((a, b) {
        final c = (qty[b] ?? 0).compareTo(qty[a] ?? 0);
        return c != 0 ? c : a.compareTo(b);
      });
    }

    // Peringatan stok live hanya relevan bila angka yang dipajang memang
    // berasal dari `accurate-stock`; di mode varian sumbernya lain.
    if (_stokGagal && varian == null) {
      children.add(Padding(
        padding: const EdgeInsets.all(14),
        child: _alertBox(m, _stokGagalPesan),
      ));
    }

    if (labels.isNotEmpty) {
      for (int i = 0; i < labels.length; i++) {
        final key = labels[i];
        children.add(_gudangRow(
          m,
          label: key,
          display: display[key] ?? key,
          qty: qty[key],
          stokTerbaca: stokTerbaca,
          rincian: rincian[key],
          divider: varian != null || i < labels.length - 1,
        ));
      }
      if (varian != null) {
        // Total = jumlah baris yang BENAR-BENAR dipajang (bukan
        // `total_available`), supaya kaki tabel selalu konsisten dengan isinya.
        children.add(MasKeyValue(
          label: 'Total',
          value: thousands(labels.fold<int>(0, (n, k) => n + (qty[k] ?? 0))),
          mono: true,
          divider: false,
        ));
        children.add(_infoText(m,
            'Rak dicatat per gudang untuk part ini (berlaku untuk semua varian).'));
      }
    } else if (varian != null) {
      children.add(_infoText(m,
          aktif != null
              ? 'Accurate tidak memberi rincian per gudang untuk varian ini.'
              : 'Accurate tidak memberi rincian per gudang untuk varian part ini.'));
    } else if (!_stokGagal) {
      children.add(_infoText(
        m,
        acc != null
            ? 'Accurate tidak memberi rincian per gudang untuk part ini.'
            // Accurate hidup & terkonfigurasi, tapi PN-nya tidak ada di sana.
            : 'Part ini tidak ditemukan di Accurate.',
      ));
    }

    // Data katalog masih berguna sebagai perkiraan — tapi harus jelas labelnya.
    // Di mode varian tak dipakai: angka katalog tak bisa dipilah per pemasok,
    // menempelkannya di bawah rincian varian justru menyesatkan.
    if (varian == null && (_stokGagal || acc == null) && lokal.isNotEmpty) {
      children.add(_subHeader(
        m,
        _stokGagal
            ? 'Cadangan dari katalog (export Accurate) — bisa basi'
            : 'Stok menurut katalog',
      ));
      for (int i = 0; i < lokal.length; i++) {
        children.add(MasKeyValue(
          label: lokal[i].$1,
          value: lokal[i].$2,
          mono: true,
          divider: i < lokal.length - 1,
        ));
      }
    }

    return MasSectionCard(
      title: 'Stok per Gudang',
      trailing: (acc != null || varian != null)
          ? Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const MasPill(label: 'Accurate', tone: MasPillTone.brand, height: 20),
              // Tegaskan angka di bawah ini milik siapa: satu kartu pemasok,
              // atau gabungan seluruh keluarga.
              if (varian != null)
                MasPill(
                    label: aktif != null ? aktif.kode : 'gabungan varian',
                    tone: MasPillTone.neutral,
                    height: 20),
            ])
          : null,
      children: children,
    );
  }

  /// Satu baris gudang — bentuknya meniru MasKeyValue, tapi BISA DIBUKA (ketuk)
  /// untuk menampilkan lokasi rak, catatan & foto kartu stok gudang itu.
  /// [rincian] hanya terisi di mode gabungan varian: (label pendek varian, qty).
  Widget _gudangRow(
    MasColors m, {
    required String label,
    required String display,
    required int? qty,
    required bool stokTerbaca,
    required bool divider,
    List<(String, int)>? rincian,
  }) {
    final info = _rak[label];
    final terbuka = _bukaGudang == label;
    final nilai = qty != null ? thousands(qty) : (stokTerbaca ? '0' : '—');

    return Container(
      decoration: BoxDecoration(
        border: divider ? Border(bottom: BorderSide(color: m.ink100)) : null,
      ),
      child: Column(children: [
        InkWell(
          // Hanya satu baris terbuka: kartu ini bisa berisi belasan gudang.
          onTap: () => setState(() => _bukaGudang = terbuka ? null : label),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(children: [
              Icon(terbuka ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 16, color: m.ink400),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(display, style: TextStyle(fontSize: 13, color: m.ink600)),
                    // Kode rak ikut terbaca TANPA membuka barisnya — itu satu
                    // informasi yang paling dicari staf saat menyisir gudang.
                    if (info != null && info.rak.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('rak ${info.rak}',
                          style: masMono(size: 11.5, color: m.brand700)),
                    ],
                    // Sub-chip per varian: di lebar HP jauh lebih terbaca
                    // daripada tabel satu kolom per varian seperti di web.
                    if (rincian != null && rincian.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(spacing: 5, runSpacing: 4, children: [
                        for (final r in rincian)
                          MasPill(
                              label: '${r.$1} ${thousands(r.$2)}',
                              tone: MasPillTone.neutral,
                              height: 19),
                      ]),
                    ],
                  ],
                ),
              ),
              if (qty == null && stokTerbaca) ...[
                const MasPill(label: 'stok 0', tone: MasPillTone.warn, height: 20),
                const SizedBox(width: 8),
              ],
              Text(nilai,
                  style: masMono(size: 13, weight: FontWeight.w600, color: m.ink900)),
            ]),
          ),
        ),
        if (terbuka) _panelRak(m, label),
      ]),
    );
  }

  /// Isi baris yang dibentangkan: rak · catatan · foto kartu stok · jejak.
  Widget _panelRak(MasColors m, String label) {
    final nav = AppNav.of(context);
    final info = _rak[label];
    final kosong = info == null || info.kosong;
    final anak = <Widget>[];

    if (_loadingRak) {
      anak.add(const MasSkeleton(height: 56));
    } else if (kosong) {
      anak.add(Text(
        'Belum ada lokasi rak tercatat untuk gudang ini.',
        style: TextStyle(fontSize: 12.5, height: 1.45, color: m.ink500),
      ));
    } else {
      anak.add(Row(children: [
        Icon(Icons.shelves, size: 15, color: m.brand600),
        const SizedBox(width: 7),
        Expanded(
          child: Text('Rak ${info.rak}',
              style: masMono(size: 13.5, weight: FontWeight.w600, color: m.ink900)),
        ),
      ]));
      if (info.catatan.trim().isNotEmpty) {
        anak
          ..add(const SizedBox(height: 6))
          ..add(Text(info.catatan,
              style: TextStyle(fontSize: 12.5, height: 1.45, color: m.ink600)));
      }
      if (info.fotoUrl.isNotEmpty) {
        anak
          ..add(const SizedBox(height: 10))
          ..add(RakFotoView(url: info.fotoUrl))
          ..add(const SizedBox(height: 4))
          ..add(Text('Foto kartu stok · ketuk untuk perbesar',
              style: TextStyle(fontSize: 11, color: m.ink400)));
      }
      final jejak = jejakRak(info);
      if (jejak.isNotEmpty) {
        anak
          ..add(const SizedBox(height: 8))
          ..add(Text(jejak, style: TextStyle(fontSize: 11, color: m.ink400)));
      }
    }

    // Tombol ubah hanya untuk pengelola gudang INI (admin kebal). Pagar tampilan
    // saja — server tetap menolak 403 kalau ditembus.
    if (nav.bolehUbahRak(label)) {
      anak
        ..add(const SizedBox(height: 10))
        ..add(MasButton(
          label: kosong ? 'Isi rak' : 'Ubah',
          icon: Icons.edit_outlined,
          primary: false,
          height: 38,
          expand: true,
          onTap: () => _ubahRak(label),
        ));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: m.ink50,
        border: Border(top: BorderSide(color: m.ink100)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: anak),
    );
  }

  Future<void> _ubahRak(String label) async {
    final hasil = await showRakEditor(
      context,
      pn: _pn,
      gudang: label,
      awal: _rak[label],
    );
    if (hasil == null || !mounted) return;
    final baru = Map<String, RakInfo>.from(_rak);
    if (hasil.dihapus || hasil.info == null) {
      baru.remove(label);
    } else {
      baru[label] = hasil.info!;
    }
    setState(() => _rak = baru);
    AppNav.of(context).toast(hasil.dihapus ? 'Data rak dihapus.' : 'Rak disimpan.');
  }

  // ── Spesifikasi fisik (SIMS) ────────────────────────────────────────

  /// Layar penuh + zoom untuk gambar exploded (bytes, bukan URL — jadi tak bisa
  /// memakai _FullscreenGallery yang menerima daftar URL foto SIMS).
  void _bukaExplodedPenuh(Uint8List png) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (ctx, _, _) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.black54,
          foregroundColor: Colors.white,
          title: const Text('Exploded view'),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 6,
            child: Container(
              color: Colors.white,
              child: Image.memory(png, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    ));
  }

  // ── Exploded view (EPC, tanpa nomor rangka) ─────────────────────────
  Widget _explodedCard(MasColors m) {
    final d = _exploded;
    final anak = <Widget>[];

    if (d == null && !_explodedBusy && _explodedErr == null) {
      anak.add(Text(
        'Gambar rakitan resmi EPC yang memuat part ini, tanpa perlu nomor rangka. '
        'Tidak dimuat otomatis karena pencarian pertamanya bisa memakan 1-2 menit '
        '(terukur 94 detik untuk part yang dipakai belasan ribu model). Sesudah itu '
        'tersimpan di server 24 jam, jadi pembukaan berikutnya seketika.',
        style: TextStyle(fontSize: 12, height: 1.5, color: m.ink500),
      ));
    }
    if (_explodedBusy) anak.add(const MasSkeleton(height: 180));
    if (_explodedErr != null) anak.add(_alertBox(m, _explodedErr!));
    if (d != null && !d.found) {
      anak.add(_alertBox(
          m, d.alasan ?? 'Figure exploded view tidak ditemukan untuk part ini.'));
    }
    if (d != null && d.found && d.png != null) {
      anak.addAll([
        GestureDetector(
          onTap: () => _bukaExplodedPenuh(d.png!),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              color: Colors.white,
              width: double.infinity,
              child: Image.memory(d.png!, fit: BoxFit.contain, gaplessPlayback: true),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (d.figureNama != null)
          Text(
            'Figure: ${d.figureNama}'
            '${d.figurePn != null ? ' (${d.figurePn})' : ''}'
            '${d.jumlahItem != null ? ' · ${d.jumlahItem} part di gambar' : ''}',
            style: TextStyle(fontSize: 12, height: 1.5, color: m.ink600),
          ),
        // Peringatan lintas-model dari server — tampil apa adanya.
        if (d.catatan != null) ...[
          const SizedBox(height: 4),
          Text('⚠️ ${d.catatan}',
              style: TextStyle(fontSize: 11.5, height: 1.5, color: m.ink500)),
        ],
      ]);
    }

    return MasSectionCard(
      title: 'Exploded View',
      trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const MasPill(label: 'sumber: EPC', tone: MasPillTone.neutral, height: 20),
        if (d != null && d.found && d.balon != null)
          MasPill(label: 'balon ${d.balon}', tone: MasPillTone.neutral, height: 20),
        if (d == null)
          TextButton(
            onPressed: _explodedBusy ? null : _loadExploded,
            child: Text(_explodedBusy ? 'memuat…' : 'Tampilkan',
                style: const TextStyle(fontSize: 12)),
          ),
      ]),
      children: anak,
    );
  }

  // ── Stok PEMASOK Weichai (portal tci-pnp) ───────────────────────────
  // Diambil LIVE saat staf menekan "Cek stok Weichai" — bukan tiap buka layar
  // (portal lambat ~5-8 dtk & di balik Cloudflare). Beda makna dari stok
  // Accurate: ketersediaan di PEMASOK untuk restok, bukan stok yang kita pegang.
  // Portal tak memberi harga → STOK saja. Internal-only (server blokir pembeli).
  Widget _weichaiCard(MasColors m) {
    final d = _weichai;
    final stock = (d != null && d.found) ? d.stock : null;

    final anak = <Widget>[];
    if (d == null && !_weichaiBusy && _weichaiErr == null) {
      anak.add(Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          'Ketersediaan di pemasok Weichai untuk restok — diambil langsung dari '
          'portal saat diminta (±5–8 dtk). Tanpa harga.',
          style: TextStyle(fontSize: 12.5, height: 1.5, color: m.ink500),
        ),
      ));
    } else if (_weichaiBusy) {
      anak.add(Padding(
        padding: const EdgeInsets.all(14),
        child: Text('Mengecek ke portal Weichai…',
            style: TextStyle(fontSize: 12.5, color: m.ink500)),
      ));
    } else if (_weichaiErr != null) {
      anak.add(Padding(padding: const EdgeInsets.all(14), child: _alertBox(m, _weichaiErr!)));
    } else if (d != null && !d.configured) {
      anak.add(Padding(
        padding: const EdgeInsets.all(14),
        child: Text('Portal Weichai belum dikonfigurasi di server.',
            style: TextStyle(fontSize: 12.5, color: m.ink500)),
      ));
    } else if (d != null && d.error) {
      anak.add(Padding(
        padding: const EdgeInsets.all(14),
        child: _alertBox(m, 'Gagal login/koneksi ke portal Weichai. Coba lagi.'),
      ));
    } else if (stock == null) {
      anak.add(Padding(
        padding: const EdgeInsets.all(14),
        child: Text('Part ini tidak tersedia di Weichai.',
            style: TextStyle(fontSize: 12.5, color: m.ink500)),
      ));
    } else {
      anak.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          Text('${thousands(stock.total)} ${stock.satuan}'.trim(),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: m.ink900)),
          const SizedBox(width: 8),
          Text('tersedia di pemasok', style: TextStyle(fontSize: 12, color: m.ink500)),
        ]),
      ));
      if (stock.perCabang.isNotEmpty) {
        for (int i = 0; i < stock.perCabang.length; i++) {
          final b = stock.perCabang[i];
          anak.add(MasKeyValue(
            label: b.cabang,
            value: '${thousands(b.qty)} ${b.satuan}'.trim(),
            divider: true,
          ));
        }
      }
      anak.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Text('Sumber: portal Weichai (tci-pnp) · stok pemasok, bukan stok kita.',
            style: TextStyle(fontSize: 11.5, color: m.ink400)),
      ));
    }

    return MasSectionCard(
      title: 'Stok Pemasok',
      trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const MasPill(label: 'Weichai', tone: MasPillTone.info, height: 20),
        if (!_weichaiBusy)
          TextButton(
            onPressed: _cekWeichai,
            child: Text(d == null ? 'Cek stok Weichai' : '↻ Perbarui',
                style: const TextStyle(fontSize: 12)),
          ),
      ]),
      children: anak,
    );
  }

  Widget _specCard(MasColors m) {
    if (_loadingSpec) return const MasSkeleton(height: 120);

    final rows = _specRows(_spec?.spec, isBuyer: AppNav.of(context).isBuyer);
    final catatan = <Widget>[];

    if (_specErr != null) {
      catatan.add(_alertBox(m, 'Spesifikasi SIMS gagal dimuat: $_specErr'));
    } else if (_spec?.spec.isEmpty ?? true) {
      catatan.add(_alertBox(m, 'Belum ada data spesifikasi (berat & dimensi) di SIMS.'));
    }
    // Berat = dasar hitung ongkir. Tanpa berat, part tidak bisa dibeli sama
    // sekali, jadi ini wajib disebut — bukan sekadar kolom kosong.
    if (_beratGram == 0) {
      catatan.add(_alertBox(m,
          'Berat belum ditetapkan. Berat dipakai untuk menghitung ongkir, sehingga part ini belum bisa dibeli.'));
    }

    if (rows.isEmpty && catatan.isEmpty) return const SizedBox.shrink();

    return MasSectionCard(
      title: 'Spesifikasi',
      trailing: const MasPill(label: 'sumber: SIMS', tone: MasPillTone.neutral, height: 20),
      children: [
        for (int i = 0; i < rows.length; i++)
          MasKeyValue(
            label: rows[i].$1,
            value: rows[i].$2,
            divider: i < rows.length - 1 || catatan.isNotEmpty,
          ),
        for (final c in catatan)
          Padding(padding: const EdgeInsets.all(14), child: c),
      ],
    );
  }

  /// Baris spesifikasi: SIMS lebih dipercaya daripada kolom katalog, jadi nilai
  /// katalog hanya dipakai untuk mengisi yang belum ada.
  List<(String, String)> _specRows(PartSpec? s, {bool isBuyer = false}) {
    final item = _part;
    final rows = <(String, String)>[];

    if (s != null) {
      final bk = s.beratKirimKg;
      final bb = s.beratBersihKg;
      if (bk != null) rows.add(('Berat (kirim)', '$bk kg'));
      if (bb != null && bb != bk) rows.add(('Berat (bersih)', '$bb kg'));
      if ((s.dimensiCm ?? '').isNotEmpty) rows.add(('Dimensi (P×L×T)', '${s.dimensiCm} cm'));
      if ((s.satuan ?? '').isNotEmpty) rows.add(('Satuan', s.satuan!));
      // Kemasan minimum = MOQ pembelian ke pabrik — internal saja (paritas web).
      if (!isBuyer && s.kemasanMinimum != null) rows.add(('Kemasan minimum', '${s.kemasanMinimum}'));
      if ((s.merek ?? '').isNotEmpty) rows.add(('Merek', s.merek!));
    }

    bool ada(String label) => rows.any((r) => r.$1 == label);

    final model = modelFromFile(item['file'] as String?);
    final merek = '${item['merek'] ?? item['brand'] ?? ''}';
    final satuan = '${item['satuan'] ?? ''}';
    final sheet = '${item['sheet'] ?? ''}';
    if (model.isNotEmpty) rows.add(('Unit / Model', model));
    if (merek.isNotEmpty && !ada('Merek')) rows.add(('Merek', merek));
    if (satuan.isNotEmpty && !ada('Satuan')) rows.add(('Satuan', satuan));
    if (sheet.isNotEmpty) rows.add(('Sumber', sheet));

    return rows;
  }

  // ── Potongan UI kecil ───────────────────────────────────────────────

  Widget _subHeader(MasColors m, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
        decoration: BoxDecoration(
          color: m.ink50,
          border: Border(bottom: BorderSide(color: m.ink100)),
        ),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: m.ink500)),
      );

  Widget _infoText(MasColors m, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Text(text, style: TextStyle(fontSize: 13, color: m.ink500)),
      );

  Widget _backButton(MasColors m) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.input),
        child: InkWell(
          onTap: () => AppNav.of(context).back(),
          borderRadius: BorderRadius.circular(MasRadii.input),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MasRadii.input),
              border: Border.all(color: m.ink200),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.arrow_back_rounded, size: 15, color: m.ink800),
              const SizedBox(width: 6),
              Text('Kembali', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: m.ink800)),
            ]),
          ),
        ),
      ),
    );
  }

  /// Galeri ala Shopee/Tokopedia (paritas web `GaleriProduk.tsx`): SATU foto
  /// utama yang bisa diusap + penanda "2/7" + deretan thumbnail. Ketuk foto
  /// utama → layar penuh. Tombol "✕ salah" (admin) menempel di foto aktif.
  Widget _imageCard(MasColors m) {
    final isAdmin = AppNav.of(context).isAdmin;
    final n = _photos.length;
    final aktif = n == 0 ? 0 : _fotoIdx.clamp(0, n - 1);

    Widget utama() {
      if (_loadingPhotos) {
        return AspectRatio(aspectRatio: 1, child: MasSkeleton(height: double.infinity));
      }
      if (n == 0) return AspectRatio(aspectRatio: 1, child: HatchBox(label: 'Tidak ada gambar'));
      return AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(children: [
            PageView.builder(
              controller: _fotoCtl,
              itemCount: n,
              onPageChanged: (i) => setState(() => _fotoIdx = i),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _openGallery(i),
                child: Container(
                  color: Colors.white,
                  child: Image.network(
                    ApiService.partImageUrl(_photos[i]),
                    fit: BoxFit.contain,
                    loadingBuilder: (c, w, p) => p == null ? w : Center(
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: m.brand100)),
                    errorBuilder: (c, e, s) => HatchBox(label: 'foto ${i + 1}'),
                  ),
                ),
              ),
            ),
            if (n > 1)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('${aktif + 1}/$n',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            if (isAdmin)
              Positioned(
                top: 6,
                right: 6,
                child: Material(
                  color: m.paper.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _fotoBusy ? null : () => _tandaiFotoSalah(_photos[aktif]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      child: Text('✕ salah',
                          style: TextStyle(
                              fontSize: 10.5, color: _fotoBusy ? m.ink400 : m.danger600)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
    }

    Widget deretan() => SizedBox(
          height: 58,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: n,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () {
                setState(() => _fotoIdx = i);
                if (_fotoCtl.hasClients) {
                  _fotoCtl.animateToPage(i,
                      duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
                }
              },
              child: Container(
                width: 58,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: i == aktif ? m.brand600 : m.ink200, width: i == aktif ? 2 : 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.network(ApiService.partImageUrl(_photos[i]),
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => const SizedBox.shrink()),
              ),
            ),
          ),
        );

    return MasCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Gambar Part', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: m.ink900)),
          const SizedBox(width: 8),
          const MasPill(label: 'sumber: SIMS', tone: MasPillTone.neutral, height: 20),
        ]),
        const SizedBox(height: 12),
        utama(),
        if (n > 1) ...[
          const SizedBox(height: 8),
          deretan(),
        ],
        if (isAdmin && _fotoTersembunyi > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text('$_fotoTersembunyi foto disembunyikan (bukan part ini)',
                  style: TextStyle(fontSize: 11.5, color: m.ink400)),
            ),
            TextButton(
              onPressed: _fotoBusy ? null : _pulihkanFoto,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('Pulihkan', style: TextStyle(fontSize: 11.5)),
            ),
          ]),
        ],
      ]),
    );
  }
}

/// Kotak peringatan (warn) / galat (danger) — dipakai di beberapa kartu.
Widget _alertBox(MasColors m, String text, {bool danger = false}) {
  final fg = danger ? m.danger600 : m.warn600;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: danger ? m.danger50 : m.warn50,
      borderRadius: BorderRadius.circular(MasRadii.input),
      border: Border.all(color: danger ? m.dangerBorder : m.warnBorder),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(danger ? Icons.error_outline_rounded : Icons.warning_amber_rounded, size: 15, color: fg),
      const SizedBox(width: 7),
      Expanded(
        child: Text(text, style: TextStyle(fontSize: 12.5, height: 1.45, color: fg)),
      ),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════
// "Cocok di unit saya?" — verifikasi part ke BOM EPC per-VIN
// ══════════════════════════════════════════════════════════════════════
//
// Aturan: kecocokan part per unit SELALU diverifikasi ke EPC, tidak boleh
// ditebak dari nama/model. Dua keadaan yang WAJIB dibedakan:
//   • `error` terisi  → pengecekan GAGAL (EPC mati / rangka tak dikenal).
//   • `cocok == false` → pengecekan BERHASIL dan part memang tidak terpasang.
// Menyamakan keduanya membuat pembeli membatalkan pembelian yang sebenarnya
// benar (atau sebaliknya).
class _CekUnitCard extends StatefulWidget {
  final String pn;
  const _CekUnitCard({required this.pn});
  @override
  State<_CekUnitCard> createState() => _CekUnitCardState();
}

class _CekUnitCardState extends State<_CekUnitCard> {
  final _ctl = TextEditingController();
  bool _busy = false;
  CekUnitResult? _res;
  String? _err; // gagal mengecek — BUKAN "tidak cocok"

  @override
  void initState() {
    super.initState();
    _muatRangkaTerakhir();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _muatRangkaTerakhir() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final r = prefs.getString(_kRangkaKey) ?? '';
      if (!mounted || r.isEmpty) return;
      setState(() => _ctl.text = r);
    } catch (_) {
      /* preferensi tak terbaca — user tinggal mengetik manual */
    }
  }

  Future<void> _simpanRangka(String rangka) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRangkaKey, rangka);
    } catch (_) {
      /* gagal menyimpan hanya mengurangi kenyamanan, bukan menggagalkan cek */
    }
  }

  Future<void> _cek() async {
    final rangka = _ctl.text.trim().toUpperCase();
    if (rangka.length < 6) {
      setState(() {
        _err = 'Isi nomor rangka (VIN) unit Anda — minimal 6 karakter.';
        _res = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
      _res = null;
    });

    CekUnitResult? hasil;
    String? gagal;
    try {
      hasil = await ApiService.cekPartDiUnit(partNumber: widget.pn, rangka: rangka);
    } on ApiException catch (e) {
      gagal = e.message;
    } catch (_) {
      gagal = 'Gagal menghubungi EPC. Coba lagi.';
    }

    // Rangka hanya diingat bila pengecekan benar-benar berhasil — jangan
    // menyimpan VIN salah ketik yang ditolak EPC.
    if (hasil?.checked == true) await _simpanRangka(rangka);
    if (!mounted) return;

    final pesanError = (hasil?.error ?? '').trim();
    setState(() {
      _busy = false;
      _res = hasil;
      _err = gagal ?? (pesanError.isNotEmpty ? pesanError : null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final res = _res;
    final cocok = res?.checked == true && res?.cocok == true;
    final tidakCocok = res?.checked == true && res?.cocok == false;
    // Vonis ringkas saja (paritas web): tanpa exploded view & rincian figure.
    final unit = (res?.frameNumber ?? '').isNotEmpty
        ? res!.frameNumber!
        : _ctl.text.trim().toUpperCase();

    return MasSectionCard(
      title: 'Cocok di unit saya?',
      trailing: const MasPill(label: 'sumber: EPC per-VIN', tone: MasPillTone.neutral, height: 20),
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Masukkan nomor rangka (VIN) unit Anda — sistem mengecek langsung ke '
              'katalog EPC apakah part ini memang terpasang di unit tersebut.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: m.ink500),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: MasInput(
                  controller: _ctl,
                  hint: 'mis. LZZ5DMSD5RT108966',
                  mono: true,
                  height: 40,
                  action: TextInputAction.search,
                  onSubmitted: (_) => _busy ? null : _cek(),
                ),
              ),
              const SizedBox(width: 8),
              MasButton(
                label: _busy ? 'Mengecek…' : 'Cek',
                icon: Icons.travel_explore_rounded,
                height: 40,
                loading: _busy,
                onTap: _cek,
              ),
            ]),
            if (_busy) ...[
              const SizedBox(height: 10),
              Text(
                'Mengecek ke katalog EPC unit ini — biasanya beberapa detik…',
                style: TextStyle(fontSize: 11.5, color: m.ink400),
              ),
            ],
            // GAGAL MENGECEK — tampilkan sebagai peringatan, bukan vonis "tidak cocok".
            if (_err != null && !_busy) ...[
              const SizedBox(height: 10),
              _alertBox(m, 'Tidak bisa mengecek ke EPC: $_err'),
            ],
            // Pengecekan berhasil, tapi part memang tidak ada di unit ini.
            if (tidakCocok) ...[
              const SizedBox(height: 10),
              _alertBox(m, '❌ Tidak cocok — part ini tidak terpasang di unit $unit.', danger: true),
            ],
            if (cocok) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: m.brand50,
                  borderRadius: BorderRadius.circular(MasRadii.input),
                  border: Border.all(color: m.brand600),
                ),
                child: Text(
                  '✅ Cocok — part ini terpasang di unit $unit.',
                  style: TextStyle(fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w600, color: m.ink800),
                ),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}

/// Penampil foto layar penuh dengan swipe + zoom.
class _FullscreenGallery extends StatefulWidget {
  final List<String> photos;
  final int initial;
  const _FullscreenGallery({required this.photos, required this.initial});
  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Material(
                color: Colors.white.withValues(alpha: 0.14),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).pop(),
                  child: const SizedBox(width: 44, height: 44, child: Icon(Icons.close_rounded, color: Colors.white, size: 26)),
                ),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: widget.photos.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.all(24),
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 1,
                  maxScale: 5,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: Center(
                    child: Image.network(ApiService.partImageUrl(widget.photos[i]), fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (int i = 0; i < widget.photos.length; i++) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == _index ? 22 : 7, height: 7,
                  decoration: BoxDecoration(
                    color: i == _index ? const Color(0xFF1EA83A) : Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                if (i < widget.photos.length - 1) const SizedBox(width: 7),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
