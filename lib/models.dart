// lib/models.dart
// Model data MASPART — cerminan tipe di frontend web (`frontend/src/lib/api.ts`).
// Nama field JSON dipertahankan persis seperti backend supaya kontraknya sama.

import 'dart:convert';
import 'dart:typed_data';

// ── Helper parsing ───────────────────────────────────────────────────
// Backend kadang mengirim angka sebagai string ("1.500") dan kadang sebagai
// num. Helper ini memaafkan keduanya supaya UI tak pernah crash karena tipe.

int _i(dynamic v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

int? _iOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

double _d(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? fallback;
  return fallback;
}

double? _dOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

bool _b(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'ya') return true;
    if (s == 'false' || s == '0' || s == 'tidak') return false;
  }
  return fallback;
}

String _s(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;

String? _sOrNull(dynamic v) => v?.toString();

List<String> _strList(dynamic v) =>
    (v as List?)?.map((e) => '$e').toList() ?? const [];

Map<String, String> _strMap(dynamic v) => (v as Map?)?.map(
      (k, val) => MapEntry('$k', val?.toString() ?? ''),
    ) ??
    <String, String>{};

/// Baris tabel generik (harga / stok / populasi) — backend mengirim
/// `Record<string, string>`, jadi di Dart cukup `Map<String, String>`.
List<Map<String, String>> _rows(dynamic v) =>
    (v as List?)?.whereType<Map>().map((r) => _strMap(r)).toList() ?? const [];

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) fromJson) =>
    (v as List?)
        ?.whereType<Map>()
        .map((e) => fromJson(e.cast<String, dynamic>()))
        .toList() ??
    const [];

// ══════════════════════════════════════════════════════════════════════
// Auth & izin
// ══════════════════════════════════════════════════════════════════════

class UserOut {
  final String username;
  final String role;
  final String? gudang;

  const UserOut({required this.username, required this.role, this.gudang});

  factory UserOut.fromJson(Map<String, dynamic> j) => UserOut(
        username: _s(j['username']),
        role: _s(j['role']),
        gudang: _sOrNull(j['gudang']),
      );
}

class TokenResponse {
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final UserOut user;

  const TokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
  });

  factory TokenResponse.fromJson(Map<String, dynamic> j) => TokenResponse(
        accessToken: _s(j['access_token']),
        tokenType: _s(j['token_type'], 'bearer'),
        expiresIn: _i(j['expires_in']),
        user: UserOut.fromJson(
            (j['user'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );
}

/// Izin efektif user: menu yang boleh dibuka, kolom yang boleh dilihat,
/// sub-tab Harga, dan (untuk akun cabang) label gudangnya.
class MyPermissions {
  final List<String> menus;
  final List<String> columns;
  final List<String> hargaSubtabs;
  final String role;
  final String? branch;
  final bool canPrice;

  /// Gudang yang boleh DITULIS user pada fitur Rak & Kartu Stok — label PENUH
  /// ("01.Jakarta"), bukan key lokasi pembeli ('jakarta').
  /// ⚠️ Kosong ≠ tak boleh melihat: MELIHAT rak terbuka untuk semua staf
  /// internal, daftar ini hanya memagari tombol Ubah/Hapus & menu pengelola.
  /// Server lama (belum ada kolomnya) tak mengirim field ini → tetap kosong,
  /// jadi fiturnya dorman, bukan error.
  final List<String> gudangKelola;

  const MyPermissions({
    this.menus = const [],
    this.columns = const [],
    this.hargaSubtabs = const [],
    this.role = '',
    this.branch,
    this.canPrice = false,
    this.gudangKelola = const [],
  });

  factory MyPermissions.fromJson(Map<String, dynamic> j) => MyPermissions(
        menus: _strList(j['menus']),
        columns: _strList(j['columns']),
        hargaSubtabs: _strList(j['harga_subtabs']),
        role: _s(j['role']),
        branch: _sOrNull(j['branch']),
        canPrice: _b(j['can_price']),
        gudangKelola: _strList(j['gudang_kelola']),
      );
}

/// Jenis izin yang bisa diatur admin. `sesi` bukan izin melainkan PEMBATASAN
/// (mis. akun hanya boleh dipakai di 1 perangkat).
/// `sesi` bukan izin melainkan PEMBATASAN (mis. hanya 1 perangkat);
/// `asisten` = kemampuan Asisten AI elevated (default kosong, centang MEMBERI).
enum PermKind { menu, column, harga, sesi, asisten }

extension PermKindPath on PermKind {
  String get path => switch (this) {
        PermKind.menu => 'menu',
        PermKind.column => 'column',
        PermKind.harga => 'harga',
        PermKind.sesi => 'sesi',
        PermKind.asisten => 'asisten',
      };
}

class PermOverview {
  final String kind;

  /// key izin → label manusiawi.
  final Map<String, String> allKeys;

  /// Key yang SELALU aktif (tak bisa dimatikan).
  final List<String> always;

  /// Key yang aktif bila user belum pernah diatur khusus.
  final List<String> defaults;

  /// username → daftar key yang diizinkan (override).
  final Map<String, List<String>> permissions;
  final List<UserOut> users;

  const PermOverview({
    this.kind = '',
    this.allKeys = const {},
    this.always = const [],
    this.defaults = const [],
    this.permissions = const {},
    this.users = const [],
  });

  factory PermOverview.fromJson(Map<String, dynamic> j) => PermOverview(
        kind: _s(j['kind']),
        allKeys: _strMap(j['all_keys']),
        always: _strList(j['always']),
        defaults: _strList(j['default']),
        permissions: (j['permissions'] as Map?)?.map(
              (k, v) => MapEntry('$k', _strList(v)),
            ) ??
            const {},
        users: _list(j['users'], UserOut.fromJson),
      );

  /// Key yang efektif berlaku untuk [username] — override bila ada,
  /// kalau tidak pakai default. `always` selalu ikut.
  List<String> effectiveFor(String username) {
    final base = permissions[username] ?? defaults;
    return {...always, ...base}.toList();
  }
}

class AdminUser {
  final String username;
  final String role;
  final bool isActive;
  final String? createdAt;

  const AdminUser({
    required this.username,
    required this.role,
    this.isActive = true,
    this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        username: _s(j['username']),
        role: _s(j['role']),
        isActive: _b(j['is_active'], true),
        createdAt: _sOrNull(j['created_at']),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Pencarian part
// ══════════════════════════════════════════════════════════════════════

class PartResult {
  final String file;
  final String path;
  final String sheet;
  final String partNumber;
  final String partName;
  final String quantity;
  final String stok;
  final String harga;

  /// gudang → qty.
  final Map<String, num> gudang;
  final int excelRow;

  /// '' = database lokal, 'sims' = nama diambil dari SIMS.
  final String source;

  /// Berat per item (gram). 0 = belum ditetapkan.
  final int berat;

  const PartResult({
    this.file = '',
    this.path = '',
    this.sheet = '',
    required this.partNumber,
    this.partName = '',
    this.quantity = '',
    this.stok = '',
    this.harga = '',
    this.gudang = const {},
    this.excelRow = 0,
    this.source = '',
    this.berat = 0,
  });

  factory PartResult.fromJson(Map<String, dynamic> j) => PartResult(
        file: _s(j['file']),
        path: _s(j['path']),
        sheet: _s(j['sheet']),
        partNumber: _s(j['part_number']),
        partName: _s(j['part_name']),
        quantity: _s(j['quantity']),
        stok: _s(j['stok']),
        harga: _s(j['harga']),
        gudang: (j['gudang'] as Map?)?.map(
              (k, v) => MapEntry('$k', (v is num) ? v : _d(v)),
            ) ??
            const {},
        excelRow: _i(j['excel_row']),
        source: _s(j['source']),
        berat: _i(j['berat']),
      );

  /// Peta mentah — dipakai layar lama yang masih menerima `Map`.
  Map<String, dynamic> toMap() => {
        'file': file,
        'path': path,
        'sheet': sheet,
        'part_number': partNumber,
        'part_name': partName,
        'quantity': quantity,
        'stok': stok,
        'harga': harga,
        'gudang': gudang,
        'excel_row': excelRow,
        'source': source,
        'berat': berat,
      };
}

class SaranPart {
  final String partNumber;
  final String partName;

  const SaranPart({required this.partNumber, this.partName = ''});

  factory SaranPart.fromJson(Map<String, dynamic> j) => SaranPart(
        partNumber: _s(j['part_number']),
        partName: _s(j['part_name']),
      );
}

class SearchResponse {
  final String term;
  final int count;
  final int page;
  final int pageSize;
  final int totalPages;
  final List<PartResult> results;

  /// "Mungkin maksud Anda" — hanya terisi saat 0 hasil.
  final List<SaranPart> saran;

  const SearchResponse({
    this.term = '',
    this.count = 0,
    this.page = 1,
    this.pageSize = 20,
    this.totalPages = 1,
    this.results = const [],
    this.saran = const [],
  });

  factory SearchResponse.fromJson(Map<String, dynamic> j) => SearchResponse(
        term: _s(j['term']),
        count: _i(j['count']),
        page: _i(j['page'], 1),
        pageSize: _i(j['page_size'], 20),
        totalPages: _i(j['total_pages'], 1),
        results: _list(j['results'], PartResult.fromJson),
        saran: _list(j['saran'], SaranPart.fromJson),
      );
}

class ImageMatch {
  final String partNumber;
  final String partName;
  final String simsUrl;
  final double similarity;
  final double rawSimilarity;
  final int nMatches;
  final int nStrong;
  final double boost;
  final double distance;
  final String stok;
  final String harga;
  final bool tersedia;

  const ImageMatch({
    required this.partNumber,
    this.partName = '',
    this.simsUrl = '',
    this.similarity = 0,
    this.rawSimilarity = 0,
    this.nMatches = 0,
    this.nStrong = 0,
    this.boost = 0,
    this.distance = 0,
    this.stok = '',
    this.harga = '',
    this.tersedia = false,
  });

  factory ImageMatch.fromJson(Map<String, dynamic> j) => ImageMatch(
        partNumber: _s(j['part_number']),
        partName: _s(j['part_name']),
        simsUrl: _s(j['sims_url']),
        similarity: _d(j['similarity']),
        rawSimilarity: _d(j['raw_similarity']),
        nMatches: _i(j['n_matches']),
        nStrong: _i(j['n_strong']),
        boost: _d(j['boost']),
        distance: _d(j['distance']),
        stok: _s(j['stok']),
        harga: _s(j['harga']),
        tersedia: _b(j['tersedia']),
      );

  /// Kecocokan dalam persen (0..100) — untuk ditampilkan di kartu hasil.
  int get matchPercent => (similarity * 100).round();
}

class ImageSearchResponse {
  final int count;
  final List<ImageMatch> results;
  final int galeriTotal;
  final int galeriParts;
  final String? pesan;

  const ImageSearchResponse({
    this.count = 0,
    this.results = const [],
    this.galeriTotal = 0,
    this.galeriParts = 0,
    this.pesan,
  });

  factory ImageSearchResponse.fromJson(Map<String, dynamic> j) =>
      ImageSearchResponse(
        count: _i(j['count']),
        results: _list(j['results'], ImageMatch.fromJson),
        galeriTotal: _i(j['galeri_total']),
        galeriParts: _i(j['galeri_parts']),
        pesan: _sOrNull(j['pesan']),
      );
}

class ImageLearnResponse {
  final bool ok;
  final String pn;
  final bool duplikat;
  final int galeriTotal;

  const ImageLearnResponse({
    this.ok = false,
    this.pn = '',
    this.duplikat = false,
    this.galeriTotal = 0,
  });

  factory ImageLearnResponse.fromJson(Map<String, dynamic> j) =>
      ImageLearnResponse(
        ok: _b(j['ok']),
        pn: _s(j['pn']),
        duplikat: _b(j['duplikat']),
        galeriTotal: _i(j['galeri_total']),
      );
}

// ── Metadata aplikasi (versi + config server-driven) ────────────────

/// Info versi APK terbaru dari server (untuk notifikasi update in-app).
class AppVersionInfo {
  final int latestCode; // legacy (app ≤2.1.3 banding versionCode)
  final String latestName; // nama versi terbaru, mis. "2.1.4" — sumber banding utama
  final int minCode; // legacy
  final String minName; // versi minimum untuk force update (semver)
  final String downloadUrl;
  final bool force;

  const AppVersionInfo({
    this.latestCode = 0,
    this.latestName = '',
    this.minCode = 0,
    this.minName = '',
    this.downloadUrl = 'https://maspart.tech/download',
    this.force = false,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> j) => AppVersionInfo(
        latestCode: _i(j['latest_code']),
        latestName: _s(j['latest_name']),
        minCode: _i(j['min_code']),
        minName: _s(j['min_name']),
        downloadUrl: j['download_url'] == null || '${j['download_url']}'.isEmpty
            ? 'https://maspart.tech/download'
            : _s(j['download_url']),
        force: _b(j['force']),
      );
}

/// Respons `/api/app/meta`: versi + config server-driven (feature-flag).
class AppMeta {
  final AppVersionInfo version;
  final Map<String, dynamic> config;

  const AppMeta({this.version = const AppVersionInfo(), this.config = const {}});

  factory AppMeta.fromJson(Map<String, dynamic> j) => AppMeta(
        version: AppVersionInfo.fromJson(
            (j['version'] as Map?)?.cast<String, dynamic>() ?? const {}),
        config: (j['config'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

// ── Bandingkan 2 part ────────────────────────────────────────────────

class CompareBest {
  final double shapeScore;
  final double colorScore;
  final double? nameScore;
  final double overall;
  final String verdict;
  final String color;
  final int i;
  final int j;

  const CompareBest({
    this.shapeScore = 0,
    this.colorScore = 0,
    this.nameScore,
    this.overall = 0,
    this.verdict = '',
    this.color = '',
    this.i = 0,
    this.j = 0,
  });

  factory CompareBest.fromJson(Map<String, dynamic> j) => CompareBest(
        shapeScore: _d(j['shape_score']),
        colorScore: _d(j['color_score']),
        nameScore: _dOrNull(j['name_score']),
        overall: _d(j['overall']),
        verdict: _s(j['verdict']),
        color: _s(j['color']),
        i: _i(j['i']),
        j: _i(j['j']),
      );
}

class CompareResponse {
  final String pn1;
  final String pn2;
  final String name1;
  final String name2;
  final List<String> urls1;
  final List<String> urls2;
  final CompareBest? best;
  final String? error;

  const CompareResponse({
    this.pn1 = '',
    this.pn2 = '',
    this.name1 = '',
    this.name2 = '',
    this.urls1 = const [],
    this.urls2 = const [],
    this.best,
    this.error,
  });

  factory CompareResponse.fromJson(Map<String, dynamic> j) => CompareResponse(
        pn1: _s(j['pn1']),
        pn2: _s(j['pn2']),
        name1: _s(j['name1']),
        name2: _s(j['name2']),
        urls1: _strList(j['urls1']),
        urls2: _strList(j['urls2']),
        best: j['best'] is Map
            ? CompareBest.fromJson((j['best'] as Map).cast<String, dynamic>())
            : null,
        error: _sOrNull(j['error']),
      );
}

// ── Foto & spesifikasi part ──────────────────────────────────────────

class PartPhotos {
  final String partNumber;
  final List<String> photos;
  final String source;

  const PartPhotos({
    this.partNumber = '',
    this.photos = const [],
    this.source = '',
  });

  factory PartPhotos.fromJson(Map<String, dynamic> j) => PartPhotos(
        partNumber: _s(j['part_number']),
        photos: _strList(j['photos']),
        source: _s(j['source']),
      );
}

/// Spesifikasi fisik resmi SIMS — sumber utama berat untuk hitung ongkir.
class PartSpec {
  final double? beratBersihKg;
  final double? beratKirimKg;
  final String? dimensiCm;
  final String? satuan;
  final int? kemasanMinimum;
  final String? merek;

  const PartSpec({
    this.beratBersihKg,
    this.beratKirimKg,
    this.dimensiCm,
    this.satuan,
    this.kemasanMinimum,
    this.merek,
  });

  factory PartSpec.fromJson(Map<String, dynamic> j) => PartSpec(
        beratBersihKg: _dOrNull(j['berat_bersih_kg']),
        beratKirimKg: _dOrNull(j['berat_kirim_kg']),
        dimensiCm: _sOrNull(j['dimensi_cm']),
        satuan: _sOrNull(j['satuan']),
        kemasanMinimum: _iOrNull(j['kemasan_minimum']),
        merek: _sOrNull(j['merek']),
      );

  bool get isEmpty =>
      beratBersihKg == null &&
      beratKirimKg == null &&
      (dimensiCm == null || dimensiCm!.isEmpty);
}

/// Exploded view sebuah PN TANPA nomor rangka (jalur global EPC).
///
/// ⚠️ Figure-nya LINTAS MODEL: memuat PN ini tapi dari model mana pun, bukan unit
/// tertentu. Untuk unit spesifik, jalur per-VIN (cek unit) tetap yang benar —
/// `catatan` dari server membawa peringatan itu dan WAJIB ditampilkan apa adanya.
class PartExplodedFigure {
  final bool found;
  final String partNumber;

  /// PNG mentah (server mengirim base64) — balon PN ini disorot kuning bila
  /// nomornya terdeteksi.
  final Uint8List? png;
  final String? figurePn;
  final String? figureNama;
  final String? namaItem;
  final String? balon;
  final int? jumlahItem;
  final String? sumberModel;
  final int? jumlahModelPemakai;
  final String? catatan;
  final String? alasan;

  const PartExplodedFigure({
    this.found = false,
    this.partNumber = '',
    this.png,
    this.figurePn,
    this.figureNama,
    this.namaItem,
    this.balon,
    this.jumlahItem,
    this.sumberModel,
    this.jumlahModelPemakai,
    this.catatan,
    this.alasan,
  });

  factory PartExplodedFigure.fromJson(Map<String, dynamic> j) {
    Uint8List? bytes;
    final b64 = _sOrNull(j['png_base64']);
    if (b64 != null && b64.isNotEmpty) {
      try {
        bytes = base64Decode(b64);
      } catch (_) {
        bytes = null;
      }
    }
    return PartExplodedFigure(
      found: j['found'] == true && bytes != null,
      partNumber: _s(j['part_number']),
      png: bytes,
      figurePn: _sOrNull(j['figure_pn']),
      figureNama: _sOrNull(j['figure_nama']),
      namaItem: _sOrNull(j['nama_item']),
      balon: _sOrNull(j['balon']),
      jumlahItem: _iOrNull(j['jumlah_item']),
      sumberModel: _sOrNull(j['sumber_model']),
      jumlahModelPemakai: _iOrNull(j['jumlah_model_pemakai']),
      catatan: _sOrNull(j['catatan']),
      alasan: _sOrNull(j['alasan']),
    );
  }
}

class PartSpecResponse {
  final String partNumber;
  final PartSpec spec;
  final int beratGram;

  const PartSpecResponse({
    this.partNumber = '',
    this.spec = const PartSpec(),
    this.beratGram = 0,
  });

  factory PartSpecResponse.fromJson(Map<String, dynamic> j) => PartSpecResponse(
        partNumber: _s(j['part_number']),
        spec: PartSpec.fromJson(
            (j['spec'] as Map?)?.cast<String, dynamic>() ?? const {}),
        beratGram: _i(j['berat_gram']),
      );
}

// ── Stok Accurate (per part) ─────────────────────────────────────────

class GudangQty {
  final String gudang;
  final String deskripsi;
  final int qty;
  final int? gudangId;

  const GudangQty({
    required this.gudang,
    this.deskripsi = '',
    this.qty = 0,
    this.gudangId,
  });

  factory GudangQty.fromJson(Map<String, dynamic> j) => GudangQty(
        gudang: _s(j['gudang']),
        deskripsi: _s(j['deskripsi']),
        qty: _i(j['qty']),
        gudangId: _iOrNull(j['gudang_id']),
      );
}

class AccurateStockDetail {
  final int availableToSell;
  final int quantity;
  final String unit;
  final String name;
  final String no;
  final String itemType;
  final double? harga;
  final List<GudangQty> perGudang;

  const AccurateStockDetail({
    this.availableToSell = 0,
    this.quantity = 0,
    this.unit = '',
    this.name = '',
    this.no = '',
    this.itemType = '',
    this.harga,
    this.perGudang = const [],
  });

  factory AccurateStockDetail.fromJson(Map<String, dynamic> j) =>
      AccurateStockDetail(
        availableToSell: _i(j['available_to_sell']),
        quantity: _i(j['quantity']),
        unit: _s(j['unit']),
        name: _s(j['name']),
        no: _s(j['no']),
        itemType: _s(j['item_type']),
        harga: _dOrNull(j['harga']),
        perGudang: _list(j['per_gudang'], GudangQty.fromJson),
      );
}

class AccurateStock {
  final bool configured;
  final bool found;
  final bool sessionExpired;
  final bool error;
  final String? reason;
  final AccurateStockDetail? stock;

  const AccurateStock({
    this.configured = false,
    this.found = false,
    this.sessionExpired = false,
    this.error = false,
    this.reason,
    this.stock,
  });

  factory AccurateStock.fromJson(Map<String, dynamic> j) => AccurateStock(
        configured: _b(j['configured']),
        found: _b(j['found']),
        sessionExpired: _b(j['session_expired']),
        error: _b(j['error']),
        reason: _sOrNull(j['reason']),
        stock: j['stock'] is Map
            ? AccurateStockDetail.fromJson(
                (j['stock'] as Map).cast<String, dynamic>())
            : null,
      );
}

// ── Keluarga varian pemasok (kartu Accurate ganda utk 1 part fisik) ──
//
// Satu part fisik bisa dipecah per PEMASOK di Accurate dengan suffix huruf
// (PN dasar + '/SN' + '/SH' dst) — stok DAN harga beda tiap kartu.
// ⛔ Aturan pemilik: harga TIDAK PERNAH dirata-rata. `hargaMin`/`hargaMax`
// murni LABEL rentang; keranjang & penawaran selalu menunjuk `kode` varian
// yang dipilih user secara eksplisit.

class PartVarianItem {
  /// PN kartu APA ADANYA, suffix ikut — inilah yang dipesan.
  final String kode;

  /// Nomor kartu barang Accurate (`000951.<pn>`).
  final String no;
  final String nama;
  final String unit;

  /// Angka stok/harga bisa HILANG (bukan 0) bila gerbang kolom server
  /// mencabutnya untuk akun tanpa centang col_stok/col_harga → null artinya
  /// "dirahasiakan", jangan dirender sebagai 0 (itu memalsukan "habis").
  final int? stok;
  final double? harga;

  /// Sebaran antar-gudang — staf/admin saja (pembeli tak berhak melihatnya).
  final List<GudangQty> perGudang;

  /// Pengganti [perGudang] untuk PEMBELI: stok di wilayahnya saja.
  final int? stokWilayah;

  const PartVarianItem({
    this.kode = '',
    this.no = '',
    this.nama = '',
    this.unit = '',
    this.stok,
    this.harga,
    this.perGudang = const [],
    this.stokWilayah,
  });

  factory PartVarianItem.fromJson(Map<String, dynamic> j) => PartVarianItem(
        kode: _s(j['kode']),
        no: _s(j['no']),
        nama: _s(j['nama']),
        unit: _s(j['unit']),
        stok: _iOrNull(j['stok']),
        harga: _dOrNull(j['harga']),
        perGudang: _list(j['per_gudang'], GudangQty.fromJson),
        stokWilayah: _iOrNull(j['stok_wilayah']),
      );
}

class PartVarian {
  final bool configured;
  final bool found;
  final bool sessionExpired;
  final bool error;
  final String? reason;

  /// PN dasar keluarga (tanpa suffix pemasok).
  final String base;
  final int? totalAvailable;
  final double? hargaMin;
  final double? hargaMax;
  final List<PartVarianItem> varian;

  const PartVarian({
    this.configured = false,
    this.found = false,
    this.sessionExpired = false,
    this.error = false,
    this.reason,
    this.base = '',
    this.totalAvailable,
    this.hargaMin,
    this.hargaMax,
    this.varian = const [],
  });

  /// True hanya bila keluarganya memang LEBIH DARI SATU kartu Accurate.
  /// Satu anggota = part biasa → UI varian tak boleh muncul sama sekali.
  bool get keluarga => found && varian.length > 1;

  factory PartVarian.fromJson(Map<String, dynamic> j) => PartVarian(
        configured: _b(j['configured']),
        found: _b(j['found']),
        sessionExpired: _b(j['session_expired']),
        error: _b(j['error']),
        reason: _sOrNull(j['reason']),
        base: _s(j['base']),
        totalAvailable: _iOrNull(j['total_available']),
        hargaMin: _dOrNull(j['harga_min']),
        hargaMax: _dOrNull(j['harga_max']),
        varian: _list(j['varian'], PartVarianItem.fromJson),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Harga
// ══════════════════════════════════════════════════════════════════════

class HargaListResponse {
  final int total;
  final int totalFiltered;
  final int page;
  final int pageSize;
  final int totalPages;
  final List<Map<String, String>> rows;

  const HargaListResponse({
    this.total = 0,
    this.totalFiltered = 0,
    this.page = 1,
    this.pageSize = 50,
    this.totalPages = 1,
    this.rows = const [],
  });

  factory HargaListResponse.fromJson(Map<String, dynamic> j) =>
      HargaListResponse(
        total: _i(j['total']),
        totalFiltered: _i(j['total_filtered']),
        page: _i(j['page'], 1),
        pageSize: _i(j['page_size'], 50),
        totalPages: _i(j['total_pages'], 1),
        rows: _rows(j['rows']),
      );
}

class CariHargaResult {
  final String pn;
  final double? cny;
  final double? idr;
  final double rate;
  final String? note;

  const CariHargaResult({
    this.pn = '',
    this.cny,
    this.idr,
    this.rate = 0,
    this.note,
  });

  factory CariHargaResult.fromJson(Map<String, dynamic> j) => CariHargaResult(
        pn: _s(j['pn']),
        cny: _dOrNull(j['cny']),
        idr: _dOrNull(j['idr']),
        rate: _d(j['rate']),
        note: _sOrNull(j['note']),
      );
}

class BatchHargaRow {
  final String pn;
  final double? cny;
  final double? idr;
  final String? note;
  final String status;

  const BatchHargaRow({
    this.pn = '',
    this.cny,
    this.idr,
    this.note,
    this.status = '',
  });

  factory BatchHargaRow.fromJson(Map<String, dynamic> j) => BatchHargaRow(
        pn: _s(j['pn']),
        cny: _dOrNull(j['cny']),
        idr: _dOrNull(j['idr']),
        note: _sOrNull(j['note']),
        status: _s(j['status']),
      );

  Map<String, dynamic> toJson() => {
        'pn': pn,
        'cny': cny,
        'idr': idr,
        'note': note,
        'status': status,
      };
}

class BatchHargaResponse {
  final double rate;
  final int count;
  final int found;
  final List<BatchHargaRow> results;

  const BatchHargaResponse({
    this.rate = 0,
    this.count = 0,
    this.found = 0,
    this.results = const [],
  });

  factory BatchHargaResponse.fromJson(Map<String, dynamic> j) =>
      BatchHargaResponse(
        rate: _d(j['rate']),
        count: _i(j['count']),
        found: _i(j['found']),
        results: _list(j['results'], BatchHargaRow.fromJson),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Stok (indeks Accurate, sinkron berkala)
// ══════════════════════════════════════════════════════════════════════

class StokListResponse {
  final bool configured;
  final bool sessionExpired;
  final bool error;
  final String? reason;
  final int total;
  final int totalFiltered;
  final int page;
  final int pageSize;
  final int totalPages;
  final List<Map<String, String>> rows;

  const StokListResponse({
    this.configured = true,
    this.sessionExpired = false,
    this.error = false,
    this.reason,
    this.total = 0,
    this.totalFiltered = 0,
    this.page = 1,
    this.pageSize = 50,
    this.totalPages = 1,
    this.rows = const [],
  });

  factory StokListResponse.fromJson(Map<String, dynamic> j) => StokListResponse(
        // `configured` absen = dianggap sudah dikonfigurasi (jalur sukses).
        configured: _b(j['configured'], true),
        sessionExpired: _b(j['session_expired']),
        error: _b(j['error']),
        reason: _sOrNull(j['reason']),
        total: _i(j['total']),
        totalFiltered: _i(j['total_filtered']),
        page: _i(j['page'], 1),
        pageSize: _i(j['page_size'], 50),
        totalPages: _i(j['total_pages'], 1),
        rows: _rows(j['rows']),
      );

  /// Ada masalah yang perlu diberitahukan ke user (bukan sekadar 0 hasil).
  bool get hasProblem => !configured || sessionExpired || error;
}

// ══════════════════════════════════════════════════════════════════════
// Populasi unit
// ══════════════════════════════════════════════════════════════════════

class PopulasiResponse {
  final List<String> columns;

  /// kolom → daftar nilai unik (untuk dropdown filter).
  final Map<String, List<String>> filterOptions;
  final int total;
  final int totalFiltered;
  final int page;
  final int pageSize;
  final int totalPages;
  final List<Map<String, String>> rows;

  const PopulasiResponse({
    this.columns = const [],
    this.filterOptions = const {},
    this.total = 0,
    this.totalFiltered = 0,
    this.page = 1,
    this.pageSize = 50,
    this.totalPages = 1,
    this.rows = const [],
  });

  factory PopulasiResponse.fromJson(Map<String, dynamic> j) => PopulasiResponse(
        columns: _strList(j['columns']),
        filterOptions: (j['filter_options'] as Map?)?.map(
              (k, v) => MapEntry('$k', _strList(v)),
            ) ??
            const {},
        total: _i(j['total']),
        totalFiltered: _i(j['total_filtered']),
        page: _i(j['page'], 1),
        pageSize: _i(j['page_size'], 50),
        totalPages: _i(j['total_pages'], 1),
        rows: _rows(j['rows']),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Repair kit transmisi
// ══════════════════════════════════════════════════════════════════════

class RepairKitModel {
  final String model;
  final String tipe;
  final int jumlahSealKit;
  final int jumlahOverhaulTambahan;
  final List<String> unit;

  const RepairKitModel({
    required this.model,
    this.tipe = '',
    this.jumlahSealKit = 0,
    this.jumlahOverhaulTambahan = 0,
    this.unit = const [],
  });

  factory RepairKitModel.fromJson(Map<String, dynamic> j) => RepairKitModel(
        model: _s(j['model']),
        tipe: _s(j['tipe']),
        jumlahSealKit: _i(j['jumlah_seal_kit']),
        jumlahOverhaulTambahan: _i(j['jumlah_overhaul_tambahan']),
        unit: _strList(j['unit']),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Pesanan, pembayaran & pengiriman
// ══════════════════════════════════════════════════════════════════════

class OrderItemDetail {
  final String partNumber;
  final String name;
  final double price;
  final int qty;
  final double lineTotal;

  const OrderItemDetail({
    required this.partNumber,
    this.name = '',
    this.price = 0,
    this.qty = 0,
    this.lineTotal = 0,
  });

  factory OrderItemDetail.fromJson(Map<String, dynamic> j) => OrderItemDetail(
        partNumber: _s(j['part_number']),
        name: _s(j['name']),
        price: _d(j['price']),
        qty: _i(j['qty']),
        lineTotal: _d(j['line_total']),
      );
}

class OrderSummary {
  final String orderCode;
  final String username;
  final String gudang;
  final double total;
  final String status;
  final String? paymentProofUrl;
  final String createdAt;

  const OrderSummary({
    required this.orderCode,
    this.username = '',
    this.gudang = '',
    this.total = 0,
    this.status = '',
    this.paymentProofUrl,
    this.createdAt = '',
  });

  factory OrderSummary.fromJson(Map<String, dynamic> j) => OrderSummary(
        orderCode: _s(j['order_code']),
        username: _s(j['username']),
        gudang: _s(j['gudang']),
        total: _d(j['total']),
        status: _s(j['status']),
        paymentProofUrl: _sOrNull(j['payment_proof_url']),
        createdAt: _s(j['created_at']),
      );
}

/// Detail pesanan. Perhatikan `tax` = komponen PPN 12% yang SUDAH TERMASUK di
/// dalam `subtotal` (inklusif, mengikuti Accurate) — bukan tambahan di atasnya.
/// Dan `fulfillGudang` = gudang FISIK pengirim, beda dari `gudang` (cabang
/// pemroses) — ongkir dihitung dari gudang pemenuh ini.
class OrderDetail extends OrderSummary {
  final String? note;
  final double? gudangLat;
  final double? gudangLon;
  final String? gudangPic;
  final double subtotal;
  final double? tax;
  final double shippingCost;
  final String? courier;
  final String? courierService;
  final String? trackingNo;
  final int weightGrams;
  final String paymentMethod;
  final String? paymentRef;
  final String? paymentChannel;
  final String? paymentVa;
  final String? paymentQr;
  final String? paymentUrl;
  final String? paymentExpiry;
  final String? paidAt;
  final String? recipientName;
  final String? recipientPhone;
  final String? recipientAddress;
  final String? recipientPostal;
  final String? fulfillGudang;

  /// Mis. dibayar setelah order batal → perlu refund.
  final String? paymentNote;

  /// Penawaran Penjualan Accurate otomatis: created | skip | failed.
  final String? penawaranStatus;
  final String? penawaranNumber;
  final String? penawaranNote;
  final List<OrderItemDetail> items;

  const OrderDetail({
    required super.orderCode,
    super.username,
    super.gudang,
    super.total,
    super.status,
    super.paymentProofUrl,
    super.createdAt,
    this.note,
    this.gudangLat,
    this.gudangLon,
    this.gudangPic,
    this.subtotal = 0,
    this.tax,
    this.shippingCost = 0,
    this.courier,
    this.courierService,
    this.trackingNo,
    this.weightGrams = 0,
    this.paymentMethod = '',
    this.paymentRef,
    this.paymentChannel,
    this.paymentVa,
    this.paymentQr,
    this.paymentUrl,
    this.paymentExpiry,
    this.paidAt,
    this.recipientName,
    this.recipientPhone,
    this.recipientAddress,
    this.recipientPostal,
    this.fulfillGudang,
    this.paymentNote,
    this.penawaranStatus,
    this.penawaranNumber,
    this.penawaranNote,
    this.items = const [],
  });

  factory OrderDetail.fromJson(Map<String, dynamic> j) => OrderDetail(
        orderCode: _s(j['order_code']),
        username: _s(j['username']),
        gudang: _s(j['gudang']),
        total: _d(j['total']),
        status: _s(j['status']),
        paymentProofUrl: _sOrNull(j['payment_proof_url']),
        createdAt: _s(j['created_at']),
        note: _sOrNull(j['note']),
        gudangLat: _dOrNull(j['gudang_lat']),
        gudangLon: _dOrNull(j['gudang_lon']),
        gudangPic: _sOrNull(j['gudang_pic']),
        subtotal: _d(j['subtotal']),
        tax: _dOrNull(j['tax']),
        shippingCost: _d(j['shipping_cost']),
        courier: _sOrNull(j['courier']),
        courierService: _sOrNull(j['courier_service']),
        trackingNo: _sOrNull(j['tracking_no']),
        weightGrams: _i(j['weight_grams']),
        paymentMethod: _s(j['payment_method']),
        paymentRef: _sOrNull(j['payment_ref']),
        paymentChannel: _sOrNull(j['payment_channel']),
        paymentVa: _sOrNull(j['payment_va']),
        paymentQr: _sOrNull(j['payment_qr']),
        paymentUrl: _sOrNull(j['payment_url']),
        paymentExpiry: _sOrNull(j['payment_expiry']),
        paidAt: _sOrNull(j['paid_at']),
        recipientName: _sOrNull(j['recipient_name']),
        recipientPhone: _sOrNull(j['recipient_phone']),
        recipientAddress: _sOrNull(j['recipient_address']),
        recipientPostal: _sOrNull(j['recipient_postal']),
        fulfillGudang: _sOrNull(j['fulfill_gudang']),
        paymentNote: _sOrNull(j['payment_note']),
        penawaranStatus: _sOrNull(j['penawaran_status']),
        penawaranNumber: _sOrNull(j['penawaran_number']),
        penawaranNote: _sOrNull(j['penawaran_note']),
        items: _list(j['items'], OrderItemDetail.fromJson),
      );

  /// Gudang yang benar-benar mengirim barang (fallback ke cabang pemroses).
  String get pengirim =>
      (fulfillGudang != null && fulfillGudang!.isNotEmpty) ? fulfillGudang! : gudang;
}

class PaymentInfo {
  final String? ref;
  final String? channel;
  final String? va;
  final String? qr;
  final String? url;
  final String? expiry;
  final String? status;

  const PaymentInfo({
    this.ref,
    this.channel,
    this.va,
    this.qr,
    this.url,
    this.expiry,
    this.status,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> j) => PaymentInfo(
        ref: _sOrNull(j['ref']),
        channel: _sOrNull(j['channel']),
        va: _sOrNull(j['va']),
        qr: _sOrNull(j['qr']),
        url: _sOrNull(j['url']),
        expiry: _sOrNull(j['expiry']),
        status: _sOrNull(j['status']),
      );
}

class PaymentChannel {
  final String code;
  final String label;

  const PaymentChannel({required this.code, this.label = ''});

  factory PaymentChannel.fromJson(Map<String, dynamic> j) => PaymentChannel(
        code: _s(j['code']),
        label: _s(j['label']),
      );
}

class PaymentMethods {
  final bool gatewayAvailable;
  final List<PaymentChannel> channels;

  const PaymentMethods({this.gatewayAvailable = false, this.channels = const []});

  factory PaymentMethods.fromJson(Map<String, dynamic> j) => PaymentMethods(
        gatewayAvailable: _b(j['gateway_available']),
        channels: _list(j['channels'], PaymentChannel.fromJson),
      );
}

/// Satu baris manifest kurir.
class TrackingStep {
  final String waktu;
  final String keterangan;
  final String lokasi;

  const TrackingStep({this.waktu = '', this.keterangan = '', this.lokasi = ''});

  factory TrackingStep.fromJson(Map<String, dynamic> j) => TrackingStep(
        waktu: _s(j['waktu']),
        keterangan: _s(j['keterangan']),
        lokasi: _s(j['lokasi']),
      );
}

/// Perjalanan paket dari kurir (`/api/orders/<code>/tracking`).
/// ⛔ BUKAN pemesanan pengiriman: resi tetap dibuat gerai ekspedisi lalu diketik
/// admin cabang. Ini hanya membacakan manifest kurir. `error` terisi = tampilkan
/// apa adanya, JANGAN diperlakukan sebagai kegagalan layar.
class TrackingResult {
  final bool adaResi;
  final bool delivered;
  final String status;
  final String penerima;
  final String waktuTerima;
  final List<TrackingStep> riwayat;
  final String? error;

  const TrackingResult({
    this.adaResi = false,
    this.delivered = false,
    this.status = '',
    this.penerima = '',
    this.waktuTerima = '',
    this.riwayat = const [],
    this.error,
  });

  factory TrackingResult.fromJson(Map<String, dynamic> j) => TrackingResult(
        adaResi: _b(j['ada_resi']),
        delivered: _b(j['delivered']),
        status: _s(j['status']),
        penerima: _s(j['penerima']),
        waktuTerima: _s(j['waktu_terima']),
        riwayat: [
          for (final r in (j['riwayat'] as List? ?? const []))
            if (r is Map) TrackingStep.fromJson(r.cast<String, dynamic>()),
        ],
        error: _sOrNull(j['error']),
      );
}

class PaymentStatus {
  final String status;
  final bool paid;
  final String? gatewayStatus;
  final String? error;

  const PaymentStatus({
    this.status = '',
    this.paid = false,
    this.gatewayStatus,
    this.error,
  });

  factory PaymentStatus.fromJson(Map<String, dynamic> j) => PaymentStatus(
        status: _s(j['status']),
        paid: _b(j['paid']),
        gatewayStatus: _sOrNull(j['gateway_status']),
        error: _sOrNull(j['error']),
      );
}

class CreatedOrder {
  final String orderCode;
  final double total;
  final String status;
  final String? paymentMethod;
  final PaymentInfo? payment;

  const CreatedOrder({
    required this.orderCode,
    this.total = 0,
    this.status = '',
    this.paymentMethod,
    this.payment,
  });

  factory CreatedOrder.fromJson(Map<String, dynamic> j) => CreatedOrder(
        orderCode: _s(j['order_code']),
        total: _d(j['total']),
        status: _s(j['status']),
        paymentMethod: _sOrNull(j['payment_method']),
        payment: j['payment'] is Map
            ? PaymentInfo.fromJson((j['payment'] as Map).cast<String, dynamic>())
            : null,
      );
}

class ShippingRate {
  final String courier;
  final String courierName;
  final String service;
  final double price;
  final String etd;

  const ShippingRate({
    required this.courier,
    this.courierName = '',
    this.service = '',
    this.price = 0,
    this.etd = '',
  });

  factory ShippingRate.fromJson(Map<String, dynamic> j) => ShippingRate(
        courier: _s(j['courier']),
        courierName: _s(j['courier_name']),
        service: _s(j['service']),
        price: _d(j['price']),
        etd: _s(j['etd']),
      );
}

class ShippingRates {
  final List<ShippingRate> rates;
  final String? error;
  final bool available;

  const ShippingRates({
    this.rates = const [],
    this.error,
    this.available = false,
  });

  factory ShippingRates.fromJson(Map<String, dynamic> j) => ShippingRates(
        rates: _list(j['rates'], ShippingRate.fromJson),
        error: _sOrNull(j['error']),
        available: _b(j['available']),
      );
}

class CartWeight {
  final int weightGrams;
  final int defaultItemGrams;

  const CartWeight({this.weightGrams = 0, this.defaultItemGrams = 0});

  factory CartWeight.fromJson(Map<String, dynamic> j) => CartWeight(
        weightGrams: _i(j['weight_grams']),
        defaultItemGrams: _i(j['default_item_grams']),
      );
}

/// Keadaan satu item keranjang menurut SERVER. Keranjang di perangkat menyimpan
/// harga saat part dimasukkan — bisa basi — jadi layar keranjang wajib
/// menyegarkan dirinya dari sini sebelum checkout.
class CartGudangItem {
  final String partNumber;

  /// Gudang pengirim ('' bila tak ada stok di mana pun).
  final String gudang;

  /// Harga TERKINI dari server — inilah yang akan ditagih.
  final double harga;
  final String hargaDisplay;
  final int berat;
  final bool bisaDibeli;

  /// 'harga belum tersedia' | 'berat belum ditetapkan' | 'stok habis'
  final String alasan;

  const CartGudangItem({
    required this.partNumber,
    this.gudang = '',
    this.harga = 0,
    this.hargaDisplay = '',
    this.berat = 0,
    this.bisaDibeli = false,
    this.alasan = '',
  });

  factory CartGudangItem.fromJson(Map<String, dynamic> j) => CartGudangItem(
        partNumber: _s(j['part_number']),
        gudang: _s(j['gudang']),
        harga: _d(j['harga']),
        hargaDisplay: _s(j['harga_display']),
        berat: _i(j['berat']),
        bisaDibeli: _b(j['bisa_dibeli']),
        alasan: _s(j['alasan']),
      );
}

class CartGudang {
  final List<CartGudangItem> items;

  /// Gudang pengirim utama — asal perhitungan ongkir.
  final String utama;

  /// Keranjang terpecah ke >1 gudang → jadi lebih dari satu paket/pesanan.
  final bool multi;

  const CartGudang({
    this.items = const [],
    this.utama = '',
    this.multi = false,
  });

  factory CartGudang.fromJson(Map<String, dynamic> j) => CartGudang(
        items: _list(j['items'], CartGudangItem.fromJson),
        utama: _s(j['utama']),
        multi: _b(j['multi']),
      );

  CartGudangItem? forPn(String pn) {
    for (final it in items) {
      if (it.partNumber == pn) return it;
    }
    return null;
  }

  /// Gudang unik yang terlibat — dipakai untuk memberi tahu pembeli bahwa
  /// keranjangnya akan dipesan bergantian (satu pesanan = satu gudang).
  List<String> get gudangList =>
      items.map((e) => e.gudang).where((g) => g.isNotEmpty).toSet().toList();
}

class GeoPlace {
  final double lat;
  final double lon;
  final String address;
  final String postal;
  final String displayName;
  final String label;

  const GeoPlace({
    this.lat = 0,
    this.lon = 0,
    this.address = '',
    this.postal = '',
    this.displayName = '',
    this.label = '',
  });

  factory GeoPlace.fromJson(Map<String, dynamic> j) => GeoPlace(
        lat: _d(j['lat']),
        lon: _d(j['lon']),
        address: _s(j['address']),
        postal: _s(j['postal']),
        displayName: _s(j['display_name']),
        label: _s(j['label']),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Pembeli: lokasi & etalase toko
// ══════════════════════════════════════════════════════════════════════

class BuyerLocation {
  final String key;
  final String label;

  const BuyerLocation({required this.key, this.label = ''});

  factory BuyerLocation.fromJson(Map<String, dynamic> j) => BuyerLocation(
        key: _s(j['key']),
        label: _s(j['label']),
      );
}

class TokoProduct {
  final String partNumber;
  final String name;
  final double harga;
  final String hargaDisplay;
  final int berat;
  final String? foto;
  final List<String> kategori;
  final bool ready;
  final int stok;
  final String gudang;

  const TokoProduct({
    required this.partNumber,
    this.name = '',
    this.harga = 0,
    this.hargaDisplay = '',
    this.berat = 0,
    this.foto,
    this.kategori = const [],
    this.ready = false,
    this.stok = 0,
    this.gudang = '',
  });

  factory TokoProduct.fromJson(Map<String, dynamic> j) => TokoProduct(
        partNumber: _s(j['part_number']),
        name: _s(j['name']),
        harga: _d(j['harga']),
        hargaDisplay: _s(j['harga_display']),
        berat: _i(j['berat']),
        foto: _sOrNull(j['foto']),
        kategori: _strList(j['kategori']),
        ready: _b(j['ready']),
        stok: _i(j['stok']),
        gudang: _s(j['gudang']),
      );
}

class TokoKategori {
  final String key;
  final String label;
  final int count;

  const TokoKategori({required this.key, this.label = '', this.count = 0});

  factory TokoKategori.fromJson(Map<String, dynamic> j) => TokoKategori(
        key: _s(j['key']),
        label: _s(j['label']),
        count: _i(j['count']),
      );
}

class TokoHome {
  final String? lokasi;
  final int totalProduk;
  final List<TokoKategori> kategori;
  final List<TokoProduct> terlaris;
  final List<TokoProduct> unggulan;

  const TokoHome({
    this.lokasi,
    this.totalProduk = 0,
    this.kategori = const [],
    this.terlaris = const [],
    this.unggulan = const [],
  });

  factory TokoHome.fromJson(Map<String, dynamic> j) => TokoHome(
        lokasi: _sOrNull(j['lokasi']),
        totalProduk: _i(j['total_produk']),
        kategori: _list(j['kategori'], TokoKategori.fromJson),
        terlaris: _list(j['terlaris'], TokoProduct.fromJson),
        unggulan: _list(j['unggulan'], TokoProduct.fromJson),
      );
}

class TokoCatalog {
  final List<TokoProduct> items;
  final int count;
  final int page;
  final int pageSize;
  final int totalPages;
  final String? lokasi;

  const TokoCatalog({
    this.items = const [],
    this.count = 0,
    this.page = 1,
    this.pageSize = 24,
    this.totalPages = 1,
    this.lokasi,
  });

  factory TokoCatalog.fromJson(Map<String, dynamic> j) => TokoCatalog(
        items: _list(j['items'], TokoProduct.fromJson),
        count: _i(j['count']),
        page: _i(j['page'], 1),
        pageSize: _i(j['page_size'], 24),
        totalPages: _i(j['total_pages'], 1),
        lokasi: _sOrNull(j['lokasi']),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Chat (pembeli ↔ gudang)
// ══════════════════════════════════════════════════════════════════════

class ChatMessage {
  final String senderUsername;

  /// 'pembeli' | 'gudang' | 'admin'
  final String senderRole;
  final String body;
  final String createdAt;

  const ChatMessage({
    this.senderUsername = '',
    this.senderRole = '',
    this.body = '',
    this.createdAt = '',
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        senderUsername: _s(j['sender_username']),
        senderRole: _s(j['sender_role']),
        body: _s(j['body']),
        createdAt: _s(j['created_at']),
      );
}

/// Percakapan di dalam satu pesanan. Dinamai `...Thread` supaya tidak bentrok
/// dengan widget `OrderChat` di `widgets/order_chat.dart`.
class OrderChatThread {
  final String role;
  final String gudang;
  final String buyer;
  final List<ChatMessage> messages;

  const OrderChatThread({
    this.role = '',
    this.gudang = '',
    this.buyer = '',
    this.messages = const [],
  });

  factory OrderChatThread.fromJson(Map<String, dynamic> j) => OrderChatThread(
        role: _s(j['role']),
        gudang: _s(j['gudang']),
        buyer: _s(j['buyer']),
        messages: _list(j['messages'], ChatMessage.fromJson),
      );
}

class BuyerChatThread {
  final String gudangKey;
  final String last;
  final String createdAt;

  const BuyerChatThread({
    required this.gudangKey,
    this.last = '',
    this.createdAt = '',
  });

  factory BuyerChatThread.fromJson(Map<String, dynamic> j) => BuyerChatThread(
        gudangKey: _s(j['gudang_key']),
        last: _s(j['last']),
        createdAt: _s(j['created_at']),
      );
}

class ChatThreadSummary {
  final String buyerUsername;
  final String last;
  final String createdAt;

  const ChatThreadSummary({
    required this.buyerUsername,
    this.last = '',
    this.createdAt = '',
  });

  factory ChatThreadSummary.fromJson(Map<String, dynamic> j) =>
      ChatThreadSummary(
        buyerUsername: _s(j['buyer_username']),
        last: _s(j['last']),
        createdAt: _s(j['created_at']),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Asisten AI
// ══════════════════════════════════════════════════════════════════════

class AIChatTurn {
  /// 'user' | 'assistant'
  final String role;
  final String content;

  const AIChatTurn({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};

  factory AIChatTurn.fromJson(Map<String, dynamic> j) => AIChatTurn(
        role: _s(j['role']),
        content: _s(j['content']),
      );
}

/// Satu pertanyaan balik dari asisten (tool `tanya_user`) → kartu pilihan.
///
/// "Lainnya"/"Lewati" DISEDIAKAN tampilan, bukan oleh model.
class AIPertanyaan {
  final String teks;
  final List<String> opsi;

  const AIPertanyaan({this.teks = '', this.opsi = const []});

  factory AIPertanyaan.fromJson(Map<String, dynamic> j) =>
      AIPertanyaan(teks: _s(j['teks']), opsi: _strList(j['opsi']));

  Map<String, dynamic> toJson() => {'teks': teks, 'opsi': opsi};
}

class AIPhotoCandidate {
  final String partNumber;
  final String partName;
  final double similarity;
  final String simsUrl;

  const AIPhotoCandidate({
    required this.partNumber,
    this.partName = '',
    this.similarity = 0,
    this.simsUrl = '',
  });

  factory AIPhotoCandidate.fromJson(Map<String, dynamic> j) => AIPhotoCandidate(
        partNumber: _s(j['part_number']),
        partName: _s(j['part_name']),
        similarity: _d(j['similarity']),
        simsUrl: _s(j['sims_url']),
      );
}

class AIBandingExport {
  final String rangka1;
  final String rangka2;
  final String kategori;
  final String kategoriNama;

  const AIBandingExport({
    required this.rangka1,
    required this.rangka2,
    this.kategori = '',
    this.kategoriNama = '',
  });

  factory AIBandingExport.fromJson(Map<String, dynamic> j) => AIBandingExport(
        rangka1: _s(j['rangka_1']),
        rangka2: _s(j['rangka_2']),
        kategori: _s(j['kategori']),
        kategoriNama: _s(j['kategori_nama']),
      );
}

class AIExcelExport {
  final String id;
  final String filename;
  final String judul;
  final int jumlahBaris;

  const AIExcelExport({
    required this.id,
    this.filename = '',
    this.judul = '',
    this.jumlahBaris = 0,
  });

  factory AIExcelExport.fromJson(Map<String, dynamic> j) => AIExcelExport(
        id: _s(j['id']),
        filename: _s(j['filename']),
        judul: _s(j['judul']),
        jumlahBaris: _i(j['jumlah_baris']),
      );
}

/// Gambar exploded view untuk 1 PN → tampil INLINE di jawaban asisten.
class AIExplodedImage {
  final String id;
  final String? pn;
  final String? balon;
  final String? namaFigure;
  final String? kategori;

  const AIExplodedImage({
    required this.id,
    this.pn,
    this.balon,
    this.namaFigure,
    this.kategori,
  });

  factory AIExplodedImage.fromJson(Map<String, dynamic> j) => AIExplodedImage(
        id: _s(j['id']),
        pn: _sOrNull(j['pn']),
        balon: _sOrNull(j['balon']),
        namaFigure: _sOrNull(j['nama_figure']),
        kategori: _sOrNull(j['kategori']),
      );
}

/// Ringkasan Excel unggahan user — kolom + peran yang dikenali server.
class AISheetSummary {
  final String filename;
  final String sheet;
  final List<String> sheetLain;
  final int jumlahBaris;
  final int jumlahKolom;

  /// Tiap kolom: {nama, peran}.
  final List<({String nama, String peran})> kolom;
  final String? kolomPartNumber;
  final int partNumberDikenalDiKatalog;
  final List<List<String>> contohBaris;
  final bool terpotong;

  const AISheetSummary({
    this.filename = '',
    this.sheet = '',
    this.sheetLain = const [],
    this.jumlahBaris = 0,
    this.jumlahKolom = 0,
    this.kolom = const [],
    this.kolomPartNumber,
    this.partNumberDikenalDiKatalog = 0,
    this.contohBaris = const [],
    this.terpotong = false,
  });

  factory AISheetSummary.fromJson(Map<String, dynamic> j) => AISheetSummary(
        filename: _s(j['filename']),
        sheet: _s(j['sheet']),
        sheetLain: _strList(j['sheet_lain']),
        jumlahBaris: _i(j['jumlah_baris']),
        jumlahKolom: _i(j['jumlah_kolom']),
        kolom: (j['kolom'] as List?)
                ?.whereType<Map>()
                .map((e) => (nama: _s(e['nama']), peran: _s(e['peran'])))
                .toList() ??
            const [],
        kolomPartNumber: _sOrNull(j['kolom_part_number']),
        partNumberDikenalDiKatalog: _i(j['part_number_dikenal_di_katalog']),
        contohBaris: (j['contoh_baris'] as List?)
                ?.whereType<List>()
                .map((r) => r.map((c) => '$c').toList())
                .toList() ??
            const [],
        terpotong: _b(j['terpotong']),
      );
}

/// Hasil baca FOTO nomor rangka (`POST /api/ai/ocr-rangka`).
///
/// Server yang membaca fotonya (OCR + cocokkan ke populasi); asisten sendiri
/// tetap tak pernah melihat gambar — yang dikirim ke chat cuma teks nomornya.
/// ⚠️ [keyakinan] 'rendah' WAJIB ditawarkan ke user untuk dikoreksi dulu: satu
/// huruf salah = unit yang salah, dan itu menjalar ke seluruh jawaban.
class AiOcrRangka {
  final bool ok;
  final String rangka;      // VIN 17 char (atau frame 8 char bila itu saja yg terbaca)
  final String frame;       // 8 char terakhir — kunci EPC
  final String keyakinan;   // pasti | tinggi | rendah | gagal
  final String? unitJenis;  // mis. "HOWO-NX 6X4" (hanya bila cocok di populasi)
  final String? unitModel;
  final String? unitTahun;
  final String pesan;       // kalimat siap tampil (sama persis dengan web)

  const AiOcrRangka({
    this.ok = false,
    this.rangka = '',
    this.frame = '',
    this.keyakinan = 'gagal',
    this.unitJenis,
    this.unitModel,
    this.unitTahun,
    this.pesan = '',
  });

  bool get bolehLangsungKirim => keyakinan == 'pasti' || keyakinan == 'tinggi';

  factory AiOcrRangka.fromJson(Map<String, dynamic> j) {
    final unit = j['unit'] is Map ? (j['unit'] as Map) : const {};
    return AiOcrRangka(
      ok: _b(j['ok']),
      rangka: _s(j['rangka']),
      frame: _s(j['frame']),
      keyakinan: _s(j['keyakinan']),
      unitJenis: _sOrNull(unit['jenis']),
      unitModel: _sOrNull(unit['model']),
      unitTahun: _sOrNull(unit['tahun']),
      pesan: _s(j['pesan']),
    );
  }
}

/// Satu kode kesalahan hasil baca FOTO LAYAR PANEL (bagian dari [AiOcrFoto]).
class AiOcrKode {
  final int spn;
  final int fmi;
  final bool dikenal;        // pasangan SPN+FMI ini terdaftar di database kode
  final String kode;         // kode pabrik bila ada (mis. "P0335")
  final String arti;
  final String unit;         // ECU sumber menurut database (mis. "EMS")
  final List<int> fmiTerdaftar;
  final List<String> alternatif;

  const AiOcrKode({
    this.spn = 0,
    this.fmi = 0,
    this.dikenal = false,
    this.kode = '',
    this.arti = '',
    this.unit = '',
    this.fmiTerdaftar = const [],
    this.alternatif = const [],
  });

  factory AiOcrKode.fromJson(Map<String, dynamic> j) => AiOcrKode(
        spn: _i(j['spn']),
        fmi: _i(j['fmi']),
        dikenal: _b(j['dikenal']),
        kode: _s(j['kode']),
        arti: _s(j['arti']),
        unit: _s(j['unit']),
        fmiTerdaftar:
            (j['fmi_terdaftar'] as List?)?.map((e) => _i(e)).toList() ?? const [],
        alternatif:
            (j['alternatif'] as List?)?.map((e) => _s(e)).toList() ?? const [],
      );
}

/// Hasil baca FOTO lapangan (`POST /api/ai/ocr-foto`) — SATU tombol kamera,
/// dua macam foto: layar panel berisi kode kesalahan ATAU nomor rangka.
///
/// User tak perlu memilih lebih dulu; server mengenali isi fotonya dan
/// mengembalikan [jenis] ('dtc' / 'rangka'). Asisten sendiri tetap tak pernah
/// melihat gambar — yang dikirim ke chat cuma [pesan].
/// ⚠️ [keyakinan] 'rendah' WAJIB ditawarkan ke user untuk dikoreksi dulu: satu
/// angka salah = kode kesalahan LAIN (mekanik membongkar komponen yang salah),
/// dan satu huruf salah = unit yang salah.
class AiOcrFoto {
  final String jenis;            // 'dtc' | 'rangka'
  final bool ok;
  final String keyakinan;        // pasti | tinggi | rendah | gagal
  final String pesan;            // kalimat siap tampil & siap kirim (sama dgn web)
  final AiOcrRangka? rangka;     // terisi bila jenis == 'rangka'
  final List<AiOcrKode> kode;    // terisi bila jenis == 'dtc'
  final String jenisPesan;       // "DM1" (aktif) / "DM2" (tersimpan)
  final String ecu;              // label sumber di layar, mis. "Engine"

  const AiOcrFoto({
    this.jenis = 'rangka',
    this.ok = false,
    this.keyakinan = 'gagal',
    this.pesan = '',
    this.rangka,
    this.kode = const [],
    this.jenisPesan = '',
    this.ecu = '',
  });

  bool get bolehLangsungKirim => keyakinan == 'pasti' || keyakinan == 'tinggi';

  /// Teks yang ditaruh di kotak ketik saat bacaan BELUM yakin: untuk nomor
  /// rangka cukup nomornya (user membetulkan satu huruf), untuk kode kesalahan
  /// kalimat utuhnya (angkanya ada di dalam kalimat itu).
  String get draf => jenis == 'rangka' ? (rangka?.rangka ?? '') : (ok ? pesan : '');

  factory AiOcrFoto.fromJson(Map<String, dynamic> j) {
    final jenis = _s(j['jenis']).isEmpty ? 'rangka' : _s(j['jenis']);
    return AiOcrFoto(
      jenis: jenis,
      ok: _b(j['ok']),
      keyakinan: _s(j['keyakinan']),
      pesan: _s(j['pesan']),
      rangka: jenis == 'rangka' ? AiOcrRangka.fromJson(j) : null,
      kode: (j['kode'] as List?)
              ?.whereType<Map>()
              .map((e) => AiOcrKode.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      jenisPesan: _s(j['jenis_pesan']),
      ecu: _s(j['ecu']),
    );
  }
}

class AIChatResult {
  final String reply;
  final List<String> toolsUsed;
  final List<AIPhotoCandidate> photoCandidates;

  /// Model transmisi yang dibahas → tampilkan tombol unduh Excel repair kit.
  final List<String> repairkitModels;

  /// Perbandingan rangka → kartu unduh Excel hasil perbandingan.
  final List<AIBandingExport> bandingExports;

  /// Export generik (tool `buat_excel`) → kartu unduh Excel dinamis.
  final List<AIExcelExport> excelExports;

  /// Gambar exploded view (tool `gambar_exploded`) → tampil inline.
  final List<AIExplodedImage> explodedImages;

  /// PN yang disebut asisten (grounded) → tampilkan thumbnail foto part.
  final List<String> partPns;

  /// Asisten BERTANYA balik (tool `tanya_user`): giliran berhenti menunggu
  /// jawaban user. `reply` sudah memuat pertanyaan + opsi sebagai teks, jadi
  /// versi lama yang belum merender kartu tetap berguna.
  final List<AIPertanyaan> pertanyaan;

  /// Id sheet di server — WAJIB dikirim lagi di giliran berikutnya supaya
  /// lampiran Excel tetap menempel di percakapan.
  final String? sheetId;
  final AISheetSummary? sheet;

  const AIChatResult({
    this.reply = '',
    this.toolsUsed = const [],
    this.photoCandidates = const [],
    this.repairkitModels = const [],
    this.bandingExports = const [],
    this.excelExports = const [],
    this.explodedImages = const [],
    this.partPns = const [],
    this.pertanyaan = const [],
    this.sheetId,
    this.sheet,
  });

  factory AIChatResult.fromJson(Map<String, dynamic> j) => AIChatResult(
        reply: _s(j['reply']).trim(),
        toolsUsed: _strList(j['tools_used']),
        photoCandidates: _list(j['photo_candidates'], AIPhotoCandidate.fromJson),
        repairkitModels: _strList(j['repairkit_models']),
        bandingExports: _list(j['banding_exports'], AIBandingExport.fromJson),
        excelExports: _list(j['excel_exports'], AIExcelExport.fromJson),
        explodedImages: _list(j['exploded_images'], AIExplodedImage.fromJson)
            .where((e) => e.id.isNotEmpty)
            .toList(),
        partPns: _strList(j['part_pns']),
        pertanyaan: _list(j['pertanyaan'], AIPertanyaan.fromJson),
        sheetId: _sOrNull(j['sheet_id']),
        sheet: j['sheet'] is Map
            ? AISheetSummary.fromJson((j['sheet'] as Map).cast<String, dynamic>())
            : null,
      );

  /// Alias lama — layar asisten yang sudah ada memakai nama ini.
  List<String> get tools => toolsUsed;
}

class AIFeedbackInput {
  /// 'up' | 'down'
  final String rating;
  final String question;
  final String answer;
  final List<String> tools;
  final String? note;
  final List<AIChatTurn> context;

  const AIFeedbackInput({
    required this.rating,
    required this.question,
    required this.answer,
    this.tools = const [],
    this.note,
    this.context = const [],
  });

  Map<String, dynamic> toJson() => {
        'rating': rating,
        'question': question,
        'answer': answer,
        'tools': tools,
        if (note != null) 'note': note,
        'context': context.map((t) => t.toJson()).toList(),
      };
}

class AIFeedbackRow {
  final int id;
  final String createdAt;
  final String? username;
  final String? role;
  final String rating;
  final String? question;
  final String? answer;
  final String? tools;
  final String? note;
  final bool resolved;

  const AIFeedbackRow({
    required this.id,
    this.createdAt = '',
    this.username,
    this.role,
    this.rating = '',
    this.question,
    this.answer,
    this.tools,
    this.note,
    this.resolved = false,
  });

  factory AIFeedbackRow.fromJson(Map<String, dynamic> j) => AIFeedbackRow(
        id: _i(j['id']),
        createdAt: _s(j['created_at']),
        username: _sOrNull(j['username']),
        role: _sOrNull(j['role']),
        rating: _s(j['rating']),
        question: _sOrNull(j['question']),
        answer: _sOrNull(j['answer']),
        tools: _sOrNull(j['tools']),
        note: _sOrNull(j['note']),
        resolved: _b(j['resolved']),
      );
}

class AIFeedbackList {
  final int total;
  final int up;
  final int down;
  final int downBelumDitangani;
  final int jumlah;
  final List<AIFeedbackRow> feedback;

  const AIFeedbackList({
    this.total = 0,
    this.up = 0,
    this.down = 0,
    this.downBelumDitangani = 0,
    this.jumlah = 0,
    this.feedback = const [],
  });

  factory AIFeedbackList.fromJson(Map<String, dynamic> j) {
    final r = (j['ringkasan'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AIFeedbackList(
      total: _i(r['total']),
      up: _i(r['up']),
      down: _i(r['down']),
      downBelumDitangani: _i(r['down_belum_ditangani']),
      jumlah: _i(j['jumlah']),
      feedback: _list(j['feedback'], AIFeedbackRow.fromJson),
    );
  }
}

/// Hasil "Cocok di unit saya?" — verifikasi part terhadap BOM EPC per rangka.
/// `error` = gagal MENGECEK (EPC down / rangka tak dikenal), beda dari
/// `cocok == false` yang berarti pengecekan berhasil tapi part tidak cocok.
class CekUnitResult {
  final bool checked;
  final String? error;
  final bool? cocok;
  final String? frameNumber;
  final String? partNumber;
  final String? pesan;
  final String? nama;
  final String? istilahLapangan;
  final String? qty;
  final String? kategori;

  /// Nama figure exploded view yang memuat part ini.
  final String? lokasi;
  final int? balon;
  final String? imageId;

  /// Kalimat siap tampil ("✅ Cocok — ... kampas rem ...").
  final String? penjelasan;

  const CekUnitResult({
    this.checked = false,
    this.error,
    this.cocok,
    this.frameNumber,
    this.partNumber,
    this.pesan,
    this.nama,
    this.istilahLapangan,
    this.qty,
    this.kategori,
    this.lokasi,
    this.balon,
    this.imageId,
    this.penjelasan,
  });

  factory CekUnitResult.fromJson(Map<String, dynamic> j) => CekUnitResult(
        checked: _b(j['checked']),
        error: _sOrNull(j['error']),
        cocok: j['cocok'] == null ? null : _b(j['cocok']),
        frameNumber: _sOrNull(j['frame_number']),
        partNumber: _sOrNull(j['part_number']),
        pesan: _sOrNull(j['pesan']),
        nama: _sOrNull(j['nama']),
        istilahLapangan: _sOrNull(j['istilah_lapangan']),
        qty: _sOrNull(j['qty']),
        kategori: _sOrNull(j['kategori']),
        lokasi: _sOrNull(j['lokasi']),
        balon: _iOrNull(j['balon']),
        imageId: _sOrNull(j['image_id']),
        penjelasan: _sOrNull(j['penjelasan']),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Admin: index foto, foto part, katalog BOM
// ══════════════════════════════════════════════════════════════════════

class AdminPhoto {
  final String id;
  final String fileName;
  final String storageUrl;
  final int? fileSize;
  final String? createdAt;

  const AdminPhoto({
    required this.id,
    this.fileName = '',
    this.storageUrl = '',
    this.fileSize,
    this.createdAt,
  });

  factory AdminPhoto.fromJson(Map<String, dynamic> j) => AdminPhoto(
        id: _s(j['id']),
        fileName: _s(j['file_name']),
        storageUrl: _s(j['storage_url']),
        fileSize: _iOrNull(j['file_size']),
        createdAt: _sOrNull(j['created_at']),
      );
}

class IndexStatusInfo {
  final bool torch;
  final bool modelReady;
  final int totalIndexed;
  final bool galleryLocal;

  const IndexStatusInfo({
    this.torch = false,
    this.modelReady = false,
    this.totalIndexed = 0,
    this.galleryLocal = false,
  });

  factory IndexStatusInfo.fromJson(Map<String, dynamic> j) => IndexStatusInfo(
        torch: _b(j['torch']),
        modelReady: _b(j['model_ready']),
        totalIndexed: _i(j['total_indexed']),
        galleryLocal: _b(j['gallery_local']),
      );
}

class ReloadGalleryResult {
  final bool ok;
  final int total;
  final String? path;
  final String? error;

  const ReloadGalleryResult({
    this.ok = false,
    this.total = 0,
    this.path,
    this.error,
  });

  factory ReloadGalleryResult.fromJson(Map<String, dynamic> j) =>
      ReloadGalleryResult(
        ok: _b(j['ok']),
        total: _i(j['total']),
        path: _sOrNull(j['path']),
        error: _sOrNull(j['error']),
      );
}

class IndexResult {
  final String pn;
  final int found;
  final int already;
  final int indexed;
  final int failed;
  final String? error;

  const IndexResult({
    this.pn = '',
    this.found = 0,
    this.already = 0,
    this.indexed = 0,
    this.failed = 0,
    this.error,
  });

  factory IndexResult.fromJson(Map<String, dynamic> j) => IndexResult(
        pn: _s(j['pn']),
        found: _i(j['found']),
        already: _i(j['already']),
        indexed: _i(j['indexed']),
        failed: _i(j['failed']),
        error: _sOrNull(j['error']),
      );
}

class CatalogBomStatus {
  final bool available;
  final int unit;
  final int kategori;

  const CatalogBomStatus({
    this.available = false,
    this.unit = 0,
    this.kategori = 0,
  });

  factory CatalogBomStatus.fromJson(Map<String, dynamic> j) => CatalogBomStatus(
        available: _b(j['available']),
        unit: _i(j['unit']),
        kategori: _i(j['kategori']),
      );
}

class CatalogBomRebuildResult {
  final bool ok;
  final int fileKatalogDipindai;
  final int unitBerkategori;
  final int kategori;
  final int assyTerindeks;
  final int totalBarisPart;
  final int ukuranKb;

  const CatalogBomRebuildResult({
    this.ok = false,
    this.fileKatalogDipindai = 0,
    this.unitBerkategori = 0,
    this.kategori = 0,
    this.assyTerindeks = 0,
    this.totalBarisPart = 0,
    this.ukuranKb = 0,
  });

  factory CatalogBomRebuildResult.fromJson(Map<String, dynamic> j) =>
      CatalogBomRebuildResult(
        ok: _b(j['ok']),
        fileKatalogDipindai: _i(j['file_katalog_dipindai']),
        unitBerkategori: _i(j['unit_berkategori']),
        kategori: _i(j['kategori']),
        assyTerindeks: _i(j['assy_terindeks']),
        totalBarisPart: _i(j['total_baris_part']),
        ukuranKb: _i(j['ukuran_kb']),
      );
}

class CatalogUploadResult {
  final bool ok;
  final List<({String path, int size})> saved;
  final int count;
  final List<({String file, String error})> errors;
  final String? refreshWarning;

  const CatalogUploadResult({
    this.ok = false,
    this.saved = const [],
    this.count = 0,
    this.errors = const [],
    this.refreshWarning,
  });

  factory CatalogUploadResult.fromJson(Map<String, dynamic> j) =>
      CatalogUploadResult(
        ok: _b(j['ok']),
        saved: (j['saved'] as List?)
                ?.whereType<Map>()
                .map((e) => (path: _s(e['path']), size: _i(e['size'])))
                .toList() ??
            const [],
        count: _i(j['count']),
        errors: (j['errors'] as List?)
                ?.whereType<Map>()
                .map((e) => (file: _s(e['file']), error: _s(e['error'])))
                .toList() ??
            const [],
        refreshWarning: _sOrNull(j['refresh_warning']),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Stok opname
// ══════════════════════════════════════════════════════════════════════

class OpnameItem {
  final int? qtySistem;
  final int? qtyFisik;
  final String note;
  final String partName;

  const OpnameItem({
    this.qtySistem,
    this.qtyFisik,
    this.note = '',
    this.partName = '',
  });

  factory OpnameItem.fromJson(Map<String, dynamic> j) => OpnameItem(
        qtySistem: _iOrNull(j['qty_sistem']),
        qtyFisik: _iOrNull(j['qty_fisik']),
        note: _s(j['note']),
        partName: _s(j['part_name']),
      );

  Map<String, dynamic> toJson() => {
        'qty_sistem': qtySistem,
        'qty_fisik': qtyFisik,
        'note': note,
        'part_name': partName,
      };

  OpnameItem copyWith({
    int? qtySistem,
    int? qtyFisik,
    String? note,
    String? partName,
    bool clearQtyFisik = false,
  }) =>
      OpnameItem(
        qtySistem: qtySistem ?? this.qtySistem,
        qtyFisik: clearQtyFisik ? null : (qtyFisik ?? this.qtyFisik),
        note: note ?? this.note,
        partName: partName ?? this.partName,
      );

  /// Selisih fisik − sistem. null bila fisik belum diisi.
  int? get selisih =>
      (qtyFisik == null || qtySistem == null) ? null : qtyFisik! - qtySistem!;
}

class OpnameSession {
  final String sessionId;

  /// part number → item opname.
  final Map<String, OpnameItem> items;
  final String? sourceFile;
  final String? sourceFilename;
  final String? finalizedAt;
  final String? createdAt;
  final String? updatedAt;
  final String? username;

  const OpnameSession({
    required this.sessionId,
    this.items = const {},
    this.sourceFile,
    this.sourceFilename,
    this.finalizedAt,
    this.createdAt,
    this.updatedAt,
    this.username,
  });

  factory OpnameSession.fromJson(Map<String, dynamic> j) => OpnameSession(
        sessionId: _s(j['session_id']),
        items: (j['items'] as Map?)?.map(
              (k, v) => MapEntry(
                '$k',
                OpnameItem.fromJson(
                    (v as Map?)?.cast<String, dynamic>() ?? const {}),
              ),
            ) ??
            const {},
        sourceFile: _sOrNull(j['source_file']),
        sourceFilename: _sOrNull(j['source_filename']),
        finalizedAt: _sOrNull(j['finalized_at']),
        createdAt: _sOrNull(j['created_at']),
        updatedAt: _sOrNull(j['updated_at']),
        username: _sOrNull(j['username']),
      );

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'items': items.map((k, v) => MapEntry(k, v.toJson())),
        'source_file': sourceFile,
        'source_filename': sourceFilename,
        'finalized_at': finalizedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'username': username,
      };

  OpnameSession copyWith({Map<String, OpnameItem>? items}) => OpnameSession(
        sessionId: sessionId,
        items: items ?? this.items,
        sourceFile: sourceFile,
        sourceFilename: sourceFilename,
        finalizedAt: finalizedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        username: username,
      );

  int get jumlahItem => items.length;
  int get jumlahTerhitung =>
      items.values.where((e) => e.qtyFisik != null).length;
  int get jumlahSelisih =>
      items.values.where((e) => (e.selisih ?? 0) != 0).length;
}

// ══════════════════════════════════════════════════════════════════════
// Monitoring & observabilitas
// ══════════════════════════════════════════════════════════════════════

class MonitoringUser {
  final String username;
  final String role;
  final bool online;
  final bool isActive;
  final String? lastLoginAt;
  final String? lastActiveAt;
  final String? lastIp;
  final String? lastDevice;

  /// Jaringan unik (/64 utk IPv6) dalam `shareDays` hari — bukan alamat unik.
  final int ipCount;

  /// Alamat unik. IPv6 memutar alamatnya sendiri, jadi ini bisa jauh lebih
  /// besar dari [ipCount] tanpa berarti akun dibagi-bagi.
  final int alamatCount;
  final int deviceCount;
  final int loginCount;
  final List<String> ips;
  final List<String> devices;

  /// SINYAL (bukan vonis) bahwa akun dipakai beramai-ramai.
  final bool kemungkinanDipakaiRamai;

  const MonitoringUser({
    required this.username,
    this.role = '',
    this.online = false,
    this.isActive = true,
    this.lastLoginAt,
    this.lastActiveAt,
    this.lastIp,
    this.lastDevice,
    this.ipCount = 0,
    this.alamatCount = 0,
    this.deviceCount = 0,
    this.loginCount = 0,
    this.ips = const [],
    this.devices = const [],
    this.kemungkinanDipakaiRamai = false,
  });

  factory MonitoringUser.fromJson(Map<String, dynamic> j) => MonitoringUser(
        username: _s(j['username']),
        role: _s(j['role']),
        online: _b(j['online']),
        isActive: _b(j['is_active'], true),
        lastLoginAt: _sOrNull(j['last_login_at']),
        lastActiveAt: _sOrNull(j['last_active_at']),
        lastIp: _sOrNull(j['last_ip']),
        lastDevice: _sOrNull(j['last_device']),
        ipCount: _i(j['ip_count']),
        alamatCount: _i(j['alamat_count']),
        deviceCount: _i(j['device_count']),
        loginCount: _i(j['login_count']),
        ips: _strList(j['ips']),
        devices: _strList(j['devices']),
        kemungkinanDipakaiRamai: _b(j['kemungkinan_dipakai_ramai']),
      );
}

class MonitoringActivity {
  final String? createdAt;
  final String username;
  final String action;
  final String? target;
  final String? ip;
  final String? device;

  const MonitoringActivity({
    this.createdAt,
    required this.username,
    this.action = '',
    this.target,
    this.ip,
    this.device,
  });

  factory MonitoringActivity.fromJson(Map<String, dynamic> j) =>
      MonitoringActivity(
        createdAt: _sOrNull(j['created_at']),
        username: _s(j['username']),
        action: _s(j['action']),
        target: _sOrNull(j['target']),
        ip: _sOrNull(j['ip']),
        device: _sOrNull(j['device']),
      );
}

class MonitoringData {
  final int onlineCount;
  final int totalUsers;
  final int onlineWindowMinutes;
  final int shareDays;
  final int shareIpMin;
  final int shareDeviceMin;

  /// false = tabel `login_history` belum dibuat di Supabase.
  final bool riwayatTersedia;
  final List<MonitoringUser> users;
  final List<MonitoringActivity> recentActivity;

  const MonitoringData({
    this.onlineCount = 0,
    this.totalUsers = 0,
    this.onlineWindowMinutes = 0,
    this.shareDays = 0,
    this.shareIpMin = 0,
    this.shareDeviceMin = 0,
    this.riwayatTersedia = true,
    this.users = const [],
    this.recentActivity = const [],
  });

  factory MonitoringData.fromJson(Map<String, dynamic> j) => MonitoringData(
        onlineCount: _i(j['online_count']),
        totalUsers: _i(j['total_users']),
        onlineWindowMinutes: _i(j['online_window_minutes']),
        shareDays: _i(j['share_days']),
        shareIpMin: _i(j['share_ip_min']),
        shareDeviceMin: _i(j['share_device_min']),
        riwayatTersedia: _b(j['riwayat_tersedia'], true),
        users: _list(j['users'], MonitoringUser.fromJson),
        recentActivity: _list(j['recent_activity'], MonitoringActivity.fromJson),
      );
}

class LoginHistoryRow {
  final int id;
  final String createdAt;
  final String username;
  final String? role;
  final String? ip;
  final String? device;

  const LoginHistoryRow({
    required this.id,
    this.createdAt = '',
    this.username = '',
    this.role,
    this.ip,
    this.device,
  });

  factory LoginHistoryRow.fromJson(Map<String, dynamic> j) => LoginHistoryRow(
        id: _i(j['id']),
        createdAt: _s(j['created_at']),
        username: _s(j['username']),
        role: _sOrNull(j['role']),
        ip: _sOrNull(j['ip']),
        device: _sOrNull(j['device']),
      );
}

class SearchMiss {
  final String query;
  final int count;
  final List<String> modes;
  final List<String> sources;
  final int last;

  const SearchMiss({
    required this.query,
    this.count = 0,
    this.modes = const [],
    this.sources = const [],
    this.last = 0,
  });

  factory SearchMiss.fromJson(Map<String, dynamic> j) => SearchMiss(
        query: _s(j['query']),
        count: _i(j['count']),
        modes: _strList(j['modes']),
        sources: _strList(j['sources']),
        last: _i(j['last']),
      );
}

class ChatLogRow {
  final int id;
  final String createdAt;
  final String username;
  final String role;
  final String question;
  final String tools;
  final int toolsCount;
  final int rounds;
  final int latencyMs;
  final bool guardHit;
  final bool toolFailed;
  final int replyLen;
  final String outcome;

  // Biaya token DeepSeek per giliran (migrasi 021). 0 = baris lama tak tercatat.
  final int tokensIn;
  final int tokensOut;
  final int tokensCacheHit;
  final int apiCalls;

  /// Teks jawaban AI (migrasi 022) — kosong untuk baris lama.
  final String reply;

  /// Nama tool yang GAGAL giliran ini (migrasi 023), dipisah koma.
  final String toolsFailed;

  const ChatLogRow({
    required this.id,
    this.createdAt = '',
    this.username = '',
    this.role = '',
    this.question = '',
    this.tools = '',
    this.toolsCount = 0,
    this.rounds = 0,
    this.latencyMs = 0,
    this.guardHit = false,
    this.toolFailed = false,
    this.replyLen = 0,
    this.outcome = '',
    this.tokensIn = 0,
    this.tokensOut = 0,
    this.tokensCacheHit = 0,
    this.apiCalls = 0,
    this.reply = '',
    this.toolsFailed = '',
  });

  factory ChatLogRow.fromJson(Map<String, dynamic> j) => ChatLogRow(
        id: _i(j['id']),
        createdAt: _s(j['created_at']),
        username: _s(j['username']),
        role: _s(j['role']),
        question: _s(j['question']),
        tools: _s(j['tools']),
        toolsCount: _i(j['tools_count']),
        rounds: _i(j['rounds']),
        latencyMs: _i(j['latency_ms']),
        guardHit: _b(j['guard_hit']),
        toolFailed: _b(j['tool_failed']),
        replyLen: _i(j['reply_len']),
        outcome: _s(j['outcome']),
        tokensIn: _i(j['tokens_in']),
        tokensOut: _i(j['tokens_out']),
        tokensCacheHit: _i(j['tokens_cache_hit']),
        apiCalls: _i(j['api_calls']),
        reply: _s(j['reply']),
        toolsFailed: _s(j['tools_failed']),
      );
}

class ChatLogSummary {
  final int total;
  final int latensiP50;
  final int latensiP90;
  final int latensiMaks;
  final int guardMenyala;
  final double guardRasioPersen;
  final int toolGagal;
  final double toolGagalRasioPersen;

  /// Tool tersering: (nama, jumlah).
  final List<({String tool, int count})> toolTersering;

  /// Tool paling sering gagal: (nama, jumlah gagal, % dari pemakaian, jumlah
  /// `nf` = lookup jujur nihil, jumlah `err` = error/infra, jumlah `brake` =
  /// DITOLAK rem anti-loop — belum sempat dicek sama sekali). Ringkasan lama
  /// (sebelum migrasi 2026-07-20) tak punya angka-angka terakhir → 0.
  final List<({String tool, int count, double pct, int nf, int err, int brake})>
      toolGagalTersering;

  /// Rincian total kegagalan per jenis. `brake` = plafon panggilan tool KITA
  /// yang menolak (bukan data hilang, bukan infra rusak) — sebelum 2026-08-16
  /// ia ikut terhitung `legacy`, sehingga kelas kegagalan yang paling bisa
  /// diperbaiki justru tampil sebagai "sisa baris lama". `legacy` = baris lama
  /// tanpa suffix jenis.
  final ({int nf, int err, int brake, int legacy})? toolGagalRincian;
  final Map<String, int> outcome;

  /// Sebab guard menyala → jumlah (migrasi 026): pn/angka = dugaan karangan,
  /// subst = PN per-model menyalip EPC per-VIN, dtc/epc/excel = jawaban tanpa
  /// tool wajib. KOSONG pada ringkasan lama — dan `guardMenyala` baris lama
  /// UNDERCOUNT (dulu hanya guard anti-karangan yang terhitung).
  final Map<String, int> guardSebab;

  // Rata-rata token DeepSeek per giliran (migrasi 021).
  final int tokenRata2In;
  final int tokenRata2Out;
  final double tokenCacheHitPersen;
  final int tokenGiliranTerukur;

  const ChatLogSummary({
    this.total = 0,
    this.latensiP50 = 0,
    this.latensiP90 = 0,
    this.latensiMaks = 0,
    this.guardMenyala = 0,
    this.guardRasioPersen = 0,
    this.toolGagal = 0,
    this.toolGagalRasioPersen = 0,
    this.toolTersering = const [],
    this.toolGagalTersering = const [],
    this.toolGagalRincian,
    this.outcome = const {},
    this.guardSebab = const {},
    this.tokenRata2In = 0,
    this.tokenRata2Out = 0,
    this.tokenCacheHitPersen = 0,
    this.tokenGiliranTerukur = 0,
  });

  factory ChatLogSummary.fromJson(Map<String, dynamic> j) {
    final lat = (j['latensi_ms'] as Map?)?.cast<String, dynamic>() ?? const {};
    final tok = (j['token'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ChatLogSummary(
      total: _i(j['total']),
      latensiP50: _i(lat['p50']),
      latensiP90: _i(lat['p90']),
      latensiMaks: _i(lat['maks']),
      guardMenyala: _i(j['guard_menyala']),
      guardRasioPersen: _d(j['guard_rasio_persen']),
      toolGagal: _i(j['tool_gagal']),
      toolGagalRasioPersen: _d(j['tool_gagal_rasio_persen']),
      // Backend mengirim list pasangan [nama, jumlah].
      toolTersering: (j['tool_tersering'] as List?)
              ?.whereType<List>()
              .where((p) => p.length >= 2)
              .map((p) => (tool: '${p[0]}', count: _i(p[1])))
              .toList() ??
          const [],
      // Backend mengirim [nama, jumlah_gagal, persen, jumlah_nf, jumlah_err,
      // jumlah_brake]. Elemen setelah persen OPSIONAL — ringkasan lama berhenti
      // di persen, dan `brake` baru ada sejak 2026-08-16.
      toolGagalTersering: (j['tool_gagal_tersering'] as List?)
              ?.whereType<List>()
              .where((p) => p.length >= 3)
              .map((p) => (
                    tool: '${p[0]}',
                    count: _i(p[1]),
                    pct: _d(p[2]),
                    nf: p.length >= 4 ? _i(p[3]) : 0,
                    err: p.length >= 5 ? _i(p[4]) : 0,
                    brake: p.length >= 6 ? _i(p[5]) : 0,
                  ))
              .toList() ??
          const [],
      toolGagalRincian: switch (j['tool_gagal_rincian']) {
        final Map r => (
            nf: _i(r['nf']),
            err: _i(r['err']),
            brake: _i(r['brake']),
            legacy: _i(r['legacy']),
          ),
        _ => null,
      },
      outcome: (j['outcome'] as Map?)?.map((k, v) => MapEntry('$k', _i(v))) ??
          const {},
      guardSebab:
          (j['guard_sebab'] as Map?)?.map((k, v) => MapEntry('$k', _i(v))) ??
              const {},
      tokenRata2In: _i(tok['rata2_in']),
      tokenRata2Out: _i(tok['rata2_out']),
      tokenCacheHitPersen: _d(tok['cache_hit_persen']),
      tokenGiliranTerukur: _i(tok['giliran_terukur']),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Pengetahuan Asisten AI (admin menulis/mengunggah, server mengindeks)
// ══════════════════════════════════════════════════════════════════════

/// Satu berkas yang dilampirkan ke sebuah dokumen pengetahuan.
class PengetahuanBerkas {
  final String nama;

  /// Nama file di disk server — DIBANGKITKAN server, bukan nama asli.
  final String namaSimpan;
  final int ukuran;
  final String ext;

  const PengetahuanBerkas({
    required this.nama,
    this.namaSimpan = '',
    this.ukuran = 0,
    this.ext = '',
  });

  factory PengetahuanBerkas.fromJson(Map<String, dynamic> j) =>
      PengetahuanBerkas(
        nama: _s(j['nama']),
        namaSimpan: _s(j['nama_simpan']),
        ukuran: _i(j['ukuran']),
        ext: _s(j['ext']),
      );

  /// Ukuran manusiawi ("1,4 MB"). Kosong bila server tak mengirim ukuran.
  String get ukuranLabel {
    if (ukuran <= 0) return '';
    if (ukuran < 1024) return '$ukuran B';
    if (ukuran < 1024 * 1024) return '${(ukuran / 1024).round()} KB';
    return '${(ukuran / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// Progres job indexing di latar.
class PengetahuanProgres {
  final String langkah;
  final int kini;
  final int total;
  final int persen;

  const PengetahuanProgres({
    this.langkah = '',
    this.kini = 0,
    this.total = 0,
    this.persen = 0,
  });

  factory PengetahuanProgres.fromJson(Map<String, dynamic> j) =>
      PengetahuanProgres(
        langkah: _s(j['langkah']),
        kini: _i(j['kini']),
        total: _i(j['total']),
        persen: _i(j['persen']),
      );
}

/// Satu dokumen pengetahuan beserta status indexingnya.
class PengetahuanDok {
  final String id;
  final String judul;
  final String deskripsi;
  final List<String> tag;
  final List<PengetahuanBerkas> berkas;

  /// true = seluruh isinya boleh dibaca akun PEMBELI lewat Asisten AI.
  final bool untukPembeli;

  /// Perkaya judul & kata kunci dengan LLM saat indexing.
  final bool pakaiAi;
  final bool aktif;

  /// 'antre' | 'proses' | 'selesai' | 'selesai_sebagian' | 'gagal'.
  final String status;
  final PengetahuanProgres progres;
  final int jumlahChunk;

  /// '' | 'llm' | 'campuran' | lainnya (otomatis tanpa LLM).
  final String pengayaan;
  final String error;
  final String oleh;

  /// Dari mana entri ini lahir. "chat" = diajarkan lewat chat (tool
  /// `ajarkan_pengetahuan`); '' = jalur lama (diketik/diunggah lewat menu).
  final String asal;

  /// Diindeks sebelum pembedahan dokumen ditingkatkan — perlu indeks ulang
  /// agar gambar, breadcrumb bab, dan nama kolom tabel ikut terambil.
  final bool perluReindex;

  const PengetahuanDok({
    required this.id,
    this.judul = '',
    this.deskripsi = '',
    this.tag = const [],
    this.berkas = const [],
    this.untukPembeli = false,
    this.pakaiAi = true,
    this.aktif = true,
    this.status = '',
    this.progres = const PengetahuanProgres(),
    this.jumlahChunk = 0,
    this.pengayaan = '',
    this.error = '',
    this.oleh = '',
    this.asal = '',
    this.perluReindex = false,
  });

  factory PengetahuanDok.fromJson(Map<String, dynamic> j) => PengetahuanDok(
        id: _s(j['id']),
        judul: _s(j['judul']),
        deskripsi: _s(j['deskripsi']),
        tag: _strList(j['tag']),
        berkas: (j['berkas'] as List?)
                ?.whereType<Map>()
                .map((b) => PengetahuanBerkas.fromJson(b.cast<String, dynamic>()))
                .toList() ??
            const [],
        untukPembeli: _b(j['untuk_pembeli']),
        pakaiAi: _b(j['pakai_ai'], true),
        aktif: _b(j['aktif'], true),
        status: _s(j['status']),
        progres: PengetahuanProgres.fromJson(
            (j['progres'] as Map?)?.cast<String, dynamic>() ?? const {}),
        jumlahChunk: _i(j['jumlah_chunk']),
        pengayaan: _s(j['pengayaan']),
        error: _s(j['error']),
        oleh: _s(j['oleh']),
        asal: _s(j['asal']),
        perluReindex: _b(j['perlu_reindex']),
      );

  /// Salinan dengan status/progres terbaru dari endpoint `/status` — dipakai
  /// polling agar baris di daftar bergerak tanpa memuat ulang semuanya.
  PengetahuanDok salinStatus(PengetahuanDok s) => PengetahuanDok(
        id: id,
        judul: judul,
        deskripsi: deskripsi,
        tag: tag,
        berkas: berkas,
        untukPembeli: untukPembeli,
        pakaiAi: pakaiAi,
        aktif: aktif,
        status: s.status,
        progres: s.progres,
        jumlahChunk: s.jumlahChunk,
        pengayaan: s.pengayaan,
        error: s.error,
        oleh: oleh,
        // `asal` melekat pada entri, bukan pada status indexing — ikut disalin
        // dari `this` supaya label "dari chat" tidak hilang saat polling.
        asal: asal,
        perluReindex: perluReindex,
      );

  bool get selesaiDiproses =>
      status == 'selesai' || status == 'selesai_sebagian' || status == 'gagal';

  String get statusLabel => switch (status) {
        'antre' => 'Antre',
        'proses' => 'Diproses',
        'selesai' => 'Selesai',
        'selesai_sebagian' => 'Selesai sebagian',
        'gagal' => 'Gagal',
        _ => status,
      };

  String get pengayaanLabel => switch (pengayaan) {
        'llm' => 'AI',
        'campuran' => 'AI sebagian',
        '' => '—',
        _ => 'otomatis',
      };
}

/// Satu bagian (chunk) hasil pembedahan dokumen — inilah yang dicari asisten.
class PengetahuanChunk {
  /// Berbentuk `<dok_id>#<seq>`.
  final String id;
  final String dokId;
  final String judul;

  /// Judul versi Indonesia hasil pengayaan; boleh dikurasi admin.
  final String judulId;
  final List<String> kataKunci;
  final String ringkasan;
  final String teks;
  final List<List<String>> tabel;
  final List<String> gambarRef;
  final String sumber;
  final int halaman;
  final String tipe;
  final bool untukPembeli;

  /// false = dikecualikan dari pencarian asisten.
  final bool dicari;
  final List<String> kode;

  // ── Hasil ekstraksi V2 — chunk berskema lama tidak punya ini ──
  final String bahasa;

  /// Breadcrumb bab/sub-bab tempat potongan ini berada.
  final List<String> jalur;
  final List<String> kolom;
  final int barisTotal;
  final List<({String file, String caption, int halaman})> gambarInfo;

  /// Judul/kata kunci sudah pernah diperbaiki admin.
  final bool kurasi;
  final int skema;

  const PengetahuanChunk({
    required this.id,
    this.dokId = '',
    this.judul = '',
    this.judulId = '',
    this.kataKunci = const [],
    this.ringkasan = '',
    this.teks = '',
    this.tabel = const [],
    this.gambarRef = const [],
    this.sumber = '',
    this.halaman = 0,
    this.tipe = '',
    this.untukPembeli = false,
    this.dicari = true,
    this.kode = const [],
    this.bahasa = '',
    this.jalur = const [],
    this.kolom = const [],
    this.barisTotal = 0,
    this.gambarInfo = const [],
    this.kurasi = false,
    this.skema = 0,
  });

  factory PengetahuanChunk.fromJson(Map<String, dynamic> j) => PengetahuanChunk(
        id: _s(j['id']),
        dokId: _s(j['dok_id']),
        judul: _s(j['judul']),
        judulId: _s(j['judul_id']),
        kataKunci: _strList(j['kata_kunci']),
        ringkasan: _s(j['ringkasan']),
        teks: _s(j['teks']),
        tabel: (j['tabel'] as List?)
                ?.whereType<List>()
                .map((r) => r.map((c) => _s(c)).toList())
                .toList() ??
            const [],
        gambarRef: _strList(j['gambar_ref']),
        sumber: _s(j['sumber']),
        halaman: _i(j['halaman']),
        tipe: _s(j['tipe']),
        untukPembeli: _b(j['untuk_pembeli']),
        dicari: _b(j['dicari'], true),
        kode: _strList(j['kode']),
        bahasa: _s(j['bahasa']),
        jalur: _strList(j['jalur']),
        kolom: _strList(j['kolom']),
        barisTotal: _i(j['baris_total']),
        gambarInfo: (j['gambar_info'] as List?)
                ?.whereType<Map>()
                .map((g) => (
                      file: _s(g['file']),
                      caption: _s(g['caption']),
                      halaman: _i(g['halaman']),
                    ))
                .toList() ??
            const [],
        kurasi: _b(j['kurasi']),
        skema: _i(j['skema']),
      );

  /// Bagian setelah `#` — itulah `cid` yang diminta endpoint PATCH chunk.
  String get seq => id.contains('#') ? id.split('#')[1] : '';

  /// Judul yang dipakai di UI: versi Indonesia bila ada.
  String get judulTampil => judulId.isNotEmpty ? judulId : judul;
}

// ══════════════════════════════════════════════════════════════════════
// Sinonim (istilah lapangan → kata kunci katalog)
// ══════════════════════════════════════════════════════════════════════

class SinonimEntry {
  final String grup;
  final List<String> triggers;
  final List<String> keywords;

  const SinonimEntry({
    required this.grup,
    this.triggers = const [],
    this.keywords = const [],
  });

  factory SinonimEntry.fromJson(Map<String, dynamic> j) => SinonimEntry(
        grup: _s(j['grup']),
        triggers: _strList(j['triggers']),
        keywords: _strList(j['keywords']),
      );

  Map<String, dynamic> toJson() => {
        'grup': grup,
        'triggers': triggers,
        'keywords': keywords,
      };
}

/// Rute Maksud: frasa khas bengkel → TOOL yang dipakai asisten.
///
/// Beda dari [SinonimEntry]: kamus sinonim mengubah KATA yang dicari (ekspansi
/// query), rute mengubah ALAT yang dipakai. Sebelum store ini ada, aturan
/// semacam "gambar teknis = exploded view" cuma bisa ditulis di berkas prompt
/// server — artinya butuh deploy.
class MaksudEntry {
  final List<String> frasa;
  final String tool;
  final String catatan;
  final String oleh;

  const MaksudEntry({
    this.frasa = const [],
    required this.tool,
    this.catatan = '',
    this.oleh = '',
  });

  factory MaksudEntry.fromJson(Map<String, dynamic> j) => MaksudEntry(
        frasa: _strList(j['frasa']),
        tool: _s(j['tool']),
        catatan: _s(j['catatan']),
        oleh: _s(j['oleh']),
      );

  Map<String, dynamic> toJson() => {
        'frasa': frasa,
        'tool': tool,
        'catatan': catatan,
      };
}

class SinonimUsulan {
  final String id;
  final String query;
  final int countMiss;
  final String grup;
  final List<String> triggers;
  final List<String> keywords;
  final List<String> keywordsDibuang;
  final double confidence;
  final String? alasan;
  final String status;
  final String? catatanApply;

  const SinonimUsulan({
    required this.id,
    this.query = '',
    this.countMiss = 0,
    this.grup = '',
    this.triggers = const [],
    this.keywords = const [],
    this.keywordsDibuang = const [],
    this.confidence = 0,
    this.alasan,
    this.status = '',
    this.catatanApply,
  });

  factory SinonimUsulan.fromJson(Map<String, dynamic> j) => SinonimUsulan(
        id: _s(j['id']),
        query: _s(j['query']),
        countMiss: _i(j['count_miss']),
        grup: _s(j['grup']),
        triggers: _strList(j['triggers']),
        keywords: _strList(j['keywords']),
        keywordsDibuang: _strList(j['keywords_dibuang']),
        confidence: _d(j['confidence']),
        alasan: _sOrNull(j['alasan']),
        status: _s(j['status']),
        catatanApply: _sOrNull(j['catatan_apply']),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Laporan penjualan & gudang
// ══════════════════════════════════════════════════════════════════════

class SalesRecap {
  final int totalOrders;
  final int paidOrders;
  final double omzet;
  final int itemsSold;

  /// status → (jumlah, omzet).
  final Map<String, ({int count, double omzet})> byStatus;
  final List<({String gudang, int count, double omzet})> byGudang;
  final List<({String month, int count, double omzet})> byMonth;
  final List<({String partNumber, String name, int qty, double omzet})> topParts;

  const SalesRecap({
    this.totalOrders = 0,
    this.paidOrders = 0,
    this.omzet = 0,
    this.itemsSold = 0,
    this.byStatus = const {},
    this.byGudang = const [],
    this.byMonth = const [],
    this.topParts = const [],
  });

  factory SalesRecap.fromJson(Map<String, dynamic> j) {
    final s = (j['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SalesRecap(
      totalOrders: _i(s['total_orders']),
      paidOrders: _i(s['paid_orders']),
      omzet: _d(s['omzet']),
      itemsSold: _i(s['items_sold']),
      byStatus: (j['by_status'] as Map?)?.map(
            (k, v) {
              final m = (v as Map?)?.cast<String, dynamic>() ?? const {};
              return MapEntry(
                  '$k', (count: _i(m['count']), omzet: _d(m['omzet'])));
            },
          ) ??
          const {},
      byGudang: (j['by_gudang'] as List?)
              ?.whereType<Map>()
              .map((e) => (
                    gudang: _s(e['gudang']),
                    count: _i(e['count']),
                    omzet: _d(e['omzet'])
                  ))
              .toList() ??
          const [],
      byMonth: (j['by_month'] as List?)
              ?.whereType<Map>()
              .map((e) => (
                    month: _s(e['month']),
                    count: _i(e['count']),
                    omzet: _d(e['omzet'])
                  ))
              .toList() ??
          const [],
      topParts: (j['top_parts'] as List?)
              ?.whereType<Map>()
              .map((e) => (
                    partNumber: _s(e['part_number']),
                    name: _s(e['name']),
                    qty: _i(e['qty']),
                    omzet: _d(e['omzet'])
                  ))
              .toList() ??
          const [],
    );
  }
}

class AdminGudang {
  final String label;
  final String display;
  final double? lat;
  final double? lon;

  /// Boleh dipilih pembeli sebagai lokasi belanja.
  final bool selectable;
  final String? key;
  final String originPostal;
  final String pic;

  /// Boleh jadi gudang PENGIRIM pesanan online. Gudang internal yang
  /// dicentang mati tak akan pernah memenuhi pesanan online.
  final bool canShip;
  final List<String> nearest;

  const AdminGudang({
    required this.label,
    this.display = '',
    this.lat,
    this.lon,
    this.selectable = false,
    this.key,
    this.originPostal = '',
    this.pic = '',
    this.canShip = false,
    this.nearest = const [],
  });

  factory AdminGudang.fromJson(Map<String, dynamic> j) => AdminGudang(
        label: _s(j['label']),
        display: _s(j['display']),
        lat: _dOrNull(j['lat']),
        lon: _dOrNull(j['lon']),
        selectable: _b(j['selectable']),
        key: _sOrNull(j['key']),
        originPostal: _s(j['origin_postal']),
        pic: _s(j['pic']),
        canShip: _b(j['can_ship']),
        nearest: _strList(j['nearest']),
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'lat': lat,
        'lon': lon,
        'selectable': selectable,
        'key': key,
        'pic': pic,
        'origin_postal': originPostal,
        'can_ship': canShip,
      };

  AdminGudang copyWith({
    double? lat,
    double? lon,
    bool? selectable,
    String? key,
    String? originPostal,
    String? pic,
    bool? canShip,
  }) =>
      AdminGudang(
        label: label,
        display: display,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        selectable: selectable ?? this.selectable,
        key: key ?? this.key,
        originPostal: originPostal ?? this.originPostal,
        pic: pic ?? this.pic,
        canShip: canShip ?? this.canShip,
        nearest: nearest,
      );
}

// ══════════════════════════════════════════════════════════════════════
// Rak & Kartu Stok
// ══════════════════════════════════════════════════════════════════════

/// Lokasi fisik satu part di SATU gudang (kunci data = pasangan pn × gudang).
/// Sistem sudah tahu BERAPA stoknya dari Accurate; baris ini menjawab DI MANA
/// barangnya, plus foto kartu stok sebagai bukti visual (bukan sumber angka).
class RakInfo {
  /// PN apa adanya seperti yang diketik pengisi (bisa ber-suffix varian).
  final String partNumber;

  /// PN ter-normalisasi milik server — dipakai server untuk mencocokkan
  /// 'WG9525160004/2' dengan 'WG9525160004'. Klien tak perlu menghitungnya.
  final String pnKey;

  /// Label PENUH gudang ("01.Jakarta") — sama persis dengan `per_gudang`
  /// Accurate. ⛔ Jangan pakai nama lokasi versi pembeli untuk mencocokkan.
  final String gudang;
  final String rak;
  final String catatan;

  /// URL publik foto kartu stok. Kosong = belum ada foto (hanya yang TERBARU
  /// disimpan server — tanpa riwayat).
  final String fotoUrl;
  final String updatedBy;
  final String updatedAt;

  const RakInfo({
    this.partNumber = '',
    this.pnKey = '',
    this.gudang = '',
    this.rak = '',
    this.catatan = '',
    this.fotoUrl = '',
    this.updatedBy = '',
    this.updatedAt = '',
  });

  factory RakInfo.fromJson(Map<String, dynamic> j) => RakInfo(
        partNumber: _s(j['part_number']),
        pnKey: _s(j['pn_key']),
        gudang: _s(j['gudang']),
        rak: _s(j['rak']),
        catatan: _s(j['catatan']),
        fotoUrl: _s(j['foto_url']),
        updatedBy: _s(j['updated_by']),
        updatedAt: _s(j['updated_at']),
      );

  /// Baris yang benar-benar kosong (server bisa membalas objek kosong saat
  /// baris baru saja dihapus) — dipakai UI untuk memutuskan tampil/tidak.
  bool get kosong => rak.trim().isEmpty && catatan.trim().isEmpty && fotoUrl.isEmpty;

  /// Dipakai setelah unggah/hapus foto: simpan rak & unggah foto adalah DUA
  /// panggilan (server menolak foto pada baris yang belum punya kode rak),
  /// jadi hasil panggilan pertama perlu ditambal URL dari panggilan kedua.
  RakInfo copyWith({String? fotoUrl}) => RakInfo(
        partNumber: partNumber,
        pnKey: pnKey,
        gudang: gudang,
        rak: rak,
        catatan: catatan,
        fotoUrl: fotoUrl ?? this.fotoUrl,
        updatedBy: updatedBy,
        updatedAt: updatedAt,
      );
}
