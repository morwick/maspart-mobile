// lib/screens/asisten_screen.dart — Asisten AI (chat live via /api/ai/chat).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard (tombol Salin)
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart'; // foto nomor rangka
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/mas_theme.dart';
import '../widgets/md_table.dart';
import '../api_service.dart';
import '../app/nav.dart';
import 'login_screen.dart';

/// Batas gambar exploded per jawaban — sama dengan `MAX_EXPLODED` di web.
const int _maxExploded = 6;

/// Kunci simpan chat. Riwayat dipertahankan agar tidak hilang saat user pindah
/// menu lalu kembali — shell membangun ulang layar tiap navigasi, jadi tanpa
/// ini percakapan lenyap (di web hal yang sama ditangani sessionStorage).
const String _chatKey = 'maspart_asisten_chat';

/// Kunci id percakapan → MEMORI SESI server (backend: services/ai_session.py).
/// Dengan ini asisten mengingat PN/angka hasil tool + nomor rangka/mesin giliran
/// lalu, sehingga follow-up "harganya berapa?" tidak disensor guard jadi
/// "⟨PN tak terverifikasi⟩". Diganti saat "chat baru" — percakapan baru tidak
/// boleh mewarisi ingatan percakapan lama. Cerminan `CONV_KEY` di web.
const String _convKey = 'maspart_asisten_conv';

/// Simpan hanya 60 pesan terakhir supaya penyimpanan tetap ringan.
const int _chatMaxSimpan = 60;

/// Status yang ditampilkan saat server MEMBUANG draf yang sudah mengalir
/// (frame `reset`: guard menyala / model diulang / salvage jalan). Draf hilang
/// dari layar, tampilan menunggu kembali — jawaban final tetap datang lewat
/// frame `done`. Sama persis dengan web (`LABEL_RAPI`).
const String _labelRapi = 'Memeriksa & merapikan jawaban…';

/// Jeda minimal antar-lukis saat draf mengalir. Potongan token datang puluhan
/// kali per detik; setState + parse markdown tiap potongan membuat layar
/// tersendat di HP (alasan yang sama dengan penjagaan setState pada notifikasi
/// scroll di bawah).
const Duration _drafJeda = Duration(milliseconds: 120);

/// Id percakapan acak (32 hex) — memenuhi pola `^[A-Za-z0-9-]{8,64}$` yang
/// divalidasi server. Tanpa paket `uuid`: cukup Random.secure().
String _buatConvId() {
  final r = Random.secure();
  return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
}

class _Msg {
  final String role; // 'user' | 'assistant'
  final String content;
  final String at;
  final List<String> tools;
  final List<AiExplodedImage> exploded;
  final List<String> pns;

  /// Nama file Excel yang dilampirkan user pada pesan ini.
  final String? sheetName;

  /// Ringkasan kolom Excel hasil deteksi server (menempel di balasan asisten).
  final AISheetSummary? sheet;
  final List<AIPhotoCandidate> photoCandidates;

  /// Asisten bertanya balik -> kartu pilihan. Hanya pesan TERAKHIR yang
  /// interaktif; kartu di pesan lama sengaja mati (pertanyaannya sudah basi).
  final List<AIPertanyaan> pertanyaan;
  final List<String> repairkitModels;
  final List<AIBandingExport> bandingExports;
  final List<AIExcelExport> excelExports;

  /// 'up' | 'down'. Sekali dinilai tidak bisa dinilai ulang — layar admin
  /// "Umpan Balik AI" membaca data ini, jadi satu jawaban = satu penilaian.
  String? rating;

  _Msg(
    this.role,
    this.content,
    this.at, {
    this.tools = const [],
    this.exploded = const [],
    this.pns = const [],
    this.sheetName,
    this.sheet,
    this.photoCandidates = const [],
    this.pertanyaan = const [],
    this.repairkitModels = const [],
    this.bandingExports = const [],
    this.excelExports = const [],
  });

  /// Balasan asisten — semua lampiran hasil (Excel, kandidat foto, exploded)
  /// dibawa dari satu tempat supaya tak ada yang terlewat di jalur chat mana pun.
  factory _Msg.assistant(AIChatResult r, String at) => _Msg(
        'assistant',
        r.reply.isEmpty ? '(tidak ada jawaban)' : r.reply,
        at,
        tools: r.tools,
        exploded: r.explodedImages,
        pns: r.partPns,
        sheet: r.sheet,
        photoCandidates: r.photoCandidates,
        pertanyaan: r.pertanyaan,
        repairkitModels: r.repairkitModels,
        bandingExports: r.bandingExports,
        excelExports: r.excelExports,
      );

  /// Bentuk JSON untuk disimpan. Sengaja memakai nama field yang SAMA dengan
  /// balasan server, supaya pemulihannya bisa memakai `fromJson` model yang
  /// sudah ada — tak ada parser kedua yang bisa ikut basi.
  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'at': at,
        'rating': rating,
        'tools_used': tools,
        'part_pns': pns,
        'sheet_name': sheetName,
        'exploded_images': [
          for (final e in exploded)
            {
              'id': e.id,
              'pn': e.pn,
              'balon': e.balon,
              'nama_figure': e.namaFigure,
              'kategori': e.kategori,
            },
        ],
        'photo_candidates': [
          for (final c in photoCandidates)
            {
              'part_number': c.partNumber,
              'part_name': c.partName,
              'similarity': c.similarity,
              'sims_url': c.simsUrl,
            },
        ],
        'pertanyaan': [for (final q in pertanyaan) q.toJson()],
        'repairkit_models': repairkitModels,
        'banding_exports': [
          for (final b in bandingExports)
            {
              'rangka_1': b.rangka1,
              'rangka_2': b.rangka2,
              'kategori': b.kategori,
              'kategori_nama': b.kategoriNama,
            },
        ],
        'excel_exports': [
          for (final x in excelExports)
            {
              'id': x.id,
              'filename': x.filename,
              'judul': x.judul,
              'jumlah_baris': x.jumlahBaris,
            },
        ],
        'sheet': sheet == null
            ? null
            : {
                'filename': sheet!.filename,
                'sheet': sheet!.sheet,
                'sheet_lain': sheet!.sheetLain,
                'jumlah_baris': sheet!.jumlahBaris,
                'jumlah_kolom': sheet!.jumlahKolom,
                'kolom': [
                  for (final k in sheet!.kolom)
                    {'nama': k.nama, 'peran': k.peran},
                ],
                'kolom_part_number': sheet!.kolomPartNumber,
                'part_number_dikenal_di_katalog':
                    sheet!.partNumberDikenalDiKatalog,
                'contoh_baris': sheet!.contohBaris,
                'terpotong': sheet!.terpotong,
              },
      };

  factory _Msg.fromJson(Map<String, dynamic> j) {
    // Lampiran hasil dipulihkan lewat AIChatResult.fromJson — satu jalur parsing
    // yang sama dengan balasan langsung dari server.
    final r = AIChatResult.fromJson(j);
    return _Msg(
      '${j['role'] ?? 'assistant'}',
      '${j['content'] ?? ''}',
      '${j['at'] ?? ''}',
      tools: r.tools,
      exploded: r.explodedImages,
      pns: r.partPns,
      sheetName: j['sheet_name']?.toString(),
      sheet: r.sheet,
      photoCandidates: r.photoCandidates,
      pertanyaan: r.pertanyaan,
      repairkitModels: r.repairkitModels,
      bandingExports: r.bandingExports,
      excelExports: r.excelExports,
    )..rating = j['rating']?.toString();
  }
}

class AsistenScreen extends StatefulWidget {
  const AsistenScreen({super.key});
  @override
  State<AsistenScreen> createState() => _AsistenScreenState();
}

class _AsistenScreenState extends State<AsistenScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];

  /// Langkah live saat streaming jawaban (label dari server, mis. "EPC · BOM
  /// unit"). Kosong = belum ada progres / bukan mode stream.
  final List<String> _steps = [];
  bool _busy = false;
  String? _error;

  /// DRAF jawaban yang sedang mengalir (opt-in `stream_tokens`) — teks MENTAH
  /// dari model yang BELUM lewat guard. Kosong = tak ada draf (gelembung
  /// menunggu menampilkan langkah seperti dulu). Sengaja hidup di luar `_msgs`:
  /// draf tak boleh ikut disimpan ke SharedPreferences dan tak boleh bisa
  /// dinilai/disalin — frame `done` yang mengganti seluruh isinya dengan
  /// jawaban final.
  String _draf = '';
  Timer? _drafTimer;
  DateTime _drafLukis = DateTime.fromMillisecondsSinceEpoch(0);

  /// Menempel di bawah atau tidak (lihat _scrollToBottom).
  bool _ikutiBawah = true;

  /// Cerminan `_ikutiBawah` untuk RENDER: begitu user menggulir ke atas ia
  /// kehilangan jalan kembali, dan selama 14-254 detik menunggu ia juga tak
  /// tahu jawabannya sudah datang. Dua penanda, bukan satu, supaya tombolnya
  /// bisa berubah dari "Ke bawah" jadi "Jawaban baru" (paritas dgn web).
  bool _jauhDariBawah = false;
  bool _adaBaru = false;

  /// Client HTTP giliran yang sedang berjalan. Menutupnya = MEMBATALKAN —
  /// padanan tombol Stop di web. Giliran bisa berjalan sampai 4 menit, dan
  /// sebelumnya satu-satunya jalan keluar adalah menutup aplikasi.
  http.Client? _streamClient;
  bool _dibatalkan = false;

  // Status asisten. `allowed` dan `available` DUA hal berbeda: allowed=false
  // berarti menu Asisten AI dimatikan admin untuk akun ini (Menu Control),
  // available=false berarti asisten belum dikonfigurasi di server.
  bool _statusLoading = true;
  bool _available = true;
  bool _allowed = true;

  /// Tawaran belajar (hanya terisi utk akun yang boleh MENGAJAR): jumlah topik
  /// yang berulang gagal dijawab + contoh pertamanya. Lingkaran
  /// gagal→terdeteksi→diajarkan menutup lewat chip di layar kosong.
  int _gapAjar = 0;
  List<String> _gapTopik = const [];
  // Mode perbaikan global (Menu Control → Asisten AI). Server yang memutuskan;
  // admin dikecualikan di sana. true → popup + input terkunci.
  bool _perbaikan = false;

  // Lampiran Excel yang SUDAH dipilih tapi BELUM dikirim — user mengetik dulu
  // maunya apa ("isikan stoknya"), baru tekan Kirim.
  ({Uint8List bytes, String filename})? _pendingSheet;

  // Lampiran Excel aktif: file dipegang server, dirujuk lewat `sheetId`.
  // WAJIB dikirim ulang di setiap giliran berikutnya — tanpa itu lampiran
  // lepas dari percakapan dan asisten "lupa" file yang barusan diunggah.
  String _sheetId = '';
  String _sheetName = '';

  // FOTO nomor rangka. Fotonya TIDAK ikut ke asisten: server membacanya (OCR +
  // cocokkan ke populasi) dan hanya NOMOR-nya yang dikirim sebagai pesan biasa.
  // `_ocrNote` = baris catatan di atas kotak ketik; bacaan yang belum yakin
  // sengaja tidak dikirim otomatis, melainkan dituliskan ke kotak ketik supaya
  // user mengoreksi — satu huruf salah = unit yang salah.
  final _picker = ImagePicker();
  bool _ocrBusy = false;
  ({String teks, bool ragu})? _ocrNote;

  /// Id percakapan aktif (memori sesi server). Dimuat/dibuat sekali di
  /// [_convId]; kosong hanya bila SharedPreferences gagal → asisten tetap
  /// jalan, cuma tanpa ingatan lintas-giliran (perilaku sebelum fitur ini).
  String _conv = '';

  Future<String> _convId() async {
    if (_conv.isNotEmpty) return _conv;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_convKey) ?? '';
      if (id.isEmpty) {
        id = _buatConvId();
        await prefs.setString(_convKey, id);
      }
      _conv = id;
    } catch (_) {
      /* penyimpanan diblokir → jalan tanpa memori sesi */
    }
    return _conv;
  }

  bool get _locked => !_allowed || !_available;

  static const _suggestions = [
    'Cek stok part WG9925520270',
    'Cari part rem depan',
    'Repair kit transmisi HW19709XST',
    'Gudang apa saja yang tersedia?',
  ];

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _muatChat();
  }

  /// Pulihkan percakapan terakhir. Shell membangun ulang layar tiap kali user
  /// pindah menu, jadi tanpa ini chat hilang begitu ia menengok menu lain.
  Future<void> _muatChat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_chatKey);
      if (raw == null || raw.isEmpty || !mounted) return;
      final saved = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => _Msg.fromJson(e.cast<String, dynamic>()))
          .toList();
      if (saved.isEmpty || !mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(saved);
      });
      _scrollToBottom();
    } catch (_) {
      // Simpanan rusak/berubah bentuk → mulai bersih, jangan meledakkan layar.
    }
  }

  /// Simpan chat. Dipanggil setelah tiap perubahan `_msgs`.
  Future<void> _simpanChat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_msgs.isEmpty) {
        await prefs.remove(_chatKey);
        return;
      }
      final potong = _msgs.length > _chatMaxSimpan
          ? _msgs.sublist(_msgs.length - _chatMaxSimpan)
          : _msgs;
      await prefs.setString(
        _chatKey,
        jsonEncode([for (final m in potong) m.toJson()]),
      );
    } catch (_) {
      /* penyimpanan penuh/diblokir → chat tetap hidup di memori */
    }
  }

  /// Mulai percakapan baru: buang riwayat DAN lampiran Excel yang menempel,
  /// kalau tidak asisten masih menganggap file lama terlampir di giliran depan.
  Future<void> _chatBaru() async {
    setState(() {
      _msgs.clear();
      _error = null;
      _sheetId = '';
      _pendingSheet = null;
    });
    await _simpanChat();
    // Obrolan baru = ingatan baru. Tanpa ini memori sesi server masih memegang
    // rangka/PN percakapan LAMA dan asisten merujuknya seolah masih relevan.
    _conv = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_convKey);
    } catch (_) {
      /* abaikan penyimpanan diblokir */
    }
  }

  @override
  void dispose() {
    _drafTimer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final s = await ApiService.aiStatusFull();
      if (!mounted) return;
      setState(() {
        _available = s.available;
        _allowed = s.allowed;
        _perbaikan = s.perbaikan;
        _gapAjar = s.gapAjar;
        _gapTopik = s.gapTopik;
        _statusLoading = false;
      });
      // Popup mode perbaikan — sekali saat layar dibuka; input tetap terkunci
      // setelah ditutup karena server mengirim available=false.
      if (s.perbaikan && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('🔧 Asisten AI sedang perbaikan'),
              content: const Text(
                  'Kami sedang melakukan pemeliharaan. Silakan coba lagi '
                  'nanti — fitur lain aplikasi tetap berjalan normal.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Mengerti'),
                ),
              ],
            ),
          );
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isAuth) {
        _toLogin();
        return;
      }
      setState(() {
        _available = false;
        _statusLoading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _available = false;
        _statusLoading = false;
      });
    }
  }

  void _toLogin() {
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  }

  /// Muara semua kegagalan panggilan API: 401 → login ulang, selebihnya pesan
  /// server ditampilkan apa adanya (jangan ditelan diam-diam).
  void _fail(Object e, String fallback) {
    if (!mounted) return;
    if (e is ApiException) {
      if (e.isAuth) {
        _toLogin();
        return;
      }
      setState(() => _error = e.message);
      return;
    }
    setState(() => _error = fallback);
  }

  String _now() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  /// Ikuti ke bawah HANYA bila user memang sedang di bawah.
  ///
  /// Status langkah masuk berkali-kali selama 14-46 detik menunggu; dulu tiap
  /// langkah menyeret user kembali ke bawah persis saat ia menggulir ke atas
  /// membaca jawaban sebelumnya. Padanan `stickBottom` di web.
  bool get _dekatBawah {
    if (!_scroll.hasClients) return true;
    return _scroll.position.maxScrollExtent - _scroll.offset < 120;
  }

  void _scrollToBottom({bool paksa = false}) {
    if (!paksa && !_ikutiBawah) {
      // Tertinggal di atas: tandai ada isi baru supaya tombol lompat berubah
      // jadi ajakan hijau. Lewat post-frame karena pemanggilnya kadang sudah
      // berada di dalam setState — setState bersarang akan melempar.
      if (!_adaBaru) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_adaBaru) setState(() => _adaBaru = true);
        });
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  /// Dipakai tombol lompat: kembali ke bawah DAN menyambung lagi mode ikut.
  void _turunKeBawah() {
    setState(() {
      _ikutiBawah = true;
      _jauhDariBawah = false;
      _adaBaru = false;
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  List<Map<String, String>> _payload() =>
      _msgs.map((m) => {'role': m.role, 'content': m.content}).toList();

  // ── Draf token (frame `delta`/`reset`) ──────────────────────────────────
  //
  // Kontraknya sederhana: potongan di-APPEND, `reset` membuang SELURUH draf,
  // dan `done` mengganti semuanya dengan jawaban final. Draf tak pernah masuk
  // `_msgs` maupun penyimpanan.

  /// Buang draf TANPA setState — dipakai dari dalam blok setState yang sudah
  /// ada (kirim baru / jawaban final / giliran gagal / batal).
  void _drafBersih() {
    _drafTimer?.cancel();
    _drafTimer = null;
    _draf = '';
  }

  /// Potongan teks baru dari model.
  void _tambahDraf(String potongan) {
    _draf += potongan;
    if (DateTime.now().difference(_drafLukis) < _drafJeda) {
      // Terlalu rapat: tunda satu lukisan. Timer-nya wajib — tanpa itu potongan
      // terakhir sebelum jeda panjang (mis. model berhenti menulis untuk
      // memanggil tool) menggantung basi di layar.
      _drafTimer ??= Timer(_drafJeda, () {
        _drafTimer = null;
        if (mounted && _draf.isNotEmpty) _lukisDraf();
      });
      return;
    }
    _lukisDraf();
  }

  void _lukisDraf() {
    _drafTimer?.cancel();
    _drafTimer = null;
    _drafLukis = DateTime.now();
    setState(() {});
    _scrollToBottom();
  }

  /// Frame `reset`: draf dibuang server (guard/retry/salvage). Layar kembali ke
  /// tampilan menunggu, dengan langkah "Memeriksa & merapikan jawaban…" supaya
  /// teks yang tiba-tiba lenyap ada penjelasannya. Bisa terjadi berkali-kali.
  void _resetDraf() {
    setState(() {
      _drafBersih();
      if (_steps.isEmpty || _steps.last != _labelRapi) _steps.add(_labelRapi);
    });
    _scrollToBottom();
  }

  Future<void> _send(String text) async {
    if (_busy || _locked) return;
    final pending = _pendingSheet;
    // File yang dilampirkan dikirim BERSAMA pesan ini, lewat endpoint chat-sheet.
    if (pending != null) return _sendWithSheet(pending, text.trim());
    final body = text.trim();
    if (body.isEmpty) return;
    setState(() {
      _resetKartu();          // kartu lama tak boleh ikut ke giliran baru
      _msgs.add(_Msg('user', body, _now()));
      _ctrl.clear();
      _busy = true;
      _error = null;
      _steps.clear();
      _drafBersih();
    });
    _ikutiBawah = true;   // mengirim = user memang ingin melihat jawabannya
    _dibatalkan = false;
    _scrollToBottom(paksa: true);
    try {
      final sid = _sheetId.isEmpty ? null : _sheetId;
      final cid = await _convId();
      AIChatResult r;
      final c = http.Client();
      _streamClient = c;
      try {
        // Utamakan streaming: status langkah tampil hidup. Bila stream gagal
        // (mis. proxy tak mendukung SSE), jatuh ke chat non-stream — persis web.
        r = await ApiService.aiChatStream(
          _payload(),
          sheetId: sid,
          conversationId: cid,
          client: c,
          onProgress: (label) {
            if (!mounted) return;
            setState(() {
              if (_steps.isEmpty || _steps.last != label) _steps.add(label);
            });
            _scrollToBottom();
          },
          // Draf token: potongan di-append, `null` = server membuangnya.
          onDelta: (potongan) {
            if (!mounted) return;
            if (potongan == null) {
              _resetDraf();
            } else {
              _tambahDraf(potongan);
            }
          },
        );
      } catch (_) {
        // Pembatalan BUKAN kegagalan stream — tanpa penjagaan ini, tombol Stop
        // justru memicu permintaan KEDUA lewat jalur non-stream.
        if (_dibatalkan) rethrow;
        // Draf separuh jalan tak boleh menggantung selama fallback berjalan.
        if (mounted && _draf.isNotEmpty) _resetDraf();
        r = await ApiService.aiChat(_payload(), sheetId: sid, conversationId: cid);
      } finally {
        c.close();
        if (identical(_streamClient, c)) _streamClient = null;
      }
      if (!mounted) return;
      setState(() {
        // Jawaban final MENGGANTI draf seutuhnya (bukan menambahnya): isinya
        // sudah lewat semua guard, draf belum.
        _drafBersih();
        _msgs.add(_Msg.assistant(r, _now()));
        _busy = false;
        _steps.clear();
      });
      _scrollToBottom();
      _simpanChat();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _drafBersih();   // batal / gagal → draf ikut hilang, tak menggantung
        _busy = false;
        _steps.clear();
      });
      // Dibatalkan user = bukan kesalahan. Pertanyaannya tetap di transkrip.
      if (_dibatalkan) {
        _dibatalkan = false;
        return;
      }
      _fail(e, 'Gagal menghubungi Asisten AI.');
    }
  }

  /// Konfirmasi sebelum menghapus percakapan. Sekali ketuk dulu menghilangkan
  /// transkrip panjang SEKALIGUS mereset ingatan sesi server, tanpa peringatan
  /// dan tanpa cara mengembalikannya.
  Future<void> _konfirmasiChatBaru() async {
    if (_msgs.isEmpty) return _chatBaru();
    final m = context.mas;
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus percakapan ini?'),
        content: const Text(
            'Riwayat di layar dan ingatan asisten untuk sesi ini akan direset.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: TextStyle(color: m.ink500)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Color(0xFFC0392B))),
          ),
        ],
      ),
    );
    if (ya == true) await _chatBaru();
  }

  /// Hentikan giliran yang sedang berjalan (padanan tombol Stop di web).
  void _stopGiliran() {
    if (!_busy) return;
    _dibatalkan = true;
    _streamClient?.close();   // memutus aliran → _send jatuh ke catch
    _streamClient = null;
  }

  /// Unggah Excel: server membaca kolomnya, menyimpan sheet, dan mengembalikan
  /// `sheetId` — itulah pegangan agar tindak lanjut ("isikan stoknya di kolom D")
  /// tetap mengacu ke file yang sama.
  Future<void> _sendWithSheet(
      ({Uint8List bytes, String filename}) file, String caption) async {
    final userText = caption.isEmpty
        ? 'Saya lampirkan ${file.filename}. Isinya apa saja?'
        : caption;
    setState(() {
      _resetKartu();          // kartu lama tak boleh ikut ke giliran baru
      _msgs.add(_Msg('user', userText, _now(), sheetName: file.filename));
      _ctrl.clear();
      _pendingSheet = null;
      _busy = true;
      _error = null;
      _steps.clear();         // STATUS langkah: giliran ber-lampiran pun hidup
      _drafBersih();
    });
    _ikutiBawah = true;
    _dibatalkan = false;
    _scrollToBottom(paksa: true);
    try {
      final cid = await _convId();
      AIChatResult r;
      final c = http.Client();
      _streamClient = c;
      try {
        // Utamakan streaming — tanpa ini giliran ber-lampiran tak menampilkan
        // status apa pun padahal ia yang paling lama (baca file + isi kolom +
        // foto + gambar teknis). Keluhan pemilik 2026-08-06.
        r = await ApiService.aiChatSheetStream(
          _payload(),
          bytes: file.bytes,
          filename: file.filename,
          conversationId: cid,
          client: c,
          onProgress: (label) {
            if (!mounted) return;
            setState(() {
              if (_steps.isEmpty || _steps.last != label) _steps.add(label);
            });
            _scrollToBottom();
          },
          onDelta: (potongan) {
            if (!mounted) return;
            if (potongan == null) {
              _resetDraf();
            } else {
              _tambahDraf(potongan);
            }
          },
        );
      } on ApiException catch (e) {
        // Galat FILE (400/413) bukan galat streaming — mengulang lewat jalur
        // lama hanya membuat user menunggu dua kali untuk pesan yang sama.
        if (_dibatalkan || e.statusCode < 500) rethrow;
        if (mounted && _draf.isNotEmpty) _resetDraf();
        r = await ApiService.aiChatSheet(_payload(),
            bytes: file.bytes, filename: file.filename, conversationId: cid);
      } catch (_) {
        if (_dibatalkan) rethrow;
        if (mounted && _draf.isNotEmpty) _resetDraf();
        r = await ApiService.aiChatSheet(_payload(),
            bytes: file.bytes, filename: file.filename, conversationId: cid);
      } finally {
        c.close();
        if (identical(_streamClient, c)) _streamClient = null;
      }
      if (!mounted) return;
      setState(() {
        _drafBersih();
        if (r.sheetId != null && r.sheetId!.isNotEmpty) {
          _sheetId = r.sheetId!;
          _sheetName = file.filename;
        }
        _msgs.add(_Msg.assistant(r, _now()));
        _busy = false;
        _steps.clear();
      });
      _scrollToBottom();
      _simpanChat();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _steps.clear();
        _drafBersih();
        _msgs.removeLast();
        _pendingSheet = file; // kembalikan lampiran supaya bisa kirim ulang
        _ctrl.text = caption;
      });
      if (_dibatalkan) return;   // dibatalkan user = bukan kegagalan
      _fail(e, 'Gagal mengunggah Excel.');
    }
  }

  // ── Foto nomor rangka ───────────────────────────────────────────────
  /// Pilih sumber foto (kamera di lapangan / galeri), lalu baca nomornya.
  void _pilihFotoRangka() {
    final m = context.mas;
    showModalBottomSheet(
      context: context,
      backgroundColor: m.paper,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: m.ink200, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Text('Foto nomor rangka',
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700, color: m.ink900)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
                'Ambil dekat & tegak lurus, seluruh 17 karakter masuk bingkai.',
                style: TextStyle(fontSize: 11.5, color: m.ink500)),
          ),
          ListTile(
            leading: Icon(Icons.photo_camera_outlined, color: m.brand600),
            title: const Text('Ambil dari kamera'),
            onTap: () {
              Navigator.pop(ctx);
              _bacaFotoRangka(ImageSource.camera);
            },
          ),
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: m.brand600),
            title: const Text('Pilih dari galeri'),
            onTap: () {
              Navigator.pop(ctx);
              _bacaFotoRangka(ImageSource.gallery);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _bacaFotoRangka(ImageSource source) async {
    final nav = AppNav.of(context);
    XFile? picked;
    try {
      // 1600 px cukup: server memperkecil ke ukuran itu juga sebelum OCR, jadi
      // mengirim foto 12 MP hanya memperlambat unggahan di sinyal lapangan.
      picked = await _picker.pickImage(
          source: source, imageQuality: 88, maxWidth: 1600);
    } catch (_) {
      nav.toast('Tidak dapat mengakses kamera/galeri.');
      return;
    }
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _error = null;
      _ocrBusy = true;
      _ocrNote = (teks: 'Membaca nomor rangka dari foto…', ragu: false);
    });
    try {
      final r = await ApiService.aiOcrRangka(
          bytes: bytes, filename: picked.name);
      if (!mounted) return;
      setState(() {
        _ocrBusy = false;
        _ocrNote = (teks: r.pesan, ragu: r.keyakinan != 'pasti');
      });
      if (r.bolehLangsungKirim) {
        await _send('Nomor rangka: ${r.rangka}');
      } else if (r.rangka.isNotEmpty) {
        // Bacaan ragu → taruh di kotak ketik, user yang memutuskan.
        _ctrl.text = r.rangka;
        _ctrl.selection =
            TextSelection.collapsed(offset: _ctrl.text.length);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocrBusy = false;
        _ocrNote = null;
      });
      _fail(e, 'Gagal membaca foto nomor rangka.');
    }
  }

  Future<void> _pickSheet() async {
    final nav = AppNav.of(context);
    try {
      // file_picker v11: API STATIS (bukan FilePicker.platform). `withData`
      // wajib — API kita mengirim multipart dari memori, dan path tidak selalu
      // ada (mis. file dari Google Drive).
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xlsm', 'xls'],
        withData: true,
      );
      final f = res?.files.first;
      final b = f?.bytes;
      if (f == null || b == null) return;
      if (!mounted) return;
      final nama = f.name.toLowerCase();
      // Backend hanya membaca format Excel modern; .xls ditolak di sana, jadi
      // dicegat di sini agar pesannya jelas dan tak membuang kuota unggah.
      if (!nama.endsWith('.xlsx') && !nama.endsWith('.xlsm')) {
        setState(() =>
            _error = 'File harus Excel .xlsx atau .xlsm (bukan .xls / .csv).');
        return;
      }
      setState(() {
        _pendingSheet = (bytes: b, filename: f.name);
        _error = null;
      });
    } catch (e) {
      nav.toast(e is ApiException ? e.message : 'Gagal membuka file.');
    }
  }

  // ── Umpan balik 👍/👎 ───────────────────────────────────────────────
  // Data ini dibaca admin di layar "Umpan Balik AI", jadi kirim apa adanya:
  // pertanyaan user sebelumnya, jawaban asisten, tool yang dipakai, dan
  // beberapa giliran terakhir sebagai konteks.
  Future<void> _sendFeedback(int idx, String rating, {String? note}) async {
    final target = _msgs[idx];
    if (target.role != 'assistant' || target.rating != null) return;
    final nav = AppNav.of(context);

    var question = '';
    for (var j = idx - 1; j >= 0; j--) {
      if (_msgs[j].role == 'user') {
        question = _msgs[j].content;
        break;
      }
    }
    final riwayat = _msgs
        .sublist(idx - 5 < 0 ? 0 : idx - 5, idx + 1)
        .map((m) => AIChatTurn(role: m.role, content: m.content))
        .toList();

    // Optimistis: tandai dulu supaya tombol langsung terkunci (cegah kirim
    // ganda); batalkan tandanya bila server menolak.
    setState(() => target.rating = rating);
    try {
      await ApiService.submitAiFeedback(AIFeedbackInput(
        rating: rating,
        question: question,
        answer: target.content,
        tools: target.tools,
        note: note,
        context: riwayat,
      ));
      if (!mounted) return;
      // Ikut disimpan supaya tombolnya tetap terkunci setelah pindah menu —
      // kalau tidak, jawaban yang sama bisa dinilai dua kali.
      _simpanChat();
      nav.toast(rating == 'up'
          ? 'Terima kasih atas umpan baliknya.'
          : 'Masukan terkirim — kami perbaiki.');
    } catch (e) {
      if (!mounted) return;
      setState(() => target.rating = null);
      _fail(e, 'Gagal menyimpan umpan balik.');
    }
  }

  /// 👎 boleh disertai catatan — opsional, tapi paling berguna buat admin.
  Future<void> _askNoteThenDown(int idx) async {
    final m = context.mas;
    final c = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: m.paper,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(MasRadii.card)),
        title: Text('Apa yang salah?',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: m.ink900)),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 3,
          cursorColor: m.brand600,
          style: TextStyle(fontSize: 13.5, color: m.ink900),
          decoration: InputDecoration(
            hintText: 'Opsional — mis. stok keliru, PN tidak cocok…',
            hintStyle: TextStyle(fontSize: 13, color: m.ink400),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: m.ink200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: m.ink200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: m.brand600),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: TextStyle(color: m.ink500)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text('Kirim', style: TextStyle(color: m.brand700)),
          ),
        ],
      ),
    );
    c.dispose();
    // null = dialog ditutup / Batal → jangan kirim apa pun.
    if (note == null || !mounted) return;
    await _sendFeedback(idx, 'down', note: note.isEmpty ? null : note);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Column(children: [
      // Header status live (setara web): dot + "Online · terhubung ke data
      // live" / "Nonaktif". "Chat Baru" muncul saat ada percakapan — riwayat
      // bertahan pindah menu, jadi harus ada jalan memulai yang baru.
      _statusBar(m),
      Expanded(
        child: _msgs.isEmpty
            ? _empty(m)
            : NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollUpdateNotification) {
                    final dekat = _dekatBawah;
                    _ikutiBawah = dekat;
                    // setState hanya saat nilainya BERUBAH — notifikasi scroll
                    // datang tiap frame dan rebuild tiap frame akan tersendat.
                    if (!dekat != _jauhDariBawah || (dekat && _adaBaru)) {
                      setState(() {
                        _jauhDariBawah = !dekat;
                        if (dekat) _adaBaru = false;
                      });
                    }
                  }
                  return false;
                },
                child: Stack(children: [
                  ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _msgs.length + (_busy ? 1 : 0),
                    itemBuilder: (ctx, i) =>
                        i >= _msgs.length ? _typing(m) : _bubble(m, _msgs[i], i),
                  ),
                  if (_jauhDariBawah)
                    Positioned(
                      left: 0, right: 0, bottom: 12,
                      child: Center(child: _tombolLompat(m)),
                    ),
                ]),
              ),
      ),
      if (!_statusLoading && _perbaikan)
        _notice(m, '🔧 Asisten AI sedang dalam perbaikan. Silakan coba lagi nanti.')
      else if (!_statusLoading && !_allowed)
        _notice(m, 'Asisten AI dimatikan untuk akun ini oleh admin (Menu Control).')
      else if (!_statusLoading && !_available)
        _notice(m,
            'Asisten AI belum dikonfigurasi di server. Hubungi admin untuk mengaktifkannya.'),
      if (_error != null)
        Container(
          width: double.infinity,
          color: m.danger50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(_error!, style: TextStyle(color: m.danger600, fontSize: 12.5)),
        ),
      _inputBar(m),
    ]);
  }

  /// Jalan kembali ke bawah. Muncul hanya saat user memang tertinggal di atas;
  /// berubah hijau bila ada jawaban yang belum ia lihat (paritas dgn web).
  Widget _tombolLompat(MasColors m) {
    final baru = _adaBaru;
    return Material(
      color: baru ? m.brand600 : m.paper,
      borderRadius: BorderRadius.circular(999),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: InkWell(
        onTap: _turunKeBawah,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: baru ? null : Border.all(color: m.ink200),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.arrow_downward_rounded,
                size: 15, color: baru ? Colors.white : m.ink700),
            const SizedBox(width: 6),
            Text(
              baru ? 'Jawaban baru' : 'Ke bawah',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: baru ? Colors.white : m.ink700,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _statusBar(MasColors m) {
    final locked = _locked;
    final label = _statusLoading
        ? 'Menghubungkan…'
        : (locked
            ? (_perbaikan ? 'Sedang perbaikan' : 'Nonaktif')
            : 'Online · terhubung ke data live');
    final dot = _statusLoading ? m.ink400 : (locked ? m.warn600 : m.brand600);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration: BoxDecoration(
        color: m.paper,
        border: Border(bottom: BorderSide(color: m.ink150)),
      ),
      child: Row(children: [
        Container(
            width: 7, height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: m.ink500)),
        ),
        if (_msgs.isNotEmpty)
          TextButton.icon(
            onPressed: _busy ? null : _konfirmasiChatBaru,
            icon: Icon(Icons.refresh_rounded, size: 15, color: m.ink600),
            label: Text('Chat Baru',
                style: TextStyle(fontSize: 12.5, color: m.ink600)),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
      ]),
    );
  }

  Widget _notice(MasColors m, String text) => Container(
        width: double.infinity,
        color: m.warn50,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, size: 15, color: m.warn600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: m.warn600, fontSize: 12.5, height: 1.4)),
          ),
        ]),
      );

  Widget _empty(MasColors m) {
    // Saran bisa diatur dari server (config `asisten_suggestions`); fallback ke
    // daftar bawaan bila belum dikonfigurasi.
    final suggestions = AppNav.of(context).asistenSuggestions(_suggestions);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 36, 16, 16),
      children: [
        Center(child: _avatar(52)),
        const SizedBox(height: 14),
        Text('Asisten AI MasPart',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: m.ink900)),
        const SizedBox(height: 4),
        Text('Tanya stok, harga, BOM per-VIN, repair kit,\nkode kesalahan, dan banding antar unit.\nBisa juga lampirkan Excel.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5)),
        const SizedBox(height: 20),
        // Tawaran belajar — hanya muncul utk yang boleh MENGAJAR & memang ada
        // topik yang berulang gagal (paritas web). Ketuk = kirim pertanyaan
        // pembuka; model memanggil topik_gagal lalu memandu alur ajar.
        if (_gapAjar > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: m.warn50,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => _send(
                    'Tampilkan topik yang berulang gagal kamu jawab, lalu bantu '
                    'saya mengajarkannya satu per satu.'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: m.warn600.withValues(alpha: .35)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💡', style: TextStyle(fontSize: 15)),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text: '$_gapAjar topik',
                                style:
                                    const TextStyle(fontWeight: FontWeight.w700)),
                            const TextSpan(
                                text: ' berulang gagal saya jawab'),
                            if (_gapTopik.isNotEmpty)
                              TextSpan(
                                  text: ' — mis. "${_gapTopik.first}"',
                                  style: const TextStyle(
                                      fontStyle: FontStyle.italic)),
                            TextSpan(
                                text: '. Ajari saya?',
                                style: TextStyle(
                                    color: m.warn600,
                                    fontWeight: FontWeight.w600)),
                          ]),
                          style: TextStyle(
                              fontSize: 12.5, height: 1.5, color: m.ink800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        for (final s in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: m.paper,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => _send(s),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: m.ink200),
                    boxShadow: m.shadow1,
                  ),
                  child: Text(s, style: TextStyle(fontSize: 13, color: m.ink800)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _avatar(double size) => Container(
        width: size, height: size, alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF028912), Color(0xFF1EA83A)]),
        ),
        child: Icon(Icons.smart_toy_rounded, color: Colors.white, size: size * 0.52),
      );

  Widget _bubble(MasColors m, _Msg msg, int index) {
    final isUser = msg.role == 'user';
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            if (msg.sheetName != null) ...[
              _FileChip(name: msg.sheetName!),
              const SizedBox(height: 5),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: m.brand600,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14), topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14), bottomRight: Radius.circular(4),
                ),
                boxShadow: m.shadow1,
              ),
              child: SelectableText(msg.content,
                  style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.white)),
            ),
            const SizedBox(height: 3),
            Text(msg.at, style: TextStyle(fontSize: 10.5, color: m.ink400)),
          ]),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _avatar(30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: m.paper,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4), topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14),
                ),
                border: Border.all(color: m.ink150),
                boxShadow: m.shadow1,
              ),
              child: MasMarkdown(data: msg.content, selectable: true),
            ),
            if (msg.sheet != null) ...[
              const SizedBox(height: 8),
              _SheetCard(s: msg.sheet!),
            ],
            // Thumbnail kandidat-foto (photoCandidates) & foto part SIMS (pns)
            // SENGAJA tidak dirender — dimatikan di web atas permintaan pemilik
            // (2026-07-08). Hanya exploded view yang ditampilkan.
            if (msg.exploded.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ExplodedImages(images: msg.exploded),
            ],
            if (msg.repairkitModels.isNotEmpty) ...[
              const SizedBox(height: 8),
              _RepairKitDownloads(models: msg.repairkitModels),
            ],
            for (final exp in msg.bandingExports) ...[
              const SizedBox(height: 8),
              _BandingExcelCard(exp: exp),
            ],
            for (final exp in msg.excelExports) ...[
              const SizedBox(height: 8),
              _AiExcelCard(exp: exp),
            ],
            const SizedBox(height: 5),
            _SourceRow(at: msg.at, tools: msg.tools),
            const SizedBox(height: 2),
            Row(children: [
              _FeedbackRow(
                rating: msg.rating,
                onUp: () => _sendFeedback(index, 'up'),
                onDown: () => _askNoteThenDown(index),
              ),
              const Spacer(),
              _copyBtn(m, msg.content),
            ]),
          ]),
        ),
      ]),
    );
  }

  /// Tombol Salin jawaban asisten (setara `CopyBtn` web).
  Widget _copyBtn(MasColors m, String text) => Tooltip(
        message: 'Salin jawaban',
        child: InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: text));
            AppNav.of(context).toast('Jawaban disalin');
          },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.copy_rounded, size: 13, color: m.ink400),
              const SizedBox(width: 4),
              Text('Salin', style: TextStyle(fontSize: 10.5, color: m.ink400)),
            ]),
          ),
        ),
      );

  // _mdStyle DIPINDAH ke widgets/md_table.dart sbg `masMdStyle(m, dense:)` —
  // dipakai bersama layar riwayat Q&A admin (yang dulu tak punya properti tabel
  // sama sekali). Semua render jawaban asisten kini lewat `MasMarkdown`.

  Widget _typing(MasColors m) {
    // Draf token sudah mengalir → tampilkan ISI jawabannya, bukan lagi daftar
    // langkah. Begitu server membuang draf (`reset`), `_draf` kosong lagi dan
    // tampilan kembali ke langkah di bawah ini.
    if (_draf.isNotEmpty) return _drafBubble(m);
    // Saat streaming: tampilkan langkah live — ✓ untuk yang selesai, ⏳ untuk
    // yang sedang berjalan (langkah terakhir). Persis web.
    if (_steps.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _avatar(30),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: m.paper,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4), topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14),
                ),
                border: Border.all(color: m.ink150),
                boxShadow: m.shadow1,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < _steps.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i < _steps.length - 1 ? 4 : 0),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(i == _steps.length - 1 ? '⏳' : '✓',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(_steps[i],
                              style: TextStyle(
                                  fontSize: 13,
                                  color: i == _steps.length - 1 ? m.ink800 : m.ink400)),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ]),
      );
    }
    return Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          _avatar(30),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: m.paper,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4), topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14),
              ),
              border: Border.all(color: m.ink150),
            ),
            child: SizedBox(
              width: 18, height: 8,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (int i = 0; i < 3; i++) ...[
                  _Dot(delay: i * 0.15, color: m.ink400),
                  if (i < 2) const SizedBox(width: 4),
                ],
              ]),
            ),
          ),
        ]),
      );
  }

  /// Gelembung DRAF: jawaban mentah yang masih mengalir dan belum lewat guard.
  /// Dirender dengan markdown yang SAMA seperti jawaban final — tabel separuh
  /// jadi memang berkedip sesaat — tapi diredupkan + diberi titik mengetik agar
  /// jelas ini belum final. Tanpa footer (sumber/salin/👍👎) dan tanpa teks
  /// bisa diseleksi: itu hak jawaban final, yang menggantikannya beberapa detik
  /// lagi lewat frame `done`.
  Widget _drafBubble(MasColors m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _avatar(30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: 0.8,
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: m.paper,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4), topRight: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      ),
                      border: Border.all(color: m.ink150),
                      boxShadow: m.shadow1,
                    ),
                    child: MasMarkdown(data: _draf),
                  ),
                ),
                const SizedBox(height: 5),
                Row(children: [
                  SizedBox(
                    width: 18, height: 8,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (int i = 0; i < 3; i++) ...[
                        _Dot(delay: i * 0.15, color: m.ink400),
                        if (i < 2) const SizedBox(width: 4),
                      ],
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text('Menulis jawaban…',
                      style: TextStyle(fontSize: 10.5, color: m.ink400)),
                ]),
              ]),
        ),
      ]),
    );
  }

  // ── Kartu pertanyaan asisten (tool `tanya_user`) ────────────────────────
  // Aktif HANYA untuk pesan asisten TERAKHIR & belum ditutup user. Kartu di
  // pesan lama sengaja mati: pertanyaannya sudah basi.
  int _tanyaIdx = 0;
  final List<String> _tanyaJawab = [];
  bool _tanyaTutup = false;

  List<AIPertanyaan>? get _kartuAktif {
    if (_tanyaTutup || _busy || _msgs.isEmpty) return null;
    final t = _msgs.last;
    if (t.role != 'assistant' || t.pertanyaan.isEmpty) return null;
    return t.pertanyaan;
  }

  void _resetKartu() {
    _tanyaIdx = 0;
    _tanyaJawab.clear();
    _tanyaTutup = false;
  }

  void _jawabKartu(String opsi) {
    final kartu = _kartuAktif;
    if (kartu == null) return;
    while (_tanyaJawab.length <= _tanyaIdx) {
      _tanyaJawab.add('');
    }
    _tanyaJawab[_tanyaIdx] = opsi;
    if (_tanyaIdx + 1 < kartu.length) {
      setState(() => _tanyaIdx += 1);
      return;
    }
    // Satu pertanyaan -> kirim jawabannya apa adanya (paling alami di transkrip).
    // Beberapa -> sertakan teks pertanyaannya supaya tak ambigu.
    final teks = kartu.length == 1
        ? _tanyaJawab.first
        : [
            for (int i = 0; i < kartu.length; i++)
              '${kartu[i].teks} ${i < _tanyaJawab.length && _tanyaJawab[i].isNotEmpty ? _tanyaJawab[i] : "(dilewati)"}'
          ].join('\n');
    setState(() => _tanyaTutup = true);
    _send(teks);
  }

  void _lewatiKartu() {
    setState(() => _tanyaTutup = true);
    _send('(lewati) Lanjutkan dengan asumsi terbaik, dan sebutkan asumsinya.');
  }

  Widget _kartuTanya(MasColors m, List<AIPertanyaan> kartu) {
    final q = kartu[_tanyaIdx.clamp(0, kartu.length - 1)];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: m.ink200),
        boxShadow: m.shadow1,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(children: [
            Expanded(
              child: Text(q.teks,
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600, color: m.ink900)),
            ),
            if (kartu.length > 1)
              Text('${_tanyaIdx + 1} dari ${kartu.length}',
                  style: TextStyle(fontSize: 11.5, color: m.ink500)),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: m.ink500,
              tooltip: 'Tutup pertanyaan',
              onPressed: () => setState(() => _tanyaTutup = true),
            ),
          ]),
        ),
        for (int i = 0; i < q.opsi.length; i++)
          InkWell(
            onTap: () => _jawabKartu(q.opsi[i]),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: m.ink150))),
              child: Row(children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: m.canvas, borderRadius: BorderRadius.circular(5)),
                  child: Text('${i + 1}',
                      style: TextStyle(fontSize: 11.5, color: m.ink600)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(q.opsi[i],
                      style: TextStyle(fontSize: 13.5, color: m.ink900)),
                ),
              ]),
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: m.ink150))),
          child: Row(children: [
            Expanded(
              child: Text('Lainnya — tulis sendiri di bawah',
                  style: TextStyle(fontSize: 12.5, color: m.ink500)),
            ),
            TextButton(
              onPressed: _lewatiKartu,
              child: const Text('Lewati', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _inputBar(MasColors m) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final pending = _pendingSheet;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottom),
      decoration: BoxDecoration(
        color: m.paper,
        border: Border(top: BorderSide(color: m.ink150)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Kartu pertanyaan asisten — DI ATAS kolom input (sesuai mockup web):
        // persis di jalur mata user saat mau mengetik, dan tetap bisa diabaikan.
        if (_kartuAktif != null) _kartuTanya(m, _kartuAktif!),
        // Lampiran yang menunggu dikirim.
        if (pending != null) ...[
          _AttachmentBar(
            icon: Icons.table_chart_outlined,
            label: pending.filename,
            hint: 'Siap dikirim — tulis dulu maunya apa',
            onRemove: () => setState(() => _pendingSheet = null),
          ),
          const SizedBox(height: 8),
        ]
        // Lampiran aktif di server: selama chip ini ada, `sheetId` ikut di tiap
        // giliran, jadi asisten masih "memegang" file itu.
        else if (_sheetName.isNotEmpty) ...[
          _AttachmentBar(
            icon: Icons.attach_file_rounded,
            label: _sheetName,
            hint: 'Lampiran aktif di percakapan ini',
            onRemove: () => setState(() {
              _sheetId = '';
              _sheetName = '';
            }),
          ),
          const SizedBox(height: 8),
        ],
        // Hasil baca foto nomor rangka — bukan bubble chat: yang belum yakin
        // masih boleh dikoreksi user sebelum dikirim.
        if (_ocrNote != null) ...[
          _OcrNoteBar(
            teks: _ocrNote!.teks,
            ragu: _ocrNote!.ragu,
            onTutup: () => setState(() => _ocrNote = null),
          ),
          const SizedBox(height: 8),
        ],
        Row(children: [
          // Kamera = jawab permintaan nomor rangka dengan FOTO. Nomornya dibaca
          // server lalu dikirim sendiri sebagai pesan — tak ada yang menunggu
          // tombol Kirim (beda dengan lampiran Excel di sebelahnya).
          Tooltip(
            message: 'Foto nomor rangka — nomornya dibaca otomatis lalu dikirim',
            child: _sqBtn(m, Icons.photo_camera_outlined,
                _busy || _locked || _ocrBusy ? null : _pilihFotoRangka, false),
          ),
          const SizedBox(width: 8),
          // Klip = lampirkan Excel, persis tombol paperclip web. Memilih file
          // hanya MELAMPIRKAN; pengiriman menunggu user menekan Kirim.
          Tooltip(
            message: 'Lampirkan Excel (.xlsx) — asisten bisa isi stok / nama part / harga',
            child: _sqBtn(m, Icons.attach_file_rounded,
                _busy || _locked ? null : _pickSheet, false),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: m.canvas,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: m.ink200),
              ),
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                enabled: !_locked,
                textInputAction: TextInputAction.send,
                onSubmitted: _busy ? null : _send,
                cursorColor: m.brand600,
                style: TextStyle(fontSize: 13.5, color: m.ink900),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: _locked
                      ? 'Asisten AI tidak aktif'
                      : (pending != null
                          ? 'Mau diapakan filenya? (mis. isikan stoknya)'
                          : _kartuAktif != null
                              ? 'Atau balas langsung…'
                              : 'Tanya stok, harga, BOM per-VIN…'),
                  hintStyle: TextStyle(color: m.ink400, fontSize: 13.5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Saat menunggu, tombol Kirim BERUBAH jadi Stop — satu-satunya jalan
          // keluar dari giliran yang bisa berjalan sampai 4 menit.
          if (_busy)
            _sqBtn(m, Icons.stop_rounded, _stopGiliran, false)
          else
            _sqBtn(m, Icons.send_rounded,
                _locked ? null : () => _send(_ctrl.text), true),
        ]),
      ]),
    );
  }

  Widget _sqBtn(MasColors m, IconData icon, VoidCallback? onTap, bool primary) {
    return Material(
      color: primary ? m.brand600 : m.paper,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: primary ? null : Border.all(color: m.ink200),
          ),
          child: Icon(icon, size: 17, color: primary ? Colors.white : m.ink600),
        ),
      ),
    );
  }
}

// ── Unduhan ─────────────────────────────────────────────────────────
// Di Android/iOS aplikasi tak bisa menulis ke "folder Download" tanpa izin
// tambahan, jadi polanya sama dengan layar Data: tulis ke direktori sementara
// lalu serahkan ke aplikasi bawaan (Excel/WPS/Sheets) — user bisa "Simpan ke…".
Future<void> _simpanDanBuka(Uint8List bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/${_namaAman(filename)}');
  await f.writeAsBytes(bytes);
  await OpenFilex.open(f.path);
}

/// Nama file dari server/model bisa mengandung karakter yang haram di path.
String _namaAman(String s) {
  final base = s.trim().isEmpty ? 'export.xlsx' : s.trim();
  return base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

// ── Baris sumber (chip tool) + waktu ────────────────────────────────
// Disalin PERSIS dari `TOOL_LABELS` web (asisten/page.tsx) agar chip "Sumber:"
// menampilkan label yang sama. Tool yang tak ada di sini di-prettify otomatis
// (lihat _labelForTool) — sama seperti web.
const Map<String, String> _toolLabels = {
  'cari_part': 'Katalog part',
  'detail_part': 'Detail part',
  'info_aplikasi': 'Status aplikasi',
  'daftar_unit': 'Daftar unit',
  'cari_kode_kesalahan': 'Kode kesalahan',
  'diagram_wiring': 'Diagram wiring',
  'cari_filter_shantui': 'Filter Shantui',
  'jadwal_perawatan': 'Jadwal perawatan',
  'repair_kit_transmisi': 'Repair kit transmisi',
  'daftar_transmisi_assy': 'Transmisi assy',
  'banding_assy': 'Banding isi assy',
  'isi_assy': 'Isi assy',
  'banding_kategori': 'Banding kategori',
  'isi_kategori': 'Isi kategori',
  'part_termasuk_assy': 'Pelacak assy',
  'cek_kendaraan': 'EPC · spesifikasi VIN',
  'bom_dari_rangka': 'EPC · BOM unit',
  'banding_rangka': 'EPC · banding unit',
  'part_aus_dari_rangka': 'EPC · part per-VIN',
  'kategori_unit': 'EPC · kategori unit',
  'uraikan_assembly': 'EPC · isi assembly',
  'uraikan_mesin': 'EPC Weichai · mesin',
  'pengganti_part': 'EPC Weichai · pengganti',
  'repair_kit_mesin': 'EPC Weichai · repair kit',
  'unit_dari_part': 'EPC · unit pemakai',
  'cek_populasi': 'Populasi unit',
  'banding_part_armada': 'Banding part armada (populasi + EPC)',
  'pesanan_saya': 'Pesanan saya',
  'detail_pesanan': 'Detail pesanan',
  'rekap_penjualan': 'Rekap penjualan',
  'daftar_pesanan': 'Daftar pesanan',
  // Harga SIMS = harga MODAL, mata uang aslinya CNY. Asisten menyajikannya apa
  // adanya (tanpa konversi) kecuali user minta rupiah — sebut satuannya di label
  // supaya angkanya tak tertukar dengan harga jual Accurate yang ber-Rupiah.
  'harga_sims': 'Harga SIMS (CNY)',
  'buat_excel': 'Export Excel',
  'katalog_kategori': 'EPC · katalog bergambar',
  'sheet_ringkasan': 'Excel lampiran',
  'sheet_isi_kolom': 'Excel lampiran · isi kolom',
  'buat_penawaran': 'Accurate · Penawaran',
};

String _labelForTool(String t) =>
    _toolLabels[t] ?? t.replaceAll('_', ' ').replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());

class _SourceRow extends StatelessWidget {
  final String at;
  final List<String> tools;
  const _SourceRow({required this.at, required this.tools});
  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (tools.isNotEmpty)
          Text('Sumber:', style: TextStyle(fontSize: 10.5, color: m.ink400)),
        for (final t in tools.take(4))
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: m.ink100,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: m.ink200),
            ),
            child: Text(_labelForTool(t),
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: m.ink700)),
          ),
        Text(at, style: TextStyle(fontSize: 10.5, color: m.ink400)),
      ],
    );
  }
}

// ── Umpan balik 👍/👎 di bawah jawaban asisten ──────────────────────
class _FeedbackRow extends StatelessWidget {
  final String? rating;
  final VoidCallback onUp;
  final VoidCallback onDown;
  const _FeedbackRow({required this.rating, required this.onUp, required this.onDown});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final r = rating;
    // Sudah dinilai → hanya konfirmasi, tombol hilang (satu jawaban satu nilai).
    if (r != null) {
      final up = r == 'up';
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.thumb_up_alt_rounded : Icons.thumb_down_alt_rounded,
            size: 12, color: up ? m.brand700 : m.warn600),
        const SizedBox(width: 5),
        Text(up ? 'Terima kasih!' : 'Masukan terkirim — kami perbaiki.',
            style: TextStyle(fontSize: 10.5, color: up ? m.brand700 : m.warn600)),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _fbBtn(m, Icons.thumb_up_off_alt_rounded, 'Jawaban ini membantu', onUp),
      const SizedBox(width: 2),
      _fbBtn(m, Icons.thumb_down_off_alt_rounded, 'Jawaban ini kurang tepat', onDown),
    ]);
  }

  Widget _fbBtn(MasColors m, IconData icon, String tooltip, VoidCallback onTap) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 14, color: m.ink400),
          ),
        ),
      );
}

// ── Kartu unduh Excel (kerangka bersama) ────────────────────────────
class _ExcelCardShell extends StatelessWidget {
  final String judul;
  final String sub;
  final bool busy;
  final String? error;
  final VoidCallback onDownload;

  /// Label & ikon tombol. PDF (lembar diagnosa SPN/FMI, penawaran, katalog)
  /// memakai "Buka" karena langsung dirender pembaca PDF perangkat.
  final String actionLabel;
  final IconData actionIcon;

  const _ExcelCardShell({
    required this.judul,
    required this.sub,
    required this.busy,
    required this.error,
    required this.onDownload,
    this.actionLabel = 'Unduh',
    this.actionIcon = Icons.download_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: m.ink200),
        boxShadow: m.shadow1,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34, height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: m.brand50,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.table_chart_rounded, size: 18, color: m.brand700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(judul,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: m.ink900)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 11, color: m.ink500)),
            ]),
          ),
          const SizedBox(width: 8),
          Material(
            color: m.paper,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              onTap: busy ? null : onDownload,
              borderRadius: BorderRadius.circular(9),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: m.ink200),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (busy)
                    SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: m.brand600),
                    )
                  else
                    Icon(actionIcon, size: 14, color: m.ink700),
                  const SizedBox(width: 6),
                  Text(busy ? 'Menyiapkan…' : actionLabel,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: m.ink800)),
                ]),
              ),
            ),
          ),
        ]),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error!, style: TextStyle(fontSize: 11.5, color: m.danger600)),
        ],
      ]),
    );
  }
}

/// Excel yang DISUSUN asisten lewat tool `buat_excel` (mis. "buatkan excelnya").
class _AiExcelCard extends StatefulWidget {
  final AIExcelExport exp;
  const _AiExcelCard({required this.exp});
  @override
  State<_AiExcelCard> createState() => _AiExcelCardState();
}

class _AiExcelCardState extends State<_AiExcelCard> {
  bool _busy = false;
  String? _err;

  Future<void> _download() async {
    final exp = widget.exp;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final bytes = await ApiService.aiExcelExport(exp.id);
      await _simpanDanBuka(
          bytes, exp.filename.isNotEmpty ? exp.filename : '${exp.judul}.xlsx');
      if (!mounted) return;
      setState(() => _busy = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // File hasil buat_excel disimpan sementara di server; setelah kedaluwarsa
        // (404) minta asisten menyusunnya lagi — persis web.
        _err = e.statusCode == 404
            ? 'File sudah kedaluwarsa — minta asisten buatkan lagi.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Kanal ini juga membawa PDF, jadi pesannya generik (ikut web).
        _err = 'Gagal membuka file.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exp = widget.exp;
    final judul = exp.judul.isNotEmpty
        ? exp.judul
        : (exp.filename.isNotEmpty ? exp.filename : 'Export Excel');
    // Kanal ini membawa PDF juga, bukan cuma Excel: lembar diagnosa per-SPN/FMI,
    // penawaran, katalog bergambar. Sub-teksnya sengaja generik — dulu hardcoded
    // 'katalog bergambar' dan keliru untuk dua jenis lainnya.
    final isPdf = exp.filename.toLowerCase().endsWith('.pdf');
    final baris = exp.jumlahBaris > 0 ? ' · ${exp.jumlahBaris} baris' : '';
    final sub =
        isPdf ? 'PDF · ketuk untuk membuka' : 'Spreadsheet · XLSX$baris';
    return _ExcelCardShell(
      judul: judul,
      sub: sub,
      busy: _busy,
      error: _err,
      onDownload: _download,
      actionLabel: isPdf ? 'Buka' : 'Unduh',
      actionIcon:
          isPdf ? Icons.open_in_new_rounded : Icons.download_rounded,
    );
  }
}

/// Excel hasil perbandingan part dua unit (tool `banding_rangka`).
class _BandingExcelCard extends StatefulWidget {
  final AIBandingExport exp;
  const _BandingExcelCard({required this.exp});
  @override
  State<_BandingExcelCard> createState() => _BandingExcelCardState();
}

class _BandingExcelCardState extends State<_BandingExcelCard> {
  bool _busy = false;
  String? _err;

  Future<void> _download() async {
    final exp = widget.exp;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final bytes = await ApiService.aiBandingExport(
        rangka1: exp.rangka1,
        rangka2: exp.rangka2,
        kategori: exp.kategori,
      );
      await _simpanDanBuka(
          bytes, 'Perbandingan_${exp.rangka1}_vs_${exp.rangka2}.xlsx');
      if (!mounted) return;
      setState(() => _busy = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = 'Gagal mengunduh Excel.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exp = widget.exp;
    final kat = exp.kategoriNama.isNotEmpty ? ' · ${exp.kategoriNama}' : '';
    return _ExcelCardShell(
      judul: 'Perbandingan ${exp.rangka1} vs ${exp.rangka2}',
      sub: 'Spreadsheet · XLSX$kat',
      busy: _busy,
      error: _err,
      onDownload: _download,
    );
  }
}

/// Model transmisi yang dibahas asisten → tombol unduh Excel repair kit-nya.
class _RepairKitDownloads extends StatefulWidget {
  final List<String> models;
  const _RepairKitDownloads({required this.models});
  @override
  State<_RepairKitDownloads> createState() => _RepairKitDownloadsState();
}

class _RepairKitDownloadsState extends State<_RepairKitDownloads> {
  String? _dl;
  String? _err;

  Future<void> _download(String model) async {
    setState(() {
      _dl = model;
      _err = null;
    });
    try {
      final bytes = await ApiService.repairKitExport(model: model);
      await _simpanDanBuka(bytes, 'repairkit_transmisi_$model.xlsx');
      if (!mounted) return;
      setState(() => _dl = null);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _dl = null;
        _err = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dl = null;
        _err = 'Gagal mengunduh Excel.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final uniq = widget.models.where((e) => e.isNotEmpty).toSet().toList();
    if (uniq.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final model in uniq)
            Material(
              color: m.paper,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                onTap: _dl != null ? null : () => _download(model),
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: m.ink200),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_dl == model)
                      SizedBox(
                        width: 11, height: 11,
                        child: CircularProgressIndicator(strokeWidth: 2, color: m.brand600),
                      )
                    else
                      Icon(Icons.download_rounded, size: 13, color: m.ink700),
                    const SizedBox(width: 6),
                    Text(_dl == model ? 'Menyiapkan…' : 'Excel $model',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: m.ink800)),
                  ]),
                ),
              ),
            ),
        ],
      ),
      if (_err != null) ...[
        const SizedBox(height: 5),
        Text(_err!, style: TextStyle(fontSize: 11.5, color: m.danger600)),
      ],
    ]);
  }
}

// ── Ringkasan Excel lampiran ────────────────────────────────────────
const Map<String, String> _peranLabel = {
  'part_number': 'Part Number',
  'part_name': 'Nama part',
  'stok': 'Stok',
  'qty': 'Qty',
  'harga': 'Harga',
  'lain': '—',
};

/// Kolom apa saja yang DIKENALI server dari file unggahan. Ditampilkan agar
/// user cepat sadar kalau deteksinya meleset dan bisa mengoreksi lewat kalimat
/// ("kolom D itu part number").
class _SheetCard extends StatelessWidget {
  final AISheetSummary s;
  const _SheetCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final dikenali = s.kolom.where((k) => k.peran != 'lain').toList();
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: m.ink200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.table_chart_outlined, size: 16, color: m.brand700),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(s.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: m.ink900)),
              Text(
                'Sheet "${s.sheet}" · ${s.jumlahBaris} baris × ${s.jumlahKolom} kolom'
                '${s.terpotong ? ' (dipotong)' : ''}',
                style: TextStyle(fontSize: 11, color: m.ink500),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        if (dikenali.isEmpty)
          Text(
            'Tidak ada kolom yang dikenali otomatis — sebutkan kolom mana yang berisi Part Number.',
            style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.4),
          )
        else
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final k in dikenali)
                Container(
                  height: 21,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: m.ink100,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: m.ink200),
                  ),
                  child: Text('${k.nama} → ${_peranLabel[k.peran] ?? k.peran}',
                      style: TextStyle(fontSize: 10.5, color: m.ink700)),
                ),
            ],
          ),
        if (s.kolomPartNumber != null && s.kolomPartNumber!.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            '${s.partNumberDikenalDiKatalog} dari ${s.jumlahBaris} Part Number dikenal di katalog.',
            style: TextStyle(fontSize: 11, color: m.ink500),
          ),
        ],
      ]),
    );
  }
}

// Catatan: kelas _PhotoCandidates (thumbnail kandidat hasil pengenalan foto)
// dihapus — fitur ini dimatikan di web atas permintaan pemilik (2026-07-08).

// ── Chip lampiran ───────────────────────────────────────────────────

/// Chip nama file di gelembung pesan user (Excel yang ia lampirkan).
class _FileChip extends StatelessWidget {
  final String name;
  const _FileChip({required this.name});
  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: m.ink200),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.table_chart_outlined, size: 14, color: m.brand700),
        const SizedBox(width: 6),
        Flexible(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: m.ink700)),
        ),
      ]),
    );
  }
}

/// Baris lampiran di atas komposer (menunggu dikirim / aktif di server).
/// Catatan hasil baca FOTO nomor rangka (di atas kotak ketik).
///
/// [ragu] = bacaan belum pasti / gagal → warna peringatan, dan nomornya TIDAK
/// dikirim otomatis (sudah dituliskan ke kotak ketik untuk dikoreksi user).
class _OcrNoteBar extends StatelessWidget {
  final String teks;
  final bool ragu;
  final VoidCallback onTutup;
  const _OcrNoteBar({required this.teks, required this.ragu, required this.onTutup});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final fg = ragu ? const Color(0xFF92400E) : m.brand700;
    final bg = ragu ? const Color(0xFFFFFBEB) : m.brand50;
    final br = ragu ? const Color(0xFFFDE68A) : m.brand100;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: br),
      ),
      child: Row(children: [
        Icon(Icons.photo_camera_outlined, size: 15, color: fg),
        const SizedBox(width: 8),
        Expanded(
          child: Text(teks,
              style: TextStyle(fontSize: 12, color: fg, height: 1.35)),
        ),
        IconButton(
          icon: Icon(Icons.close_rounded, size: 15, color: fg),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          tooltip: 'Tutup',
          onPressed: onTutup,
        ),
      ]),
    );
  }
}

class _AttachmentBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onRemove;
  const _AttachmentBar({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
      decoration: BoxDecoration(
        color: m.brand50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: m.brand100),
      ),
      child: Row(children: [
        Icon(icon, size: 15, color: m.brand700),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: m.ink800)),
            Text(hint, style: TextStyle(fontSize: 10.5, color: m.ink500)),
          ]),
        ),
        IconButton(
          onPressed: onRemove,
          icon: Icon(Icons.close_rounded, size: 16, color: m.ink500),
          visualDensity: VisualDensity.compact,
          tooltip: 'Lepas lampiran',
        ),
      ]),
    );
  }
}

// Catatan: kelas _AttachTile (menu lampiran kamera/galeri/Excel) dihapus
// 2026-07-21 mengikuti web — fitur cari part dari foto di Asisten dibuang, dan
// tombol klip kini LANGSUNG membuka pemilih Excel tanpa menu perantara.

// ── Gambar exploded view (inline) ───────────────────────────────────
class _ExplodedImages extends StatelessWidget {
  final List<AiExplodedImage> images;
  const _ExplodedImages({required this.images});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Batas 6 gambar, sama dengan MAX_EXPLODED di web — jawaban yang
        // menyebut banyak part bisa membawa puluhan figure dan membanjiri layar.
        for (final img in images.take(_maxExploded))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ExplodedTile(img: img),
          ),
      ],
    );
  }
}

class _ExplodedTile extends StatefulWidget {
  final AiExplodedImage img;
  const _ExplodedTile({required this.img});
  @override
  State<_ExplodedTile> createState() => _ExplodedTileState();
}

class _ExplodedTileState extends State<_ExplodedTile> {
  Uint8List? _bytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    ApiService.aiImage(widget.img.id).then((b) {
      if (mounted) setState(() => _bytes = b);
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final img = widget.img;
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: m.ink200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_bytes != null)
          GestureDetector(
            onTap: () => _openFull(context, _bytes!),
            child: Container(color: Colors.white, child: Image.memory(_bytes!, fit: BoxFit.contain)),
          )
        else
          Container(
            height: 180,
            alignment: Alignment.center,
            child: _error
                ? Text('Gambar kedaluwarsa — minta lagi.', style: TextStyle(fontSize: 12, color: m.ink400))
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: m.brand100)),
                    const SizedBox(height: 10),
                    Text('Memuat gambar exploded view…', style: TextStyle(fontSize: 12, color: m.ink400)),
                  ]),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: m.ink100))),
          child: Row(children: [
            if (img.balon != null && img.balon!.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: m.brand600, borderRadius: BorderRadius.circular(999)),
                child: Text(img.balon!, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: img.pn ?? '', style: masMono(size: 12, weight: FontWeight.w600, color: m.ink800)),
                  if ((img.namaFigure ?? '').isNotEmpty)
                    TextSpan(text: ' · ${img.namaFigure}', style: TextStyle(fontSize: 12, color: m.ink500)),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  void _openFull(BuildContext context, Uint8List bytes) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.white,
      pageBuilder: (_, _, _) => Scaffold(
        // Latar putih penuh: gambar teknis EPC bergaris gelap & latar transparan,
        // di atas latar gelap garisnya tak terlihat.
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(children: [
            Center(
              child: InteractiveViewer(
                minScale: 1, maxScale: 5,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              right: 8, top: 8,
              child: Material(
                color: Colors.black12, shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context),
                  child: const SizedBox(width: 44, height: 44, child: Icon(Icons.close_rounded, color: Colors.black87)),
                ),
              ),
            ),
          ]),
        ),
      ),
    ));
  }
}

// Catatan: kelas _SimsThumbs (foto SIMS untuk PN yang disebut asisten) dihapus —
// fitur ini dimatikan di web atas permintaan pemilik (2026-07-08).

class _Dot extends StatefulWidget {
  final double delay;
  final Color color;
  const _Dot({required this.delay, required this.color});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = ((_c.value + widget.delay) % 1.0);
        final o = t < 0.3 ? (0.25 + (t / 0.3) * 0.75) : (t < 0.6 ? (1 - ((t - 0.3) / 0.3) * 0.75) : 0.25);
        return Opacity(
          opacity: o.clamp(0.25, 1.0),
          child: Container(width: 6, height: 6, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
        );
      },
    );
  }
}
