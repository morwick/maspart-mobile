// lib/screens/admin_pengetahuan_screen.dart — Pengetahuan Asisten AI (admin).
//
// Padanan halaman web `/admin/pengetahuan`. Admin menulis dan/atau mengunggah
// pengetahuan internal; server membedah isinya (termasuk tabel & gambar) jadi
// "bagian" (chunk) yang dicari asisten lewat tool `cari_pengetahuan`.
//
// Susunan mengikuti web, hanya dijadikan satu kolom vertikal: form tambah ·
// progres job · uji pencarian · daftar dokumen (kartu, bisa dibentangkan untuk
// mengurasi tiap bagian). Tabel web diganti kartu karena lebarnya tidak muat.

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api_service.dart'; // model Pengetahuan* ikut diekspor dari sini
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';

/// Selang polling status indexing. Sama dengan `POLL_MS` di web — indexing PDF
/// besar bisa puluhan detik, admin perlu melihat progresnya bergerak.
const Duration _pollTiap = Duration(seconds: 2);

class PengetahuanScreen extends StatefulWidget {
  const PengetahuanScreen({super.key});

  @override
  State<PengetahuanScreen> createState() => _PengetahuanScreenState();
}

class _PengetahuanScreenState extends State<PengetahuanScreen> {
  List<PengetahuanDok> _docs = [];
  int _jumlahChunk = 0;
  bool _loading = true;
  String? _error;
  String? _info;

  // ── Form tambah ──
  final _judul = TextEditingController();
  final _deskripsi = TextEditingController();
  final _teks = TextEditingController();
  final _tabel = TextEditingController();
  final _tag = TextEditingController();
  bool _untukPembeli = false;
  bool _pakaiAi = true;
  List<({Uint8List bytes, String filename})> _files = [];
  bool _saving = false;

  /// Dokumen yang sedang diindeks (job berjalan) + timer pollingnya.
  String _jobId = '';
  Timer? _poll;

  /// Dokumen yang sedang dibentangkan untuk kurasi + isinya.
  String _dibuka = '';
  List<PengetahuanChunk> _chunks = [];
  bool _chunkLoading = false;

  /// Id dokumen yang aksinya sedang berjalan ('semua' = reindex massal).
  String _busyId = '';

  /// Saring daftar ke entri yang diajarkan lewat chat saja — admin biasanya
  /// ingin meninjau yang baru diajari asisten tanpa menyisir seluruh daftar.
  bool _dariChat = false;

  // ── Uji pencarian ──
  final _uji = TextEditingController();
  List<PengetahuanChunk>? _ujiHasil;
  bool _ujiBusy = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _judul.dispose();
    _deskripsi.dispose();
    _teks.dispose();
    _tabel.dispose();
    _tag.dispose();
    _uji.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.pengetahuan();
      if (!mounted) return;
      setState(() {
        _docs = d.dokumen;
        _jumlahChunk = d.jumlahChunk;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  // ── Polling status job ────────────────────────────────────────────────
  void _mulaiPolling(String id) {
    _poll?.cancel();
    setState(() => _jobId = id);
    _poll = Timer.periodic(_pollTiap, (_) => _tarikStatus(id));
  }

  void _hentikanPolling() {
    _poll?.cancel();
    _poll = null;
    if (mounted) setState(() => _jobId = '');
  }

  Future<void> _tarikStatus(String id) async {
    try {
      final s = await ApiService.pengetahuanStatus(id);
      if (!mounted) return;
      setState(() {
        _docs = [
          for (final d in _docs) d.id == id ? d.salinStatus(s) : d,
        ];
      });
      if (!s.selesaiDiproses) return;
      _hentikanPolling();
      setState(() => _info = s.status == 'gagal'
          ? 'Indexing gagal: ${s.error}'
          : 'Indexing selesai — ${s.jumlahChunk} bagian terindeks'
              '${s.error.isNotEmpty ? " (dengan catatan: ${s.error})" : ""}');
      await _muat();
      // Isi yang sedang dibentangkan ikut disegarkan supaya chunk baru tampil.
      if (_dibuka == id) await _muatChunk(id);
    } on ApiException {
      // Dokumen mungkin sudah dihapus — hentikan polling, jangan spam error.
      _hentikanPolling();
    }
  }

  // ── Tambah pengetahuan ────────────────────────────────────────────────
  /// Teks tabel tempel-dari-Excel (TSV/CSV) → matriks. Sama dengan `parseTabel`
  /// di web: satu baris per baris tabel, sel dipisah tab / titik-koma / koma.
  List<List<String>> _parseTabel(String raw) => raw
      .split(RegExp(r'\r?\n'))
      .map((ln) => ln.trim())
      .where((ln) => ln.isNotEmpty)
      .map((ln) => ln.split(RegExp(r'\t|;|,')).map((s) => s.trim()).toList())
      .toList();

  void _bersihkanForm() {
    _judul.clear();
    _deskripsi.clear();
    _teks.clear();
    _tabel.clear();
    _tag.clear();
    setState(() {
      _untukPembeli = false;
      _pakaiAi = true;
      _files = [];
    });
  }

  Future<void> _pilihBerkas() async {
    try {
      // file_picker v11: API STATIS. `withData` wajib — unggahan dikirim
      // multipart dari memori dan path tidak selalu ada (mis. Google Drive).
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ApiService.pengetahuanEkstensi,
        allowMultiple: true,
        withData: true,
      );
      if (res == null || !mounted) return;
      setState(() {
        _files = [
          for (final f in res.files)
            if (f.bytes case final b?) (bytes: b, filename: f.name),
        ];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal membuka berkas: $e');
    }
  }

  Future<void> _simpan() async {
    if (_judul.text.trim().isEmpty) {
      setState(() => _error = 'Judul wajib diisi.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _info = null;
    });
    try {
      final id = await ApiService.addPengetahuan(
        judul: _judul.text.trim(),
        deskripsi: _deskripsi.text,
        teks: _teks.text,
        tabel: _tabel.text.trim().isEmpty ? const [] : _parseTabel(_tabel.text),
        tag: _tag.text,
        untukPembeli: _untukPembeli,
        pakaiAi: _pakaiAi,
        files: _files,
      );
      if (!mounted) return;
      _bersihkanForm();
      setState(() => _info = 'Pengetahuan tersimpan — sedang diindeks di latar.');
      await _muat();
      if (mounted) _mulaiPolling(id);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Aksi per dokumen ──────────────────────────────────────────────────
  Future<void> _jalankan(String id, Future<void> Function() aksi) async {
    setState(() {
      _busyId = id;
      _error = null;
    });
    try {
      await aksi();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  Future<void> _togglePublik(PengetahuanDok d) async {
    if (!d.untukPembeli) {
      final ok = await _konfirmasi(
        context,
        judul: 'Publikasikan ke pembeli?',
        pesan: 'Seluruh isi "${d.judul}" akan bisa dibaca akun pembeli lewat '
            'Asisten AI. Pastikan tidak ada data internal (harga modal, stok '
            'gudang, catatan pribadi) di dalamnya.',
        tombol: 'Publikasikan',
        bahaya: true,
      );
      if (!ok || !mounted) return;
    }
    await _jalankan(d.id, () async {
      await ApiService.updatePengetahuan(d.id, untukPembeli: !d.untukPembeli);
      await _muat();
    });
  }

  Future<void> _toggleAktif(PengetahuanDok d) => _jalankan(d.id, () async {
        await ApiService.updatePengetahuan(d.id, aktif: !d.aktif);
        await _muat();
      });

  Future<void> _hapus(PengetahuanDok d) async {
    final ok = await _konfirmasi(
      context,
      judul: 'Hapus pengetahuan?',
      pesan: '"${d.judul}" beserta seluruh isi terindeksnya dihapus. '
          'Asisten tidak akan bisa memakainya lagi.',
      tombol: 'Hapus',
      bahaya: true,
    );
    if (!ok || !mounted) return;
    await _jalankan(d.id, () async {
      await ApiService.deletePengetahuan(d.id);
      if (_dibuka == d.id) {
        _dibuka = '';
        _chunks = [];
      }
      if (_jobId == d.id) _hentikanPolling();
      await _muat();
    });
  }

  Future<void> _reindex(PengetahuanDok d) => _jalankan(d.id, () async {
        await ApiService.reindexPengetahuan(d.id);
        if (!mounted) return;
        setState(() => _info = '"${d.judul}" diantre untuk diindeks ulang.');
        _mulaiPolling(d.id);
      });

  Future<void> _reindexSemua() async {
    final perlu = _docs.where((d) => d.perluReindex).toList();
    if (perlu.isEmpty) return;
    final ok = await _konfirmasi(
      context,
      judul: 'Indeks ulang ${perlu.length} dokumen?',
      pesan: 'Dokumen berskema lama akan dibedah ulang agar gambar di dalam '
          'berkas, breadcrumb bab, dan nama kolom tabel ikut terambil. Kurasi '
          'manual (judul & kata kunci yang Anda perbaiki) dipertahankan. Job '
          'berjalan satu per satu di latar, jadi bisa memakan waktu.',
      tombol: 'Indeks ulang',
    );
    if (!ok || !mounted) return;
    await _jalankan('semua', () async {
      // Antrian server berjalan SERIAL, jadi mengirim semuanya sekaligus aman
      // untuk RAM — tak ada dua dokumen besar diproses bersamaan.
      for (final d in perlu) {
        await ApiService.reindexPengetahuan(d.id);
      }
      if (!mounted) return;
      setState(() =>
          _info = '${perlu.length} dokumen diantre untuk diindeks ulang.');
      await _muat();
      if (mounted) _mulaiPolling(perlu.last.id);
    });
  }

  // ── Kurasi bagian (chunk) ─────────────────────────────────────────────
  Future<void> _buka(PengetahuanDok d) async {
    if (_dibuka == d.id) {
      setState(() {
        _dibuka = '';
        _chunks = [];
      });
      return;
    }
    setState(() {
      _dibuka = d.id;
      _chunks = [];
    });
    await _muatChunk(d.id);
  }

  Future<void> _muatChunk(String id) async {
    setState(() => _chunkLoading = true);
    try {
      final res = await ApiService.pengetahuanDetail(id);
      if (!mounted || _dibuka != id) return;
      setState(() {
        _chunks = res.chunk;
        _chunkLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _chunkLoading = false;
      });
    }
  }

  /// Simpan perubahan satu bagian. Optimistis: UI dipakai lebih dulu, kalau
  /// server menolak isinya dimuat ulang supaya tak ada kurasi palsu di layar.
  Future<void> _simpanChunk(
    PengetahuanChunk c, {
    String? judulId,
    List<String>? kataKunci,
    bool? dicari,
  }) async {
    try {
      final baru = await ApiService.updatePengetahuanChunk(
        c.dokId.isEmpty ? _dibuka : c.dokId,
        c.seq,
        judulId: judulId,
        kataKunci: kataKunci,
        dicari: dicari,
      );
      if (!mounted) return;
      setState(() {
        _chunks = [
          for (final x in _chunks) x.id == c.id ? baru : x,
        ];
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      await _muatChunk(_dibuka);
    }
  }

  // ── Uji pencarian ─────────────────────────────────────────────────────
  Future<void> _jalankanUji() async {
    final q = _uji.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _ujiBusy = true;
      _error = null;
    });
    try {
      final hasil = await ApiService.cariPengetahuan(q);
      if (mounted) setState(() => _ujiHasil = hasil);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _ujiBusy = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final perluReindex = _docs.where((d) => d.perluReindex).length;
    final jumlahChat = _docs.where((d) => d.asal == 'chat').length;
    // Saringan hanya berlaku bila memang ada entri chat — kalau entri terakhir
    // terhapus, daftar kembali penuh dan tidak menyisakan layar kosong.
    final saringChat = _dariChat && jumlahChat > 0;
    final tampil =
        saringChat ? _docs.where((d) => d.asal == 'chat').toList() : _docs;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (_error != null) ...[
          _KotakError(_error!),
          const SizedBox(height: 12),
        ],
        if (_info != null) ...[
          _KotakInfo(_info!),
          const SizedBox(height: 12),
        ],

        _formTambah(m),
        const SizedBox(height: 14),

        if (_jobId.isNotEmpty) ...[
          _kartuProgres(m),
          const SizedBox(height: 14),
        ],

        _kartuUji(m),
        const SizedBox(height: 14),

        Row(children: [
          Expanded(
            // Angka di judul mengikuti apa yang benar-benar tampil; saat
            // tersaring sebutkan totalnya agar tidak terbaca seperti kehilangan
            // data.
            child: Text(
                'Pengetahuan tersimpan (${tampil.length}'
                '${saringChat ? " dari ${_docs.length}" : ""})',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: m.ink900)),
          ),
          Text('$_jumlahChunk bagian',
              style: TextStyle(fontSize: 11.5, color: m.ink500)),
        ]),
        if (jumlahChat > 0) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => setState(() => _dariChat = !_dariChat),
              child: MasPill(
                label: '${saringChat ? "✕ " : ""}dari chat ($jumlahChat)',
                tone: saringChat ? MasPillTone.brand : MasPillTone.neutral,
              ),
            ),
          ),
        ],
        if (perluReindex > 0) ...[
          const SizedBox(height: 8),
          MasButton(
            label: 'Indeks ulang yang perlu ($perluReindex)',
            primary: false,
            expand: true,
            loading: _busyId == 'semua',
            onTap: _busyId.isNotEmpty || _jobId.isNotEmpty ? null : _reindexSemua,
          ),
        ],
        const SizedBox(height: 10),

        if (_loading)
          const MasSkeleton(height: 200)
        else if (_docs.isEmpty)
          const MasEmpty(
            icon: Icons.auto_stories_outlined,
            title: 'Belum ada pengetahuan',
            subtitle: 'Tambahkan lewat form di atas — tulis langsung atau '
                'lampirkan berkas.',
          )
        else
          for (final d in tampil) ...[
            _kartuDokumen(m, d),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  // ── Form tambah ───────────────────────────────────────────────────────
  Widget _formTambah(MasColors m) => MasSectionCard(
        title: 'Tambah pengetahuan',
        children: [
          Text(
            'Tulis langsung dan/atau lampirkan berkas (PDF, Excel, Word, CSV, '
            'TXT, gambar). Server membaca isinya — termasuk tabel dan gambar di '
            'dalamnya — lalu mengindeksnya supaya bisa ditemukan Asisten AI.',
            style: TextStyle(fontSize: 12, color: m.ink500, height: 1.55),
          ),
          const SizedBox(height: 12),
          MasInput(
              controller: _judul,
              hint: 'Judul — mis. Prosedur Retur Barang'),
          const SizedBox(height: 8),
          MasInput(
              controller: _deskripsi, hint: 'Deskripsi singkat (opsional)'),
          const SizedBox(height: 8),
          MasInput(
            controller: _teks,
            hint: 'Isi pengetahuan — tulis apa adanya, boleh panjang.',
            maxLines: 6,
          ),
          const SizedBox(height: 8),
          MasInput(
            controller: _tabel,
            hint: 'Tabel (opsional) — tempel dari Excel, satu baris per baris '
                'tabel.',
            maxLines: 4,
          ),
          const SizedBox(height: 8),
          MasInput(
            controller: _tag,
            hint: 'Tag pencarian, pisahkan koma (opsional) — mis. retur, garansi',
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: MasButton(
                label: _files.isEmpty
                    ? 'Pilih berkas'
                    : '${_files.length} berkas dipilih',
                icon: Icons.attach_file_rounded,
                primary: false,
                expand: true,
                onTap: _saving ? null : _pilihBerkas,
              ),
            ),
            if (_files.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Kosongkan pilihan berkas',
                onPressed: _saving ? null : () => setState(() => _files = []),
                icon: Icon(Icons.close_rounded, size: 18, color: m.ink500),
              ),
            ],
          ]),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final f in _files)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${f.filename}  ${_ukuran(f.bytes.lengthInBytes)}',
                  style: TextStyle(fontSize: 11.5, color: m.ink600),
                ),
              ),
          ],
          const SizedBox(height: 10),
          _Centang(
            value: _pakaiAi,
            label: 'Perkaya dengan AI',
            subtitle: 'Judul & kata kunci Indonesia dibuat otomatis',
            onChanged: _saving ? null : (v) => setState(() => _pakaiAi = v),
          ),
          _Centang(
            value: _untukPembeli,
            label: 'Boleh dibaca PEMBELI',
            subtitle: 'Seluruh isinya terbuka lewat Asisten AI akun pembeli',
            bahaya: true,
            onChanged: _saving ? null : (v) => setState(() => _untukPembeli = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: MasButton(
                label: 'Simpan & indeks',
                icon: Icons.check_rounded,
                expand: true,
                loading: _saving,
                onTap: _saving ? null : _simpan,
              ),
            ),
            const SizedBox(width: 8),
            MasButton(
              label: 'Bersihkan',
              primary: false,
              onTap: _saving ? null : _bersihkanForm,
            ),
          ]),
        ],
      );

  // ── Progres job ───────────────────────────────────────────────────────
  Widget _kartuProgres(MasColors m) {
    final d = _docs.where((x) => x.id == _jobId).firstOrNull;
    if (d == null) return const SizedBox.shrink();
    final p = d.progres;
    return MasSectionCard(
      title: 'Mengindeks "${d.judul}"',
      children: [
        Text(
          '${p.langkah.isEmpty ? "Menyiapkan" : p.langkah}'
          '${p.total > 0 ? " — ${p.kini}/${p.total}" : ""}',
          style: TextStyle(fontSize: 12, color: m.ink600),
        ),
        const SizedBox(height: 8),
        // Minimal 5% agar bar tidak terlihat mati saat langkah pertama.
        MasBar(value: (p.persen <= 0 ? 5 : p.persen) / 100, height: 8),
      ],
    );
  }

  // ── Uji pencarian ─────────────────────────────────────────────────────
  Widget _kartuUji(MasColors m) {
    final hasil = _ujiHasil;
    return MasSectionCard(
      title: 'Uji pencarian',
      children: [
        Text('Lihat persis apa yang ditemukan Asisten AI untuk sebuah pertanyaan.',
            style: TextStyle(fontSize: 12, color: m.ink500, height: 1.5)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: MasInput(
              controller: _uji,
              hint: 'mis. cara retur barang',
              action: TextInputAction.search,
              onSubmitted: (_) => _jalankanUji(),
            ),
          ),
          const SizedBox(width: 8),
          MasButton(
            label: 'Cari',
            primary: false,
            loading: _ujiBusy,
            onTap: _ujiBusy ? null : _jalankanUji,
          ),
        ]),
        if (hasil != null) ...[
          const SizedBox(height: 10),
          if (hasil.isEmpty)
            Text(
              'Tidak ada yang cocok — tambahkan kata kunci pada bagian terkait '
              'supaya bisa ditemukan.',
              style: TextStyle(fontSize: 12.5, color: m.danger600, height: 1.5),
            )
          else
            for (final (i, h) in hasil.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${i + 1}. ${h.judulTampil}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: m.ink900)),
                  TextSpan(
                      text: ' — ${h.sumber}'
                          '${h.halaman > 0 ? " hal ${h.halaman}" : ""}',
                      style: TextStyle(fontSize: 12.5, color: m.ink500)),
                ])),
              ),
        ],
      ],
    );
  }

  // ── Kartu dokumen ─────────────────────────────────────────────────────
  Widget _kartuDokumen(MasColors m, PengetahuanDok d) {
    final terbuka = _dibuka == d.id;
    final sibuk = _busyId == d.id;
    // Entri hasil "ajarkan lewat chat" tidak punya berkas dan bukan hasil
    // ketikan di form ini — tanpa penanda ia tampak seperti entri manual,
    // padahal asalnya beda (dan siapa yang mengajari itu penting saat audit).
    final sumber = d.asal == 'chat'
        ? '💬 dari chat${d.oleh.isEmpty ? "" : " · ${d.oleh}"}'
        : d.berkas.isEmpty
            ? 'diketik admin'
            : d.berkas.map((b) => b.nama).join(', ');

    return Opacity(
      opacity: d.aktif ? 1 : 0.6,
      child: MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => _buka(d),
            child: Row(children: [
              Icon(
                terbuka
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 20,
                color: m.ink500,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(d.judul,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: m.ink900)),
                    if (d.deskripsi.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(d.deskripsi,
                          style: TextStyle(fontSize: 11.5, color: m.ink500)),
                    ],
                  ],
                ),
              ),
              MasPill(label: d.statusLabel, tone: _tone(d.status)),
            ]),
          ),
          const SizedBox(height: 8),
          Text(
            '$sumber · ${d.jumlahChunk} bagian · pengayaan ${d.pengayaanLabel}',
            style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.45),
          ),
          if (d.perluReindex) ...[
            const SizedBox(height: 6),
            Text(
              'Skema lama — indeks ulang agar gambar di dalam berkas, '
              'breadcrumb bab, dan nama kolom tabel ikut terambil.',
              style: TextStyle(fontSize: 11, color: m.warn600, height: 1.45),
            ),
          ],
          if (d.error.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(d.error,
                style: TextStyle(fontSize: 11, color: m.ink500, height: 1.45)),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _AksiKecil(
              label: d.untukPembeli ? 'Publik' : 'Internal',
              icon: d.untukPembeli
                  ? Icons.public_rounded
                  : Icons.lock_outline_rounded,
              bahaya: d.untukPembeli,
              onTap: sibuk ? null : () => _togglePublik(d),
            ),
            _AksiKecil(
              label: 'Indeks ulang',
              icon: Icons.refresh_rounded,
              onTap: sibuk || _jobId.isNotEmpty ? null : () => _reindex(d),
            ),
            _AksiKecil(
              label: d.aktif ? 'Nonaktifkan' : 'Aktifkan',
              icon: d.aktif
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              onTap: sibuk ? null : () => _toggleAktif(d),
            ),
            _AksiKecil(
              label: 'Hapus',
              icon: Icons.delete_outline_rounded,
              bahaya: true,
              onTap: sibuk ? null : () => _hapus(d),
            ),
          ]),
          if (terbuka) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: m.ink100),
            const SizedBox(height: 12),
            if (_chunkLoading)
              const MasSkeleton(height: 90)
            else if (_chunks.isEmpty)
              Text('Belum ada bagian terindeks.',
                  style: TextStyle(fontSize: 12, color: m.ink500))
            else ...[
              Text(
                'Perbaiki judul & kata kunci di sini bila hasil pencarian kurang '
                'tepat — inilah yang dipakai untuk mencocokkan pertanyaan user.',
                style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.5),
              ),
              const SizedBox(height: 10),
              for (final c in _chunks) ...[
                _KartuChunk(
                  key: ValueKey(c.id),
                  chunk: c,
                  onSimpan: (judulId, kataKunci, dicari) => _simpanChunk(
                    c,
                    judulId: judulId,
                    kataKunci: kataKunci,
                    dicari: dicari,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ]),
      ),
    );
  }

  MasPillTone _tone(String status) => switch (status) {
        'selesai' => MasPillTone.brand,
        'gagal' => MasPillTone.danger,
        'selesai_sebagian' => MasPillTone.warn,
        _ => MasPillTone.neutral,
      };
}

String _ukuran(int b) {
  if (b <= 0) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

// ── Satu bagian (chunk) yang bisa dikurasi ─────────────────────────────
//
// StatefulWidget tersendiri karena punya dua TextEditingController: kurasi
// disimpan saat field KEHILANGAN FOKUS (pola web `onBlur`), bukan tiap ketikan.
class _KartuChunk extends StatefulWidget {
  final PengetahuanChunk chunk;
  final void Function(String? judulId, List<String>? kataKunci, bool? dicari)
      onSimpan;

  const _KartuChunk({super.key, required this.chunk, required this.onSimpan});

  @override
  State<_KartuChunk> createState() => _KartuChunkState();
}

class _KartuChunkState extends State<_KartuChunk> {
  late final TextEditingController _judul;
  late final TextEditingController _kunci;
  final _fJudul = FocusNode();
  final _fKunci = FocusNode();

  @override
  void initState() {
    super.initState();
    _judul = TextEditingController(text: widget.chunk.judulId);
    _kunci = TextEditingController(text: widget.chunk.kataKunci.join(', '));
    _fJudul.addListener(() {
      if (!_fJudul.hasFocus && _judul.text != widget.chunk.judulId) {
        widget.onSimpan(_judul.text.trim(), null, null);
      }
    });
    _fKunci.addListener(() {
      if (_fKunci.hasFocus) return;
      final baru = _kunci.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (baru.join(' ') != widget.chunk.kataKunci.join(' ')) {
        widget.onSimpan(null, baru, null);
      }
    });
  }

  @override
  void dispose() {
    _judul.dispose();
    _kunci.dispose();
    _fJudul.dispose();
    _fKunci.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final c = widget.chunk;

    // Hasil ekstraksi V2 — supaya admin bisa MELIHAT apakah pembedahan dokumen
    // berhasil, bukan menebak dari hasil pencarian saja.
    final v2 = <String>[
      if (c.jalur.isNotEmpty) c.jalur.join(' › '),
      if (c.kolom.isNotEmpty) 'kolom: ${c.kolom.join(", ")}',
      if (c.barisTotal > 0) '${c.barisTotal} baris',
    ].join(' · ');

    final meta = <String>[
      c.sumber,
      if (c.halaman > 0) 'hal ${c.halaman}',
      if (c.tipe.isNotEmpty) c.tipe,
      if (c.bahasa.isNotEmpty && c.bahasa != 'id') 'bahasa ${c.bahasa}',
      if (c.kurasi) 'dikurasi admin',
    ].where((s) => s.isNotEmpty).join(' · ');

    final captions =
        c.gambarInfo.where((g) => g.caption.isNotEmpty).map((g) => g.caption);
    final gambarLabel = c.gambarRef.isEmpty
        ? ''
        : '${c.gambarRef.length} gambar · '
            '${captions.isEmpty ? "tanpa keterangan" : _potong(captions.join(" | "), 160)}';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: m.canvas,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.ink150),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(meta, style: TextStyle(fontSize: 11, color: m.ink400)),
        if (v2.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(v2, style: TextStyle(fontSize: 11, color: m.ink500)),
        ],
        const SizedBox(height: 8),
        MasInput(
            controller: _judul, focusNode: _fJudul, hint: 'Judul bagian (ID)'),
        const SizedBox(height: 6),
        MasInput(
          controller: _kunci,
          focusNode: _fKunci,
          hint: 'kata kunci, pisahkan koma',
        ),
        const SizedBox(height: 4),
        _Centang(
          value: c.dicari,
          label: 'Ikut dicari asisten',
          onChanged: (v) => widget.onSimpan(null, null, v),
        ),
        if (c.ringkasan.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(c.ringkasan,
              style: TextStyle(fontSize: 12, color: m.ink600, height: 1.45)),
        ],
        if (c.teks.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(_potong(c.teks, 400),
              style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.45)),
        ],
        if (gambarLabel.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(gambarLabel, style: TextStyle(fontSize: 11, color: m.ink400)),
        ],
      ]),
    );
  }
}

String _potong(String s, int n) => s.length <= n ? s : s.substring(0, n);

// ── Komponen kecil ─────────────────────────────────────────────────────

/// Baris centang dengan label + keterangan. `bahaya` = merah (aksi sensitif).
class _Centang extends StatelessWidget {
  final bool value;
  final String label;
  final String? subtitle;
  final bool bahaya;
  final ValueChanged<bool>? onChanged;

  const _Centang({
    required this.value,
    required this.label,
    this.subtitle,
    this.bahaya = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final warna = bahaya && value ? m.danger600 : m.ink800;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: value,
              onChanged:
                  onChanged == null ? null : (v) => onChanged!(v ?? false),
              activeColor: bahaya ? m.danger600 : m.brand600,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: warna)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(subtitle!,
                        style: TextStyle(fontSize: 11, color: m.ink500)),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Tombol aksi kecil pada kartu dokumen.
class _AksiKecil extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool bahaya;
  final VoidCallback? onTap;

  const _AksiKecil({
    required this.label,
    required this.icon,
    this.bahaya = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final mati = onTap == null;
    final fg = mati
        ? m.ink400
        : bahaya
            ? m.danger600
            : m.ink700;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MasRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MasRadii.pill),
          border: Border.all(color: mati ? m.ink150 : m.ink200),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
        ]),
      ),
    );
  }
}

class _KotakError extends StatelessWidget {
  final String message;
  const _KotakError(this.message);

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: m.danger50,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.dangerBorder),
      ),
      child: Text(message,
          style: TextStyle(fontSize: 12.5, color: m.danger600, height: 1.45)),
    );
  }
}

class _KotakInfo extends StatelessWidget {
  final String message;
  const _KotakInfo(this.message);

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: m.brand50,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.brand100),
      ),
      child: Text(message,
          style: TextStyle(fontSize: 12.5, color: m.brand700, height: 1.45)),
    );
  }
}

Future<bool> _konfirmasi(
  BuildContext context, {
  required String judul,
  required String pesan,
  String tombol = 'Lanjut',
  bool bahaya = false,
}) async {
  final m = context.mas;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(judul, style: const TextStyle(fontSize: 16)),
      content: Text(pesan, style: const TextStyle(fontSize: 13.5, height: 1.5)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tombol,
              style: TextStyle(
                  color: bahaya ? m.danger600 : m.brand700,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok == true;
}
