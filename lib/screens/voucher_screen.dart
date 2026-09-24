// lib/screens/voucher_screen.dart
// "Voucher" pembeli — klaim voucher gratis ongkir & diskon, Voucher Saya, dan
// tukar kode. Paritas dengan web `frontend/src/app/voucher/page.tsx`.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';
import '../widgets/voucher_tiket.dart';

class VoucherScreen extends StatefulWidget {
  const VoucherScreen({super.key});

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  bool _aktif = true;
  List<Voucher> _tersedia = [];
  List<Voucher> _saya = [];
  bool _loading = true;
  String? _error;
  bool _tabSaya = false;
  String _filter = 'semua';
  final _kode = TextEditingController();
  Object? _sibuk; // id voucher / 'kode'

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ApiService.vouchers();
      if (!mounted) return;
      setState(() {
        _aktif = d.aktif;
        _tersedia = d.tersedia;
        _saya = d.saya;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat voucher. Periksa koneksi Anda.';
        _loading = false;
      });
    }
  }

  void _toast(String teks, {bool ok = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(teks),
      backgroundColor: ok ? null : context.mas.danger600,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _klaim(Voucher v) async {
    setState(() => _sibuk = v.id);
    try {
      _toast(await ApiService.klaimVoucher(v.id));
      await _load();
    } on ApiException catch (e) {
      _toast(e.message, ok: false);
    } catch (_) {
      _toast('Gagal mengklaim voucher.', ok: false);
    } finally {
      if (mounted) setState(() => _sibuk = null);
    }
  }

  Future<void> _tukarKode() async {
    final c = _kode.text.trim().toUpperCase();
    if (c.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _sibuk = 'kode');
    try {
      _toast(await ApiService.klaimKodeVoucher(c));
      _kode.clear();
      setState(() => _tabSaya = true);
      await _load();
    } on ApiException catch (e) {
      _toast(e.message, ok: false);
    } catch (_) {
      _toast('Kode voucher tidak valid.', ok: false);
    } finally {
      if (mounted) setState(() => _sibuk = null);
    }
  }

  List<Voucher> get _sayaBisa =>
      _saya.where((v) => v.usedOrderCode.isEmpty && v.berlaku).toList();
  List<Voucher> get _sayaLain =>
      _saya.where((v) => v.usedOrderCode.isNotEmpty || !v.berlaku).toList();

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final sumber = _tabSaya ? _sayaBisa : _tersedia;
    final daftar =
        _filter == 'semua' ? sumber : sumber.where((v) => v.jenis == _filter).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: m.danger50,
                borderRadius: BorderRadius.circular(MasRadii.card),
                border: Border.all(color: m.dangerBorder),
              ),
              child: Text(_error!,
                  style: TextStyle(fontSize: 12.5, color: m.danger600)),
            ),
            const SizedBox(height: 12),
          ],
          _hero(m),
          const SizedBox(height: 14),
          if (!_loading && !_aktif)
            MasCard(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              child: Column(children: [
                Text('Voucher belum tersedia',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: m.ink900)),
                const SizedBox(height: 4),
                Text('Program voucher belum aktif di toko ini. Nantikan promonya.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: m.ink500)),
              ]),
            )
          else ...[
            _tabBar(m),
            const SizedBox(height: 10),
            _chips(m, sumber),
            const SizedBox(height: 12),
            if (_loading)
              for (var i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 100),
                )
            else if (daftar.isEmpty)
              MasCard(
                padding:
                    const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                child: Column(children: [
                  Text(
                      _tabSaya
                          ? 'Voucher Saya masih kosong'
                          : 'Belum ada voucher untuk diklaim',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: m.ink900)),
                  const SizedBox(height: 4),
                  Text(
                      _tabSaya
                          ? 'Klaim voucher di tab Klaim Voucher, lalu voucher otomatis terpasang saat checkout.'
                          : 'Promo baru akan muncul di sini. Punya kode voucher? Masukkan di kolom atas.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: m.ink500, height: 1.5)),
                  if (_tabSaya) ...[
                    const SizedBox(height: 12),
                    MasButton(
                      label: 'Lihat voucher',
                      height: 36,
                      onTap: () => setState(() => _tabSaya = false),
                    ),
                  ],
                ]),
              )
            else
              for (final v in daftar)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _tiket(v, nav),
                ),
            if (_tabSaya && _sayaLain.isNotEmpty) ...[
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Riwayat voucher (${_sayaLain.length})',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: m.ink700)),
                  children: [
                    for (final v in _sayaLain)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: VoucherTiket(
                          v: v,
                          redup: true,
                          catatan: v.usedOrderCode.isNotEmpty
                              ? 'Dipakai di pesanan ${v.usedOrderCode} ›'
                              : 'Sudah berakhir',
                          // Ketuk → buka pesanan tempat voucher dipakai
                          // (paritas web: kode pesanan = tautan).
                          onTap: v.usedOrderCode.isNotEmpty
                              ? () => nav.go(MasScreen.pesananDetail,
                                  part: {'order_code': v.usedOrderCode})
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            _ketentuan(m),
          ],
        ],
      ),
    );
  }

  Widget _tiket(Voucher v, AppNav nav) {
    if (_tabSaya) {
      return VoucherTiket(
        v: v,
        aksi: VoucherTombol(
            label: 'Pakai',
            ongkir: v.ongkir,
            garis: true,
            onTap: () => nav.go(MasScreen.keranjang)),
      );
    }
    final habis = v.sisaKuota == 0 && !v.diklaim;
    final Widget aksi;
    if (v.terpakai) {
      aksi = VoucherTombol(label: 'Terpakai', ongkir: v.ongkir);
    } else if (v.diklaim || v.otomatis) {
      // Voucher otomatis tak perlu diklaim: sudah ada di keranjang.
      aksi = VoucherTombol(
          label: 'Pakai',
          ongkir: v.ongkir,
          garis: true,
          onTap: () => nav.go(MasScreen.keranjang));
    } else {
      aksi = VoucherTombol(
        label: habis ? 'Habis' : (_sibuk == v.id ? '…' : 'Klaim'),
        ongkir: v.ongkir,
        onTap: (habis || _sibuk == v.id) ? null : () => _klaim(v),
      );
    }
    return VoucherTiket(
      v: v,
      redup: habis || v.terpakai,
      catatan: v.otomatis && !v.diklaim
          ? 'Otomatis — tanpa klaim, langsung ada di keranjang'
          : v.deskripsi,
      aksi: aksi,
    );
  }

  Widget _hero(MasColors m) {
    final siap = _tersedia.where((v) => !v.diklaim).length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF028912), kTealVoucher, Color(0xFFB9772F)],
          stops: [0, 0.6, 1],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Voucher MasPart',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4)),
        const SizedBox(height: 2),
        Text(
            _loading
                ? 'Memuat…'
                : !_aktif
                    ? 'Gratis ongkir & potongan harga untuk belanja part'
                    : '$siap voucher tersedia · ${_sayaBisa.length} di Voucher Saya',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _kode,
                enabled: _aktif,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1B211D)),
                decoration: const InputDecoration(
                  hintText: 'Punya kode voucher?',
                  hintStyle:
                      TextStyle(color: Color(0xFF9EA5A0), fontWeight: FontWeight.w400),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                onSubmitted: (_) => _tukarKode(),
              ),
            ),
            SizedBox(
              height: 38,
              child: FilledButton(
                onPressed: (!_aktif || _sibuk == 'kode') ? null : _tukarKode,
                style: FilledButton.styleFrom(
                  backgroundColor: m.brand600,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7)),
                ),
                child: Text(_sibuk == 'kode' ? '…' : 'Pakai'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _tabBar(MasColors m) {
    Widget tab(String label, bool on, VoidCallback tap, {int n = 0}) => Expanded(
          child: InkWell(
            onTap: tap,
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: on ? m.brand600 : m.ink150, width: on ? 3 : 1),
                ),
              ),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: on
                            ? (m.isDark ? m.brand700 : m.brand600)
                            : m.ink600)),
                if (n > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: m.danger600,
                        borderRadius: BorderRadius.circular(99)),
                    child: Text('$n',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
            ),
          ),
        );
    return Row(children: [
      tab('Klaim Voucher', !_tabSaya, () => setState(() => _tabSaya = false)),
      tab('Voucher Saya', _tabSaya, () => setState(() => _tabSaya = true),
          n: _sayaBisa.length),
    ]);
  }

  Widget _chips(MasColors m, List<Voucher> sumber) {
    int hitung(String j) =>
        j == 'semua' ? sumber.length : sumber.where((v) => v.jenis == j).length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (j, label) in const [
          ('semua', 'Semua'),
          ('ongkir', 'Gratis Ongkir'),
          ('diskon', 'Diskon'),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('$label  ${hitung(j)}'),
              selected: _filter == j,
              onSelected: (_) => setState(() => _filter = j),
              selectedColor: m.brand50,
              labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: _filter == j ? FontWeight.w600 : FontWeight.w500,
                  color: _filter == j ? m.brand700 : m.ink700),
              side: BorderSide(color: _filter == j ? m.brand600 : m.ink200),
              showCheckmark: false,
            ),
          ),
      ]),
    );
  }

  Widget _ketentuan(MasColors m) {
    const aturan = [
      'Per pesanan bisa memakai 1 voucher Gratis Ongkir dan 1 voucher Diskon sekaligus.',
      'Minimal belanja dihitung dari harga barang, belum termasuk ongkir.',
      'Voucher Gratis Ongkir tidak berlaku untuk Ambil di Toko.',
      'Voucher yang sudah diklaim tetap tersimpan sampai masa berlakunya habis.',
      'Pesanan dibatalkan? Voucher kembali ke Voucher Saya selama masih berlaku.',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: m.ink50,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.ink150),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ketentuan umum',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: m.ink800)),
        const SizedBox(height: 6),
        for (final t in aturan)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('•  ', style: TextStyle(fontSize: 12.5, color: m.ink500)),
              Expanded(
                child: Text(t,
                    style: TextStyle(
                        fontSize: 12.5, height: 1.5, color: m.ink700)),
              ),
            ]),
          ),
      ]),
    );
  }
}
