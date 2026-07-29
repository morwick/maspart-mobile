// lib/screens/harga_screen.dart — Harga: List, Cari (per-PN), Batch.
import 'package:flutter/material.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';
import '../utils.dart';
import '../api_service.dart';
import '../app/nav.dart';

class HargaScreen extends StatefulWidget {
  const HargaScreen({super.key});
  @override
  State<HargaScreen> createState() => _HargaScreenState();
}

class _HargaScreenState extends State<HargaScreen> {
  int _tab = 0; // 0 list, 1 cari, 2 batch

  // list
  final _listCtrl = TextEditingController();
  bool _listLoading = false;
  bool _listSearched = false;
  List<Map<String, dynamic>> _listRows = [];

  // cari (per-PN)
  final _cariCtrl = TextEditingController();
  bool _cariLoading = false;
  Map<String, dynamic>? _cariResult;
  bool _cariNotFound = false;

  final _batchCtrl = TextEditingController();

  @override
  void dispose() {
    _listCtrl.dispose();
    _cariCtrl.dispose();
    _batchCtrl.dispose();
    super.dispose();
  }

  Future<void> _runList() async {
    final q = _listCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _listSearched = true;
      _listLoading = true;
    });
    try {
      final byName = !RegExp(r'[0-9]').hasMatch(q);
      final data = await ApiService.searchPart(query: q, byName: byName, limit: 100);
      if (!mounted) return;
      setState(() {
        _listRows = data;
        _listLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _listRows = [];
        _listLoading = false;
      });
    }
  }

  Future<void> _runCari() async {
    final q = _cariCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _cariLoading = true;
      _cariResult = null;
      _cariNotFound = false;
    });
    try {
      final data = await ApiService.searchPart(query: q, byName: false, limit: 5);
      if (!mounted) return;
      final hit = data.isNotEmpty ? data.first : null;
      setState(() {
        _cariResult = hit;
        _cariNotFound = hit == null;
        _cariLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cariNotFound = true;
        _cariLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: MasSegmentTabs(
            tabs: const ['List Harga', 'Cari Harga', 'Batch Cari'],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        const SizedBox(height: 16),
        if (_tab == 0) ..._listView() else if (_tab == 1) ..._cariView() else ..._batchView(),
      ],
    );
  }

  List<Widget> _listView() {
    final m = context.mas;
    return [
      Row(children: [
        Expanded(
          child: MasInput(
            controller: _listCtrl,
            hint: 'Cari Part Number / Part Name…',
            mono: true,
            height: 40,
            onSubmitted: (_) => _runList(),
            action: TextInputAction.search,
          ),
        ),
        const SizedBox(width: 8),
        MasButton(label: 'Cari', height: 40, onTap: _runList),
      ]),
      const SizedBox(height: 12),
      if (!_listSearched)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Ketik untuk menampilkan daftar harga part.', style: TextStyle(fontSize: 12, color: m.ink500)),
        )
      else if (_listLoading)
        const MasSkeleton(height: 200)
      else if (_listRows.isEmpty)
        MasEmpty(icon: Icons.search_off_rounded, title: 'Tidak ada hasil', subtitle: 'Coba kata kunci lain.')
      else ...[
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${_listRows.length} part', style: TextStyle(fontSize: 12, color: m.ink500)),
          Text('Urut: Part Number', style: TextStyle(fontSize: 12, color: m.ink500)),
        ]),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: m.paper,
            borderRadius: BorderRadius.circular(MasRadii.card),
            border: Border.all(color: m.ink150),
            boxShadow: m.shadow1,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final r in _listRows)
              InkWell(
                onTap: () => AppNav.of(context).go(MasScreen.part, part: r),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: m.ink100))),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('${r['part_number'] ?? ''}', style: masMono(size: 12.5, weight: FontWeight.w500, color: m.ink900)),
                        const SizedBox(height: 2),
                        Text('${r['part_name'] ?? ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: m.ink600)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Text(asNum(r['harga']) == null ? '—' : formatRupiah(asNum(r['harga'])),
                        style: masMono(size: 12.5, weight: FontWeight.w600, color: m.brand700)),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        MasButton(label: 'Export Excel', icon: Icons.download_rounded, primary: false, height: 36,
            onTap: () => AppNav.of(context).toast('Export Excel diproses di server.')),
      ],
    ];
  }

  List<Widget> _cariView() {
    final m = context.mas;
    return [
      Row(children: [
        Expanded(
          child: MasInput(
            controller: _cariCtrl,
            hint: 'Part Number…',
            mono: true,
            height: 40,
            onSubmitted: (_) => _runCari(),
            action: TextInputAction.search,
          ),
        ),
        const SizedBox(width: 8),
        MasButton(label: 'Cari', height: 40, onTap: _runCari),
      ]),
      const SizedBox(height: 14),
      if (_cariLoading)
        const MasSkeleton(height: 120)
      else if (_cariNotFound)
        MasEmpty(icon: Icons.search_off_rounded, title: 'PN tidak ditemukan', subtitle: 'Periksa kembali nomor part.')
      else if (_cariResult != null)
        MasSectionCard(
          title: '${_cariResult!['part_number'] ?? ''}',
          trailing: const MasPill(label: 'live', tone: MasPillTone.info, height: 20),
          children: [
            MasKeyValue(
              label: 'Estimasi Harga',
              value: asNum(_cariResult!['harga']) == null ? '—' : formatRupiah(asNum(_cariResult!['harga'])),
              mono: true,
              valueColor: m.brand700,
            ),
            MasKeyValue(label: 'Nama part', value: '${_cariResult!['part_name'] ?? '-'}'),
            // Server memasang topeng '—' bila izin Kolom Stok dimatikan untuk
            // akun ini — jangan diterjemahkan jadi angka 0 (stok nol ≠ dirahasiakan).
            MasKeyValue(
                label: 'Stok',
                value: asNum(_cariResult!['stok']) == null
                    ? '—'
                    : '${asInt(_cariResult!['stok'])}',
                divider: false),
          ],
        ),
    ];
  }

  List<Widget> _batchView() {
    final m = context.mas;
    return [
      Text('Tempel daftar Part Number (satu per baris), lalu jalankan pencarian harga massal.',
          style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5)),
      const SizedBox(height: 10),
      MasInput(
        controller: _batchCtrl,
        hint: 'WG9925520270\nVG61000070005\n612630080087',
        mono: true,
        maxLines: 6,
      ),
      const SizedBox(height: 12),
      MasButton(label: 'Jalankan Batch', expand: true, height: 44,
          onTap: () => AppNav.of(context).toast('Batch harga diproses — hasil dikirim sebagai Excel.')),
      const SizedBox(height: 10),
      Text('Hasil batch dikirim sebagai file Excel — progres tampil di sini.',
          style: TextStyle(fontSize: 11.5, color: m.ink400)),
    ];
  }
}
