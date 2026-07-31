// lib/screens/rak_screen.dart — menu "Rak & Kartu Stok": lookup TERBALIK
// (isi satu gudang) + edit satu-satu.
//
// Sistem sudah tahu BERAPA stoknya (Accurate); layar ini menjawab DI MANA
// barangnya. Menu ini hanya muncul untuk pengelola gudang (lihat nav.dart) —
// staf lain tetap bisa MELIHAT rak dari halaman Detail Part.
//
// ⛔ Impor massal Excel sengaja TIDAK ada di mobile: formatnya butuh menyiapkan
// file kolom "Part Number | Rak | Catatan" di komputer, jadi fiturnya web-only
// (`/rak` di web). Di HP alurnya satu-satu sambil berdiri di depan rak.
import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';
import '../widgets/rak_editor.dart';

class RakScreen extends StatefulWidget {
  const RakScreen({super.key});

  @override
  State<RakScreen> createState() => _RakScreenState();
}

class _RakScreenState extends State<RakScreen> {
  final _cariCtrl = TextEditingController();

  /// Gudang yang boleh dipilih di dropdown. Untuk staf = daftar wewenangnya
  /// sendiri (dari izin); untuk admin = SEMUA gudang (admin kebal gerbang tulis,
  /// jadi membatasinya ke gudang_kelola miliknya justru mengunci dia keluar).
  List<String> _gudangOpsi = const [];
  String? _gudang;

  List<RakInfo> _items = const [];
  bool _loadingGudang = true;
  bool _loading = false;
  String? _err;
  bool _siap = false; // daftar gudang cukup disiapkan sekali

  /// Saring "kartunya belum difoto" — kelengkapan foto adalah misi staf,
  /// jadi sisa kerjaannya harus bisa dipanggil satu ketukan (paritas web).
  bool _tanpaFoto = false;

  /// Saringan LIVE di klien atas baris yang sudah dimuat: mengetik menyaring
  /// seketika; tombol Cari tetap menembak server (utk gudang > limit baris).
  List<RakInfo> get _shown {
    final q = _cariCtrl.text.trim().toLowerCase();
    return [
      for (final r in _items)
        if ((!_tanpaFoto || r.fotoUrl.isEmpty) &&
            (q.isEmpty ||
                r.partNumber.toLowerCase().contains(q) ||
                r.rak.toLowerCase().contains(q) ||
                r.catatan.toLowerCase().contains(q)))
          r,
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_siap) return;
    _siap = true;
    _siapkanGudang();
  }

  @override
  void dispose() {
    _cariCtrl.dispose();
    super.dispose();
  }

  Future<void> _siapkanGudang() async {
    final nav = AppNav.of(context);
    var opsi = [...nav.gudangKelola];
    if (nav.isAdmin) {
      // Admin butuh daftar penuh; endpoint ini memang sudah dipakai layar
      // Lokasi Gudang, jadi tak ada permukaan API baru.
      try {
        final semua = await ApiService.adminGudang();
        final label = [
          for (final g in semua)
            if (g.label.trim().isNotEmpty) g.label,
        ]..sort();
        if (label.isNotEmpty) opsi = label;
      } catch (_) {
        /* gagal → jatuh ke gudang_kelola milik admin (bisa kosong) */
      }
    }
    if (!mounted) return;
    setState(() {
      _gudangOpsi = opsi;
      _gudang = opsi.isNotEmpty ? opsi.first : null;
      _loadingGudang = false;
    });
    if (_gudang != null) _muat();
  }

  Future<void> _muat() async {
    final g = _gudang;
    if (g == null) return;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final rows = await ApiService.rakGudang(g, q: _cariCtrl.text);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _ubah(String pn, RakInfo? awal) async {
    final g = _gudang;
    if (g == null) return;
    final hasil = await showRakEditor(context, pn: pn, gudang: g, awal: awal);
    if (hasil == null || !mounted) return;
    AppNav.of(context)
        .toast(hasil.dihapus ? 'Data rak dihapus.' : 'Rak $pn disimpan.');
    // Muat ulang, bukan tambal lokal: urutan daftar ditentukan server (rak.asc)
    // dan pencarian `q` bisa membuat baris yang baru diubah tak lagi cocok.
    await _muat();
  }

  /// Tambah baris baru: PN diketik dulu, sisanya lewat editor yang sama.
  Future<void> _tambah() async {
    final ctrl = TextEditingController();
    final pn = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah lokasi rak'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Part Number',
            hintText: 'mis. WG9525160004',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (pn == null || pn.isEmpty || !mounted) return;
    await _ubah(pn.toUpperCase(), null);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final g = _gudang;

    if (_loadingGudang) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: MasSkeleton(height: 120),
      );
    }

    if (g == null) {
      return MasEmpty(
        icon: Icons.shelves,
        title: 'Belum ada gudang yang Anda kelola',
        subtitle:
            'Minta admin mengisi "Gudang Kelola" akun Anda di Manajemen User '
            '(web). Tanpa itu, tak ada gudang yang bisa diisi rak dari sini.',
      );
    }

    return RefreshIndicator(
      onRefresh: _muat,
      color: m.brand600,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Catat lokasi rak & foto kartu stok per gudang. Angka stok yang '
            'berlaku tetap dari Accurate — data di sini menjawab DI MANA '
            'barangnya, bukan berapa.',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: m.ink500),
          ),
          const SizedBox(height: 14),
          _pemilihGudang(m),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: MasInput(
                controller: _cariCtrl,
                hint: 'Cari PN, kode rak, atau catatan',
                prefix: Icon(Icons.search_rounded, size: 16, color: m.ink400),
                action: TextInputAction.search,
                // Mengetik = saring live atas baris termuat; submit = server.
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _muat(),
              ),
            ),
            const SizedBox(width: 8),
            MasButton(label: 'Cari', onTap: _muat, height: 44),
          ]),
          const SizedBox(height: 10),
          // Tombol tambah hanya berarti bila gudang terpilih memang wewenangnya.
          if (nav.bolehUbahRak(g))
            MasButton(
              label: 'Tambah lokasi rak',
              icon: Icons.add_rounded,
              primary: false,
              height: 40,
              expand: true,
              onTap: _tambah,
            ),
          const SizedBox(height: 14),
          if (_err != null) ...[
            _kotakGalat(m, _err!),
            const SizedBox(height: 12),
          ],
          if (_loading) ...[
            const MasSkeleton(height: 66),
            const SizedBox(height: 8),
            const MasSkeleton(height: 66),
            const SizedBox(height: 8),
            const MasSkeleton(height: 66),
          ] else if (_shown.isEmpty)
            MasEmpty(
              icon: Icons.inventory_2_outlined,
              title: _items.isEmpty && _cariCtrl.text.trim().isEmpty
                  ? 'Gudang ini belum punya data rak'
                  : 'Tidak ada yang cocok',
              subtitle: _items.isEmpty && _cariCtrl.text.trim().isEmpty
                  ? 'Mulai dengan menambahkan satu part beserta kode raknya.'
                  : 'Coba kata kunci lain — pencarian menyisir PN, kode rak, '
                      'dan catatan.',
              action: _items.isEmpty && _cariCtrl.text.trim().isEmpty
                  ? (nav.bolehUbahRak(g)
                      ? MasButton(
                          label: 'Tambah lokasi rak',
                          icon: Icons.add_rounded,
                          onTap: _tambah,
                        )
                      : null)
                  : MasButton(
                      label: 'Hapus saringan',
                      primary: false,
                      onTap: () {
                        _cariCtrl.clear();
                        setState(() => _tanpaFoto = false);
                        _muat();
                      },
                    ),
            )
          else ...[
            // Bilah statistik: kelengkapan foto = misi ("semua kartu terpotret");
            // chip menyaring sisa kerjaan, bukan sekadar angka pasif.
            Builder(builder: (_) {
              final berfoto =
                  _items.where((r) => r.fotoUrl.isNotEmpty).length;
              final saring =
                  _cariCtrl.text.trim().isNotEmpty || _tanpaFoto;
              return Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  Text(
                    saring
                        ? '${_shown.length} dari ${_items.length} baris · $berfoto berfoto'
                        : '${_items.length} baris · $berfoto berfoto',
                    style: TextStyle(fontSize: 12, color: m.ink500),
                  ),
                  if (berfoto < _items.length)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _tanpaFoto = !_tanpaFoto),
                      child: MasPill(
                        label:
                            '${_tanpaFoto ? "✕ " : ""}tanpa foto: ${_items.length - berfoto}',
                        tone: _tanpaFoto
                            ? MasPillTone.warn
                            : MasPillTone.neutral,
                      ),
                    ),
                ],
              );
            }),
            const SizedBox(height: 8),
            for (final it in _shown) ...[
              _baris(m, nav, it),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _pemilihGudang(MasColors m) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.input),
        border: Border.all(color: m.ink200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _gudang,
          isExpanded: true,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: m.ink500),
          style: TextStyle(fontSize: 13.5, color: m.ink900),
          dropdownColor: m.paper,
          items: [
            for (final g in _gudangOpsi)
              DropdownMenuItem(
                value: g,
                child: Text(g, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v == null || v == _gudang) return;
            setState(() => _gudang = v);
            _muat();
          },
        ),
      ),
    );
  }

  Widget _baris(MasColors m, AppNav nav, RakInfo it) {
    final boleh = nav.bolehUbahRak(it.gudang.isEmpty ? (_gudang ?? '') : it.gudang);
    final jejak = jejakRak(it);

    return MasCard(
      // Ketuk baris = ubah (bila berwenang). Membuka Detail Part disediakan
      // tombol terpisah supaya dua niat itu tak saling tertukar.
      onTap: boleh ? () => _ubah(it.partNumber, it) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(it.partNumber,
                style: masMono(size: 14, weight: FontWeight.w600, color: m.ink900)),
          ),
          if (it.fotoUrl.isNotEmpty) ...[
            Icon(Icons.image_outlined, size: 15, color: m.ink400),
            const SizedBox(width: 6),
          ],
          MasPill(label: 'rak ${it.rak}', tone: MasPillTone.brand, height: 22),
        ]),
        if (it.catatan.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(it.catatan,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: m.ink600)),
        ],
        if (it.fotoUrl.isNotEmpty) ...[
          const SizedBox(height: 10),
          RakFotoView(url: it.fotoUrl, tinggi: 130),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text(jejak, style: TextStyle(fontSize: 11, color: m.ink400)),
          ),
          _tautanKecil(m, 'Detail part', Icons.open_in_new_rounded, () {
            nav.go(MasScreen.part, part: {'part_number': it.partNumber});
          }),
          if (boleh) ...[
            const SizedBox(width: 6),
            _tautanKecil(m, 'Ubah', Icons.edit_outlined,
                () => _ubah(it.partNumber, it)),
          ],
        ]),
      ]),
    );
  }

  Widget _tautanKecil(
          MasColors m, String label, IconData icon, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MasRadii.input),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: m.brand600),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: m.brand700)),
          ]),
        ),
      );

  Widget _kotakGalat(MasColors m, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: m.danger50,
          borderRadius: BorderRadius.circular(MasRadii.input),
          border: Border.all(color: m.dangerBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline_rounded, size: 15, color: m.danger600),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, height: 1.45, color: m.danger600)),
          ),
        ]),
      );
}
