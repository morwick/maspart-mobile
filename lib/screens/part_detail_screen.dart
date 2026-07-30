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
  bool _loadingPhotos = true;

  /// Semua unit yang memakai PN ini (nama model dari kolom `file` katalog).
  List<String> _units = [];

  AccurateStock? _stock;
  bool _loadingStock = true;
  String? _stockErr; // panggilan API gagal (jaringan / server), bukan stok 0

  PartSpecResponse? _spec;
  bool _loadingSpec = true;
  String? _specErr;

  String get _pn => '${_part['part_number'] ?? ''}';
  String get _name => '${_part['part_name'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCartChanged);
    _backfillFromCatalog();
    _loadPhotos();
    _loadStock();
    _loadSpec();
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
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = _pn.isEmpty ? <String>[] : await ApiService.getPartPhotos(_pn);
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loadingPhotos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _photos = [];
        _loadingPhotos = false;
      });
    }
  }

  /// Stok live per gudang dari Accurate (ERP). Kegagalan di sini TIDAK boleh
  /// diterjemahkan jadi angka 0 — 0 berarti habis, gagal berarti tidak tahu.
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

  // Exploded view TANPA nomor rangka. SENGAJA tidak dimuat saat layar dibuka:
  // panggilan pertama bisa 10-60 dtk (PN umum dipakai belasan ribu model), dan
  // gambar hanya tampil bila user memang meminta.
  PartExplodedFigure? _exploded;
  bool _explodedBusy = false;
  String? _explodedErr;

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
    nav.toast('$_pn masuk keranjang');
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _backButton(m),
        const SizedBox(height: 14),
        InkWell(
          onTap: pn.isEmpty ? null : () => _copyPn(pn),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(pn, style: masMono(size: 22, weight: FontWeight.w600, color: m.ink900)),
                if (name.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(name, style: TextStyle(fontSize: 13.5, color: m.ink600)),
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
        if (isBuyer) ...[
          const SizedBox(height: 14),
          _buyerStatRow(m),
        ] else if (showStok || showHarga) ...[
          const SizedBox(height: 14),
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
        ],
        const SizedBox(height: 14),
        _specCard(m),
        const SizedBox(height: 14),
        _explodedCard(m),
        // Semua unit yang memakai PN ini (web: "Ditemukan di N unit"). Sebelum
        // katalog terjawab, tampilkan dulu unit dari argumen navigasi supaya
        // bagian ini tidak berkedip muncul-hilang.
        if (unitList.isNotEmpty) ...[
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
        ],
      ],
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

    Widget aksi;
    if (stok != null && stok <= 0) {
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
          onTap: () => nav.go(MasScreen.chat,
              part: {if (_lokasiBuyer != null) 'gudang': _lokasiBuyer}),
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
    final lokal = _gudangLokal;
    final children = <Widget>[];

    if (acc != null && acc.perGudang.isNotEmpty) {
      final g = acc.perGudang;
      for (int i = 0; i < g.length; i++) {
        final nama = g[i].deskripsi.isNotEmpty ? g[i].deskripsi : g[i].gudang;
        children.add(MasKeyValue(
          label: nama,
          value: thousands(g[i].qty),
          mono: true,
          divider: i < g.length - 1,
        ));
      }
    } else if (_stokGagal) {
      children.add(Padding(
        padding: const EdgeInsets.all(14),
        child: _alertBox(m, _stokGagalPesan),
      ));
      // Data katalog masih berguna sebagai perkiraan — tapi harus jelas labelnya.
      if (lokal.isNotEmpty) {
        children.add(_subHeader(m, 'Cadangan dari katalog (export Accurate) — bisa basi'));
        for (int i = 0; i < lokal.length; i++) {
          children.add(MasKeyValue(
            label: lokal[i].$1,
            value: lokal[i].$2,
            mono: true,
            divider: i < lokal.length - 1,
          ));
        }
      }
    } else if (acc != null) {
      children.add(_infoText(m, 'Accurate tidak memberi rincian per gudang untuk part ini.'));
    } else {
      // Accurate hidup & terkonfigurasi, tapi PN-nya tidak ada di sana.
      children.add(_infoText(m, 'Part ini tidak ditemukan di Accurate.'));
      if (lokal.isNotEmpty) {
        children.add(_subHeader(m, 'Stok menurut katalog'));
        for (int i = 0; i < lokal.length; i++) {
          children.add(MasKeyValue(
            label: lokal[i].$1,
            value: lokal[i].$2,
            mono: true,
            divider: i < lokal.length - 1,
          ));
        }
      }
    }

    return MasSectionCard(
      title: 'Stok per Gudang',
      trailing: acc != null
          ? const MasPill(label: 'Accurate', tone: MasPillTone.brand, height: 20)
          : null,
      children: children,
    );
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

  Widget _specCard(MasColors m) {
    if (_loadingSpec) return const MasSkeleton(height: 120);

    final rows = _specRows(_spec?.spec);
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
  List<(String, String)> _specRows(PartSpec? s) {
    final item = _part;
    final rows = <(String, String)>[];

    if (s != null) {
      final bk = s.beratKirimKg;
      final bb = s.beratBersihKg;
      if (bk != null) rows.add(('Berat (kirim)', '$bk kg'));
      if (bb != null && bb != bk) rows.add(('Berat (bersih)', '$bb kg'));
      if ((s.dimensiCm ?? '').isNotEmpty) rows.add(('Dimensi (P×L×T)', '${s.dimensiCm} cm'));
      if ((s.satuan ?? '').isNotEmpty) rows.add(('Satuan', s.satuan!));
      if (s.kemasanMinimum != null) rows.add(('Kemasan minimum', '${s.kemasanMinimum}'));
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

  Widget _imageCard(MasColors m) {
    Widget tile(int i) {
      if (_loadingPhotos) {
        return AspectRatio(aspectRatio: 1, child: MasSkeleton(height: double.infinity));
      }
      if (i < _photos.length) {
        return GestureDetector(
          onTap: () => _openGallery(i),
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                ApiService.partImageUrl(_photos[i]),
                fit: BoxFit.cover,
                loadingBuilder: (c, w, p) => p == null ? w : Center(
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: m.brand100)),
                errorBuilder: (c, e, s) => HatchBox(label: 'foto ${i + 1}'),
              ),
            ),
          ),
        );
      }
      return HatchBox(label: 'foto ${i + 1}');
    }

    return MasCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Gambar Part', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: m.ink900)),
          const SizedBox(width: 8),
          const MasPill(label: 'sumber: SIMS', tone: MasPillTone.neutral, height: 20),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: tile(0)),
          const SizedBox(width: 8),
          Expanded(child: tile(1)),
        ]),
        if (_photos.length > 2) ...[
          const SizedBox(height: 8),
          Text('${_photos.length} foto · ketuk untuk perbesar',
              style: TextStyle(fontSize: 11.5, color: m.ink400)),
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
  Uint8List? _img;
  bool _imgGagal = false;

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
      _img = null;
      _imgGagal = false;
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

    final id = hasil?.imageId;
    if (id != null && id.isNotEmpty) await _muatExploded(id);
  }

  Future<void> _muatExploded(String id) async {
    try {
      final b = await ApiService.partExploded(id);
      if (!mounted) return;
      setState(() => _img = b);
    } catch (_) {
      // Gambar gagal ≠ hasil cek gagal: penjelasan teksnya tetap sahih.
      if (!mounted) return;
      setState(() => _imgGagal = true);
    }
  }

  void _zoom(Uint8List bytes) {
    showDialog<void>(
      context: context,
      // Latar putih: gambar EPC adalah garis gelap di atas latar transparan —
      // di atas latar gelap gambarnya nyaris tak terlihat.
      barrierColor: Colors.white,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(children: [
          InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: Material(
              color: Colors.black12,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(ctx).pop(),
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.close_rounded, size: 22, color: Colors.black87),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final res = _res;
    final cocok = res?.checked == true && res?.cocok == true;
    final tidakCocok = res?.checked == true && res?.cocok == false;

    final detail = <(String, String)>[
      if (cocok) ...[
        if ((res!.nama ?? '').isNotEmpty) ('Nama part', res.nama!),
        if ((res.istilahLapangan ?? '').isNotEmpty) ('Istilah lapangan', res.istilahLapangan!),
        if ((res.qty ?? '').isNotEmpty) ('Qty di unit', res.qty!),
        if ((res.kategori ?? '').isNotEmpty) ('Kategori', res.kategori!),
        if ((res.lokasi ?? '').isNotEmpty) ('Lokasi (figure)', res.lokasi!),
        if (res.balon != null) ('Nomor balon', '${res.balon}'),
      ],
    ];

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
                'Mengecek ke katalog EPC unit ini — biasanya beberapa detik; '
                'menyiapkan gambar exploded view bisa sedikit lebih lama…',
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
              _alertBox(m, res!.pesan ?? 'Part ini tidak terpasang di unit tersebut.', danger: true),
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
                  res!.penjelasan ?? res.pesan ?? 'Cocok — part ini terpasang di unit tersebut.',
                  style: TextStyle(fontSize: 12.5, height: 1.5, color: m.ink800),
                ),
              ),
              if (_img != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _zoom(_img!),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(MasRadii.card),
                      border: Border.all(color: m.ink150),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      Image.memory(_img!, fit: BoxFit.contain, width: double.infinity),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: m.paper,
                          border: Border(top: BorderSide(color: m.ink100)),
                        ),
                        child: Text(
                          'Exploded view: ${res.lokasi ?? '-'}'
                          '${res.balon != null ? ' — part ini nomor balon ${res.balon} (disorot)' : ''}'
                          ' · ketuk untuk perbesar',
                          style: TextStyle(fontSize: 11.5, color: m.ink500),
                        ),
                      ),
                    ]),
                  ),
                ),
              ] else if (_imgGagal) ...[
                const SizedBox(height: 8),
                Text('Gambar exploded view gagal dimuat — hasil pengecekan di atas tetap sahih.',
                    style: TextStyle(fontSize: 11.5, color: m.ink400)),
              ],
            ],
          ]),
        ),
        for (int i = 0; i < detail.length; i++)
          MasKeyValue(
            label: detail[i].$1,
            value: detail[i].$2,
            divider: i < detail.length - 1,
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
