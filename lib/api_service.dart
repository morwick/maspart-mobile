// lib/api_service.dart
// Klien API MASPART — cerminan `frontend/src/lib/api.ts`.
//
// Aturan main:
// • Nama path & field JSON dijaga PERSIS sama dengan backend/web.
// • Semua panggilan ber-auth lewat helper di `_Api`, jadi penanganan 401
//   (token dibuang + pesan "Sesi habis") cuma ditulis sekali.
// • Method lama (login/searchPart/searchByImage/…) dipertahankan apa adanya
//   supaya layar yang sudah jalan tidak perlu diubah.

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'auth_storage.dart';
import 'models.dart';

export 'models.dart';

/// Exception khusus dari API — supaya UI bisa tangkap & tampilkan pesan rapi.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  /// Sesi tidak berlaku lagi (token kedaluwarsa / akun dipakai di perangkat
  /// lain). Layar bisa memakai ini untuk melempar user ke halaman login.
  bool get isAuth => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

// Nama lama yang masih dipakai layar Asisten AI.
typedef AiChatResult = AIChatResult;
typedef AiExplodedImage = AIExplodedImage;

/// Satu item keranjang saat dikirim ke server (berat/harga/ongkir dihitung
/// server dari PN + qty, bukan dari angka yang disimpan perangkat).
class CartLine {
  final String partNumber;
  final int qty;
  final String? name;

  const CartLine({required this.partNumber, required this.qty, this.name});

  Map<String, dynamic> toJson() => {
        'part_number': partNumber,
        'qty': qty,
        if (name != null) 'name': name,
      };
}

// ══════════════════════════════════════════════════════════════════════
// Inti HTTP
// ══════════════════════════════════════════════════════════════════════

class _Api {
  static const _timeout = Duration(seconds: 60);

  /// Timeout longgar untuk operasi berat (asisten AI, indexing, rebuild BOM,
  /// pencarian foto) yang di server memang bisa makan puluhan detik.
  static const _timeoutLong = Duration(seconds: 180);

  /// Khusus Batch Download berkolom exploded: gambar diambil satu per satu dari
  /// EPC (±94 dtk per PN yang belum pernah dibuka, cap 25 PN, 3 pekerja) → bisa
  /// 15 menit. ⚠️ Di HP, request sepanjang itu tetap rawan diputus OS bila
  /// aplikasi di-minimize — layarnya memperingatkan user soal ini.
  static const _timeoutExploded = Duration(minutes: 20);

  static Future<String> _token() async {
    final t = await AuthStorage.getToken();
    if (t == null) throw ApiException(401, 'Belum login');
    return t;
  }

  static Uri _uri(String path, [Map<String, dynamic>? query]) {
    final u = Uri.parse('${AppConfig.apiBaseUrl}$path');
    if (query == null || query.isEmpty) return u;
    final q = <String, String>{};
    query.forEach((k, v) {
      if (v != null) q[k] = '$v';
    });
    return u.replace(queryParameters: q);
  }

  /// Ambil pesan error yang bisa dibaca manusia dari body FastAPI.
  /// `detail` bisa berupa string, atau list error validasi Pydantic.
  static String _errorMessage(http.Response r) {
    try {
      final data = jsonDecode(utf8.decode(r.bodyBytes));
      final detail = data is Map ? data['detail'] : null;
      if (detail is String && detail.trim().isNotEmpty) return detail;
      if (detail is List) {
        final msgs = detail
            .map((d) => (d is Map ? d['msg'] : null)?.toString())
            .whereType<String>()
            .where((s) => s.isNotEmpty);
        if (msgs.isNotEmpty) return msgs.join(', ');
      }
    } catch (_) {
      /* body bukan JSON — pakai pesan default di bawah */
    }
    return 'HTTP ${r.statusCode}';
  }

  /// Terjemahkan response gagal jadi ApiException. 401 juga membuang token
  /// supaya aplikasi tidak terus memakai sesi yang sudah mati.
  static Future<Never> _throw(http.Response r) async {
    final msg = _errorMessage(r);
    if (r.statusCode == 401) {
      await AuthStorage.clearToken();
      // Pesan dari server lebih informatif (mis. "dipakai di perangkat lain"),
      // jadi pakai itu bila ada; kalau tidak, jelaskan secara umum.
      throw ApiException(
        401,
        msg.startsWith('HTTP ') ? 'Sesi habis. Login ulang.' : msg,
      );
    }
    throw ApiException(r.statusCode, msg);
  }

  static Future<dynamic> _decode(http.Response r) async {
    if (r.statusCode < 200 || r.statusCode >= 300) await _throw(r);
    if (r.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  static Map<String, dynamic> _obj(dynamic v) =>
      (v as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

  // ── Verb ────────────────────────────────────────────────────────────

  static Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    Duration? timeout,
  }) async {
    final token = await _token();
    final r = await http
        .get(_uri(path, query), headers: {'Authorization': 'Bearer $token'})
        .timeout(timeout ?? _timeout);
    return _decode(r);
  }

  static Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Duration? timeout,
  }) async {
    final token = await _token();
    final r = await http
        .post(
          _uri(path, query),
          headers: {
            'Authorization': 'Bearer $token',
            if (body != null) 'Content-Type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(timeout ?? _timeout);
    return _decode(r);
  }

  static Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final token = await _token();
    final r = await http
        .put(
          _uri(path, query),
          headers: {
            'Authorization': 'Bearer $token',
            if (body != null) 'Content-Type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_timeout);
    return _decode(r);
  }

  static Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final token = await _token();
    final r = await http
        .patch(
          _uri(path, query),
          headers: {
            'Authorization': 'Bearer $token',
            if (body != null) 'Content-Type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_timeout);
    return _decode(r);
  }

  static Future<dynamic> delete(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final token = await _token();
    final r = await http
        .delete(_uri(path, query), headers: {'Authorization': 'Bearer $token'})
        .timeout(_timeout);
    return _decode(r);
  }

  /// Unduh biner (Excel / PNG). Padanan `res.blob()` di web.
  static Future<Uint8List> bytes(
    String path, {
    Map<String, dynamic>? query,
    Duration? timeout,
  }) async {
    final token = await _token();
    final r = await http
        .get(_uri(path, query), headers: {'Authorization': 'Bearer $token'})
        .timeout(timeout ?? _timeoutLong);
    if (r.statusCode < 200 || r.statusCode >= 300) await _throw(r);
    return r.bodyBytes;
  }

  static Future<Uint8List> postBytes(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Duration? timeout,
  }) async {
    final token = await _token();
    final r = await http
        .post(
          _uri(path, query),
          headers: {
            'Authorization': 'Bearer $token',
            if (body != null) 'Content-Type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(timeout ?? _timeoutLong);
    if (r.statusCode < 200 || r.statusCode >= 300) await _throw(r);
    return r.bodyBytes;
  }

  /// Unggah multipart. [files] = daftar (field, bytes, filename).
  /// [expectBytes] true → kembalikan biner (mis. endpoint yang membalas Excel).
  static Future<dynamic> multipart(
    String path, {
    required List<({String field, Uint8List bytes, String filename})> files,
    Map<String, String> fields = const {},
    Map<String, dynamic>? query,
    String method = 'POST',
    bool expectBytes = false,
    Duration? timeout,
  }) async {
    final token = await _token();
    final req = http.MultipartRequest(method, _uri(path, query))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields.addAll(fields);
    for (final f in files) {
      req.files.add(
        http.MultipartFile.fromBytes(f.field, f.bytes, filename: f.filename),
      );
    }
    final streamed = await req.send().timeout(timeout ?? _timeoutLong);
    final r = await http.Response.fromStream(streamed);
    if (r.statusCode < 200 || r.statusCode >= 300) await _throw(r);
    if (expectBytes) return r.bodyBytes;
    if (r.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }
}

// ══════════════════════════════════════════════════════════════════════
// ApiService
// ══════════════════════════════════════════════════════════════════════

class ApiService {
  // ────────────────────────────────────────────────────────────────────
  // Auth
  // ────────────────────────────────────────────────────────────────────

  /// Login. Menyimpan JWT ke AuthStorage dan mengembalikan tokennya.
  static Future<String> login(String username, String password) async {
    final r = await http
        .post(
          _Api._uri('/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(_Api._timeout);

    if (r.statusCode < 200 || r.statusCode >= 300) {
      // Jangan pakai _throw: 401 di sini berarti "password salah", bukan
      // "sesi habis" — dan tidak ada token untuk dibuang.
      throw ApiException(r.statusCode, _Api._errorMessage(r));
    }

    final data = TokenResponse.fromJson(_Api._obj(jsonDecode(r.body)));
    await AuthStorage.saveToken(data.accessToken);
    return data.accessToken;
  }

  /// Login yang mengembalikan token + profil user sekaligus.
  static Future<TokenResponse> loginFull(String username, String password) async {
    final r = await http
        .post(
          _Api._uri('/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(_Api._timeout);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(r.statusCode, _Api._errorMessage(r));
    }
    final data = TokenResponse.fromJson(_Api._obj(jsonDecode(r.body)));
    await AuthStorage.saveToken(data.accessToken);
    return data;
  }

  /// Info user yang sedang login (bentuk peta — dipakai layar lama).
  static Future<Map<String, dynamic>> me() async =>
      _Api._obj(await _Api.get('/api/auth/me'));

  static Future<UserOut> getMe() async =>
      UserOut.fromJson(_Api._obj(await _Api.get('/api/auth/me')));

  /// Izin efektif user (bentuk peta — dipakai drawer lama).
  static Future<Map<String, dynamic>> permissions() async =>
      _Api._obj(await _Api.get('/api/auth/permissions'));

  static Future<MyPermissions> getMyPermissions() async =>
      MyPermissions.fromJson(_Api._obj(await _Api.get('/api/auth/permissions')));

  /// Metadata aplikasi: versi APK terbaru (notifikasi update) + config
  /// server-driven. Endpoint publik `/api/app/meta`.
  static Future<AppMeta> appMeta() async =>
      AppMeta.fromJson(_Api._obj(await _Api.get('/api/app/meta')));

  // ────────────────────────────────────────────────────────────────────
  // Gambar part
  // ────────────────────────────────────────────────────────────────────

  /// URL gambar yang aman dipakai klien.
  ///
  /// Foto SIMS disajikan lewat http:// tanpa header CORS — gagal dimuat di
  /// Flutter Web dan diblokir mixed-content di halaman HTTPS / iOS ATS. Proxy
  /// backend menyajikannya ulang lewat origin backend. Skema `learned://`
  /// adalah foto galeri belajar (Cari by Foto) yang hanya ada di backend.
  static String partImageUrl(String url) {
    if (url.startsWith('http://')) {
      return '${AppConfig.apiBaseUrl}/api/parts/image-proxy'
          '?url=${Uri.encodeComponent(url)}';
    }
    if (url.startsWith('learned://')) {
      final id = url.substring('learned://'.length);
      return '${AppConfig.apiBaseUrl}/api/parts/learned-photo/'
          '${Uri.encodeComponent(id)}';
    }
    return url;
  }

  // ────────────────────────────────────────────────────────────────────
  // Pencarian part
  // ────────────────────────────────────────────────────────────────────

  /// Cari part (bentuk peta, auto-paginasi sampai `limit`) — dipakai layar lama.
  static Future<List<Map<String, dynamic>>> searchPart({
    required String query,
    required bool byName,
    int limit = 50,
  }) async {
    const maxPageSize = 200;
    final pageSize = limit < maxPageSize ? limit : maxPageSize;
    final collected = <Map<String, dynamic>>[];
    var page = 1;
    var totalPages = 1;

    do {
      final res = await searchParts(
        query,
        byName: byName,
        page: page,
        pageSize: pageSize,
      );
      collected.addAll(res.results.map((e) => e.toMap()));
      totalPages = res.totalPages;
      page++;
    } while (page <= totalPages && collected.length < limit);

    return collected.length > limit ? collected.sublist(0, limit) : collected;
  }

  /// Cari part — satu halaman, hasil bertipe.
  static Future<SearchResponse> searchParts(
    String q, {
    bool byName = false,
    int page = 1,
    int pageSize = 20,
  }) async {
    final path = byName ? 'search-name' : 'search';
    final data = await _Api.get(
      '/api/parts/$path',
      query: {'q': q, 'page': page, 'page_size': pageSize},
    );
    return SearchResponse.fromJson(_Api._obj(data));
  }

  /// Cari part via FOTO (bentuk peta) — dipakai layar Cari by Foto yang ada.
  static Future<List<Map<String, dynamic>>> searchByImage({
    required Uint8List bytes,
    String filename = 'upload.jpg',
    int topK = 10,
    double threshold = 0.5,
  }) async {
    final res = await searchImage(
      bytes: bytes,
      filename: filename,
      topK: topK,
      threshold: threshold,
    );
    return res.results
        .map((m) => {
              'part_number': m.partNumber,
              'part_name': m.partName,
              'sims_url': m.simsUrl,
              'photo_url': m.simsUrl,
              'similarity': m.similarity,
              'match_percent': m.matchPercent,
              'stok': m.stok,
              'harga': m.harga,
              'tersedia': m.tersedia,
            })
        .toList();
  }

  /// Cari part via FOTO — hasil bertipe (termasuk info galeri & pesan).
  static Future<ImageSearchResponse> searchImage({
    required Uint8List bytes,
    String filename = 'upload.jpg',
    int topK = 12,
    double threshold = 0.3,
    bool useTta = true,
  }) async {
    final data = await _Api.multipart(
      '/api/parts/search-image',
      files: [(field: 'file', bytes: bytes, filename: filename)],
      query: {'top_k': topK, 'threshold': threshold, 'use_tta': useTta},
    );
    return ImageSearchResponse.fromJson(_Api._obj(data));
  }

  /// GALERI BELAJAR (admin): konfirmasi "foto ini = PN X". Foto diindeks ke
  /// galeri sehingga pencarian foto lapangan serupa berikutnya makin akurat.
  static Future<ImageLearnResponse> learnImageMatch({
    required Uint8List bytes,
    required String pn,
    String filename = 'upload.jpg',
  }) async {
    final data = await _Api.multipart(
      '/api/parts/search-image/learn',
      files: [(field: 'file', bytes: bytes, filename: filename)],
      fields: {'pn': pn},
    );
    return ImageLearnResponse.fromJson(_Api._obj(data));
  }

  /// Bandingkan 2 part (interchange) via foto SIMS + kemiripan nama.
  static Future<CompareResponse> compareParts(String pn1, String pn2) async {
    final data = await _Api.get(
      '/api/parts/compare',
      query: {'pn1': pn1, 'pn2': pn2},
      timeout: _Api._timeoutLong,
    );
    return CompareResponse.fromJson(_Api._obj(data));
  }

  /// Daftar URL foto SIMS untuk satu PN (bentuk list — dipakai layar lama).
  static Future<List<String>> getPartPhotos(String partNumber) async {
    final res = await partPhotos(partNumber);
    return res.photos;
  }

  static Future<PartPhotos> partPhotos(String pn) async {
    final data = await _Api.get('/api/parts/photos', query: {'pn': pn});
    return PartPhotos.fromJson(_Api._obj(data));
  }

  /// Spesifikasi fisik resmi SIMS (berat & dimensi) — dasar hitung ongkir.
  static Future<PartSpecResponse> partSpec(String pn) async {
    final data = await _Api.get('/api/parts/spec', query: {'pn': pn});
    return PartSpecResponse.fromJson(_Api._obj(data));
  }

  /// Exploded view sebuah PN TANPA nomor rangka (jalur global EPC).
  ///
  /// ⚠️ LAMBAT: panggilan pertama 10-60 dtk (pernah 105 dtk) karena PN umum
  /// dipakai belasan ribu model; server men-cache 24 jam. Karena itu pakai
  /// `_timeoutLong` (180 dtk) dan JANGAN dipanggil saat layar dibuka — hanya
  /// saat user menekan tombol.
  static Future<PartExplodedFigure> partExplodedFigure(String pn) async {
    final data = await _Api.get('/api/parts/exploded-figure',
        query: {'pn': pn}, timeout: _Api._timeoutLong);
    return PartExplodedFigure.fromJson(_Api._obj(data));
  }

  /// Stok live satu part dari Accurate, termasuk rincian per gudang.
  static Future<AccurateStock> accurateStock(String pn) async {
    final data = await _Api.get('/api/parts/accurate-stock', query: {'pn': pn});
    return AccurateStock.fromJson(_Api._obj(data));
  }

  /// "Cocok di unit saya?" — verifikasi part terhadap BOM EPC unit pembeli.
  static Future<CekUnitResult> cekPartDiUnit({
    required String partNumber,
    required String rangka,
  }) async {
    final data = await _Api.post(
      '/api/parts/cek-unit',
      body: {'part_number': partNumber, 'rangka': rangka},
      timeout: _Api._timeoutLong,
    );
    return CekUnitResult.fromJson(_Api._obj(data));
  }

  /// PNG exploded view untuk fitur cek-unit. Endpoint ini terpisah dari
  /// `/api/ai/excel/{id}` yang digembok izin menu Asisten AI.
  static Future<Uint8List> partExploded(String id) =>
      _Api.bytes('/api/parts/exploded/${Uri.encodeComponent(id)}');

  // ── Batch download (katalog Excel) ──────────────────────────────────

  static Future<Uint8List> batchTemplate() =>
      _Api.bytes('/api/parts/batch-template');

  /// Susun katalog Excel untuk banyak PN sekaligus. Isi [text] (PN dipisah
  /// baris/koma) ATAU [file]; [columns] memilih kolom yang ikut diekspor.
  static Future<Uint8List> buildBatchCatalog({
    String text = '',
    ({Uint8List bytes, String filename})? file,
    List<String> columns = const [],
  }) async {
    return await _Api.multipart(
      '/api/parts/batch-catalog',
      files: file == null
          ? const []
          : [(field: 'file', bytes: file.bytes, filename: file.filename)],
      fields: {
        if (file == null) 'text': text,
        if (columns.isNotEmpty) 'columns': columns.join(','),
      },
      expectBytes: true,
      // Kolom exploded: 94 dtk/PN dingin, cap 25 PN, 3 pekerja paralel → bisa
      // 15 menit. `_timeoutLong` (180 dtk) jauh tak cukup untuk itu.
      timeout: columns.contains('exploded')
          ? _Api._timeoutExploded
          : _Api._timeoutLong,
    ) as Uint8List;
  }

  // ────────────────────────────────────────────────────────────────────
  // Harga
  // ────────────────────────────────────────────────────────────────────

  static Future<HargaListResponse> hargaList({
    String q = '',
    String sort = 'pn',
    int page = 1,
    int pageSize = 50,
  }) async {
    final data = await _Api.get(
      '/api/harga/list',
      query: {'q': q, 'sort': sort, 'page': page, 'page_size': pageSize},
    );
    return HargaListResponse.fromJson(_Api._obj(data));
  }

  static Future<Uint8List> hargaListExport({
    String q = '',
    String sort = 'pn',
  }) =>
      _Api.bytes('/api/harga/list/export', query: {'q': q, 'sort': sort});

  /// Cari harga satu PN. [refresh] memaksa ambil ulang dari sumber.
  static Future<CariHargaResult> cariHarga(String pn, {bool refresh = false}) async {
    final data = await _Api.get(
      '/api/harga/cari',
      query: {'pn': pn, 'refresh': refresh},
      timeout: _Api._timeoutLong,
    );
    return CariHargaResult.fromJson(_Api._obj(data));
  }

  /// Harga untuk banyak PN sekaligus ([text] = PN dipisah baris/koma).
  static Future<BatchHargaResponse> batchHarga(String text) async {
    final data = await _Api.post(
      '/api/harga/batch',
      body: {'text': text},
      timeout: _Api._timeoutLong,
    );
    return BatchHargaResponse.fromJson(_Api._obj(data));
  }

  static Future<Uint8List> batchHargaExport(
    double rate,
    List<BatchHargaRow> rows,
  ) =>
      _Api.postBytes(
        '/api/harga/batch/export',
        body: {'rate': rate, 'rows': rows.map((r) => r.toJson()).toList()},
      );

  // ────────────────────────────────────────────────────────────────────
  // Stok (indeks Accurate)
  // ────────────────────────────────────────────────────────────────────

  static Future<StokListResponse> stokList({
    String q = '',
    String sort = 'pn',
    int page = 1,
    int pageSize = 50,
  }) async {
    final data = await _Api.get(
      '/api/stok/list',
      query: {'q': q, 'sort': sort, 'page': page, 'page_size': pageSize},
    );
    return StokListResponse.fromJson(_Api._obj(data));
  }

  static Future<Uint8List> stokListExport({
    String q = '',
    String sort = 'pn',
  }) =>
      _Api.bytes('/api/stok/list/export', query: {'q': q, 'sort': sort});

  // ────────────────────────────────────────────────────────────────────
  // Populasi unit
  // ────────────────────────────────────────────────────────────────────

  static Future<PopulasiResponse> populasi({
    String q = '',
    Map<String, String> filters = const {},
    int page = 1,
    int pageSize = 50,
    String? sort,
    String dir = 'asc',
  }) async {
    final data = await _Api.get(
      '/api/populasi',
      query: {
        'q': q,
        'page': page,
        'page_size': pageSize,
        if (filters.isNotEmpty) 'filters': jsonEncode(filters),
        if (sort != null && sort.isNotEmpty) 'sort': sort,
        if (sort != null && sort.isNotEmpty) 'dir': dir,
      },
    );
    return PopulasiResponse.fromJson(_Api._obj(data));
  }

  /// Nilai satu kolom untuk seluruh baris yang cocok filter — dipakai untuk
  /// menyalin daftar nomor rangka. [kolom] kosong = kolom nomor rangka.
  static Future<({String? kolom, int jumlah, List<String> values})> populasiKolom({
    String q = '',
    Map<String, String> filters = const {},
    String? sort,
    String dir = 'asc',
    String kolom = '',
  }) async {
    final data = _Api._obj(await _Api.get(
      '/api/populasi/kolom',
      query: {
        'q': q,
        if (filters.isNotEmpty) 'filters': jsonEncode(filters),
        if (sort != null && sort.isNotEmpty) 'sort': sort,
        if (sort != null && sort.isNotEmpty) 'dir': dir,
        if (kolom.isNotEmpty) 'kolom': kolom,
      },
    ));
    return (
      kolom: data['kolom']?.toString(),
      jumlah: (data['jumlah'] as num?)?.toInt() ?? 0,
      values: (data['values'] as List?)?.map((e) => '$e').toList() ?? const [],
    );
  }

  static Future<Uint8List> populasiExport({
    String q = '',
    Map<String, String> filters = const {},
  }) =>
      _Api.bytes('/api/populasi/export', query: {
        'q': q,
        if (filters.isNotEmpty) 'filters': jsonEncode(filters),
      });

  // ────────────────────────────────────────────────────────────────────
  // Repair kit transmisi
  // ────────────────────────────────────────────────────────────────────

  static Future<({bool available, List<RepairKitModel> models})> repairKitModels() async {
    final data = _Api._obj(await _Api.get('/api/repairkit/transmisi'));
    return (
      available: data['available'] == true,
      models: (data['models'] as List?)
              ?.whereType<Map>()
              .map((e) => RepairKitModel.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <RepairKitModel>[],
    );
  }

  /// Excel repair kit transmisi. [model] kosong = semua model.
  static Future<Uint8List> repairKitExport({String model = ''}) =>
      _Api.bytes('/api/repairkit/transmisi/export', query: {'model': model});

  // ────────────────────────────────────────────────────────────────────
  // Pembeli: lokasi & etalase toko
  // ────────────────────────────────────────────────────────────────────

  static Future<List<BuyerLocation>> buyerLocations() async {
    final data = _Api._obj(await _Api.get('/api/buyer/locations'));
    return (data['locations'] as List?)
            ?.whereType<Map>()
            .map((e) => BuyerLocation.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  static Future<({String? key, String? label})> buyerLocation() async {
    final data = _Api._obj(await _Api.get('/api/buyer/location'));
    return (key: data['key']?.toString(), label: data['label']?.toString());
  }

  static Future<({String key, String label})> setBuyerLocation(String key) async {
    final data = _Api._obj(
      await _Api.post('/api/buyer/location', body: {'key': key}),
    );
    return (
      key: data['key']?.toString() ?? key,
      label: data['label']?.toString() ?? '',
    );
  }

  /// Beranda toko: kategori, produk terlaris & unggulan untuk lokasi pembeli.
  static Future<TokoHome> tokoHome() async =>
      TokoHome.fromJson(_Api._obj(await _Api.get('/api/buyer/home')));

  /// Etalase toko dengan filter. [ready] true = hanya yang stoknya siap kirim.
  static Future<TokoCatalog> tokoCatalog({
    String q = '',
    String kategori = '',
    String sort = 'relevan',
    bool ready = false,
    int page = 1,
    int pageSize = 24,
  }) async {
    final data = await _Api.get(
      '/api/buyer/catalog',
      query: {
        'q': q,
        'kategori': kategori,
        'sort': sort,
        'ready': ready,
        'page': page,
        'page_size': pageSize,
      },
    );
    return TokoCatalog.fromJson(_Api._obj(data));
  }

  // ────────────────────────────────────────────────────────────────────
  // Keranjang, ongkir & lokasi
  // ────────────────────────────────────────────────────────────────────

  /// Keadaan terkini tiap item keranjang menurut SERVER: gudang pengirim,
  /// harga yang akan ditagih, berat, dan boleh-tidaknya dibeli.
  ///
  /// Keranjang di perangkat menyimpan harga saat part dimasukkan — bisa basi —
  /// jadi layar keranjang WAJIB menyegarkan dirinya dari sini sebelum checkout.
  static Future<CartGudang> cartGudang(List<CartLine> items) async {
    final data = await _Api.post(
      '/api/cart/gudang',
      body: {'items': items.map((e) => e.toJson()).toList()},
    );
    return CartGudang.fromJson(_Api._obj(data));
  }

  /// Berat tertagih keranjang = max(berat asli, berat volumetrik) dari dimensi
  /// SIMS. Dihitung server supaya sama persis dengan yang dipakai saat order.
  static Future<CartWeight> cartWeight(List<CartLine> items) async {
    final data = await _Api.post(
      '/api/shipping/weight',
      body: {'items': items.map((e) => e.toJson()).toList()},
    );
    return CartWeight.fromJson(_Api._obj(data));
  }

  /// Tarif ongkir. Item keranjang ikut dikirim supaya server menghitung dari
  /// gudang PEMENUH (bukan sekadar gudang pilihan pembeli) — dengan begitu
  /// ongkir yang dipratinjau sama dengan ongkir saat order dibuat.
  static Future<ShippingRates> shippingRates({
    required int weightGrams,
    double value = 0,
    String destPostal = '',
    List<CartLine> items = const [],
  }) async {
    final data = await _Api.post(
      '/api/shipping/rates',
      body: {
        'weight_grams': weightGrams,
        'value': value,
        'dest_postal': destPostal,
        'items': items.map((e) => e.toJson()).toList(),
      },
      timeout: _Api._timeoutLong,
    );
    return ShippingRates.fromJson(_Api._obj(data));
  }

  /// Alamat dari koordinat (untuk pin peta).
  static Future<GeoPlace> geoReverse(double lat, double lon) async {
    final data = await _Api.get(
      '/api/geo/reverse',
      query: {'lat': lat, 'lon': lon},
    );
    return GeoPlace.fromJson(_Api._obj(data));
  }

  /// Cari alamat berdasarkan teks.
  static Future<List<GeoPlace>> geoSearch(String q) async {
    final data = _Api._obj(await _Api.get('/api/geo/search', query: {'q': q}));
    return (data['results'] as List?)
            ?.whereType<Map>()
            .map((e) => GeoPlace.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  // ────────────────────────────────────────────────────────────────────
  // Pesanan & pembayaran (pembeli)
  // ────────────────────────────────────────────────────────────────────

  static Future<PaymentMethods> paymentMethods() async =>
      PaymentMethods.fromJson(_Api._obj(await _Api.get('/api/payments/methods')));

  /// Perjalanan paket dari kurir untuk resi yang diisi admin cabang.
  /// ⛔ BUKAN pemesanan pengiriman. Backend men-cache 10 menit, jadi aman
  /// dipanggil tiap layar dibuka.
  static Future<TrackingResult> orderTracking(String code) async {
    final data = await _Api.get(
      '/api/orders/${Uri.encodeComponent(code)}/tracking',
    );
    return TrackingResult.fromJson(_Api._obj(data));
  }

  /// Status pembayaran satu order — dipakai untuk polling setelah user
  /// menyelesaikan Snap Midtrans.
  static Future<PaymentStatus> paymentStatus(String code) async {
    final data = await _Api.get(
      '/api/orders/${Uri.encodeComponent(code)}/payment/status',
    );
    return PaymentStatus.fromJson(_Api._obj(data));
  }

  /// Buat pesanan. INGAT: satu pesanan = satu gudang. Keranjang yang barangnya
  /// tersebar di beberapa gudang harus dipesan bergantian per gudang.
  static Future<CreatedOrder> createOrder({
    required List<CartLine> items,
    String? note,
    String? courier,
    String? courierService,
    double? shippingCost,
    int? weightGrams,
    String? paymentMethod,
    String? paymentChannel,
    String? recipientName,
    String? recipientPhone,
    String? recipientAddress,
    String? recipientPostal,
  }) async {
    final data = await _Api.post(
      '/api/orders',
      body: {
        'items': items.map((e) => e.toJson()).toList(),
        'note': ?note,
        'courier': ?courier,
        'courier_service': ?courierService,
        'shipping_cost': ?shippingCost,
        'weight_grams': ?weightGrams,
        'payment_method': ?paymentMethod,
        'payment_channel': ?paymentChannel,
        'recipient_name': ?recipientName,
        'recipient_phone': ?recipientPhone,
        'recipient_address': ?recipientAddress,
        'recipient_postal': ?recipientPostal,
      },
      timeout: _Api._timeoutLong,
    );
    return CreatedOrder.fromJson(_Api._obj(data));
  }

  static Future<List<OrderSummary>> myOrders() async {
    final data = _Api._obj(await _Api.get('/api/orders'));
    return (data['orders'] as List?)
            ?.whereType<Map>()
            .map((e) => OrderSummary.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  static Future<OrderDetail> order(String code) async {
    final data = await _Api.get('/api/orders/${Uri.encodeComponent(code)}');
    return OrderDetail.fromJson(_Api._obj(data));
  }

  /// Pembeli mengonfirmasi barang sudah diterima.
  static Future<void> confirmOrder(String code) =>
      _Api.post('/api/orders/${Uri.encodeComponent(code)}/confirm');

  static Future<void> cancelOrder(String code) =>
      _Api.post('/api/orders/${Uri.encodeComponent(code)}/cancel');

  /// Unggah bukti transfer manual.
  static Future<String> uploadProof(
    String code, {
    required Uint8List bytes,
    String filename = 'bukti.jpg',
  }) async {
    final data = _Api._obj(await _Api.multipart(
      '/api/orders/${Uri.encodeComponent(code)}/proof',
      files: [(field: 'file', bytes: bytes, filename: filename)],
    ));
    return data['url']?.toString() ?? '';
  }

  // ────────────────────────────────────────────────────────────────────
  // Chat pesanan & pra-pesanan
  // ────────────────────────────────────────────────────────────────────

  static Future<OrderChatThread> orderChat(String code) async {
    final data = await _Api.get('/api/orders/${Uri.encodeComponent(code)}/chat');
    return OrderChatThread.fromJson(_Api._obj(data));
  }

  static Future<void> sendOrderChat(String code, String body) => _Api.post(
        '/api/orders/${Uri.encodeComponent(code)}/chat',
        body: {'body': body},
      );

  /// Percakapan pra-pesanan pembeli dengan tiap gudang.
  static Future<List<BuyerChatThread>> buyerChatThreads() async {
    final data = _Api._obj(await _Api.get('/api/chat/buyer/threads'));
    return (data['threads'] as List?)
            ?.whereType<Map>()
            .map((e) => BuyerChatThread.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  static Future<List<ChatMessage>> buyerGudangChat(String key) async {
    final data = _Api._obj(
      await _Api.get('/api/chat/gudang/${Uri.encodeComponent(key)}'),
    );
    return (data['messages'] as List?)
            ?.whereType<Map>()
            .map((e) => ChatMessage.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  static Future<void> sendBuyerGudangChat(String key, String body) => _Api.post(
        '/api/chat/gudang/${Uri.encodeComponent(key)}',
        body: {'body': body},
      );

  /// Sisi cabang: daftar pembeli yang mengirim pesan.
  static Future<List<ChatThreadSummary>> branchChatThreads() async {
    final data = _Api._obj(await _Api.get('/api/chat/branch/threads'));
    return (data['threads'] as List?)
            ?.whereType<Map>()
            .map((e) => ChatThreadSummary.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  static Future<List<ChatMessage>> branchChat(String buyer) async {
    final data = _Api._obj(
      await _Api.get('/api/chat/branch/${Uri.encodeComponent(buyer)}'),
    );
    return (data['messages'] as List?)
            ?.whereType<Map>()
            .map((e) => ChatMessage.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  static Future<void> sendBranchChat(String buyer, String body) => _Api.post(
        '/api/chat/branch/${Uri.encodeComponent(buyer)}',
        body: {'body': body},
      );

  // ────────────────────────────────────────────────────────────────────
  // Cabang: pesanan masuk & penjualan
  // ────────────────────────────────────────────────────────────────────

  static Future<({String branch, List<OrderSummary> orders})> branchOrders() async {
    final data = _Api._obj(await _Api.get('/api/branch/orders'));
    return (
      branch: data['branch']?.toString() ?? '',
      orders: (data['orders'] as List?)
              ?.whereType<Map>()
              .map((e) => OrderSummary.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <OrderSummary>[],
    );
  }

  /// Jumlah pesanan masuk — untuk lencana notifikasi di drawer.
  static Future<int> branchOrdersCount() async {
    final data = _Api._obj(await _Api.get('/api/branch/orders/count'));
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  static Future<OrderDetail> branchOrder(String code) async {
    final data = await _Api.get('/api/branch/orders/${Uri.encodeComponent(code)}');
    return OrderDetail.fromJson(_Api._obj(data));
  }

  static Future<void> setBranchOrderStatus(
    String code,
    String status, {
    String? trackingNo,
  }) =>
      _Api.put(
        '/api/branch/orders/${Uri.encodeComponent(code)}/status',
        body: {'status': status, 'tracking_no': ?trackingNo},
      );

  static Future<SalesRecap> branchSales() async =>
      SalesRecap.fromJson(_Api._obj(await _Api.get('/api/branch/sales')));

  // ────────────────────────────────────────────────────────────────────
  // Admin: pesanan & penjualan
  // ────────────────────────────────────────────────────────────────────

  static Future<List<OrderSummary>> adminOrders() async {
    final data = _Api._obj(await _Api.get('/api/admin/orders'));
    return (data['orders'] as List?)
            ?.whereType<Map>()
            .map((e) => OrderSummary.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  static Future<OrderDetail> adminOrder(String code) async {
    final data = await _Api.get('/api/admin/orders/${Uri.encodeComponent(code)}');
    return OrderDetail.fromJson(_Api._obj(data));
  }

  static Future<void> setOrderStatus(String code, String status) => _Api.put(
        '/api/admin/orders/${Uri.encodeComponent(code)}/status',
        body: {'status': status},
      );

  static Future<SalesRecap> salesRecap() async =>
      SalesRecap.fromJson(_Api._obj(await _Api.get('/api/admin/sales')));

  // ────────────────────────────────────────────────────────────────────
  // Admin: user & izin
  // ────────────────────────────────────────────────────────────────────

  static Future<List<AdminUser>> listUsers() async {
    final data = _Api._obj(await _Api.get('/api/admin/users'));
    return (data['users'] as List?)
            ?.whereType<Map>()
            .map((e) => AdminUser.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  static Future<void> createUser({
    required String username,
    required String password,
    required String role,
  }) =>
      _Api.post('/api/admin/users', body: {
        'username': username,
        'password': password,
        'role': role,
      });

  static Future<void> updateUser(
    String username, {
    String? role,
    String? password,
    bool? isActive,
  }) =>
      _Api.put('/api/admin/users/${Uri.encodeComponent(username)}', body: {
        'role': ?role,
        'password': ?password,
        'is_active': ?isActive,
      });

  static Future<void> deleteUser(String username) =>
      _Api.delete('/api/admin/users/${Uri.encodeComponent(username)}');

  /// Semua izin jenis [kind] beserta daftar user — sumber layar Menu Control.
  static Future<PermOverview> permOverview(PermKind kind) async {
    final data = await _Api.get('/api/admin/perms/${kind.path}');
    return PermOverview.fromJson(_Api._obj(data));
  }

  static Future<void> setPerm(
    PermKind kind,
    String username,
    List<String> keys,
  ) =>
      _Api.put('/api/admin/perms/${kind.path}',
          body: {'username': username, 'keys': keys});

  /// Kembalikan izin user ke default (hapus override).
  static Future<void> resetPerm(PermKind kind, String username) => _Api.delete(
        '/api/admin/perms/${kind.path}/${Uri.encodeComponent(username)}',
      );

  // ────────────────────────────────────────────────────────────────────
  // Admin: monitoring
  // ────────────────────────────────────────────────────────────────────

  static Future<MonitoringData> monitoring() async =>
      MonitoringData.fromJson(_Api._obj(await _Api.get('/api/admin/monitoring')));

  /// Riwayat login mentah. [username] kosong = semua user.
  static Future<({int jumlah, List<LoginHistoryRow> riwayat})> loginHistory({
    String username = '',
    int limit = 200,
  }) async {
    final data = _Api._obj(await _Api.get(
      '/api/admin/monitoring/login-history',
      query: {'limit': limit, if (username.isNotEmpty) 'username': username},
    ));
    return (
      jumlah: (data['jumlah'] as num?)?.toInt() ?? 0,
      riwayat: (data['riwayat'] as List?)
              ?.whereType<Map>()
              .map((e) => LoginHistoryRow.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <LoginHistoryRow>[],
    );
  }

  /// DDL tabel `login_history` — ditampilkan bila tabelnya belum dibuat.
  static Future<String> monitoringSql() async {
    final data = _Api._obj(await _Api.get('/api/admin/monitoring/sql'));
    return data['sql']?.toString() ?? '';
  }

  // ────────────────────────────────────────────────────────────────────
  // Admin: upload dataset & katalog
  // ────────────────────────────────────────────────────────────────────

  /// [kind] = 'stok' | 'harga' | 'populasi'.
  static Future<({bool ok, int size})> uploadDataset({
    required String kind,
    required Uint8List bytes,
    required String filename,
  }) async {
    final data = _Api._obj(await _Api.multipart(
      '/api/admin/upload/$kind',
      files: [(field: 'file', bytes: bytes, filename: filename)],
    ));
    return (
      ok: data['ok'] == true,
      size: (data['size'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<List<String>> catalogFolders() async {
    final data = _Api._obj(await _Api.get('/api/admin/catalog/folders'));
    return (data['folders'] as List?)?.map((e) => '$e').toList() ?? const [];
  }

  /// Unggah file katalog Excel per unit ke folder [subdir].
  static Future<CatalogUploadResult> uploadCatalog({
    required String subdir,
    required List<({Uint8List bytes, String filename})> files,
  }) async {
    final data = await _Api.multipart(
      '/api/admin/upload-catalog',
      files: [
        for (final f in files)
          (field: 'files', bytes: f.bytes, filename: f.filename),
      ],
      fields: {'subdir': subdir},
    );
    return CatalogUploadResult.fromJson(_Api._obj(data));
  }

  // ────────────────────────────────────────────────────────────────────
  // Admin: foto part
  // ────────────────────────────────────────────────────────────────────

  static Future<List<AdminPhoto>> adminPhotos(String pn) async {
    final data = _Api._obj(await _Api.get('/api/admin/photos', query: {'pn': pn}));
    return (data['photos'] as List?)
            ?.whereType<Map>()
            .map((e) => AdminPhoto.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  static Future<void> uploadPhoto({
    required String pn,
    required Uint8List bytes,
    required String filename,
  }) =>
      _Api.multipart(
        '/api/admin/photos',
        files: [(field: 'file', bytes: bytes, filename: filename)],
        fields: {'pn': pn},
      );

  static Future<void> deletePhoto(String id) =>
      _Api.delete('/api/admin/photos/${Uri.encodeComponent(id)}');

  // ────────────────────────────────────────────────────────────────────
  // Admin: image index & katalog BOM
  // ────────────────────────────────────────────────────────────────────

  static Future<IndexStatusInfo> indexStatus() async =>
      IndexStatusInfo.fromJson(_Api._obj(await _Api.get('/api/admin/index/status')));

  static Future<ReloadGalleryResult> reloadGallery() async => ReloadGalleryResult.fromJson(
        _Api._obj(await _Api.post('/api/admin/index/reload-gallery')),
      );

  static Future<IndexResult> indexPart(String pn, {bool reindex = false}) async {
    final data = await _Api.post(
      '/api/admin/index',
      body: {'pn': pn, 'reindex': reindex},
      timeout: _Api._timeoutLong,
    );
    return IndexResult.fromJson(_Api._obj(data));
  }

  static Future<({int totalIndexed, List<IndexResult> results})> indexBulk(
    String text, {
    bool reindex = false,
  }) async {
    final data = _Api._obj(await _Api.post(
      '/api/admin/index/bulk',
      body: {'text': text, 'reindex': reindex},
      timeout: _Api._timeoutLong,
    ));
    return (
      totalIndexed: (data['total_indexed'] as num?)?.toInt() ?? 0,
      results: (data['results'] as List?)
              ?.whereType<Map>()
              .map((e) => IndexResult.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <IndexResult>[],
    );
  }

  static Future<CatalogBomStatus> catalogBomStatus() async => CatalogBomStatus.fromJson(
        _Api._obj(await _Api.get('/api/admin/catalog-bom/status')),
      );

  static Future<CatalogBomRebuildResult> rebuildCatalogBom() async =>
      CatalogBomRebuildResult.fromJson(
        _Api._obj(await _Api.post(
          '/api/admin/catalog-bom/rebuild',
          timeout: _Api._timeoutLong,
        )),
      );

  // ────────────────────────────────────────────────────────────────────
  // Admin: pencarian nihil, chat-log, sinonim
  // ────────────────────────────────────────────────────────────────────

  static Future<({int total, int jumlah, List<SearchMiss> misses})> searchMisses() async {
    final data = _Api._obj(await _Api.get('/api/admin/search-misses'));
    return (
      total: (data['total'] as num?)?.toInt() ?? 0,
      jumlah: (data['jumlah'] as num?)?.toInt() ?? 0,
      misses: (data['misses'] as List?)
              ?.whereType<Map>()
              .map((e) => SearchMiss.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <SearchMiss>[],
    );
  }

  static Future<void> resolveSearchMiss(String query) =>
      _Api.post('/api/admin/search-misses/resolve', body: {'query': query});

  static Future<({ChatLogSummary ringkasan, List<ChatLogRow> log})> chatLog({
    int limit = 200,
  }) async {
    final data = _Api._obj(
      await _Api.get('/api/admin/chat-log', query: {'limit': limit}),
    );
    return (
      ringkasan: ChatLogSummary.fromJson(_Api._obj(data['ringkasan'])),
      log: (data['log'] as List?)
              ?.whereType<Map>()
              .map((e) => ChatLogRow.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <ChatLogRow>[],
    );
  }

  /// Hapus log observabilitas. [beforeDays] > 0 = hanya yang lebih tua dari N
  /// hari; null = hapus SEMUA. Mengembalikan jumlah baris terhapus.
  static Future<int> deleteChatLog({int? beforeDays}) async {
    final data = _Api._obj(await _Api.delete(
      '/api/admin/chat-log',
      query: {
        if (beforeDays != null && beforeDays > 0) 'before_days': beforeDays,
      },
    ));
    return (data['dihapus'] as num?)?.toInt() ?? 0;
  }

  // ────────────────────────────────────────────────────────────────────
  // Admin: Pengetahuan Asisten AI
  //
  // Admin menulis/mengunggah pengetahuan internal; server mengindeksnya di
  // latar (statusnya di-polling) lalu asisten memakainya lewat tool
  // `cari_pengetahuan`.
  // ────────────────────────────────────────────────────────────────────

  /// Ekstensi berkas yang diterima server (`pengetahuan_extract.EKSTENSI`).
  static const pengetahuanEkstensi = <String>[
    'pdf', 'xlsx', 'xlsm', 'csv', 'docx', 'txt', 'png', 'jpg', 'jpeg',
  ];

  static Future<({int jumlah, int jumlahChunk, List<PengetahuanDok> dokumen})>
      pengetahuan() async {
    final data = _Api._obj(await _Api.get('/api/admin/pengetahuan'));
    return (
      jumlah: (data['jumlah'] as num?)?.toInt() ?? 0,
      jumlahChunk: (data['jumlah_chunk'] as num?)?.toInt() ?? 0,
      dokumen: (data['dokumen'] as List?)
              ?.whereType<Map>()
              .map((d) => PengetahuanDok.fromJson(d.cast<String, dynamic>()))
              .toList() ??
          const <PengetahuanDok>[],
    );
  }

  static Future<({PengetahuanDok dokumen, List<PengetahuanChunk> chunk})>
      pengetahuanDetail(String id) async {
    final data = _Api._obj(
        await _Api.get('/api/admin/pengetahuan/${Uri.encodeComponent(id)}'));
    return (
      dokumen: PengetahuanDok.fromJson(_Api._obj(data['dokumen'])),
      chunk: (data['chunk'] as List?)
              ?.whereType<Map>()
              .map((c) => PengetahuanChunk.fromJson(c.cast<String, dynamic>()))
              .toList() ??
          const <PengetahuanChunk>[],
    );
  }

  /// Status ringkas untuk polling job indexing. Field selain status/progres
  /// tidak dikirim server — pakai `PengetahuanDok.salinStatus` untuk menempelnya.
  static Future<PengetahuanDok> pengetahuanStatus(String id) async {
    final data = await _Api
        .get('/api/admin/pengetahuan/${Uri.encodeComponent(id)}/status');
    return PengetahuanDok.fromJson(_Api._obj(data));
  }

  /// Tambah pengetahuan (202 + antre indexing). `tag` dipisah koma seperti web.
  static Future<String> addPengetahuan({
    required String judul,
    String deskripsi = '',
    String teks = '',
    List<List<String>> tabel = const [],
    String tag = '',
    bool untukPembeli = false,
    bool pakaiAi = true,
    List<({Uint8List bytes, String filename})> files = const [],
  }) async {
    final data = await _Api.multipart(
      '/api/admin/pengetahuan',
      files: [
        for (final f in files)
          (field: 'files', bytes: f.bytes, filename: f.filename),
      ],
      fields: {
        'judul': judul,
        'deskripsi': deskripsi,
        'teks': teks,
        if (tabel.isNotEmpty) 'tabel_json': jsonEncode(tabel),
        'tag': tag,
        'untuk_pembeli': '$untukPembeli',
        'pakai_ai': '$pakaiAi',
      },
    );
    return '${_Api._obj(data)['id'] ?? ''}';
  }

  static Future<void> reindexPengetahuan(String id) => _Api.post(
      '/api/admin/pengetahuan/${Uri.encodeComponent(id)}/reindex',
      body: const {});

  /// Ubah metadata dokumen. Field null tidak dikirim — backend menolak PATCH
  /// tanpa perubahan sama sekali.
  static Future<PengetahuanDok> updatePengetahuan(
    String id, {
    String? judul,
    String? deskripsi,
    List<String>? tag,
    bool? untukPembeli,
    bool? aktif,
    bool? pakaiAi,
  }) async {
    final data = await _Api.patch(
      '/api/admin/pengetahuan/${Uri.encodeComponent(id)}',
      body: {
        'judul': ?judul,
        'deskripsi': ?deskripsi,
        'tag': ?tag,
        'untuk_pembeli': ?untukPembeli,
        'aktif': ?aktif,
        'pakai_ai': ?pakaiAi,
      },
    );
    return PengetahuanDok.fromJson(_Api._obj(_Api._obj(data)['dokumen']));
  }

  static Future<PengetahuanChunk> updatePengetahuanChunk(
    String dokId,
    String seq, {
    String? judulId,
    List<String>? kataKunci,
    bool? dicari,
  }) async {
    final data = await _Api.patch(
      '/api/admin/pengetahuan/${Uri.encodeComponent(dokId)}'
      '/chunk/${Uri.encodeComponent(seq)}',
      body: {
        'judul_id': ?judulId,
        'kata_kunci': ?kataKunci,
        'dicari': ?dicari,
      },
    );
    return PengetahuanChunk.fromJson(_Api._obj(_Api._obj(data)['chunk']));
  }

  static Future<void> deletePengetahuan(String id) =>
      _Api.delete('/api/admin/pengetahuan/${Uri.encodeComponent(id)}');

  /// Uji pencarian PERSIS seperti yang dilihat asisten.
  static Future<List<PengetahuanChunk>> cariPengetahuan(String q) async {
    final data = _Api._obj(
        await _Api.post('/api/admin/pengetahuan/cari', body: {'q': q}));
    return (data['hasil'] as List?)
            ?.whereType<Map>()
            .map((c) => PengetahuanChunk.fromJson(c.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  static Future<List<SinonimEntry>> sinonim() async {
    final data = _Api._obj(await _Api.get('/api/admin/sinonim'));
    return (data['entries'] as List?)
            ?.whereType<Map>()
            .map((e) => SinonimEntry.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  static Future<void> addSinonim(SinonimEntry entry) =>
      _Api.post('/api/admin/sinonim', body: entry.toJson());

  static Future<void> updateSinonim(int index, SinonimEntry entry) =>
      _Api.put('/api/admin/sinonim/$index', body: entry.toJson());

  static Future<void> deleteSinonim(int index) =>
      _Api.delete('/api/admin/sinonim/$index');

  /// Rute Maksud + daftar nama tool yang SAH (server yang menentukan, supaya
  /// rute tak pernah menunjuk tool yang tidak ada).
  static Future<({List<MaksudEntry> entries, List<String> tools, int maks})>
      maksud() async {
    final data = _Api._obj(await _Api.get('/api/admin/maksud'));
    return (
      entries: (data['entries'] as List?)
              ?.whereType<Map>()
              .map((e) => MaksudEntry.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <MaksudEntry>[],
      tools: (data['tools'] as List?)
              ?.map((t) => '$t')
              .where((t) => t.isNotEmpty)
              .toList() ??
          const <String>[],
      maks: (data['maks'] as num?)?.toInt() ?? 60,
    );
  }

  static Future<void> addMaksud(MaksudEntry entry) =>
      _Api.post('/api/admin/maksud', body: entry.toJson());

  static Future<void> updateMaksud(int index, MaksudEntry entry) =>
      _Api.put('/api/admin/maksud/$index', body: entry.toJson());

  static Future<void> deleteMaksud(int index) =>
      _Api.delete('/api/admin/maksud/$index');

  static Future<List<SinonimUsulan>> sinonimUsulan() async {
    final data = _Api._obj(await _Api.get('/api/admin/sinonim/usulan'));
    return (data['usulan'] as List?)
            ?.whereType<Map>()
            .map((e) => SinonimUsulan.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  /// Minta LLM memetakan istilah lapangan yang gagal dicari → kata kunci
  /// katalog. Hasilnya divalidasi ke katalog nyata di backend.
  static Future<({int dibuat, int autoDisetujui, List<SinonimUsulan> usulan, String? catatan, String? error})>
      generateSinonimUsulan({int limit = 10, bool autoApprove = false}) async {
    final data = _Api._obj(await _Api.post(
      '/api/admin/sinonim/usulan/generate',
      body: {'limit': limit, 'auto_approve': autoApprove},
      timeout: _Api._timeoutLong,
    ));
    return (
      dibuat: (data['dibuat'] as num?)?.toInt() ?? 0,
      autoDisetujui: (data['auto_disetujui'] as num?)?.toInt() ?? 0,
      usulan: (data['usulan'] as List?)
              ?.whereType<Map>()
              .map((e) => SinonimUsulan.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <SinonimUsulan>[],
      catatan: data['catatan']?.toString(),
      error: data['error']?.toString(),
    );
  }

  static Future<void> approveSinonimUsulan(String id) =>
      _Api.post('/api/admin/sinonim/usulan/approve', body: {'id': id});

  static Future<void> rejectSinonimUsulan(String id) =>
      _Api.post('/api/admin/sinonim/usulan/reject', body: {'id': id});

  // ────────────────────────────────────────────────────────────────────
  // Admin: lokasi gudang
  // ────────────────────────────────────────────────────────────────────

  static Future<List<AdminGudang>> adminGudang() async {
    final data = _Api._obj(await _Api.get('/api/admin/gudang'));
    return (data['gudang'] as List?)
            ?.whereType<Map>()
            .map((e) => AdminGudang.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  static Future<void> saveAdminGudang(List<AdminGudang> items) => _Api.put(
        '/api/admin/gudang',
        body: {'items': items.map((e) => e.toJson()).toList()},
      );

  // ────────────────────────────────────────────────────────────────────
  // Rak & Kartu Stok
  // ────────────────────────────────────────────────────────────────────
  //
  // ⚠️ PN bisa mengandung '/' ('WG9525160004/2'). Karena itu SEMUA endpoint di
  // sini memakai bentuk alias yang menaruh PN di segmen TERAKHIR path
  // (`.../gudang/{gudang}/part/{pn}`) — server mendeklarasikannya sebagai
  // `{pn:path}` sehingga garis miringnya ikut terbaca. ⛔ Jangan pindah ke
  // bentuk `/api/rak/part/{pn}/{gudang}`: PN ber-suffix akan memecah rute.

  /// Rak satu part di SEMUA gudang → {label gudang penuh: RakInfo}.
  static Future<Map<String, RakInfo>> rakForPart(String pn) async {
    final data = _Api._obj(
      await _Api.get('/api/rak/part-of/${Uri.encodeComponent(pn)}'),
    );
    final rak = data['rak'];
    if (rak is! Map) return const {};
    return {
      for (final e in rak.entries)
        if (e.value is Map)
          '${e.key}': RakInfo.fromJson((e.value as Map).cast<String, dynamic>()),
    };
  }

  /// Lookup TERBALIK: isi satu gudang. [q] mencari di PN, kode rak & catatan —
  /// staf lebih sering bertanya "rak A-12 isinya apa" daripada mencari PN.
  static Future<List<RakInfo>> rakGudang(String label, {String q = ''}) async {
    final data = _Api._obj(await _Api.get(
      '/api/rak/gudang/${Uri.encodeComponent(label)}',
      query: {if (q.trim().isNotEmpty) 'q': q.trim(), 'limit': 300},
    ));
    return (data['items'] as List?)
            ?.whereType<Map>()
            .map((e) => RakInfo.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  /// Simpan rak (upsert). 403 = gudang ini bukan wewenang user (ApiException).
  static Future<RakInfo> saveRak({
    required String pn,
    required String gudang,
    required String rak,
    String catatan = '',
  }) async {
    final data = _Api._obj(await _Api.put(
      '/api/rak/gudang/${Uri.encodeComponent(gudang)}/part/${Uri.encodeComponent(pn)}',
      body: {'rak': rak, 'catatan': catatan},
    ));
    final row = data['rak'];
    return row is Map
        ? RakInfo.fromJson(row.cast<String, dynamic>())
        : const RakInfo();
  }

  static Future<void> deleteRak({required String pn, required String gudang}) =>
      _Api.delete(
        '/api/rak/gudang/${Uri.encodeComponent(gudang)}/part/${Uri.encodeComponent(pn)}',
      );

  /// Unggah/ganti foto kartu stok → URL publik foto baru. Server hanya menyimpan
  /// yang TERBARU: foto lama ikut dihapus dari storage.
  static Future<String> uploadRakFoto({
    required String pn,
    required String gudang,
    required Uint8List bytes,
    required String filename,
  }) async {
    final data = _Api._obj(await _Api.multipart(
      '/api/rak/foto/${Uri.encodeComponent(gudang)}/part/${Uri.encodeComponent(pn)}',
      files: [(field: 'file', bytes: bytes, filename: filename)],
    ));
    return '${data['foto_url'] ?? ''}';
  }

  static Future<void> deleteRakFoto({
    required String pn,
    required String gudang,
  }) =>
      _Api.delete(
        '/api/rak/foto/${Uri.encodeComponent(gudang)}/part/${Uri.encodeComponent(pn)}',
      );

  // ────────────────────────────────────────────────────────────────────
  // Stok opname
  // ────────────────────────────────────────────────────────────────────

  static Future<OpnameSession?> opnameDraft() async {
    final data = _Api._obj(await _Api.get('/api/opname/draft'));
    final draft = data['draft'];
    if (draft is! Map) return null;
    return OpnameSession.fromJson(draft.cast<String, dynamic>());
  }

  static Future<List<OpnameSession>> opnameHistory() async {
    final data = _Api._obj(await _Api.get('/api/opname/history'));
    return (data['history'] as List?)
            ?.whereType<Map>()
            .map((e) => OpnameSession.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  /// Mulai draft opname dari file stok yang diunggah.
  static Future<OpnameSession> opnameFromUpload({
    required Uint8List bytes,
    required String filename,
  }) async {
    final data = _Api._obj(await _Api.multipart(
      '/api/opname/draft/from-upload',
      files: [(field: 'file', bytes: bytes, filename: filename)],
    ));
    return OpnameSession.fromJson(_Api._obj(data['session']));
  }

  static Future<void> saveOpnameDraft(OpnameSession session) =>
      _Api.put('/api/opname/draft', body: session.toJson());

  /// Kunci hasil opname. Setelah ini draft tidak bisa diubah lagi.
  static Future<void> finalizeOpname(OpnameSession session) =>
      _Api.post('/api/opname/finalize', body: session.toJson());

  static Future<void> deleteOpnameDraft() => _Api.delete('/api/opname/draft');

  // ────────────────────────────────────────────────────────────────────
  // Asisten AI
  // ────────────────────────────────────────────────────────────────────

  /// Status asisten. `available` = server terkonfigurasi; `allowed` = menu
  /// Asisten AI tidak dimatikan admin untuk akun ini (Menu Control);
  /// `perbaikan` = mode perbaikan global menyala (admin dikecualikan server)
  /// → layar asisten menampilkan popup "sedang perbaikan".
  ///
  /// [gapAjar]/[gapTopik] = tawaran belajar (hanya terisi utk akun yang boleh
  /// MENGAJAR): jumlah & contoh topik yang berulang gagal dijawab asisten.
  static Future<
      ({bool available, bool allowed, bool perbaikan, int gapAjar, List<String> gapTopik})>
      aiStatusFull() async {
    final data = _Api._obj(await _Api.get('/api/ai/status'));
    final gap = data['gap_ajar'];
    return (
      available: data['available'] == true,
      allowed: data['allowed'] != false,
      perbaikan: data['perbaikan'] == true,
      gapAjar: gap is Map ? (gap['jumlah'] as num?)?.toInt() ?? 0 : 0,
      gapTopik: gap is Map
          ? [for (final t in (gap['topik'] as List? ?? const [])) '$t']
          : const <String>[],
    );
  }

  /// Versi ringkas untuk kartu dashboard: aktif = tersedia DAN diizinkan.
  static Future<bool> aiStatus() async {
    try {
      final s = await aiStatusFull();
      return s.available && s.allowed;
    } catch (_) {
      return false;
    }
  }

  /// Kirim percakapan ke asisten. [sheetId] wajib diteruskan dari balasan
  /// sebelumnya bila ada lampiran Excel, supaya file tetap menempel.
  ///
  /// [conversationId] = id percakapan (dibuat klien, diganti saat "hapus
  /// obrolan") → MEMORI SESI server: PN/angka hasil tool + nomor rangka/mesin
  /// giliran lalu diingat, sehingga follow-up "harganya berapa?" tidak disensor
  /// guard jadi "⟨PN tak terverifikasi⟩". Opsional — kosong = perilaku lama.
  static Future<AIChatResult> aiChat(
    List<Map<String, String>> messages, {
    String? sheetId,
    String? conversationId,
  }) async {
    final data = await _Api.post(
      '/api/ai/chat',
      body: {
        'messages': messages,
        'sheet_id': sheetId ?? '',
        'conversation_id': conversationId ?? '',
      },
      timeout: _Api._timeoutLong,
    );
    return AIChatResult.fromJson(_Api._obj(data));
  }

  /// Versi STREAMING dari [aiChat] — server mengirim status langkah live lewat
  /// SSE (`/api/ai/chat-stream`, event `progress`/`done`/`error`, frame dipisah
  /// `\n\n`, baris `data:`). [onProgress] dipanggil tiap label langkah baru.
  /// Cerminan `aiChatStream` di web. Pemanggil sebaiknya fallback ke [aiChat]
  /// bila ini melempar (mis. proxy tak mendukung streaming).
  ///
  /// [client] opsional: bila diberikan, PEMANGGIL yang memiliki dan menutupnya.
  /// Menutup client di tengah aliran = MEMBATALKAN giliran — satu-satunya cara
  /// keluar dari giliran yang berjalan sampai 4 menit (padanan AbortController
  /// di web). Bila tak diberikan, client dibuat & ditutup sendiri seperti dulu.
  static Future<AIChatResult> aiChatStream(
    List<Map<String, String>> messages, {
    String? sheetId,
    String? conversationId,
    http.Client? client,
    required void Function(String label) onProgress,
  }) async {
    final token = await _Api._token();
    final req = http.Request('POST', _Api._uri('/api/ai/chat-stream'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'messages': messages,
        'sheet_id': sheetId ?? '',
        'conversation_id': conversationId ?? '',
      });
    final milikSendiri = client == null;
    final c = client ?? http.Client();
    try {
      final streamed = await c.send(req).timeout(_Api._timeoutLong);
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        await _Api._throw(await http.Response.fromStream(streamed));
      }
      AIChatResult? result;
      String? errMsg;
      var buf = '';
      await for (final chunk in streamed.stream.transform(utf8.decoder)) {
        buf += chunk;
        final parts = buf.split('\n\n');
        buf = parts.removeLast(); // sisa tak lengkap → tunggu chunk berikutnya
        for (final part in parts) {
          final line = part
              .split('\n')
              .firstWhere((l) => l.startsWith('data:'), orElse: () => '');
          if (line.isEmpty) continue;
          Map<String, dynamic> ev;
          try {
            ev = (jsonDecode(line.substring(5).trim()) as Map)
                .cast<String, dynamic>();
          } catch (_) {
            continue;
          }
          switch (ev['type']) {
            case 'progress':
              if (ev['label'] != null) onProgress('${ev['label']}');
            case 'done':
              if (ev['result'] != null) {
                result = AIChatResult.fromJson(
                    (ev['result'] as Map).cast<String, dynamic>());
              }
            case 'error':
              errMsg = ev['message']?.toString() ?? 'Asisten AI gagal merespons.';
          }
        }
      }
      if (errMsg != null) throw ApiException(500, errMsg);
      if (result == null) {
        throw ApiException(500, 'Aliran jawaban berakhir tanpa hasil.');
      }
      return result;
    } finally {
      if (milikSendiri) c.close();
    }
  }

  // Catatan: aiChatImage (`/api/ai/chat-image`) dihapus 2026-07-21 mengikuti
  // web — fitur cari part dari foto lewat Asisten dibuang. Endpointnya masih
  // hidup di backend, tapi tak ada lagi klien yang memakainya. Menu "Cari by
  // Foto" (`/api/parts/search-image`) TIDAK terpengaruh.

  /// Chat dengan LAMPIRAN EXCEL: server membaca kolomnya, asisten bisa mengisi
  /// stok/nama/harga lalu mengeluarkan Excel baru. Balasan memuat `sheetId`
  /// yang harus dikirim ulang di giliran berikutnya.
  static Future<AIChatResult> aiChatSheet(
    List<Map<String, String>> messages, {
    required Uint8List bytes,
    required String filename,
    String? conversationId,
  }) async {
    final data = await _Api.multipart(
      '/api/ai/chat-sheet',
      files: [(field: 'file', bytes: bytes, filename: filename)],
      fields: {
        'messages': jsonEncode(messages),
        'conversation_id': conversationId ?? '',
      },
    );
    return AIChatResult.fromJson(_Api._obj(data));
  }

  /// Gambar exploded view / Excel yang disusun asisten, per id.
  static Future<Uint8List> aiImage(String id) =>
      _Api.bytes('/api/ai/excel/${Uri.encodeComponent(id)}');

  /// Alias yang lebih jujur namanya — endpoint yang sama melayani Excel.
  static Future<Uint8List> aiExcelExport(String id) => aiImage(id);

  /// Excel hasil perbandingan part dua unit (tool `banding_rangka`).
  static Future<Uint8List> aiBandingExport({
    required String rangka1,
    required String rangka2,
    String kategori = '',
  }) =>
      _Api.bytes('/api/ai/banding-rangka/export', query: {
        'rangka_1': rangka1,
        'rangka_2': rangka2,
        'kategori': kategori,
      });

  // ── Umpan balik asisten (👍/👎) ─────────────────────────────────────

  static Future<void> submitAiFeedback(AIFeedbackInput fb) =>
      _Api.post('/api/ai/feedback', body: fb.toJson());

  static Future<AIFeedbackList> listAiFeedback({
    String? rating,
    bool onlyOpen = false,
  }) async {
    final data = await _Api.get('/api/ai/feedback', query: {
      'rating': ?rating,
      if (onlyOpen) 'only_open': true,
    });
    return AIFeedbackList.fromJson(_Api._obj(data));
  }

  static Future<void> resolveAiFeedback(int id, {bool resolved = true}) =>
      _Api.post('/api/ai/feedback/$id/resolve', query: {'resolved': resolved});
}
