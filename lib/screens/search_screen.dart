// lib/screens/search_screen.dart — Cari Part (Part Number / Part Name), data live.
//
// Setara web (search/page.tsx): muat sampai MAX_FETCH baris, saring live di sisi
// klien, urutkan per kolom, paginasi + pilih per-halaman, dan "Mungkin maksud
// Anda" saat 0 hasil. Pembeli bisa menambah ke keranjang langsung dari hasil.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';
import '../utils.dart';
import '../cart.dart';
import '../api_service.dart';
import '../app/nav.dart';
import 'login_screen.dart';

/// Batas total baris yang ditarik (sama dengan web). Melebihi ini → hasil
/// dipotong dan user diberi tahu untuk mempersempit kata kunci.
const int _kMaxFetch = 2000;
const int _kFetchSize = 200;
const List<int> _kPageSizes = [20, 50, 100];

class SearchPartScreen extends StatefulWidget {
  const SearchPartScreen({super.key});
  @override
  State<SearchPartScreen> createState() => _SearchPartScreenState();
}

class _SearchPartScreenState extends State<SearchPartScreen> {
  final _ctrl = TextEditingController();
  final _refineCtrl = TextEditingController();
  Timer? _debounce;
  int _reqId = 0;

  int _tab = 0; // 0 = Part Number, 1 = Part Name
  bool _loading = false;
  bool _searched = false;
  String _query = '';

  // Hasil mentah dari server (bisa sampai _kMaxFetch), sebelum saring/urut/paginasi.
  List<PartResult> _all = [];
  int _totalCount = 0;
  bool _truncated = false;
  List<SaranPart> _saran = [];
  String _activeQuery = '';

  // Saring live (klien) + urut + paginasi.
  String _refine = '';
  String? _sortKey; // part_number | part_name | file | stok | harga
  String _dir = 'asc';
  int _page = 1;
  int _pageSize = 0; // 0 = belum di-resolve dari config server (default 20)

  bool get _byName => _tab == 1;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _refineCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _query = v;
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _all = [];
        _saran = [];
        _loading = false;
        _searched = false;
      });
      return;
    }
    setState(() {
      _searched = true;
      _loading = true;
    });
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(q, _byName));
  }

  void _submit() {
    final q = _query.trim();
    if (q.isEmpty) return;
    setState(() {
      _searched = true;
      _loading = true;
    });
    _runSearch(q, _byName);
  }

  /// Muat halaman pertama, lalu sisanya sampai _kMaxFetch, agar saring & urut
  /// menyentuh semua hasil (persis web).
  Future<void> _runSearch(String term, bool byName) async {
    final id = ++_reqId;
    // Batas muat bisa diatur server (config `search`); fallback ke konstanta.
    final nav = AppNav.of(context);
    final fetchSize = nav.searchFetchSize(_kFetchSize);
    final maxFetch = nav.searchMaxFetch(_kMaxFetch);
    try {
      final first = await ApiService.searchParts(term,
          byName: byName, page: 1, pageSize: fetchSize);
      if (!mounted || id != _reqId) return;
      final acc = [...first.results];
      final maxPages = math.min(
          first.totalPages, (maxFetch / fetchSize).ceil());
      for (var p = 2; p <= maxPages; p++) {
        final r = await ApiService.searchParts(term,
            byName: byName, page: p, pageSize: fetchSize);
        if (!mounted || id != _reqId) return;
        acc.addAll(r.results);
      }
      setState(() {
        _all = acc;
        _totalCount = first.count;
        _truncated = first.count > acc.length;
        _saran = first.saran;
        _activeQuery = term;
        _refine = '';
        _refineCtrl.clear();
        _sortKey = null;
        _dir = 'asc';
        _page = 1;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || id != _reqId) return;
      if (e.statusCode == 401) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
        return;
      }
      setState(() {
        _all = [];
        _saran = [];
        _loading = false;
      });
      AppNav.of(context).toast(e.message);
    } catch (_) {
      if (!mounted || id != _reqId) return;
      setState(() {
        _all = [];
        _saran = [];
        _loading = false;
      });
      AppNav.of(context).toast('Gagal memuat hasil. Periksa koneksi.');
    }
  }

  // ── Turunan: saring live + urut ──────────────────────────────────────
  List<PartResult> get _refined {
    final t = _refine.trim().toLowerCase();
    var list = _all;
    if (t.isNotEmpty) {
      final words = t.split(RegExp(r'\s+'));
      list = _all.where((r) {
        final hay = '${r.partNumber} ${r.partName} ${r.file}'.toLowerCase();
        return words.every(hay.contains);
      }).toList();
    }
    final key = _sortKey;
    if (key == null) return list;
    final sorted = [...list];
    double num1(String v) {
      final n = double.tryParse(v.replaceAll(RegExp(r'[^0-9.-]'), ''));
      return n ?? -1;
    }
    sorted.sort((a, b) {
      if (key == 'stok' || key == 'harga') {
        final va = num1(key == 'stok' ? a.stok : a.harga);
        final vb = num1(key == 'stok' ? b.stok : b.harga);
        return _dir == 'asc' ? va.compareTo(vb) : vb.compareTo(va);
      }
      String field(PartResult r) => key == 'part_number'
          ? r.partNumber
          : (key == 'part_name' ? r.partName : r.file);
      final va = field(a).toLowerCase();
      final vb = field(b).toLowerCase();
      return _dir == 'asc' ? va.compareTo(vb) : vb.compareTo(va);
    });
    return sorted;
  }

  int get _totalPages => math.max(1, (_refined.length / _pageSize).ceil());
  int get _pageClamped => math.min(_page, _totalPages);
  List<PartResult> get _pageItems {
    final r = _refined;
    final start = (_pageClamped - 1) * _pageSize;
    final end = math.min(start + _pageSize, r.length);
    return start < end ? r.sublist(start, end) : const [];
  }

  void _addToCart(PartResult r) {
    CartStore.instance.add(CartItem(
      partNumber: r.partNumber,
      name: r.partName,
      harga: r.harga,
      berat: r.berat,
    ));
    AppNav.of(context).toast('${r.partNumber} masuk keranjang');
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    // Gating kolom stok/harga — persis web (Menu Control). Pembeli tak pernah
    // lihat stok di hasil cari (hanya di detail part).
    final nav = AppNav.of(context);
    final showStok = nav.showStok;
    final showHarga = nav.showHarga;
    final isBuyer = nav.isBuyer;
    // Default per-halaman dari config (sekali), lalu dikendalikan user.
    if (_pageSize == 0) _pageSize = nav.searchPageSize(20);

    final refined = _refined;
    final shown = refined.length;
    final from = shown > 0 ? (_pageClamped - 1) * _pageSize + 1 : 0;
    final to = shown > 0 ? math.min(_pageClamped * _pageSize, shown) : 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        MasCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MasUnderlineTabs(
              tabs: const ['Part Number', 'Part Name'],
              index: _tab,
              onChanged: (i) {
                setState(() => _tab = i);
                _submit();
              },
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: MasInput(
                  controller: _ctrl,
                  hint: _byName ? 'Contoh: oil filter' : 'Contoh: 16Y-15-00010',
                  mono: !_byName,
                  onChanged: _onChanged,
                  onSubmitted: (_) => _submit(),
                  action: TextInputAction.search,
                ),
              ),
              const SizedBox(width: 10),
              MasButton(label: 'Cari', onTap: _submit),
            ]),
          ]),
        ),
        if (_searched) ...[
          const SizedBox(height: 14),
          if (_loading)
            Column(children: [
              for (int i = 0; i < 4; i++) const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: MasSkeleton(height: 66),
              ),
            ])
          else
            _resultsArea(m, refined, shown, from, to, showStok, showHarga, isBuyer),
        ],
      ],
    );
  }

  Widget _resultsArea(MasColors m, List<PartResult> refined, int shown, int from,
      int to, bool showStok, bool showHarga, bool isBuyer) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Saring live — hanya bila ada hasil mentah.
      if (_all.isNotEmpty) ...[
        Row(children: [
          Expanded(
            child: MasInput(
              controller: _refineCtrl,
              hint: 'Saring hasil "$_activeQuery" langsung… (mis. sg21)',
              height: 40,
              prefix: Icon(Icons.filter_alt_outlined, size: 16, color: m.ink400),
              onChanged: (v) => setState(() {
                _refine = v;
                _page = 1;
              }),
            ),
          ),
          if (_refine.isNotEmpty) ...[
            const SizedBox(width: 6),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: m.ink500),
              onPressed: () => setState(() {
                _refine = '';
                _refineCtrl.clear();
                _page = 1;
              }),
            ),
          ],
        ]),
        const SizedBox(height: 10),
      ],

      // Meta: jumlah + rentang + peringatan terpotong.
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          MasEyebrow(_refine.trim().isNotEmpty ? 'Hasil saring' : 'Hasil'),
          Text(thousands(shown),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: m.ink900)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            // Saat hasil NOL, keterangannya pindah ke MasEmpty di bawah —
            // dulu ia jadi teks 12px abu-abu yang mudah terlewat, lalu di
            // bawahnya cuma ada ruang kosong (paritas dgn web).
            child: Text(
              shown > 0 ? 'Menampilkan $from–$to · ketuk baris untuk detail' : '',
              style: TextStyle(fontSize: 12, color: m.ink500),
            ),
          ),
        ),
      ]),
      if (_truncated && _refine.trim().isEmpty) ...[
        const SizedBox(height: 6),
        Text(
          'Memuat ${thousands(_all.length)} dari ${thousands(_totalCount)} — persempit kata kunci utama.',
          style: TextStyle(fontSize: 11.5, color: m.warn600),
        ),
      ],

      // Hasil NOL → empty state penuh dengan jalan keluar, bukan ruang kosong.
      if (shown == 0)
        MasEmpty(
          icon: Icons.search_off_rounded,
          title: _refine.trim().isNotEmpty
              ? 'Saringan tidak menyisakan hasil'
              : 'Tidak ada part yang cocok',
          subtitle: _refine.trim().isNotEmpty
              ? 'Tidak ada baris yang mengandung "${_refine.trim()}" di antara ${thousands(_all.length)} hasil pencarian.'
              : 'Coba kata kunci lain, atau beralih ke mode ${_byName ? "Part Number" : "Nama Part"}.',
          action: _refine.trim().isNotEmpty
              ? MasButton(
                  label: 'Hapus saringan',
                  primary: false,
                  height: 36,
                  onTap: () => setState(() {
                    _refine = '';
                    _refineCtrl.clear();
                    _page = 1;
                  }),
                )
              : (_saran.isNotEmpty
                  ? Column(children: [
                      Text('Mungkin maksud Anda:',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600, color: m.ink700)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [for (final s in _saran) _saranChip(m, s)],
                      ),
                    ])
                  : null),
        ),

      // Kontrol urut + per-halaman (hanya bila ada hasil).
      if (shown > 0) ...[
        const SizedBox(height: 12),
        _controlsRow(m, showStok, showHarga),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: m.paper,
            borderRadius: BorderRadius.circular(MasRadii.card),
            border: Border.all(color: m.ink150),
            boxShadow: m.shadow1,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final r in _pageItems) _row(m, r, showStok, showHarga, isBuyer),
          ]),
        ),
        if (_totalPages > 1) ...[
          const SizedBox(height: 14),
          _pager(m),
        ],
      ],
    ]);
  }

  Widget _saranChip(MasColors m, SaranPart s) {
    final label = s.partNumber.isNotEmpty
        ? (s.partName.isNotEmpty ? '${s.partNumber} — ${s.partName}' : s.partNumber)
        : s.partName;
    return Material(
      color: m.ink50,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () {
          // PN → cari mode PN; hanya-nama → cari mode nama (persis web).
          final byName = s.partNumber.isEmpty;
          final term = s.partNumber.isNotEmpty ? s.partNumber : s.partName;
          setState(() {
            _tab = byName ? 1 : 0;
            _ctrl.text = term;
            _query = term;
            _loading = true;
          });
          _runSearch(term, byName);
        },
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: m.ink200),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 11.5, color: m.ink700)),
        ),
      ),
    );
  }

  Widget _controlsRow(MasColors m, bool showStok, bool showHarga) {
    final sortOptions = <(String, String)>[
      ('', 'Urutkan: default'),
      ('part_number', 'Part Number'),
      ('part_name', 'Nama Part'),
      ('file', 'Unit / File'),
      if (showStok) ('stok', 'Stok'),
      if (showHarga) ('harga', 'Harga'),
    ];
    return Row(children: [
      Expanded(
        child: _MiniDropdown(
          value: _sortKey ?? '',
          options: sortOptions,
          onChanged: (v) => setState(() {
            _sortKey = v.isEmpty ? null : v;
            _dir = 'asc';
            _page = 1;
          }),
        ),
      ),
      const SizedBox(width: 8),
      _DirButton(
        dir: _dir,
        enabled: _sortKey != null,
        onTap: () => setState(() => _dir = _dir == 'asc' ? 'desc' : 'asc'),
      ),
      const SizedBox(width: 8),
      _MiniDropdown(
        value: '$_pageSize',
        options: [for (final s in _kPageSizes) ('$s', '$s / hal')],
        onChanged: (v) => setState(() {
          _pageSize = int.tryParse(v) ?? 20;
          _page = 1;
        }),
      ),
    ]);
  }

  Widget _pager(MasColors m) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      MasButton(
        label: '← Sebelumnya',
        primary: false,
        height: 34,
        onTap: _pageClamped <= 1 ? null : () => setState(() => _page = _pageClamped - 1),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('Hal $_pageClamped / $_totalPages',
            style: TextStyle(fontSize: 12.5, color: m.ink500)),
      ),
      MasButton(
        label: 'Berikutnya →',
        primary: false,
        height: 34,
        onTap: _pageClamped >= _totalPages ? null : () => setState(() => _page = _pageClamped + 1),
      ),
    ]);
  }

  Widget _row(MasColors m, PartResult r, bool showStok, bool showHarga, bool isBuyer) {
    final pn = r.partNumber;
    final name = r.partName;
    final file = r.file.isNotEmpty ? r.file : r.sheet;
    final hasSims = r.source == 'sims';

    return InkWell(
      onTap: () => AppNav.of(context).go(MasScreen.part, part: r.toMap()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: m.ink100))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(pn, style: masMono(size: 13, weight: FontWeight.w500, color: m.ink900)),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: m.ink900)),
                ),
                if (hasSims) ...[
                  const SizedBox(width: 6),
                  const MasPill(label: 'SIMS', tone: MasPillTone.info, height: 18),
                ],
              ]),
              if (file.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(file, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: m.ink600)),
              ],
            ]),
          ),
          if (showStok || showHarga) ...[
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              if (showStok)
                Text(r.stok.isEmpty ? '—' : r.stok,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: m.ink900)),
              if (showStok && showHarga) const SizedBox(height: 2),
              if (showHarga)
                Text(r.harga.isEmpty ? '—' : r.harga,
                    style: masMono(size: 11.5, weight: FontWeight.w500, color: m.brand700)),
            ]),
          ],
          if (isBuyer) ...[
            const SizedBox(width: 8),
            _buyerAction(m, r),
          ],
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 16, color: m.ink300),
        ]),
      ),
    );
  }

  /// Aksi keranjang pembeli — persis web: Habis / Tanpa harga / Tanpa berat /
  /// tombol tambah.
  Widget _buyerAction(MasColors m, PartResult r) {
    final totalGudang = r.gudang.values.fold<num>(0, (n, q) => n + q);
    if (totalGudang <= 0) {
      return const MasPill(label: 'Habis', tone: MasPillTone.danger, height: 22);
    }
    if (!hasPrice(r.harga)) {
      return const MasPill(label: 'Tanpa harga', tone: MasPillTone.warn, height: 22);
    }
    if (!hasWeight(r.berat)) {
      return const MasPill(label: 'Tanpa berat', tone: MasPillTone.warn, height: 22);
    }
    return Material(
      color: m.paper,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _addToCart(r),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34, height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: m.ink200),
          ),
          child: Icon(Icons.add_shopping_cart_outlined, size: 16, color: m.brand700),
        ),
      ),
    );
  }
}

/// Dropdown ringkas (urut / per-halaman).
class _MiniDropdown extends StatelessWidget {
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  const _MiniDropdown({required this.value, required this.options, required this.onChanged});

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
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: m.ink500),
          style: TextStyle(fontSize: 12.5, color: m.ink800),
          dropdownColor: m.paper,
          items: [
            for (final (key, label) in options)
              DropdownMenuItem(value: key, child: Text(label, overflow: TextOverflow.ellipsis)),
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

/// Tombol arah urut (naik/turun).
class _DirButton extends StatelessWidget {
  final String dir;
  final bool enabled;
  final VoidCallback onTap;
  const _DirButton({required this.dir, required this.enabled, required this.onTap});

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
            const SizedBox(width: 3),
            Text(asc ? 'A→Z' : 'Z→A',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: enabled ? m.ink700 : m.ink300)),
          ]),
        ),
      ),
    );
  }
}
