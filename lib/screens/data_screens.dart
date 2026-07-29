// lib/screens/data_screens.dart
// Layar DATA — semuanya mengambil data ASLI dari API (tidak ada contoh statis):
//   • StokScreen     — indeks stok Accurate + rincian per gudang (on-demand)
//   • PopulasiScreen — populasi unit + filter dinamis + salin nomor rangka
//   • CompareScreen  — interchange 2 part (foto SIMS + kemiripan nama)
//   • BatchScreen    — katalog Excel banyak PN sekaligus
//   • OpnameScreen   — stok opname (unggah → hitung fisik → finalisasi)
//
// Menggantikan layar contoh berdata hardcoded di `admin_screens.dart`.
// Perilaku mengikuti halaman web padanannya (stok/populasi/compare/batch/opname).

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/mas_ui.dart';

const _pageSize = 50;

// ══════════════════════════════════════════════════════════════════════
// Helper bersama
// ══════════════════════════════════════════════════════════════════════

/// Simpan hasil ekspor lalu buka dengan aplikasi bawaan perangkat.
///
/// Di Android/iOS tidak ada "folder Download" yang bisa ditulis aplikasi tanpa
/// izin tambahan, jadi polanya: tulis ke direktori sementara → serahkan ke
/// OpenFilex (Excel/WPS/Sheets). User bisa "Simpan ke…" dari sana.
Future<void> _simpanDanBuka(Uint8List bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$filename');
  await f.writeAsBytes(bytes);
  await OpenFilex.open(f.path);
}

/// Ambil file dari perangkat dengan byte-nya sekaligus (`withData`) — API kita
/// mengirim multipart dari memori, bukan dari path (path tidak selalu ada,
/// mis. file dari Google Drive).
Future<({Uint8List bytes, String filename})?> _pilihFile(
  List<String> ekstensi,
) async {
  final res = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ekstensi,
    withData: true,
  );
  final f = res?.files.first;
  final b = f?.bytes;
  if (f == null || b == null) return null;
  return (bytes: b, filename: f.name);
}

/// Waktu ISO dari backend ("2026-07-13T04:12:33Z") → tampilan ringkas.
String _waktu(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  return iso.replaceFirst('T', ' ').replaceFirst('Z', '').split('.').first;
}

/// Kotak error merah — dipakai untuk `ApiException.message` di semua layar.
class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

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

/// Kotak peringatan kuning — masalah yang bisa pulih sendiri (sesi Accurate).
class _NoticeBox extends StatelessWidget {
  final String message;
  const _NoticeBox(this.message);

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: m.warn50,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.warnBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: 16, color: m.warn600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: TextStyle(fontSize: 12.5, color: m.warn600, height: 1.45)),
        ),
      ]),
    );
  }
}

/// Kotak info hijau — konfirmasi aksi berhasil (draft tersimpan, dll).
class _InfoBox extends StatelessWidget {
  final String message;
  const _InfoBox(this.message);

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

/// Paginasi server-side (halaman N dari M).
class _Pager extends StatelessWidget {
  final int page;
  final int totalPages;
  final bool busy;
  final ValueChanged<int> onGo;
  const _Pager({
    required this.page,
    required this.totalPages,
    required this.busy,
    required this.onGo,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    if (totalPages <= 1) return const SizedBox.shrink();
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      MasButton(
        label: 'Sebelumnya',
        icon: Icons.chevron_left_rounded,
        primary: false,
        height: 36,
        onTap: (page <= 1 || busy) ? null : () => onGo(page - 1),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('Hal $page / $totalPages',
            style: TextStyle(fontSize: 12.5, color: m.ink500)),
      ),
      MasButton(
        label: 'Berikutnya',
        primary: false,
        height: 36,
        onTap: (page >= totalPages || busy) ? null : () => onGo(page + 1),
      ),
    ]);
  }
}

/// Kotak TextField sederhana — MasInput tidak menerima `keyboardType`, padahal
/// qty opname wajib memunculkan papan tik angka.
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;
  final bool mono;
  const _Field({
    required this.controller,
    required this.hint,
    this.keyboard,
    this.onChanged,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.input),
        border: Border.all(color: m.ink200),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        onChanged: onChanged,
        style: mono
            ? masMono(size: 13, color: m.ink900)
            : TextStyle(fontSize: 13, color: m.ink900),
        cursorColor: m.brand600,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: m.ink400, fontSize: 12.5),
        ),
      ),
    );
  }
}

/// Dropdown bergaya MasPart (dipakai untuk sort stok & filter populasi).
class _Dropdown extends StatelessWidget {
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  const _Dropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.input),
        border: Border.all(color: m.ink200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              size: 16, color: m.ink500),
          style: TextStyle(fontSize: 12.5, color: m.ink800),
          dropdownColor: m.paper,
          items: [
            for (final (key, label) in options)
              DropdownMenuItem(
                value: key,
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v == null || v == value) return;
            onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Tombol arah urut (naik/turun) yang menemani dropdown kolom Populasi.
class _SortDirButton extends StatelessWidget {
  final String dir;
  final bool enabled;
  final VoidCallback onTap;
  const _SortDirButton({
    required this.dir,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final asc = dir == 'asc';
    return Material(
      color: m.paper,
      borderRadius: BorderRadius.circular(MasRadii.input),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(MasRadii.input),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MasRadii.input),
            border: Border.all(color: m.ink200),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 14, color: enabled ? m.ink700 : m.ink300),
            const SizedBox(width: 4),
            Text(asc ? 'A→Z' : 'Z→A',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: enabled ? m.ink700 : m.ink300)),
          ]),
        ),
      ),
    );
  }
}

// ── Pencocokan kolom dinamis ────────────────────────────────────────────
// `rows` dari backend adalah peta kolom→nilai yang NAMA KOLOMNYA ikut file
// sumber ("Part Number", "part_no", "PN", …). Jadi kolom penting dicari lewat
// pola, tidak boleh diasumsikan — kalau tidak ketemu, baris tetap tampil
// (nilainya kosong) daripada aplikasi meledak.

final _polaPn = <RegExp>[
  RegExp(r'part.*(number|no)'),
  RegExp(r'^pn$'),
  RegExp(r'^no\b'),
];
final _polaNama = <RegExp>[
  RegExp(r'part.*name'),
  RegExp(r'nama'),
  RegExp(r'name|deskripsi|description'),
];
final _polaQty = <RegExp>[
  RegExp(r'stok|stock'),
  RegExp(r'qty|quantity|jumlah'),
];
final _polaSatuan = <RegExp>[RegExp(r'satuan|unit')];

/// Kunci pertama di [row] yang cocok salah satu [pola] (urut prioritas).
String? _kolomCocok(Map<String, String> row, List<RegExp> pola) {
  for (final p in pola) {
    for (final k in row.keys) {
      if (p.hasMatch(k.toLowerCase())) return k;
    }
  }
  return null;
}

// ══════════════════════════════════════════════════════════════════════
// 1. Stok — indeks Accurate
// ══════════════════════════════════════════════════════════════════════

const _sortStok = <(String, String)>[
  ('pn', 'Urut: Part Number'),
  ('name', 'Urut: Part Name'),
  ('stok_desc', 'Stok terbanyak'),
  ('stok_asc', 'Stok tersedikit'),
];

class StokScreen extends StatefulWidget {
  const StokScreen({super.key});

  @override
  State<StokScreen> createState() => _StokScreenState();
}

class _StokScreenState extends State<StokScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  StokListResponse? _data;
  String _q = '';
  String _sort = 'pn';
  int _page = 1;
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  /// Indeks stok hanya menyimpan AGREGAT per part. Rincian per gudang diambil
  /// on-demand saat baris dibuka (1 panggilan kecil per PN) lalu di-cache
  /// supaya membuka-tutup baris yang sama tidak memukul Accurate berulang.
  String? _openPn;
  final Map<String, AccurateStock> _detail = {};
  final Set<String> _detailLoading = {};

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ApiService.stokList(
        q: _q,
        sort: _sort,
        page: page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _data = r;
        _page = r.page;
        _openPn = null;
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

  void _cari() {
    _debounce?.cancel();
    final q = _ctrl.text.trim();
    _q = q;
    _load(1);
  }

  void _onKetik(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      final q = v.trim();
      if (q == _q) return;
      _q = q;
      _load(1);
    });
  }

  Future<void> _export() async {
    final nav = AppNav.of(context);
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final bytes = await ApiService.stokListExport(q: _q, sort: _sort);
      await _simpanDanBuka(bytes, 'stok_accurate.xlsx');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      // Gagal menulis / membuka file di perangkat — bukan error API.
      if (mounted) nav.toast('Gagal membuka file: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _toggle(String pn) async {
    if (pn.isEmpty) return;
    final tutup = _openPn == pn;
    setState(() => _openPn = tutup ? null : pn);
    if (tutup || _detail.containsKey(pn) || _detailLoading.contains(pn)) return;

    setState(() => _detailLoading.add(pn));
    try {
      final d = await ApiService.accurateStock(pn);
      if (!mounted) return;
      setState(() {
        _detail[pn] = d;
        _detailLoading.remove(pn);
      });
    } on ApiException {
      // Rincian gudang cuma pelengkap: kegagalannya tidak boleh menutup tabel,
      // cukup tampilkan "rincian tidak tersedia" di baris itu saja.
      if (!mounted) return;
      setState(() {
        _detail[pn] = const AccurateStock(error: true);
        _detailLoading.remove(pn);
      });
    }
  }

  /// Pesan jelas saat indeks stok tidak bisa dipakai — JANGAN tampilkan tabel
  /// kosong seolah-olah memang tidak ada barang.
  String _pesanMasalah(StokListResponse d) {
    final inti = !d.configured
        ? 'Koneksi Accurate belum dikonfigurasi. Hubungi admin untuk mengaktifkannya.'
        : d.sessionExpired
            ? 'Sesi Accurate kedaluwarsa. Coba lagi beberapa saat, atau minta admin memperbarui sesi.'
            : 'Gagal mengambil stok dari Accurate. Coba lagi beberapa saat.';
    final alasan = (d.reason ?? '').trim();
    return alasan.isEmpty ? inti : '$inti\n$alasan';
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final d = _data;
    final bermasalah = d != null && d.hasProblem;

    return RefreshIndicator(
      onRefresh: () => _load(_page),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(children: [
            Expanded(
              child: MasInput(
                controller: _ctrl,
                hint: 'Cari Part Number / Part Name…',
                mono: true,
                height: 40,
                action: TextInputAction.search,
                onChanged: _onKetik,
                onSubmitted: (_) => _cari(),
              ),
            ),
            const SizedBox(width: 8),
            MasButton(label: 'Cari', height: 40, onTap: _cari),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Flexible(
              child: _Dropdown(
                value: _sort,
                options: _sortStok,
                onChanged: (v) {
                  setState(() => _sort = v);
                  _load(1);
                },
              ),
            ),
            const Spacer(),
            if (d != null && !bermasalah)
              MasButton(
                label: 'Ekspor Excel',
                icon: Icons.download_rounded,
                primary: false,
                height: 34,
                loading: _exporting,
                onTap: d.totalFiltered == 0 ? null : _export,
              ),
          ]),

          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBox(_error!),
          ],

          if (bermasalah) ...[
            const SizedBox(height: 12),
            _NoticeBox(_pesanMasalah(d)),
          ] else if (_loading) ...[
            const SizedBox(height: 12),
            const MasSkeleton(height: 240),
          ] else if (d != null) ...[
            const SizedBox(height: 12),
            Text(
              'Total ${thousands(d.total)} barang · hasil filter ${thousands(d.totalFiltered)}',
              style: TextStyle(fontSize: 12.5, color: m.ink500),
            ),
            const SizedBox(height: 10),
            if (d.rows.isEmpty)
              MasEmpty(
                icon: Icons.inventory_2_outlined,
                title: 'Tidak ada barang yang cocok',
                subtitle: _q.isEmpty
                    ? 'Indeks stok kosong untuk filter ini.'
                    : 'Tidak ditemukan hasil untuk "$_q".',
              )
            else ...[
              Container(
                decoration: BoxDecoration(
                  color: m.paper,
                  borderRadius: BorderRadius.circular(MasRadii.card),
                  border: Border.all(color: m.ink150),
                  boxShadow: m.shadow1,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [for (final r in d.rows) _baris(m, r)],
                ),
              ),
              const SizedBox(height: 8),
              Text('Ketuk baris untuk rincian stok per gudang (langsung dari Accurate).',
                  style: TextStyle(fontSize: 11.5, color: m.ink400)),
              const SizedBox(height: 16),
              _Pager(
                page: _page,
                totalPages: d.totalPages,
                busy: _loading,
                onGo: _load,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _baris(MasColors m, Map<String, String> r) {
    final kPn = _kolomCocok(r, _polaPn);
    final kNama = _kolomCocok(r, _polaNama);
    final kQty = _kolomCocok(r, _polaQty);
    final kSatuan = _kolomCocok(r, _polaSatuan);

    final pn = kPn == null ? '' : (r[kPn] ?? '');
    final nama = kNama == null ? '' : (r[kNama] ?? '');
    final qty = kQty == null ? '' : (r[kQty] ?? '');
    final satuan = kSatuan == null ? '' : (r[kSatuan] ?? '');
    final open = _openPn == pn && pn.isNotEmpty;

    // Kolom yang sudah tampil di ringkasan tidak diulang di panel rincian.
    final sisa = r.keys.where((k) => k != kPn && k != kNama && k != kQty).toList();

    return Column(children: [
      InkWell(
        onTap: () => _toggle(pn),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: m.ink100)),
          ),
          child: Row(children: [
            Icon(
              open ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
              size: 16,
              color: m.ink400,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(pn.isEmpty ? '—' : pn,
                      style: masMono(
                          size: 12.5, weight: FontWeight.w600, color: m.ink900)),
                  if (nama.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(nama,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: m.ink600)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(qty.isEmpty ? '—' : qty,
                    style: masMono(
                        size: 13, weight: FontWeight.w700, color: m.brand700)),
                if (satuan.isNotEmpty)
                  Text(satuan, style: TextStyle(fontSize: 10.5, color: m.ink500)),
              ],
            ),
          ]),
        ),
      ),
      if (open) _rincian(m, pn, r, sisa),
    ]);
  }

  Widget _rincian(
    MasColors m,
    String pn,
    Map<String, String> r,
    List<String> sisa,
  ) {
    final det = _detail[pn];
    final memuat = _detailLoading.contains(pn);
    final gagal = det != null &&
        (det.error || det.sessionExpired || !det.configured || !det.found);
    final per = det?.stock?.perGudang ?? const <GudangQty>[];

    return Container(
      width: double.infinity,
      color: m.ink50,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const MasEyebrow('Stok per gudang'),
        const SizedBox(height: 8),
        if (memuat)
          Text('Memuat rincian gudang…',
              style: TextStyle(fontSize: 12.5, color: m.ink500))
        else if (gagal)
          Text(
            'Rincian per gudang tidak tersedia saat ini (koneksi Accurate gagal / PN tidak ditemukan).',
            style: TextStyle(fontSize: 12.5, color: m.warn600, height: 1.4),
          )
        else if (per.isEmpty)
          Text('Tidak ada gudang berstok untuk barang ini.',
              style: TextStyle(fontSize: 12.5, color: m.ink500))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in per)
                MasPill(
                  label: '${g.gudang} · ${thousands(g.qty)}',
                  tone: g.qty > 0 ? MasPillTone.brand : MasPillTone.neutral,
                ),
            ],
          ),

        // Kolom lain dari indeks (nama kolomnya ikut sumber data, jadi
        // ditampilkan apa adanya sebagai key-value).
        if (sisa.isNotEmpty) ...[
          const SizedBox(height: 12),
          const MasEyebrow('Kolom lain'),
          const SizedBox(height: 4),
          for (final k in sisa)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(k,
                        style: TextStyle(fontSize: 12, color: m.ink500)),
                  ),
                  Expanded(
                    child: Text(
                      (r[k] ?? '').isEmpty ? '—' : r[k]!,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: m.ink800),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 2. Populasi unit
// ══════════════════════════════════════════════════════════════════════

class PopulasiScreen extends StatefulWidget {
  const PopulasiScreen({super.key});

  @override
  State<PopulasiScreen> createState() => _PopulasiScreenState();
}

class _PopulasiScreenState extends State<PopulasiScreen> {
  final _ctrl = TextEditingController();

  PopulasiResponse? _data;
  String _q = '';

  /// kolom → nilai terpilih. Kolom yang tidak ada di sini = "Semua".
  Map<String, String> _filters = {};

  /// Kolom pengurutan (null = urutan default server) + arah. Diteruskan ke
  /// `/populasi` DAN `/populasi/kolom`, jadi hasil "Salin No. Rangka" ikut urut —
  /// setara sort klik-header di web.
  String? _sort;
  String _dir = 'asc';
  int _page = 1;
  bool _loading = true;
  bool _busy = false; // ekspor / salin rangka
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ApiService.populasi(
        q: _q,
        filters: _filters,
        page: page,
        pageSize: _pageSize,
        sort: _sort,
        dir: _dir,
      );
      if (!mounted) return;
      setState(() {
        _data = r;
        _page = r.page;
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

  void _cari() {
    _q = _ctrl.text.trim();
    _load(1);
  }

  void _setFilter(String kolom, String nilai) {
    setState(() {
      final next = Map<String, String>.of(_filters);
      // Sentinel '' = "Semua" → kolomnya dibuang dari payload filter.
      if (nilai.isEmpty) {
        next.remove(kolom);
      } else {
        next[kolom] = nilai;
      }
      _filters = next;
      _info = null;
    });
    _load(1);
  }

  void _resetFilter() {
    setState(() {
      _filters = {};
      _info = null;
    });
    _load(1);
  }

  /// Pilih kolom urut ('' = default server). Ganti kolom → arah kembali asc,
  /// persis web (`handleSort`).
  void _setSort(String kolom) {
    setState(() {
      _sort = kolom.isEmpty ? null : kolom;
      _dir = 'asc';
      _info = null;
    });
    _load(1);
  }

  void _toggleDir() {
    if (_sort == null) return;
    setState(() => _dir = _dir == 'asc' ? 'desc' : 'asc');
    _load(1);
  }

  /// Salin SELURUH nomor rangka hasil filter (bukan hanya halaman ini) — ini
  /// alasan endpoint `/populasi/kolom` ada: user menempelkannya ke Excel/WA.
  Future<void> _salinRangka() async {
    final nav = AppNav.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final r = await ApiService.populasiKolom(
          q: _q, filters: _filters, sort: _sort, dir: _dir);
      if (!mounted) return;
      if (r.values.isEmpty) {
        setState(() => _info = 'Tidak ada nomor rangka pada hasil filter.');
        return;
      }
      await Clipboard.setData(ClipboardData(text: r.values.join('\n')));
      if (!mounted) return;
      setState(() => _info =
          '${thousands(r.jumlah)} nomor rangka disalin — tinggal tempel (satu per baris).');
      nav.toast('${thousands(r.jumlah)} nomor rangka disalin');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final nav = AppNav.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await ApiService.populasiExport(q: _q, filters: _filters);
      await _simpanDanBuka(bytes, 'populasi_unit.xlsx');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) nav.toast('Gagal membuka file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Detail satu unit: seluruh kolom, karena kolom populasi berbeda-beda per
  /// dataset dan tidak muat ditampilkan di daftar.
  void _bukaDetail(Map<String, String> row) {
    final cols = _data?.columns ?? row.keys.toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final m = ctx.mas;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: m.paper,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(MasRadii.sheet),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(children: [
                Expanded(
                  child: Text('Detail Unit',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: m.ink900)),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Icon(Icons.close_rounded, size: 20, color: m.ink500),
                ),
              ]),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 20),
                children: [
                  for (final c in cols)
                    MasKeyValue(
                      label: c,
                      value: (row[c] ?? '').isEmpty ? '—' : row[c]!,
                      mono: _isRangka(c),
                    ),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  /// Kolom identitas unit (rangka/VIN/mesin) ditulis monospace supaya mudah
  /// dibaca & dicocokkan digit per digit.
  bool _isRangka(String kolom) =>
      RegExp(r'rangka|vin|mesin').hasMatch(kolom.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final d = _data;
    final cols = d?.columns ?? const <String>[];
    final fopts = d?.filterOptions ?? const <String, List<String>>{};

    return RefreshIndicator(
      onRefresh: () => _load(_page),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(children: [
            Expanded(
              child: MasInput(
                controller: _ctrl,
                hint: 'Cari customer, nomor rangka, model…',
                height: 40,
                action: TextInputAction.search,
                onSubmitted: (_) => _cari(),
              ),
            ),
            const SizedBox(width: 8),
            MasButton(label: 'Cari', height: 40, onTap: _cari),
          ]),

          if (fopts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final e in fopts.entries)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: _Dropdown(
                      value: _filters[e.key] ?? '',
                      options: [
                        ('', '${e.key}: Semua'),
                        for (final o in e.value) (o, o),
                      ],
                      onChanged: (v) => _setFilter(e.key, v),
                    ),
                  ),
                if (_filters.isNotEmpty)
                  GestureDetector(
                    onTap: _resetFilter,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.close_rounded, size: 14, color: m.danger600),
                      const SizedBox(width: 4),
                      Text('Reset filter',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: m.danger600)),
                    ]),
                  ),
              ],
            ),
          ],

          if (cols.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _Dropdown(
                  value: _sort ?? '',
                  options: [
                    ('', 'Urutkan: default'),
                    for (final c in cols) (c, 'Urutkan: $c'),
                  ],
                  onChanged: _setSort,
                ),
              ),
              const SizedBox(width: 8),
              _SortDirButton(
                dir: _dir,
                enabled: _sort != null,
                onTap: _toggleDir,
              ),
            ]),
          ],

          const SizedBox(height: 10),
          Row(children: [
            MasButton(
              label: 'Salin No. Rangka',
              icon: Icons.copy_all_rounded,
              primary: false,
              height: 34,
              loading: _busy,
              onTap: (d == null || d.totalFiltered == 0) ? null : _salinRangka,
            ),
            const SizedBox(width: 8),
            MasButton(
              label: 'Ekspor',
              icon: Icons.download_rounded,
              primary: false,
              height: 34,
              onTap: (d == null || d.totalFiltered == 0) ? null : _export,
            ),
          ]),

          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBox(_error!),
          ],
          if (_info != null) ...[
            const SizedBox(height: 12),
            _InfoBox(_info!),
          ],

          const SizedBox(height: 12),
          if (_loading)
            const MasSkeleton(height: 260)
          else if (d == null)
            const SizedBox.shrink()
          else ...[
            Text(
              'Total ${thousands(d.total)} unit · hasil filter ${thousands(d.totalFiltered)}',
              style: TextStyle(fontSize: 12.5, color: m.ink500),
            ),
            const SizedBox(height: 10),
            if (d.rows.isEmpty)
              MasEmpty(
                icon: Icons.local_shipping_outlined,
                title: 'Tidak ada unit yang cocok',
                subtitle: 'Ubah kata kunci atau reset filter.',
              )
            else ...[
              Container(
                decoration: BoxDecoration(
                  color: m.paper,
                  borderRadius: BorderRadius.circular(MasRadii.card),
                  border: Border.all(color: m.ink150),
                  boxShadow: m.shadow1,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [for (final r in d.rows) _baris(m, r, cols)],
                ),
              ),
              const SizedBox(height: 16),
              _Pager(
                page: _page,
                totalPages: d.totalPages,
                busy: _loading,
                onGo: _load,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _baris(MasColors m, Map<String, String> row, List<String> cols) {
    // Judul baris = kolom rangka/VIN bila ada (identitas unit yang dicari
    // orang di lapangan), kalau tidak ada pakai kolom pertama.
    final kUtama = cols.firstWhere(
      _isRangka,
      orElse: () => cols.isEmpty ? '' : cols.first,
    );
    final utama = kUtama.isEmpty ? '' : (row[kUtama] ?? '');
    final lain = cols
        .where((c) => c != kUtama)
        .map((c) => row[c] ?? '')
        .where((v) => v.isNotEmpty)
        .take(3)
        .join(' · ');

    return InkWell(
      onTap: () => _bukaDetail(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: m.ink100)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(utama.isEmpty ? '—' : utama,
                    style: masMono(
                        size: 12.5, weight: FontWeight.w600, color: m.ink900)),
                if (lain.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(lain,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: m.ink600, height: 1.35)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, size: 18, color: m.ink400),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 3. Bandingkan 2 part (interchange)
// ══════════════════════════════════════════════════════════════════════

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();

  CompareResponse? _res;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    super.dispose();
  }

  Future<void> _bandingkan() async {
    final a = _c1.text.trim();
    final b = _c2.text.trim();
    if (a.isEmpty || b.isEmpty) {
      setState(() => _error = 'Isi kedua Part Number.');
      return;
    }
    if (a.toUpperCase() == b.toUpperCase()) {
      setState(() => _error = 'Part Number tidak boleh sama.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _res = null;
    });
    try {
      // Operasi lambat: backend menarik & menganalisis foto SIMS kedua part.
      final r = await ApiService.compareParts(a, b);
      if (!mounted) return;
      setState(() {
        _res = r;
        _error = r.error; // mis. "foto PN tidak ditemukan di SIMS"
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

  /// `best.color` dari server adalah hex yang dipatok untuk latar terang web.
  /// Di mobile pill harus ikut tema, jadi nadanya diturunkan dari skor
  /// keseluruhan (ambang sama dengan verdict server).
  MasPillTone _tone(double overall) => overall >= 0.75
      ? MasPillTone.brand
      : overall >= 0.5
          ? MasPillTone.warn
          : MasPillTone.danger;

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final r = _res;
    final best = r?.best;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          'Analisis interchange berdasarkan foto SIMS (bentuk + warna) dan nama part.',
          style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
        ),
        const SizedBox(height: 12),
        MasInput(
            controller: _c1, hint: 'Part Number #1', mono: true, height: 42),
        const SizedBox(height: 8),
        MasInput(
            controller: _c2, hint: 'Part Number #2', mono: true, height: 42),
        const SizedBox(height: 10),
        MasButton(
          label: _loading ? 'Menganalisis…' : 'Bandingkan',
          icon: Icons.compare_arrows_rounded,
          expand: true,
          loading: _loading,
          onTap: _bandingkan,
        ),

        if (_loading) ...[
          const SizedBox(height: 10),
          Text('Mengambil & menganalisis foto dari SIMS — bisa memakan waktu.',
              style: TextStyle(fontSize: 11.5, color: m.ink400)),
          const SizedBox(height: 14),
          const MasSkeleton(height: 200),
        ],

        if (_error != null) ...[
          const SizedBox(height: 14),
          _ErrorBox(_error!),
        ],

        if (!_loading && r != null && best != null) ...[
          const SizedBox(height: 18),
          _verdict(m, best),
          const SizedBox(height: 14),
          MasCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MasEyebrow('Skor kemiripan'),
                const SizedBox(height: 10),
                _skor(m, 'Bentuk (shape)', best.shapeScore),
                _skor(m, 'Nama part', best.nameScore),
                _skor(m, 'Warna', best.colorScore),
                _skor(m, 'Keseluruhan', best.overall),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _pasanganTerbaik(m, r, best),
          const SizedBox(height: 14),
          _galeri(m, r.pn1, r.name1, r.urls1),
          const SizedBox(height: 14),
          _galeri(m, r.pn2, r.name2, r.urls2),
        ],
      ],
    );
  }

  Widget _verdict(MasColors m, CompareBest best) => MasCard(
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  best.verdict.isEmpty ? 'Hasil analisis' : best.verdict,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: m.ink900),
                ),
                const SizedBox(height: 3),
                Text('Skor keseluruhan ${(best.overall * 100).round()}%',
                    style: TextStyle(fontSize: 12.5, color: m.ink500)),
              ],
            ),
          ),
          MasPill(
            label: '${(best.overall * 100).round()}%',
            tone: _tone(best.overall),
            dot: true,
            height: 26,
          ),
        ]),
      );

  Widget _skor(MasColors m, String label, double? v) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: m.ink500)),
            ),
            // Nama part bisa null bila salah satu PN tak punya nama di katalog.
            Text(v == null ? '—' : '${(v * 100).round()}%',
                style: masMono(
                    size: 12, weight: FontWeight.w600, color: m.ink700)),
          ]),
          const SizedBox(height: 5),
          MasBar(value: v ?? 0, height: 8),
        ]),
      );

  Widget _pasanganTerbaik(MasColors m, CompareResponse r, CompareBest best) {
    // `best.i`/`best.j` menunjuk ke indeks foto termirip di tiap galeri —
    // dijaga agar tidak keluar batas kalau server & klien beda versi.
    final a = (best.i >= 0 && best.i < r.urls1.length) ? r.urls1[best.i] : null;
    final b = (best.j >= 0 && best.j < r.urls2.length) ? r.urls2[best.j] : null;
    if (a == null && b == null) return const SizedBox.shrink();

    return MasCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const MasEyebrow('Pasangan foto termirip'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: a == null ? const HatchBox() : _foto(m, a)),
          const SizedBox(width: 10),
          Expanded(child: b == null ? const HatchBox() : _foto(m, b)),
        ]),
      ]),
    );
  }

  Widget _galeri(MasColors m, String pn, String nama, List<String> urls) =>
      MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pn,
              style: masMono(
                  size: 13, weight: FontWeight.w700, color: m.ink900)),
          if (nama.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(nama, style: TextStyle(fontSize: 12, color: m.ink500)),
          ],
          const SizedBox(height: 10),
          if (urls.isEmpty)
            Text('Tidak ada gambar dari SIMS.',
                style: TextStyle(fontSize: 12.5, color: m.ink400))
          else
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final u in urls) _foto(m, u)],
            ),
        ]),
      );

  Widget _foto(MasColors m, String url) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border.all(color: m.ink200),
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 1,
          child: Image.network(
            // Foto SIMS harus lewat proxy backend (http:// & tanpa CORS).
            ApiService.partImageUrl(url),
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : Container(color: m.ink50),
            errorBuilder: (_, _, _) => const HatchBox(label: 'gagal dimuat'),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════
// 4. Batch download (katalog Excel)
// ══════════════════════════════════════════════════════════════════════

/// Kolom yang bisa dipilih. Part Number SELALU ikut (tidak bisa dimatikan).
const _kolomBatch = <({String key, String label, String desc})>[
  (key: 'nama', label: 'Nama Part', desc: 'Nama/deskripsi part'),
  (key: 'foto', label: 'Foto', desc: '2 gambar dari SIMS (paling lambat)'),
  (key: 'stok', label: 'Stok', desc: 'Stok Accurate (live)'),
  (key: 'harga_sims', label: 'Harga SIMS', desc: 'Harga SIMS × kurs → Rupiah'),
  (
    key: 'harga_accurate',
    label: 'Harga Jual Accurate',
    desc: 'Harga jual dari Accurate'
  ),
  (
    key: 'harga_daftar',
    label: 'Harga (Daftar)',
    desc: 'Dari daftar harga internal'
  ),
  (key: 'kecocokan', label: 'Kecocokan', desc: 'File katalog lokal yang cocok'),
];

/// Kolom harga hanya untuk akun berizin — backend juga menegakkan ini, tapi
/// menyembunyikannya di sini mencegah user menunggu proses panjang lalu ditolak.
const _kolomHarga = {'harga_sims', 'harga_accurate', 'harga_daftar'};
const _kolomDefault = {'nama', 'foto', 'stok'};

class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  final _textCtrl = TextEditingController();

  Set<String> _columns = {..._kolomDefault};
  bool _canPrice = false;
  ({Uint8List bytes, String filename})? _file;

  bool _busy = false;
  bool _template = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _muatIzin();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _muatIzin() async {
    try {
      final p = await ApiService.getMyPermissions();
      if (!mounted) return;
      setState(() {
        _canPrice = p.canPrice;
        if (!p.canPrice) {
          _columns = {..._columns}..removeWhere(_kolomHarga.contains);
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  int get _jumlahBaris => _textCtrl.text
      .split(RegExp(r'[\n,]'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .length;

  Future<void> _unduhTemplate() async {
    final nav = AppNav.of(context);
    setState(() {
      _template = true;
      _error = null;
    });
    try {
      final bytes = await ApiService.batchTemplate();
      await _simpanDanBuka(bytes, 'template_batch_input.xlsx');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) nav.toast('Gagal membuka file: $e');
    } finally {
      if (mounted) setState(() => _template = false);
    }
  }

  Future<void> _ambilFile() async {
    final f = await _pilihFile(['xlsx', 'xls', 'xlsm', 'csv']);
    if (f == null || !mounted) return;
    setState(() {
      _file = f;
      // Server memakai file bila ada — kosongkan teks supaya tidak ada dua
      // sumber PN yang membingungkan user.
      _textCtrl.clear();
      _error = null;
    });
  }

  Future<void> _proses() async {
    final text = _textCtrl.text.trim();
    if (_file == null && text.isEmpty) {
      setState(() => _error = 'Masukkan part number atau unggah file dulu.');
      return;
    }
    if (_columns.isEmpty) {
      setState(() => _error = 'Pilih minimal satu kolom untuk disertakan.');
      return;
    }
    final nav = AppNav.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await ApiService.buildBatchCatalog(
        text: text,
        file: _file,
        // Kirim menurut urutan kanonik supaya kolom Excel selalu sama urutannya.
        columns: [
          for (final c in _kolomBatch)
            if (_columns.contains(c.key)) c.key,
        ],
      );
      await _simpanDanBuka(bytes, 'catalog.xlsx');
      if (mounted) nav.toast('Katalog Excel selesai.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal membuka file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final opsi = _kolomBatch
        .where((o) => _canPrice || !_kolomHarga.contains(o.key))
        .toList();
    final lambat =
        _columns.contains('foto') || _columns.contains('harga_sims');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          'Masukkan banyak part number sekaligus → unduh katalog Excel. Pilih sendiri '
          'kolom yang disertakan. Maksimum 300 PN per batch.',
          style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
        ),
        const SizedBox(height: 12),
        MasButton(
          label: 'Unduh Template',
          icon: Icons.description_outlined,
          primary: false,
          height: 38,
          loading: _template,
          onTap: _unduhTemplate,
        ),

        const SizedBox(height: 18),
        const MasEyebrow('Kolom yang disertakan'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          // Part Number wajib — ditampilkan sebagai chip mati.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: m.brand50,
              borderRadius: BorderRadius.circular(MasRadii.chip),
              border: Border.all(color: m.brand100),
            ),
            child: Text('Part Number · wajib',
                style: masMono(
                    size: 12, weight: FontWeight.w600, color: m.brand700)),
          ),
          for (final o in opsi) _chip(m, o),
        ]),
        const SizedBox(height: 8),
        Text('Tip: matikan Foto agar jauh lebih cepat bila hanya butuh stok/harga.',
            style: TextStyle(fontSize: 11.5, color: m.ink400)),

        if (_error != null) ...[
          const SizedBox(height: 14),
          _ErrorBox(_error!),
        ],

        const SizedBox(height: 18),
        const MasEyebrow('Ketik manual (1 PN per baris)'),
        const SizedBox(height: 8),
        MasInput(
          controller: _textCtrl,
          hint: 'WG1642821034\nWG9925520270\nAZ9100443082',
          mono: true,
          maxLines: 8,
          onChanged: (_) => setState(() => _file = null),
        ),
        if (_jumlahBaris > 0 && _file == null) ...[
          const SizedBox(height: 4),
          Text('$_jumlahBaris baris',
              style: TextStyle(fontSize: 12, color: m.ink500)),
        ],

        const SizedBox(height: 14),
        const MasEyebrow('Atau unggah file (Excel/CSV, PN di kolom A)'),
        const SizedBox(height: 8),
        Row(children: [
          MasButton(
            label: 'Pilih File',
            icon: Icons.attach_file_rounded,
            primary: false,
            height: 38,
            onTap: _ambilFile,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _file == null ? 'Belum ada file dipilih.' : _file!.filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: m.ink600),
            ),
          ),
          if (_file != null)
            GestureDetector(
              onTap: () => setState(() => _file = null),
              child: Icon(Icons.close_rounded, size: 18, color: m.ink400),
            ),
        ]),

        const SizedBox(height: 20),
        MasButton(
          label: _busy ? 'Memproses…' : 'Buat Katalog Excel',
          icon: Icons.download_rounded,
          expand: true,
          height: 46,
          loading: _busy,
          onTap: _proses,
        ),
        if (_busy) ...[
          const SizedBox(height: 8),
          Text(
            lambat
                ? 'Mengambil data SIMS untuk tiap part — bisa beberapa menit untuk banyak PN.'
                : 'Menyusun katalog — sebentar lagi selesai.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: m.ink400),
          ),
        ],
      ],
    );
  }

  Widget _chip(MasColors m, ({String key, String label, String desc}) o) {
    final on = _columns.contains(o.key);
    return Tooltip(
      message: o.desc,
      child: GestureDetector(
        onTap: () => setState(() {
          final next = {..._columns};
          on ? next.remove(o.key) : next.add(o.key);
          _columns = next;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: on ? m.brand600 : m.paper,
            borderRadius: BorderRadius.circular(MasRadii.chip),
            border: Border.all(color: on ? m.brand600 : m.ink200),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? Icons.check_rounded : Icons.add_rounded,
                size: 13, color: on ? Colors.white : m.ink500),
            const SizedBox(width: 6),
            Text(o.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: on ? Colors.white : m.ink600,
                )),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 5. Stok opname
// ══════════════════════════════════════════════════════════════════════

class OpnameScreen extends StatefulWidget {
  const OpnameScreen({super.key});

  @override
  State<OpnameScreen> createState() => _OpnameScreenState();
}

class _OpnameScreenState extends State<OpnameScreen> {
  OpnameSession? _draft;

  /// Salinan item draft yang sedang diedit (belum tentu tersimpan di server).
  Map<String, OpnameItem> _items = {};
  List<String> _pns = [];

  // Controller dibuat malas per baris — daftar opname bisa ratusan PN dan
  // hanya baris yang terlihat yang benar-benar dibangun (SliverList).
  final Map<String, TextEditingController> _qtyCtl = {};
  final Map<String, TextEditingController> _noteCtl = {};

  List<OpnameSession> _history = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _buangController();
    super.dispose();
  }

  void _buangController() {
    for (final c in _qtyCtl.values) {
      c.dispose();
    }
    for (final c in _noteCtl.values) {
      c.dispose();
    }
    _qtyCtl.clear();
    _noteCtl.clear();
  }

  void _pasangDraft(OpnameSession? s) {
    _buangController();
    _draft = s;
    _items = s == null ? {} : Map.of(s.items);
    _pns = _items.keys.toList();
  }

  Future<void> _muat() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.opnameDraft();
      final h = await ApiService.opnameHistory();
      if (!mounted) return;
      setState(() {
        _pasangDraft(d);
        _history = h;
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

  TextEditingController _ctlQty(String pn) => _qtyCtl.putIfAbsent(
        pn,
        () => TextEditingController(text: _items[pn]?.qtyFisik?.toString() ?? ''),
      );

  TextEditingController _ctlNote(String pn) => _noteCtl.putIfAbsent(
        pn,
        () => TextEditingController(text: _items[pn]?.note ?? ''),
      );

  void _setQty(String pn, String v) {
    final it = _items[pn];
    if (it == null) return;
    final t = v.trim();
    setState(() {
      _items[pn] = t.isEmpty
          // Kolom dikosongkan = "belum dihitung", BUKAN nol. Nol adalah hasil
          // hitung yang sah (barang habis) dan ikut dihitung sebagai selisih.
          ? it.copyWith(clearQtyFisik: true)
          : it.copyWith(qtyFisik: int.tryParse(t) ?? it.qtyFisik);
    });
  }

  void _setNote(String pn, String v) {
    final it = _items[pn];
    if (it == null) return;
    _items[pn] = it.copyWith(note: v);
  }

  /// Sesi versi terkini (draft server + editan lokal) — dipakai untuk ringkasan
  /// maupun payload simpan/finalisasi.
  OpnameSession? get _sesi => _draft?.copyWith(items: _items);

  Future<void> _unggah() async {
    final f = await _pilihFile(['xlsx', 'xls']);
    if (f == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final s = await ApiService.opnameFromUpload(
        bytes: f.bytes,
        filename: f.filename,
      );
      if (!mounted) return;
      setState(() {
        _pasangDraft(s);
        _info = 'Sesi dibuat: ${thousands(s.jumlahItem)} part.';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _simpan() async {
    final s = _sesi;
    if (s == null) return;
    final nav = AppNav.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ApiService.saveOpnameDraft(s);
      if (!mounted) return;
      setState(() => _info = 'Draft tersimpan.');
      nav.toast('Draft opname tersimpan');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selesaikan() async {
    final s = _sesi;
    if (s == null) return;
    final ok = await _konfirmasi(
      judul: 'Selesaikan opname?',
      pesan:
          'Hasil dikunci dan masuk riwayat. Setelah final, qty fisik & catatan '
          'tidak bisa diubah lagi.',
      tombol: 'Selesaikan',
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ApiService.finalizeOpname(s);
      if (!mounted) return;
      setState(() => _pasangDraft(null));
      await _muat();
      if (mounted) setState(() => _info = 'Opname difinalisasi.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hapus() async {
    final ok = await _konfirmasi(
      judul: 'Hapus draft opname?',
      pesan: 'Seluruh qty fisik & catatan yang belum difinalisasi akan hilang.',
      tombol: 'Hapus',
      bahaya: true,
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ApiService.deleteOpnameDraft();
      if (!mounted) return;
      setState(() {
        _pasangDraft(null);
        _info = 'Draft dihapus.';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _konfirmasi({
    required String judul,
    required String pesan,
    required String tombol,
    bool bahaya = false,
  }) async {
    final m = context.mas;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: m.paper,
        title: Text(judul,
            style: TextStyle(
                fontSize: 15.5, fontWeight: FontWeight.w700, color: m.ink900)),
        content: Text(pesan,
            style: TextStyle(fontSize: 13, color: m.ink600, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: TextStyle(color: m.ink600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tombol,
                style: TextStyle(
                  color: bahaya ? m.danger600 : m.brand700,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final s = _sesi;

    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            if (_error != null) ...[_ErrorBox(_error!), const SizedBox(height: 12)],
            if (_info != null) ...[_InfoBox(_info!), const SizedBox(height: 12)],
            if (_loading)
              const MasSkeleton(height: 160)
            else if (s == null)
              _mulaiSesi(m)
            else
              _ringkasan(m, s),
            const SizedBox(height: 12),
          ]),
        ),
      ),

      if (!_loading && s != null)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _kartuItem(m, _pns[i]),
              ),
              childCount: _pns.length,
            ),
          ),
        ),

      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        sliver: SliverList(
          delegate: SliverChildListDelegate([_riwayat(m)]),
        ),
      ),
    ]);
  }

  Widget _mulaiSesi(MasColors m) => MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const MasEyebrow('Mulai sesi baru'),
          const SizedBox(height: 8),
          Text(
            'Unggah file stok (Part Number + qty sistem). Kolom dikenali otomatis: '
            'part number, qty sistem/stok, dan nama part.',
            style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
          ),
          const SizedBox(height: 12),
          MasButton(
            label: _busy ? 'Memproses…' : 'Unggah File Stok',
            icon: Icons.upload_file_rounded,
            expand: true,
            loading: _busy,
            onTap: _unggah,
          ),
        ]),
      );

  Widget _ringkasan(MasColors m, OpnameSession s) => MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: _angka(m, 'Item', thousands(s.jumlahItem), m.ink900)),
            Expanded(
                child: _angka(
                    m, 'Terhitung', thousands(s.jumlahTerhitung), m.brand700)),
            Expanded(
                child: _angka(
                    m, 'Selisih', thousands(s.jumlahSelisih), m.warn600)),
          ]),
          if ((s.sourceFilename ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Sumber: ${s.sourceFilename}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: m.ink400)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: MasButton(
                label: 'Simpan Draft',
                icon: Icons.save_outlined,
                primary: false,
                height: 38,
                expand: true,
                onTap: _busy ? null : _simpan,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MasButton(
                label: 'Selesaikan',
                icon: Icons.check_rounded,
                height: 38,
                expand: true,
                onTap: _busy ? null : _selesaikan,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _busy ? null : _hapus,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.delete_outline_rounded, size: 15, color: m.danger600),
              const SizedBox(width: 5),
              Text('Hapus Draft',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: m.danger600)),
            ]),
          ),
        ]),
      );

  Widget _angka(MasColors m, String label, String nilai, Color warna) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: m.ink500)),
          const SizedBox(height: 2),
          Text(nilai,
              style: masMono(size: 17, weight: FontWeight.w700, color: warna)),
        ],
      );

  Widget _kartuItem(MasColors m, String pn) {
    final it = _items[pn];
    if (it == null) return const SizedBox.shrink();
    final sel = it.selisih;

    // Selisih 0 = cocok (netral). Fisik lebih banyak = warn (kelebihan catat),
    // fisik lebih sedikit = danger (barang hilang — konsekuensinya paling berat).
    final tone = sel == null
        ? MasPillTone.neutral
        : sel == 0
            ? MasPillTone.neutral
            : sel > 0
                ? MasPillTone.warn
                : MasPillTone.danger;
    final label = sel == null
        ? '—'
        : sel > 0
            ? '+${thousands(sel)}'
            : thousands(sel);

    return MasCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(pn,
                    style: masMono(
                        size: 12.5, weight: FontWeight.w600, color: m.ink900)),
                if (it.partName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(it.partName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: m.ink600)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          MasPill(label: 'Selisih $label', tone: tone),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Sistem', style: TextStyle(fontSize: 11, color: m.ink500)),
                const SizedBox(height: 4),
                Text(it.qtySistem == null ? '—' : thousands(it.qtySistem),
                    style: masMono(
                        size: 13, weight: FontWeight.w600, color: m.ink800)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Qty fisik',
                    style: TextStyle(fontSize: 11, color: m.ink500)),
                const SizedBox(height: 4),
                _Field(
                  controller: _ctlQty(pn),
                  hint: 'Belum dihitung',
                  mono: true,
                  keyboard: const TextInputType.numberWithOptions(signed: true),
                  onChanged: (v) => _setQty(pn, v),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _Field(
          controller: _ctlNote(pn),
          hint: 'Catatan (opsional)',
          onChanged: (v) => _setNote(pn, v),
        ),
      ]),
    );
  }

  Widget _riwayat(MasColors m) {
    if (_history.isEmpty) return const SizedBox.shrink();
    return MasSectionCard(
      title: 'Riwayat Opname',
      children: [
        for (final h in _history)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: m.ink100)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_waktu(h.finalizedAt),
                        style: masMono(
                            size: 12,
                            weight: FontWeight.w600,
                            color: m.ink900)),
                    const SizedBox(height: 2),
                    Text(
                      '${thousands(h.jumlahItem)} part · sumber ${h.sourceFilename ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: m.ink500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              MasPill(
                label: 'Selisih ${thousands(h.jumlahSelisih)}',
                tone: h.jumlahSelisih == 0
                    ? MasPillTone.neutral
                    : MasPillTone.warn,
              ),
            ]),
          ),
      ],
    );
  }
}
