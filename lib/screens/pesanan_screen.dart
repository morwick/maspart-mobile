// lib/screens/pesanan_screen.dart
// "Pesanan Saya" — daftar pesanan milik pembeli.

import 'dart:async';

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../invoice_pdf.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/beli_lagi.dart';
import '../widgets/mas_ui.dart';

/// Status LUNAS — baris pesanan ini boleh mencetak invoice.
const _kPaidStatus = {'diproses', 'dikirim', 'selesai'};

/// Tab filter status — sama persis dengan web (`pesanan/page.tsx` TABS).
class _OrderTab {
  final String key;
  final String label;
  final bool Function(String status) match;
  const _OrderTab(this.key, this.label, this.match);
}

final _orderTabs = <_OrderTab>[
  _OrderTab('all', 'Semua', (s) => true),
  _OrderTab('belum', 'Belum Bayar',
      (s) => s == 'menunggu_pembayaran' || s == 'menunggu_verifikasi'),
  _OrderTab('diproses', 'Diproses', (s) => s == 'diproses'),
  _OrderTab('dikirim', 'Dikirim', (s) => s == 'dikirim'),
  _OrderTab('selesai', 'Selesai', (s) => s == 'selesai'),
  _OrderTab('batal', 'Dibatalkan', (s) => s == 'batal'),
];

class PesananScreen extends StatefulWidget {
  /// `{'tab': 'belum'|'diproses'|'dikirim'|'selesai'|'batal'}` — pintasan
  /// status dari Profil Saya (cermin `/pesanan?tab=` di web).
  final Map<String, dynamic>? args;
  const PesananScreen({super.key, this.args});

  @override
  State<PesananScreen> createState() => _PesananScreenState();
}

class _PesananScreenState extends State<PesananScreen> {
  List<OrderSummary> _orders = [];
  bool _loading = true;
  String? _error;
  final Set<String> _invoiceBusy = {}; // kode pesanan yang sedang dibuat invoice-nya
  final Set<String> _beliLagiBusy = {}; // kode pesanan yang sedang di-"Beli Lagi"

  String _tab = 'all';
  final _searchCtrl = TextEditingController();
  String _q = '';

  // Hitung mundur batas bayar — cukup per 30 dtk (tampilannya per menit).
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    final awal = widget.args?['tab']?.toString();
    if (awal != null && _orderTabs.any((t) => t.key == awal)) _tab = awal;
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Jumlah pesanan per tab (untuk badge hitungan).
  Map<String, int> get _counts => {
        for (final t in _orderTabs)
          t.key: _orders.where((o) => t.match(o.status)).length,
      };

  /// Pesanan setelah difilter tab + kata kunci (kode / gudang / nama barang /
  /// PN) — persis web.
  List<OrderSummary> get _filtered {
    final t = _orderTabs.firstWhere((e) => e.key == _tab,
        orElse: () => _orderTabs.first);
    final term = _q.trim().toLowerCase();
    return _orders
        .where((o) => t.match(o.status))
        .where((o) =>
            term.isEmpty ||
            o.orderCode.toLowerCase().contains(term) ||
            _namaGudang(o).toLowerCase().contains(term) ||
            o.cuplikan.any((it) =>
                it.name.toLowerCase().contains(term) ||
                it.partNumber.toLowerCase().contains(term)))
        .toList();
  }

  /// Ambil detail pesanan lalu buat & buka Invoice PDF (setara tombol invoice
  /// per-baris di web). Daftar hanya punya ringkasan, jadi detail di-fetch dulu.
  Future<void> _cetakInvoice(String code) async {
    if (_invoiceBusy.contains(code)) return;
    setState(() => _invoiceBusy.add(code));
    try {
      final o = await ApiService.order(code);
      await downloadInvoicePdf(o);
    } catch (e) {
      if (mounted) AppNav.of(context).toast('Gagal membuat invoice: $e');
    } finally {
      if (mounted) setState(() => _invoiceBusy.remove(code));
    }
  }

  /// Tombol "Beli Lagi" di kartu — alur lengkapnya di `beliLagiDariPesanan`
  /// (isi ulang keranjang → ringkasan → buka Keranjang).
  Future<void> _beliLagi(String code) async {
    if (_beliLagiBusy.contains(code)) return;
    setState(() => _beliLagiBusy.add(code));
    try {
      await beliLagiDariPesanan(context, code);
    } finally {
      if (mounted) setState(() => _beliLagiBusy.remove(code));
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final o = await ApiService.myOrders();
      if (!mounted) return;
      setState(() {
        _orders = o;
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

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final counts = _counts;
    final belumBayar =
        _orders.where((o) => o.status == 'menunggu_pembayaran').length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
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
            const SizedBox(height: 14),
          ],

          // Ringkasan status — sekaligus pintasan ke tab (sama dengan web).
          _ringkasan(m, counts),
          const SizedBox(height: 12),

          // Pintu masuk riwayat "Beli Lagi" (pola Tokopedia) — hanya pembeli.
          if (nav.isBuyer) ...[
            _pintuBeliLagi(m, nav),
            const SizedBox(height: 12),
          ],

          if (!_loading && belumBayar > 0 && _tab != 'belum') ...[
            _pengingatBayar(m, belumBayar),
            const SizedBox(height: 12),
          ],

          if (_loading)
            Column(children: [
              for (int i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: MasSkeleton(height: 150),
                ),
            ])
          else ...[
            _tabBar(m, counts),
            const SizedBox(height: 10),
            MasInput(
              controller: _searchCtrl,
              hint: 'Cari kode, nama barang, atau PN…',
              height: 40,
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 12),
            if (_orders.isEmpty)
            Column(children: [
              const SizedBox(height: 30),
              const MasEmpty(
                icon: Icons.receipt_long_outlined,
                title: 'Belum ada pesanan',
                subtitle:
                    'Pesanan yang kamu buat akan muncul di sini lengkap dengan statusnya.',
              ),
              const SizedBox(height: 12),
              Center(
                child: MasButton(
                  label: 'Mulai belanja',
                  icon: Icons.storefront_outlined,
                  onTap: () => nav.go(MasScreen.toko),
                ),
              ),
            ])
            else if (_filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Column(children: [
                  Text('Tidak ada pesanan yang cocok',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: m.ink800)),
                  const SizedBox(height: 4),
                  Text('Coba tab lain atau ubah kata pencarian.',
                      style: TextStyle(fontSize: 12.5, color: m.ink500)),
                  const SizedBox(height: 12),
                  MasButton(
                    label: 'Tampilkan semua',
                    primary: false,
                    height: 36,
                    onTap: () => setState(() {
                      _tab = 'all';
                      _q = '';
                      _searchCtrl.clear();
                    }),
                  ),
                ]),
              )
            else
              for (final o in _filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _card(m, nav, o),
                ),
          ],
        ],
      ),
    );
  }

  Widget _ringkasan(MasColors m, Map<String, int> counts) {
    const items = <(String, String, IconData, _Nada)>[
      ('belum', 'Belum Bayar', Icons.account_balance_wallet_outlined, _Nada.warn),
      ('diproses', 'Diproses', Icons.inventory_2_outlined, _Nada.info),
      ('dikirim', 'Dikirim', Icons.local_shipping_outlined, _Nada.info),
      ('selesai', 'Selesai', Icons.check_circle_outline, _Nada.brand),
    ];
    return Row(children: [
      for (int i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(child: _ringkasItem(m, items[i], counts[items[i].$1] ?? 0)),
      ],
    ]);
  }

  Widget _ringkasItem(
      MasColors m, (String, String, IconData, _Nada) it, int n) {
    final aktif = _tab == it.$1;
    final (fg, bg) = _warnaNada(m, it.$4);
    return Material(
      color: m.paper,
      borderRadius: BorderRadius.circular(MasRadii.card),
      child: InkWell(
        onTap: () => setState(() => _tab = aktif ? 'all' : it.$1),
        borderRadius: BorderRadius.circular(MasRadii.card),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MasRadii.card),
            border: Border.all(
                color: aktif ? m.brand600 : m.ink200, width: aktif ? 1.5 : 1),
          ),
          child: Column(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(10)),
              child: Icon(it.$3, size: 19, color: fg),
            ),
            const SizedBox(height: 5),
            Text(_loading ? '–' : '$n',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: m.ink900)),
            Text(it.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: m.ink500)),
          ]),
        ),
      ),
    );
  }

  Widget _pengingatBayar(MasColors m, int n) => Material(
        color: m.warn50,
        borderRadius: BorderRadius.circular(MasRadii.card),
        child: InkWell(
          onTap: () => setState(() => _tab = 'belum'),
          borderRadius: BorderRadius.circular(MasRadii.card),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MasRadii.card),
              border: Border.all(color: m.warnBorder),
            ),
            child: Row(children: [
              Icon(Icons.schedule, size: 18, color: m.warn600),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '$n pesanan',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(
                        text:
                            ' menunggu pembayaran — bayar sebelum batas waktu agar tidak batal otomatis.'),
                  ]),
                  style: TextStyle(fontSize: 12.5, color: m.warn600),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: m.warn600),
            ]),
          ),
        ),
      );

  Widget _tabBar(MasColors m, Map<String, int> counts) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final t in _orderTabs) ...[
            _tabChip(m, t.label, counts[t.key] ?? 0, _tab == t.key,
                () => setState(() => _tab = t.key)),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _tabChip(MasColors m, String label, int count, bool active, VoidCallback onTap) {
    return Material(
      color: active ? m.brand600 : m.paper,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? m.brand600 : m.ink200),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : m.ink700,
                )),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: active ? const Color(0x38FFFFFF) : m.ink100,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$count',
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : m.ink600)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// Kartu pesanan — kepala (asal kirim + kode/tanggal + status), cuplikan
  /// barang, lalu kaki (keterangan status, total, aksi). Cerminan web.
  Widget _card(MasColors m, AppNav nav, OrderSummary o) {
    final nada = _nadaStatus(o.status);
    final (fg, bg) = _warnaNada(m, nada);
    final bayar = o.status == 'menunggu_pembayaran';
    final gudang = _namaGudang(o);
    final jml = o.cuplikan.fold<int>(0, (n, it) => n + it.qty);
    final ket = _keterangan(m, o);
    void buka() =>
        nav.go(MasScreen.pesananDetail, part: {'order_code': o.orderCode});

    return Opacity(
      opacity: nada == _Nada.mati ? 0.78 : 1,
      child: Material(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: buka,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                    color: nada == _Nada.mati ? m.ink200 : fg, width: 3),
                top: BorderSide(color: m.ink150),
                right: BorderSide(color: m.ink150),
                bottom: BorderSide(color: m.ink150),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Kepala
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                          color: bg, borderRadius: BorderRadius.circular(9)),
                      child: Icon(
                          o.ringkasPickup
                              ? Icons.storefront_outlined
                              : Icons.local_shipping_outlined,
                          size: 17,
                          color: fg),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gudang.isEmpty
                                ? 'Pesanan'
                                : (o.ringkasPickup
                                    ? 'Ambil di Gudang $gudang'
                                    : 'Dikirim dari $gudang'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: m.ink900),
                          ),
                          const SizedBox(height: 1),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                  text: o.orderCode,
                                  style: masMono(size: 11, color: m.ink500)),
                              TextSpan(text: ' · ${fmtDate(o.createdAt)}'),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: m.ink500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    MasPill(
                      label:
                          orderStatusLabel(o.status, pickup: o.ringkasPickup),
                      tone: orderStatusTone(o.status),
                      height: 20,
                    ),
                  ]),
                ),
                Container(height: 1, color: m.ink150),

                // Cuplikan barang
                if (o.cuplikan.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Column(children: [
                      for (int i = 0;
                          i < o.cuplikan.length && i < _kCuplikan;
                          i++)
                        _barisBarang(m, o.cuplikan[i], garis: i > 0),
                      if (o.cuplikan.length > _kCuplikan)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(46, 2, 0, 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                                '+${o.cuplikan.length - _kCuplikan} barang lainnya',
                                style:
                                    TextStyle(fontSize: 12, color: m.ink500)),
                          ),
                        ),
                    ]),
                  ),

                // Kaki
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: m.ink50,
                    border: Border(top: BorderSide(color: m.ink150)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (ket != null) ...[ket, const SizedBox(height: 8)],
                      Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(jml > 0 ? 'Total $jml barang' : 'Total',
                                  style: TextStyle(
                                      fontSize: 11, color: m.ink500)),
                              Text(formatRupiah(o.total),
                                  style: masMono(
                                      size: 15,
                                      weight: FontWeight.w700,
                                      color: m.ink900)),
                            ],
                          ),
                        ),
                        if (_kPaidStatus.contains(o.status)) ...[
                          _tombolInvoice(m, o),
                          const SizedBox(width: 6),
                        ],
                        _aksiCepat(m, o, buka, bayar),
                      ]),
                      // Baris aksi kedua: Return (migrasi 039 — hanya pesanan
                      // selesai dalam batas hari retur) + Beli Lagi (selesai /
                      // batal / dikirim, paritas web).
                      if ((o.bisaRetur && o.status == 'selesai') ||
                          kStatusBeliLagi.contains(o.status)) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (o.bisaRetur && o.status == 'selesai')
                              _tombolRetur(m, nav, o),
                            if (kStatusBeliLagi.contains(o.status)) ...[
                              const SizedBox(width: 6),
                              _tombolBeliLagi(m, o),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _barisBarang(MasColors m, OrderItemDetail it, {bool garis = false}) {
    final judul = it.name.isNotEmpty ? it.name : it.partNumber;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: garis ? Border(top: BorderSide(color: m.ink150)) : null,
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: m.ink50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: m.ink150),
          ),
          child: Icon(Icons.inventory_2_outlined, size: 17, color: m.ink400),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(judul,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: m.ink800)),
              if (it.name.isNotEmpty)
                Text(it.partNumber, style: masMono(size: 11, color: m.ink500)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('×${it.qty}', style: TextStyle(fontSize: 12.5, color: m.ink600)),
      ]),
    );
  }

  /// Keterangan kecil di kaki kartu — hal paling berguna untuk status ini.
  Widget? _keterangan(MasColors m, OrderSummary o) {
    Widget baris(IconData ic, String teks, {Color? warna}) {
      final c = warna ?? m.ink600;
      return Row(children: [
        Icon(ic, size: 14, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(teks,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c)),
        ),
      ]);
    }

    switch (o.status) {
      case 'menunggu_pembayaran':
        final sisa = _sisaWaktu(o.batasBayar);
        if (sisa == null) return null;
        return sisa.isEmpty
            ? baris(Icons.info_outline, 'Batas bayar lewat', warna: m.warn600)
            : baris(Icons.schedule, 'Bayar dalam $sisa', warna: m.warn600);
      case 'menunggu_verifikasi':
        return baris(Icons.schedule, 'Bukti bayar sedang dicek admin');
      case 'diproses':
        return baris(Icons.inventory_2_outlined, 'Sedang disiapkan gudang');
      case 'dikirim':
        if (o.ringkasPickup) {
          return baris(
              Icons.storefront_outlined, 'Barang siap diambil di gudang');
        }
        final resi = (o.ringkasResi ?? '').trim();
        if (resi.isEmpty) return null;
        final kurir = (o.ringkasKurir ?? '').trim();
        return baris(Icons.local_shipping_outlined,
            '${kurir.isEmpty ? 'KURIR' : kurir.toUpperCase()} · $resi');
      case 'selesai':
        if (o.bisaNilai) {
          final batas = _batasNilai(o);
          return baris(Icons.star_rounded,
              'Belum dinilai${batas.isEmpty ? '' : ' · nilai sebelum $batas'}',
              warna: const Color(0xFFB36F00));
        }
        if (o.sudahDinilai) return baris(Icons.star_rounded, 'Sudah dinilai');
    }
    return null;
  }

  static const _kBulanPendek = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  /// "24 Okt" — batas menilai = selesai (updated_at) + 30 hari, sama dgn server.
  String _batasNilai(OrderSummary o) {
    final raw = o.updatedAt ?? '';
    if (raw.isEmpty) return '';
    final ada = RegExp(r'[zZ]$|[+-]\d{2}:?\d{2}$').hasMatch(raw);
    final d = DateTime.tryParse(ada ? raw : '${raw}Z');
    if (d == null) return '';
    final b = d.toLocal().add(const Duration(days: 30));
    return '${b.day} ${_kBulanPendek[b.month - 1]}';
  }

  Widget _tombolRetur(MasColors m, AppNav nav, OrderSummary o) {
    return Tooltip(
      message: 'Ajukan pengembalian barang',
      child: InkWell(
        onTap: () =>
            nav.go(MasScreen.returAjukan, part: {'order_code': o.orderCode}),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: Text('↩ Ajukan Return',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: m.ink700)),
        ),
      ),
    );
  }

  Widget _tombolBeliLagi(MasColors m, OrderSummary o) {
    final busy = _beliLagiBusy.contains(o.orderCode);
    return Material(
      color: m.paper,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: busy ? null : () => _beliLagi(o.orderCode),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: m.brand600),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (busy)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: m.brand600),
              )
            else
              Icon(Icons.replay_rounded, size: 15, color: m.brand700),
            const SizedBox(width: 5),
            Text('Beli Lagi',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: m.brand700)),
          ]),
        ),
      ),
    );
  }

  /// Tautan ke layar "Beli Lagi" — daftar semua barang yang pernah dibeli.
  Widget _pintuBeliLagi(MasColors m, AppNav nav) => Material(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.card),
        child: InkWell(
          onTap: () => nav.go(MasScreen.beliLagi),
          borderRadius: BorderRadius.circular(MasRadii.card),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MasRadii.card),
              border: Border.all(color: m.ink200),
            ),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: m.brand50, borderRadius: BorderRadius.circular(9)),
                child: Icon(Icons.replay_rounded, size: 18, color: m.brand700),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Beli Lagi',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: m.ink900)),
                    Text('Barang yang pernah kamu beli, siap dipesan ulang',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: m.ink500)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: m.ink400),
            ]),
          ),
        ),
      );

  Widget _tombolInvoice(MasColors m, OrderSummary o) {
    final busy = _invoiceBusy.contains(o.orderCode);
    return InkWell(
      onTap: busy ? null : () => _cetakInvoice(o.orderCode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (busy)
            SizedBox(
              width: 12,
              height: 12,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: m.brand600),
            )
          else
            Icon(Icons.receipt_long_outlined, size: 15, color: m.ink600),
          const SizedBox(width: 5),
          Text('Invoice',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: m.ink700)),
        ]),
      ),
    );
  }

  /// Tombol aksi kontekstual — Bayar / Lacak / Lihat Lokasi / Detail.
  /// Semua menuju detail pesanan, persis web.
  Widget _aksiCepat(
      MasColors m, OrderSummary o, VoidCallback buka, bool bayar) {
    // Seperti Shopee: pesanan selesai yang belum dinilai → tombol utama "⭐ Nilai"
    // yang membuka detail lalu langsung sheet penilaian.
    final nilai = o.bisaNilai;
    final utama = bayar || nilai;
    final label = nilai
        ? '⭐ Nilai'
        : bayar
            ? 'Bayar Sekarang'
            : o.status == 'dikirim'
                ? (o.ringkasPickup ? 'Lihat Lokasi' : 'Pesanan Diterima / Lacak')
                : 'Lihat Detail';
    final nav = AppNav.of(context);
    return Material(
      color: utama ? m.brand600 : m.paper,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: nilai
            ? () => nav.go(MasScreen.pesananDetail,
                part: {'order_code': o.orderCode, 'nilai': true})
            : buka,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: utama ? null : Border.all(color: m.ink200),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: utama ? Colors.white : m.ink700)),
        ),
      ),
    );
  }
}

/// Baris barang yang tampil di kartu (sisanya "+N barang lainnya").
const _kCuplikan = 2;

enum _Nada { warn, info, brand, mati }

_Nada _nadaStatus(String s) => switch (s) {
      'menunggu_pembayaran' => _Nada.warn,
      'selesai' => _Nada.brand,
      'batal' => _Nada.mati,
      _ => _Nada.info,
    };

/// (warna ikon/aksen, latar ikon) per nada.
(Color, Color) _warnaNada(MasColors m, _Nada n) => switch (n) {
      _Nada.warn => (m.warn600, m.warn50),
      _Nada.info => (m.info600, m.info50),
      _Nada.brand => (m.brand700, m.brand50),
      _Nada.mati => (m.ink500, m.ink100),
    };

/// Label gudang kadang berawalan nomor urut ("02.Pekanbaru") — buang untuk pembeli.
String _namaGudang(OrderSummary o) {
  final kirim = o.ringkasGudangKirim ?? '';
  final g = kirim.isNotEmpty ? kirim : o.gudang;
  return g.replaceFirst(RegExp(r'^\s*\d+\s*\.\s*'), '').trim();
}

/// Sisa waktu bayar: null = tak diketahui, '' = sudah lewat.
String? _sisaWaktu(String? s) {
  if (s == null || s.isEmpty) return null;
  final sudahAdaZona =
      RegExp(r'[zZ]$').hasMatch(s) || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
  final d = DateTime.tryParse(sudahAdaZona ? s : '${s}Z');
  if (d == null) return null;
  final ms = d.difference(DateTime.now()).inMilliseconds;
  if (ms <= 0) return '';
  final menit = (ms / 60000).ceil();
  final jam = menit ~/ 60;
  return jam > 0 ? '$jam jam ${menit % 60} mnt' : '$menit mnt';
}
