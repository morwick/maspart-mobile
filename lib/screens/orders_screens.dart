// lib/screens/orders_screens.dart
// Tiga layar PESANAN sisi ADMIN, seluruhnya dari API nyata:
//
//   OrdersScreen      — semua pesanan lintas cabang (+ ringkasan status, cari,
//                       muat lebih — masukan penguji 2026-09-29).
//   OrderDetailScreen — satu pesanan: uang, penerima, gudang, aksi & chat.
//   PenjualanScreen   — rekap omzet, per bulan, per gudang, part terlaris.
//
// `OrderChat` ada DUA: model (dari models.dart lewat api_service) dan widget
// percakapan. Model tidak dipakai di sini, jadi disembunyikan supaya nama
// `OrderChat` tegas menunjuk widget-nya.

import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/bukti_packing.dart';
import '../widgets/koreksi_resi.dart';
import '../widgets/mas_ui.dart';
import '../widgets/order_chat.dart';

// ══════════════════════════════════════════════════════════════════════
// Potongan UI bersama
// ══════════════════════════════════════════════════════════════════════

/// Kotak pesan berwarna (error / peringatan / info / sukses).
class _Alert extends StatelessWidget {
  final String message;
  final MasPillTone tone;
  const _Alert(this.message, {this.tone = MasPillTone.danger});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    late Color bg, fg, bd;
    switch (tone) {
      case MasPillTone.brand:
        bg = m.brand50;
        fg = m.brand700;
        bd = m.brand100;
      case MasPillTone.warn:
        bg = m.warn50;
        fg = m.warn600;
        bd = m.warnBorder;
      case MasPillTone.info:
        bg = m.info50;
        fg = m.info600;
        bd = m.infoBorder;
      default:
        bg = m.danger50;
        fg = m.danger600;
        bd = m.dangerBorder;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: bd),
      ),
      child: Text(message,
          style: TextStyle(fontSize: 12.5, color: fg, height: 1.45)),
    );
  }
}

/// Kartu angka ringkas (KPI penjualan).
class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Stat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return MasCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: m.ink500)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: masMono(
                    size: 18,
                    weight: FontWeight.w700,
                    color: color ?? m.ink900)),
          ),
        ],
      ),
    );
  }
}

/// IntrinsicHeight wajib: di dalam ListView tinggi tak terbatas, dan Row
/// ber-`stretch` pada tinggi tak terbatas akan meledak.
Widget _statRow(List<Widget> cards) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );

// ══════════════════════════════════════════════════════════════════════
// 1. Daftar pesanan (admin)
// ══════════════════════════════════════════════════════════════════════

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

/// Chip ringkasan status (masukan penguji 2026-09-29, paritas web
/// /admin/orders). "Perlu Diverifikasi" hanya tampil bila ada isinya.
const List<(String, String, bool)> _kKartuStatus = [
  ('menunggu_pembayaran', 'Belum Bayar', false),
  ('menunggu_verifikasi', 'Perlu Diverifikasi', true),
  ('diproses', 'Perlu Diproses', false),
  ('dikirim', 'Dikirim', false),
  ('selesai', 'Selesai', false),
  ('batal', 'Dibatalkan', false),
];
const int _kPerHalaman = 50;

class _OrdersScreenState extends State<OrdersScreen> {
  List<OrderSummary> _orders = [];
  Map<String, String> _penerima = {};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  AdminOrdersRingkasan? _ringkasan;

  /// '' = semua status. Disaring di SERVER (bukan dari 200 pesanan terbaru).
  String _filter = '';
  String _q = '';
  final _cariCtrl = TextEditingController();
  Timer? _debounce;

  /// Nomor permintaan terakhir: jawaban lama (ketik cepat / ganti filter) dibuang.
  int _reqId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cariCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_reqId;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    _muatRingkasan();
    try {
      final hal = await ApiService.adminOrdersCari(
          status: _filter, q: _q, offset: 0, limit: _kPerHalaman);
      if (!mounted || id != _reqId) return;
      setState(() {
        _orders = hal.orders;
        _penerima = Map.of(hal.penerima);
        _hasMore = hal.hasMore;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || id != _reqId) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _muatLagi() async {
    if (_loadingMore || _loading) return;
    final id = _reqId;
    setState(() => _loadingMore = true);
    try {
      final hal = await ApiService.adminOrdersCari(
          status: _filter, q: _q, offset: _orders.length, limit: _kPerHalaman);
      if (!mounted || id != _reqId) return;
      final ada = {for (final o in _orders) o.orderCode};
      setState(() {
        _orders = [
          ..._orders,
          ...hal.orders.where((o) => !ada.contains(o.orderCode)),
        ];
        _penerima = {..._penerima, ...hal.penerima};
        _hasMore = hal.hasMore;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted || id != _reqId) return;
      setState(() {
        _error = e.message;
        _loadingMore = false;
      });
    }
  }

  Future<void> _muatRingkasan() async {
    try {
      final r = await ApiService.adminOrdersRingkasan();
      if (!mounted) return;
      setState(() => _ringkasan = r);
    } on ApiException {
      // Ringkasan hanya pelengkap — daftar tetap jalan tanpanya.
    }
  }

  void _pilihStatus(String st) {
    setState(() => _filter = _filter == st ? '' : st);
    _load();
  }

  void _onCari(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final kata = v.trim();
      if (!mounted || kata == _q) return;
      _q = kata;
      _load();
    });
  }

  void _resetFilter() {
    _debounce?.cancel();
    _cariCtrl.clear();
    setState(() {
      _filter = '';
      _q = '';
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final counts = _ringkasan?.counts ?? const <String, int?>{};
    final kartu = _kKartuStatus
        .where((k) => !k.$3 || (counts[k.$1] ?? 0) > 0 || _filter == k.$1)
        .toList();
    final adaFilter = _filter.isNotEmpty || _q.isNotEmpty;

    String angka(String st) {
      if (_ringkasan == null) return '…';
      return counts[st]?.toString() ?? '–';
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Ringkasan status = filter; ketuk lagi chip aktif untuk melepas.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip(m, 'Semua', _filter.isEmpty, () {
                if (_filter.isEmpty) return;
                setState(() => _filter = '');
                _load();
              }),
              for (final k in kartu) ...[
                const SizedBox(width: 6),
                _chip(m, '${k.$2} (${angka(k.$1)})', _filter == k.$1,
                    () => _pilihStatus(k.$1)),
              ],
            ]),
          ),
          const SizedBox(height: 10),
          MasInput(
            controller: _cariCtrl,
            hint: 'Cari PO, pembeli, penerima, resi, PN / barang…',
            prefix: Icon(Icons.search_rounded, size: 18, color: m.ink400),
            suffix: adaFilter
                ? InkResponse(
                    radius: 20,
                    onTap: _resetFilter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      child: Icon(Icons.close_rounded, size: 17, color: m.ink500),
                    ),
                  )
                : null,
            action: TextInputAction.search,
            autocorrect: false,
            onChanged: _onCari,
            onSubmitted: (v) {
              _debounce?.cancel();
              _q = v.trim();
              _load();
            },
          ),
          const SizedBox(height: 12),

          if (_error != null) ...[
            _Alert(_error!),
            const SizedBox(height: 14),
          ],

          if (_loading)
            Column(children: [
              for (int i = 0; i < 5; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 96),
                ),
            ])
          else if (_orders.isEmpty)
            MasEmpty(
              icon: Icons.shopping_cart_outlined,
              title: adaFilter
                  ? 'Tidak ada pesanan yang cocok'
                  : 'Belum ada pesanan',
              subtitle: adaFilter
                  ? 'Ubah kata cari atau pilih status lain.'
                  : 'Pesanan dari pembeli akan muncul di sini.',
            )
          else ...[
            for (final o in _orders)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _card(m, nav, o),
              ),
            if (_hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: MasButton(
                  label: 'Muat lebih',
                  primary: false,
                  expand: true,
                  loading: _loadingMore,
                  onTap: _loadingMore ? null : _muatLagi,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chip(MasColors m, String label, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: active ? m.brand600 : m.paper,
            borderRadius: BorderRadius.circular(MasRadii.pill),
            border: Border.all(color: active ? m.brand600 : m.ink200),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : m.ink600,
              )),
        ),
      );

  Widget _card(MasColors m, AppNav nav, OrderSummary o) => MasCard(
        onTap: () =>
            nav.go(MasScreen.orderDetail, part: {'order_code': o.orderCode}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(o.orderCode,
                    style: masMono(
                        size: 13, weight: FontWeight.w700, color: m.ink900)),
              ),
              MasPill(
                label: orderStatusLabel(o.status),
                tone: orderStatusTone(o.status),
                height: 20,
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.person_outline_rounded, size: 14, color: m.ink400),
              const SizedBox(width: 5),
              Expanded(
                child: Text(o.username.isNotEmpty ? o.username : '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: m.ink700)),
              ),
              Text(formatRupiah(o.total),
                  style: masMono(
                      size: 14, weight: FontWeight.w700, color: m.brand700)),
            ]),
            const SizedBox(height: 5),
            Row(children: [
              Icon(Icons.warehouse_outlined, size: 14, color: m.ink400),
              const SizedBox(width: 5),
              Expanded(
                child: Text(o.gudang.isNotEmpty ? o.gudang : '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: m.ink600)),
              ),
              // Bukti PEMBAYARAN (transfer pembeli / foto struk Lunasi manual) —
              // paritas web "Bukti Bayar" (masukan penguji 2026-09-29).
              if (o.paymentProofUrl != null && o.paymentProofUrl!.isNotEmpty)
                const MasPill(
                    label: 'bukti bayar', tone: MasPillTone.info, height: 19),
            ]),
            if ((_penerima[o.orderCode] ?? '').isNotEmpty &&
                _penerima[o.orderCode] != o.username) ...[
              const SizedBox(height: 5),
              Text('Penerima: ${_penerima[o.orderCode]}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: m.ink500)),
            ],
            if ((o.ringkasResi ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Resi ${o.ringkasResi}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: masMono(size: 11, color: m.ink500)),
            ],
            const SizedBox(height: 6),
            Text('Dibuat ${fmtDate(o.createdAt)}',
                style: TextStyle(fontSize: 11, color: m.ink400)),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════
// 1b. Pesanan Bermasalah (admin) — audit 2026-09-28 T-7, padanan web
//     /admin/bermasalah. Dulu daftar ini hanya bisa dibaca lewat asisten AI.
// ══════════════════════════════════════════════════════════════════════

class BermasalahScreen extends StatefulWidget {
  const BermasalahScreen({super.key});

  @override
  State<BermasalahScreen> createState() => _BermasalahScreenState();
}

class _BermasalahScreenState extends State<BermasalahScreen> {
  PesananBermasalah? _data;
  bool _loading = true;
  String? _error;

  static const _judul = {
    'uang_perlu_dicek': ('Uang perlu dicek',
        'Uang pembeli sudah masuk tapi pesanannya bermasalah — refund, konfirmasi, atau cek stok.'),
    'kendala_gudang': ('Kendala (gudang / pembeli)',
        'Kendala dari gudang, atau pembeli belum menerima barang — putuskan lanjut kirim, batalkan, atau cek paket.'),
    'kirim_lama': ('Lama dikirim, belum selesai',
        'Resi belum dinyatakan terkirim / tak bisa dilacak — cek paketnya ke ekspedisi.'),
    'bayar_macet': ('Pembayaran macet',
        'Lewat tenggat bayar tapi belum lunas/batal — periksa manual.'),
    'belum_diambil': ('Ambil di Toko belum diambil', 'Sudah lewat batas ambil — hubungi pembeli.'),
    'lunas_belum_dikirim': ('Lunas, belum dikirim',
        'Sudah lunas beberapa hari tapi belum dikirim — pembeli menunggu.'),
    'penawaran_gagal': ('Penawaran Accurate gagal / dilewati',
        'Pesanan lunas belum tercatat di Accurate — buat manual, lalu tandai beres di halaman pesanan.'),
    'accurate_batal': ('Pesanan batal, penawaran Accurate masih ada',
        'Hapus/batalkan penawaran (dan dokumen turunannya bila sudah diproses) di Accurate, lalu tandai beres.'),
    'piutang_lewat': ('Tagihan tempo lewat > 30 hari',
        'Pelanggan tempo belum membayar lebih dari 30 hari setelah jatuh tempo — tagih, atau tandai lunas bila sudah dibayar.'),
    'retur_accurate': ('Retur: dokumen Accurate belum dibuat',
        'Retur Penjualan / Pengiriman pengganti belum dibuat di Accurate — stok & omzet belum dikoreksi.'),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.pesananBermasalah();
      if (!mounted) return;
      setState(() {
        _data = d;
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
    final d = _data;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (_error != null) ...[
            _Alert(_error!),
            const SizedBox(height: 14),
          ],
          if (_loading && d == null)
            Column(children: [
              for (int i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 96),
                ),
            ])
          else if (d == null || d.jumlah == 0)
            const MasEmpty(
              icon: Icons.verified_outlined,
              title: 'Tidak ada pesanan bermasalah',
              subtitle: 'Uang perlu dicek, kendala gudang & pesanan macet akan muncul di sini.',
            )
          else
            for (final k in PesananBermasalah.kunci)
              if ((d.daftar[k] ?? const []).isNotEmpty) ...[
                Text('${_judul[k]?.$1 ?? k} (${d.daftar[k]!.length})',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: m.ink900)),
                const SizedBox(height: 2),
                Text(_judul[k]?.$2 ?? '',
                    style: TextStyle(fontSize: 12, color: m.ink500)),
                const SizedBox(height: 8),
                for (final o in d.daftar[k]!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _kartu(m, nav, o),
                  ),
                const SizedBox(height: 8),
              ],
        ],
      ),
    );
  }

  Widget _kartu(MasColors m, AppNav nav, PesananMasalah o) => MasCard(
        onTap: () => nav.go(MasScreen.orderDetail, part: {'order_code': o.orderCode}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(o.orderCode,
                    style: masMono(size: 13, weight: FontWeight.w700, color: m.ink900)),
              ),
              if (o.perluRefund) ...[
                const MasPill(label: 'Perlu refund', tone: MasPillTone.danger, height: 20),
                const SizedBox(width: 6),
              ],
              if (o.returnCode.isNotEmpty)
                const MasPill(label: 'Retur', tone: MasPillTone.warn, height: 20)
              else
                MasPill(
                  label: orderStatusLabel(o.status),
                  tone: orderStatusTone(o.status),
                  height: 20,
                ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text(
                    '${o.pembeli.isNotEmpty ? o.pembeli : '—'} · '
                    '${o.gudang.isNotEmpty ? o.gudang : '—'}'
                    '${o.umurHari != null ? ' · ${o.umurHari} hari' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: m.ink600)),
              ),
              if (o.returnCode.isEmpty)
                Text(formatRupiah(o.total),
                    style: masMono(size: 13, weight: FontWeight.w700, color: m.brand700)),
            ]),
            if (o.catatan.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(o.catatan, style: TextStyle(fontSize: 12, color: m.ink700)),
            ],
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════
// 2. Detail pesanan (admin)
// ══════════════════════════════════════════════════════════════════════

class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> args;
  const OrderDetailScreen({super.key, required this.args});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  OrderDetail? _order;
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  String get _code => '${widget.args['order_code'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await ApiService.adminOrder(_code);
      if (!mounted) return;
      setState(() {
        _order = o;
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loaded = true;
      });
    }
  }

  /// Ubah status pesanan. Selalu konfirmasi: status memicu efek nyata di sisi
  /// pembeli (notifikasi, tombol konfirmasi terima) dan tak bisa diurungkan
  /// begitu saja.
  Future<void> _setStatus(String status) async {
    final nav = AppNav.of(context);
    // Batal punya konfirmasi sendiri yang menyebut akibatnya; pesanan LUNAS
    // wajib ketik ulang kode (paritas web — uang harus dikembalikan).
    if (status == 'batal') {
      final alasan = await _konfirmasiBatal();
      if (alasan == null || !mounted) return;
      await _jalankanBatal(nav, alasan.$1, alasan.$2);
      return;
    }
    // Masukan penguji 2026-09-29: pesanan bernilai besar wajib VIDEO packing —
    // admin pun tak bisa melompatinya (server menolak 409); tampilkan alasannya.
    final op = _order;
    if (status == 'dikirim' && op != null && !op.pickup && (op.packingTahanKirim ?? '').isNotEmpty) {
      setState(() => _error = op.packingTahanKirim);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah status pesanan',
            style: TextStyle(fontSize: 16)),
        content: Text(
          'Ubah status $_code menjadi "${orderStatusLabel(status)}"?'
          '${status == 'batal' ? '\n\nMembatalkan pesanan yang sudah dibayar mengharuskan refund manual.' : ''}',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ya')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // T-11: pesanan kurir tak boleh 'dikirim' tanpa resi yang sah (server
    // memeriksa format & keunikannya). Biasanya diisi gudang.
    String? resi;
    final o = _order;
    if (status == 'dikirim' && o != null && !o.pickup && (o.trackingNo ?? '').isEmpty) {
      resi = await tanyaResiKirim(context, _code);
      if (resi == null || !mounted) return;
    }
    // R-12: kendala gudang (stok kurang / rusak / beda) masih terbuka → 'dikirim'
    // hanya dengan alasan yang tercatat (kendala ikut ditutup).
    String? abaikan;
    if (status == 'dikirim' && o != null && o.kendalaTahanKirim) {
      abaikan = await tanyaAbaikanKendala(context, _code, o.kendalaNote ?? '-');
      if (abaikan == null || !mounted) return;
    }
    // S-19: Ambil di Toko diselesaikan admin = TANPA bukti serah terima gudang
    // (kode ambil + foto) → alasan wajib & dicatat di pesanan.
    String? alasanSelesai;
    if (status == 'selesai' && o != null && o.pickup) {
      alasanSelesai = await tanyaAlasanSelesaiPickup(context, _code);
      if (alasanSelesai == null || !mounted) return;
    } else if (status == 'selesai' && o != null && (o.tahanSelesai ?? '').isNotEmpty) {
      // QA2-G1: kendala pengiriman / resi tak dikenal → selesai hanya dengan alasan.
      alasanSelesai = await tanyaAlasanSelesaiPickup(context, _code,
          judul: 'Pesanan tertahan',
          pesan: '${o.tahanSelesai} Tetap tandai $_code selesai? Tulis alasannya '
              '(mis. paket sudah diterima, dikonfirmasi pembeli lewat chat) — dicatat '
              'di pesanan.');
      if (alasanSelesai == null || !mounted) return;
    }
    await _jalankanStatus(nav, status,
        trackingNo: resi, alasanSelesai: alasanSelesai, abaikanKendala: abaikan);
  }

  Future<void> _koreksiResi() async {
    final nav = AppNav.of(context);
    final hasil = await tanyaKoreksiResi(context, _order?.trackingNo);
    if (hasil == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.koreksiResi(_code, hasil.$1, hasil.$2, admin: true);
      if (!mounted) return;
      setState(() => _busy = false);
      nav.toast('Resi dikoreksi — pembeli sudah dikabari.');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  Future<void> _jalankanStatus(AppNav nav, String status,
      {String? trackingNo, String? alasanSelesai, String? abaikanKendala}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.setOrderStatus(_code, status,
          trackingNo: trackingNo, alasanSelesai: alasanSelesai,
          abaikanKendala: abaikanKendala);
      if (!mounted) return;
      setState(() => _busy = false);
      nav.toast('Status → ${orderStatusLabel(status)}');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  Future<void> _jalankanBatal(AppNav nav, String alasan, String ket) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.adminBatalkan(_code, alasan, ket);
      if (!mounted) return;
      setState(() => _busy = false);
      nav.toast('Pesanan dibatalkan — pembeli dikabari beserta alasannya.');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  /// Alasan pembatalan (T-6) — kode sama dengan backend orders.ALASAN_BATAL.
  static const _alasanBatal = <(String, String)>[
    ('stok_habis', 'Stok habis / barang tidak tersedia'),
    ('permintaan_pembeli', 'Permintaan pembeli'),
    ('penipuan', 'Pesanan mencurigakan / indikasi penipuan'),
    ('pembayaran', 'Pembayaran bermasalah'),
    ('lainnya', 'Lainnya'),
  ];

  /// Konfirmasi BATAL (paritas web, P-1 + T-6): alasan WAJIB dipilih (dicatat &
  /// dikirim ke pembeli; 'Lainnya' wajib keterangan). Sudah LUNAS
  /// (diproses/dikirim) → wajib ketik ulang kode pesanan: uang harus
  /// dikembalikan ke pembeli. Return (kode alasan, keterangan) atau null.
  Future<(String, String)?> _konfirmasiBatal() async {
    final o = _order;
    final lunas = o != null && (o.status == 'diproses' || o.status == 'dikirim');
    final total = formatRupiah(o?.total ?? 0);
    final ketCtl = TextEditingController();
    final kodeCtl = TextEditingController();
    String? alasan;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final m = ctx.mas;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final ketCukup = alasan != 'lainnya' ||
                ketCtl.text.trim().replaceAll(RegExp(r'\s+'), ' ').length >= 5;
            final cocok = !lunas ||
                kodeCtl.text.trim().toUpperCase() == _code.toUpperCase();
            return AlertDialog(
              title: Text(lunas ? 'Batalkan pesanan LUNAS?' : 'Batalkan pesanan?',
                  style: const TextStyle(fontSize: 16)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lunas
                          ? 'Pesanan $_code sudah LUNAS ($total)'
                              '${o?.status == 'dikirim' ? ' dan barangnya SUDAH DIKIRIM' : ''}. '
                              'Uang HARUS dikembalikan ke pembeli (transfer manual) — '
                              'pesanan ditandai perlu refund, retur yang masih berjalan '
                              'ditutup, dan tidak bisa dihidupkan lagi.'
                          : 'Batalkan $_code ($total)? Tagihan gateway pembayaran pembeli DITUTUP, '
                              'tahanan stok dilepas, voucher & poin dikembalikan. Pesanan '
                              'batal TIDAK BISA dihidupkan lagi.',
                      style: TextStyle(
                          fontSize: 12.5, color: lunas ? m.danger600 : m.ink600),
                    ),
                    const SizedBox(height: 10),
                    Text('Alasan pembatalan (dikirim ke pembeli)',
                        style: TextStyle(fontSize: 12, color: m.ink600)),
                    const SizedBox(height: 5),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final a in _alasanBatal)
                        ChoiceChip(
                          label: Text(a.$2, style: const TextStyle(fontSize: 12.5)),
                          selected: alasan == a.$1,
                          onSelected: (_) => setLocal(() => alasan = a.$1),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    MasInput(
                      controller: ketCtl,
                      hint: alasan == 'lainnya'
                          ? 'Keterangan untuk pembeli (wajib)'
                          : 'Keterangan untuk pembeli (opsional)',
                      height: 40,
                      onChanged: (_) => setLocal(() {}),
                    ),
                    if (lunas) ...[
                      const SizedBox(height: 10),
                      Text('Ketik ulang kode $_code untuk membatalkan',
                          style: TextStyle(fontSize: 12, color: m.ink600)),
                      const SizedBox(height: 5),
                      MasInput(
                        controller: kodeCtl,
                        hint: _code,
                        mono: true,
                        height: 40,
                        onChanged: (_) => setLocal(() {}),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Kembali')),
                TextButton(
                  onPressed: alasan != null && ketCukup && cocok
                      ? () => Navigator.pop(ctx, true)
                      : null,
                  child: const Text('Batalkan pesanan'),
                ),
              ],
            );
          },
        );
      },
    );
    final ket = ketCtl.text.trim();
    ketCtl.dispose();
    kodeCtl.dispose();
    final kode = alasan;
    if (ok != true || kode == null) return null;
    return (kode, ket);
  }

  /// "Refund sudah dibayar" (T-6, padanan web): nominal + nomor referensi
  /// transfer → tanda perlu refund ditutup, pembeli dikabari.
  Future<void> _refundDibayar() async {
    final nav = AppNav.of(context);
    final o = _order;
    if (o == null) return;
    final jumlahCtl = TextEditingController(
        text: o.saranRefund > 0 ? '${o.saranRefund}' : '');
    final refCtl = TextEditingController();
    final ketCtl = TextEditingController();
    var refundFinal = false;   // QA2-P2
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final m = ctx.mas;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final n = int.tryParse(jumlahCtl.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
            final sah = n > 0 &&
                refCtl.text.trim().replaceAll(RegExp(r'\s+'), ' ').length >= 4;
            return AlertDialog(
              title: const Text('Refund sudah dibayar', style: TextStyle(fontSize: 16)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catat HANYA setelah transfernya benar-benar berhasil. Tanda '
                      '"perlu refund" ditutup SEBESAR nominal ini (admin lain tak akan '
                      'mentransfer lagi) dan pembeli dikabari dananya sudah dikembalikan.',
                      style: TextStyle(fontSize: 12.5, color: m.warn600),
                    ),
                    const SizedBox(height: 10),
                    Text('Nominal ditransfer${n > 0 ? ' (${formatRupiah(n)})' : ''}',
                        style: TextStyle(fontSize: 12, color: m.ink600)),
                    const SizedBox(height: 5),
                    MasInput(
                      controller: jumlahCtl,
                      hint: 'mis. 1160000',
                      mono: true,
                      height: 40,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text('Nomor referensi transfer (bank + nomor)',
                        style: TextStyle(fontSize: 12, color: m.ink600)),
                    const SizedBox(height: 5),
                    MasInput(
                      controller: refCtl,
                      hint: 'mis. BCA 28/09 ref 123456',
                      height: 40,
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 8),
                    MasInput(
                      controller: ketCtl,
                      hint: 'Keterangan (opsional)',
                      height: 40,
                    ),
                    InkWell(
                      onTap: () => setLocal(() => refundFinal = !refundFinal),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Checkbox(
                            value: refundFinal,
                            activeColor: m.brand600,
                            visualDensity: VisualDensity.compact,
                            onChanged: (v) => setLocal(() => refundFinal = v ?? false),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                'Ini refund TERAKHIR — tutup sisa tanda walau nominalnya lebih '
                                'kecil dari saran (mis. dipotong biaya yang disepakati). Tanpa '
                                'centang, tanda ditutup sebesar nominal ini saja.',
                                style: TextStyle(fontSize: 12, color: m.ink600),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal')),
                TextButton(
                  onPressed: sah ? () => Navigator.pop(ctx, true) : null,
                  child: const Text('Catat refund dibayar'),
                ),
              ],
            );
          },
        );
      },
    );
    final jumlah = int.tryParse(jumlahCtl.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    final ref = refCtl.text.trim();
    final ket = ketCtl.text.trim();
    jumlahCtl.dispose();
    refCtl.dispose();
    ketCtl.dispose();
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.adminRefundDibayar(_code, jumlah, ref, ket,
          finalRefund: refundFinal);
      if (!mounted) return;
      setState(() => _busy = false);
      nav.toast('Refund dicatat sudah dibayar — pembeli dikabari.');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  /// Lunasi MANUAL (audit 2026-09-28 T-4) — padanan web: bukti pembayaran
  /// wajib (≥ 10 karakter) + ketik ulang kode pesanan. Dulu "Diproses" satu
  /// ketukan = lunas tanpa uang, gudang dikabari "segera kirim".
  Future<void> _lunasiManual() async {
    final nav = AppNav.of(context);
    final alasanCtl = TextEditingController();
    final kodeCtl = TextEditingController();
    // Foto struk / PDF bukti transfer (opsional) — padanan web "+ Foto struk".
    Uint8List? bukti;
    String buktiNama = '';
    String? buktiErr;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final m = ctx.mas;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final alasanCukup =
                alasanCtl.text.trim().replaceAll(RegExp(r'\s+'), ' ').length >= 10;
            final kodeCocok =
                kodeCtl.text.trim().toUpperCase() == _code.toUpperCase();
            final pdf = buktiNama.toLowerCase().endsWith('.pdf');

            void pasang(Uint8List? b, String nama) => setLocal(() {
                  if (b != null && b.length > 10 * 1024 * 1024) {
                    buktiErr = 'Ukuran file bukti maksimal 10 MB.';
                    return;
                  }
                  bukti = b;
                  buktiNama = nama;
                  buktiErr = null;
                });

            Future<void> ambilFoto(ImageSource src) async {
              try {
                // 2200 px: tulisan & nominal di struk harus tetap terbaca.
                final x = await ImagePicker()
                    .pickImage(source: src, imageQuality: 85, maxWidth: 2200);
                if (x == null) return;
                pasang(await x.readAsBytes(),
                    x.name.isEmpty ? 'struk.jpg' : x.name);
              } catch (_) {
                setLocal(() => buktiErr = 'Tidak dapat mengakses kamera/galeri.');
              }
            }

            Future<void> ambilPdf() async {
              try {
                // withData wajib: file dari Drive/Cloud sering tak punya path.
                final res = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['pdf'],
                  withData: true,
                );
                final f = res?.files.first;
                if (f == null || f.bytes == null) return;
                pasang(f.bytes, f.name);
              } catch (_) {
                setLocal(() => buktiErr = 'Tidak dapat membuka file.');
              }
            }
            return AlertDialog(
              title: const Text('Lunasi manual', style: TextStyle(fontSize: 16)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hanya bila uang SUDAH MASUK di luar gateway pembayaran '
                      '(RajaOngkir/Midtrans), mis. transfer langsung. Server mengecek '
                      'gateway dulu, lalu menutup tagihannya, mengunci stok, dan '
                      'mengabari gudang untuk mengirim.',
                      style: TextStyle(fontSize: 12.5, color: m.warn600),
                    ),
                    const SizedBox(height: 12),
                    Text('Bukti pembayaran (bank, tanggal, nomor referensi)',
                        style: TextStyle(fontSize: 12, color: m.ink600)),
                    const SizedBox(height: 5),
                    MasInput(
                      controller: alasanCtl,
                      hint: 'mis. Transfer BCA 28/09 ref 123456',
                      height: 40,
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 10),
                    Text('Foto struk / bukti transfer (opsional)',
                        style: TextStyle(fontSize: 12, color: m.ink600)),
                    const SizedBox(height: 5),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      MasButton(
                        label: 'Kamera',
                        icon: Icons.photo_camera_outlined,
                        primary: false,
                        height: 34,
                        onTap: () => ambilFoto(ImageSource.camera),
                      ),
                      MasButton(
                        label: 'Galeri',
                        icon: Icons.photo_library_outlined,
                        primary: false,
                        height: 34,
                        onTap: () => ambilFoto(ImageSource.gallery),
                      ),
                      MasButton(
                        label: 'PDF',
                        icon: Icons.picture_as_pdf_outlined,
                        primary: false,
                        height: 34,
                        onTap: ambilPdf,
                      ),
                    ]),
                    if (bukti != null) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        if (pdf)
                          Icon(Icons.picture_as_pdf_outlined, color: m.ink500)
                        else
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(bukti!,
                                width: 56, height: 56, fit: BoxFit.cover),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(buktiNama,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: m.ink700)),
                        ),
                        IconButton(
                          tooltip: 'Hapus',
                          icon: Icon(Icons.close, size: 18, color: m.ink500),
                          onPressed: () => pasang(null, ''),
                        ),
                      ]),
                    ],
                    if (buktiErr != null) ...[
                      const SizedBox(height: 4),
                      Text(buktiErr!,
                          style: TextStyle(fontSize: 11.5, color: m.danger600)),
                    ],
                    const SizedBox(height: 10),
                    Text('Ketik ulang kode $_code untuk konfirmasi',
                        style: TextStyle(fontSize: 12, color: m.ink600)),
                    const SizedBox(height: 5),
                    MasInput(
                      controller: kodeCtl,
                      hint: _code,
                      mono: true,
                      height: 40,
                      onChanged: (_) => setLocal(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal')),
                TextButton(
                  onPressed: alasanCukup && kodeCocok
                      ? () => Navigator.pop(ctx, true)
                      : null,
                  child: const Text('Lunasi manual'),
                ),
              ],
            );
          },
        );
      },
    );
    final alasan = alasanCtl.text.trim();
    alasanCtl.dispose();
    kodeCtl.dispose();
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pesan = await ApiService.adminLunasiManual(_code, alasan,
          bukti: bukti, buktiNama: buktiNama.isEmpty ? null : buktiNama);
      if (!mounted) return;
      setState(() => _busy = false);
      nav.toast(pesan ??
          ((_order?.isTempo ?? false)
              ? 'Tagihan tempo ditandai lunas — limit pelanggan dipulihkan.'
              : 'Pesanan dilunasi manual — gudang sudah dikabari.'));
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  /// Lepas tahanan kirim (audit 2026-09-28 T-5) — padanan web: dana pembeli
  /// tercatat sudah ditarik (refund/chargeback) sehingga gudang dilarang
  /// mengirim. Hanya bila tetap harus dikirim; alasan wajib (≥ 10 karakter).
  Future<void> _lepasTahan() async {
    final nav = AppNav.of(context);
    final alasanCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final m = ctx.mas;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final alasanCukup =
                alasanCtl.text.trim().replaceAll(RegExp(r'\s+'), ' ').length >= 10;
            return AlertDialog(
              title: const Text('Lepas tahanan', style: TextStyle(fontSize: 16)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dana pembeli tercatat sudah DITARIK kembali (refund/'
                      'chargeback). Melepas tahanan membuat gudang bisa mengirim '
                      'barang lagi. Biasanya pesanan seperti ini dibatalkan.',
                      style: TextStyle(fontSize: 12.5, color: m.warn600),
                    ),
                    const SizedBox(height: 12),
                    Text('Alasan (mis. refund keliru, dana sudah ditagih ulang)',
                        style: TextStyle(fontSize: 12, color: m.ink600)),
                    const SizedBox(height: 5),
                    MasInput(
                      controller: alasanCtl,
                      hint: 'Minimal 10 karakter',
                      height: 40,
                      onChanged: (_) => setLocal(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal')),
                TextButton(
                  onPressed:
                      alasanCukup ? () => Navigator.pop(ctx, true) : null,
                  child: const Text('Lepas tahanan'),
                ),
              ],
            );
          },
        );
      },
    );
    final alasan = alasanCtl.text.trim();
    alasanCtl.dispose();
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.adminLepasTahan(_code, alasan);
      if (!mounted) return;
      setState(() => _busy = false);
      nav.toast('Tahanan dilepas — gudang bisa melanjutkan pesanan ini.');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  /// "Tandai sudah ditangani" (T-7, padanan web): menutup catatan pembayaran
  /// umum (nominal tak cocok, stok gagal dikunci, …). Catatan wajib ≥ 10.
  Future<void> _tandaiDitangani() async {
    final nav = AppNav.of(context);
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final m = ctx.mas;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final cukup =
                ctl.text.trim().replaceAll(RegExp(r'\s+'), ' ').length >= 10;
            return AlertDialog(
              title: const Text('Tandai sudah ditangani', style: TextStyle(fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tulis apa yang sudah dilakukan (tercatat di riwayat pesanan).',
                      style: TextStyle(fontSize: 12.5, color: m.ink600)),
                  const SizedBox(height: 8),
                  MasInput(
                    controller: ctl,
                    hint: 'mis. selisih sudah ditransfer balik ke pembeli',
                    height: 40,
                    onChanged: (_) => setLocal(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal')),
                TextButton(
                  onPressed: cukup ? () => Navigator.pop(ctx, true) : null,
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
    final catatan = ctl.text.trim();
    ctl.dispose();
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.adminTandaiDitangani(_code, catatan);
      if (!mounted) return;
      setState(() => _busy = false);
      nav.toast('Catatan pembayaran ditandai sudah ditangani.');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  /// T-10 (padanan web): kendala setelah dikirim selesai ditangani → selesai
  /// otomatis berjalan lagi. Catatan wajib ≥ 10 karakter.
  Future<void> _tutupKendala() async {
    final nav = AppNav.of(context);
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final m = ctx.mas;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Kendala selesai', style: TextStyle(fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bagaimana kendalanya selesai? Selesai otomatis berjalan lagi.',
                    style: TextStyle(fontSize: 12.5, color: m.ink600)),
                const SizedBox(height: 8),
                MasInput(
                  controller: ctl,
                  hint: 'mis. paket ketemu, sudah diterima pembeli',
                  height: 40,
                  onChanged: (_) => setLocal(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal')),
              TextButton(
                onPressed: ctl.text.trim().replaceAll(RegExp(r'\s+'), ' ').length >= 10
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: const Text('Simpan'),
              ),
            ],
          ),
        );
      },
    );
    final catatan = ctl.text.trim();
    ctl.dispose();
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.adminTutupKendala(_code, catatan);
      if (!mounted) return;
      setState(() => _busy = false);
      nav.toast('Kendala ditutup — selesai otomatis berjalan lagi.');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  /// Audit S-5/S-21 (padanan web): tindakan manual di Accurate sudah dikerjakan.
  /// Pesanan batal → keterangan wajib ≥ 10; pesanan lunas tanpa penawaran →
  /// nomor dokumen Accurate yang dibuat manual wajib.
  Future<void> _accurateBeres(OrderDetail o) async {
    final nav = AppNav.of(context);
    final tutup = o.accuratePerluTutup;
    final dokCtl = TextEditingController();
    final ketCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final m = ctx.mas;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final cukup = tutup
                ? ketCtl.text.trim().replaceAll(RegExp(r'\s+'), ' ').length >= 10
                : dokCtl.text.trim().length >= 3;
            return AlertDialog(
              title: const Text('Tindakan Accurate beres', style: TextStyle(fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      tutup
                          ? 'Penawaran ${o.penawaranNumber ?? ''} sudah dihapus/dibatalkan di '
                              'Accurate (juga dokumen turunannya)? Tulis apa yang dilakukan.'
                          : 'Isi nomor dokumen Accurate (Penawaran / Pesanan Penjualan) yang '
                              'dibuat manual untuk pesanan ini.',
                      style: TextStyle(fontSize: 12.5, color: m.ink600)),
                  const SizedBox(height: 8),
                  if (!tutup) ...[
                    MasInput(
                      controller: dokCtl,
                      hint: 'No. dokumen Accurate',
                      height: 40,
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 8),
                  ],
                  MasInput(
                    controller: ketCtl,
                    hint: tutup
                        ? 'mis. penawaran dihapus, belum jadi SO'
                        : 'Keterangan (opsional)',
                    height: 40,
                    onChanged: (_) => setLocal(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal')),
                TextButton(
                  onPressed: cukup ? () => Navigator.pop(ctx, true) : null,
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
    final dokumen = dokCtl.text.trim();
    final keterangan = ketCtl.text.trim();
    dokCtl.dispose();
    ketCtl.dispose();
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.adminAccurateBeres(_code,
          dokumen: dokumen, keterangan: keterangan);
      if (!mounted) return;
      setState(() => _busy = false);
      nav.toast('Tindakan Accurate ditandai beres.');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  Future<void> _launch(String url) async {
    final nav = AppNav.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      nav.toast('Tidak bisa membuka $url');
    }
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final o = _order;

    if (o == null) {
      return Center(
        child: _loaded
            ? MasEmpty(
                icon: Icons.receipt_long_outlined,
                title: 'Pesanan tidak ditemukan',
                subtitle: _error ?? 'Kode pesanan "$_code" tidak dikenal.',
              )
            : CircularProgressIndicator(color: m.brand600),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          if (_error != null) ...[
            _Alert(_error!),
            const SizedBox(height: 14),
          ],

          // Pembayaran bermasalah (mis. dana masuk setelah pesanan batal →
          // perlu refund manual). Ditaruh paling atas: ini butuh tindakan.
          // T-6: hanya catatan yang MASIH perlu tindakan; refund pesanan
          // ditutup lewat "Refund sudah dibayar".
          if (o.catatanTerbuka.isNotEmpty) ...[
            _Alert('⚠️ Pembayaran perlu ditindaklanjuti.\n• '
                '${o.catatanTerbuka.join('\n• ')}',
                tone: MasPillTone.warn),
            if (o.bisaDitangani) ...[
              const SizedBox(height: 8),
              MasButton(
                label: 'Tandai sudah ditangani…',
                primary: false,
                expand: true,
                height: 40,
                loading: _busy,
                onTap: _busy ? null : _tandaiDitangani,
              ),
            ],
            if (o.perluRefund) ...[
              const SizedBox(height: 8),
              MasButton(
                label: 'Refund sudah dibayar…',
                primary: false,
                expand: true,
                height: 40,
                loading: _busy,
                onTap: _busy ? null : _refundDibayar,
              ),
            ],
            const SizedBox(height: 14),
          ],
          if (o.status == 'batal' && o.alasanBatalLabel != null) ...[
            _Alert(
                'Alasan batal: ${o.alasanBatalLabel}'
                '${o.alasanBatalKet != null ? ' — ${o.alasanBatalKet}' : ''}'
                '${o.alasanBatalOleh != null ? '\n(oleh ${o.alasanBatalOleh}'
                    '${o.alasanBatalWaktu != null ? ', ${o.alasanBatalWaktu} UTC' : ''})' : ''}',
                tone: MasPillTone.danger),
            const SizedBox(height: 14),
          ],

          // Kendala dari gudang / pembeli (T-10: juga SETELAH dikirim — menahan
          // selesai otomatis sampai admin menutupnya).
          if ((o.kendalaNote ?? '').isNotEmpty &&
              (o.status == 'diproses' || o.kendalaKirim)) ...[
            // R-7 (paritas web admin): waktu laporan + akibat membatalkan.
            _Alert(
                '⚠️ ${o.kendalaKirim ? 'Kendala pengiriman' : 'Kendala dari gudang'}'
                '${o.kendalaBy != null ? ' (${o.kendalaBy})' : ''}: ${o.kendalaNote}'
                '${(o.kendalaAt ?? '').isNotEmpty ? ' · ${fmtDate(o.kendalaAt)}' : ''}'
                '${o.kendalaKirim ? '\nSelesai otomatis DITAHAN — cek paket ke ekspedisi; setelah beres, tutup kendalanya.' : ''}'
                '${!o.kendalaKirim && o.status == 'diproses' ? '\nPesanan sudah lunas. Bila dibatalkan, pesanan otomatis ditandai perlu refund ke pembeli.' : ''}',
                tone: MasPillTone.warn),
            if (o.kendalaKirim) ...[
              const SizedBox(height: 8),
              MasButton(
                label: 'Kendala selesai…',
                primary: false,
                expand: true,
                height: 40,
                loading: _busy,
                onTap: _busy ? null : _tutupKendala,
              ),
            ],
            const SizedBox(height: 14),
          ],

          // Audit 2026-09-28 T-5: dana ditarik → gudang dilarang mengirim
          // sampai admin melepas tahanan (dengan alasan) atau membatalkan.
          if (o.tahanKirim) ...[
            _Alert(
                '⛔ Pengiriman DITAHAN. ${o.alasanTahan ?? ''} Biasanya pesanan '
                'ini dibatalkan. Bila tetap harus dikirim (mis. refund keliru & '
                'dana sudah ditagih ulang), lepas tahanan dengan alasan.'),
            const SizedBox(height: 8),
            MasButton(
              label: 'Lepas tahanan…',
              primary: false,
              expand: true,
              height: 40,
              loading: _busy,
              onTap: _busy ? null : _lepasTahan,
            ),
            const SizedBox(height: 14),
          ],

          MasCard(child: OrderStepper(status: o.status, pickup: o.pickup)),
          const SizedBox(height: 14),

          _items(m, o),
          const SizedBox(height: 14),

          if (o.recipientName != null || o.recipientAddress != null) ...[
            _penerima(m, o),
            const SizedBox(height: 14),
          ],

          _pengirim(m, o),
          const SizedBox(height: 14),

          // Ambil di Toko yang sudah diserahkan: foto pengambil dari gudang —
          // rujukan admin bila pembeli mengaku belum mengambil barang.
          if (o.pickup && (o.pickupProofUrl ?? '').isNotEmpty) ...[
            MasSectionCard(
              title: '🏬 Serah Terima',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: BuktiSerahTerima(order: o),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // Bukti packing foto/video dari gudang (masukan penguji 2026-09-29,
          // migrasi 046) — admin juga bisa mengunggah/menghapus selama diproses.
          if (!o.pickup &&
              o.packingBuktiAktif &&
              (o.packingBukti.isNotEmpty || o.status == 'diproses')) ...[
            MasSectionCard(
              title: '🎥 Bukti Packing',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: BuktiPackingPanel(order: o, admin: true, onChanged: _load),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          if (o.trackingNo != null && o.trackingNo!.isNotEmpty) ...[
            _pengiriman(m, o),
            const SizedBox(height: 14),
          ],

          _pembayaran(m, o),
          const SizedBox(height: 14),

          if (o.penawaranStatus != null && o.penawaranStatus!.isNotEmpty) ...[
            _penawaran(m, o),
            const SizedBox(height: 14),
          ],

          _aksi(m, o),
          const SizedBox(height: 14),

          // Paritas web detail pesanan admin (masukan penguji 2026-09-29).
          OrderChat(
            title: 'Chat pesanan — pembeli ${o.username} · gudang ${o.gudang.isNotEmpty ? o.gudang : "-"}',
            me: nav.username,
            fetch: () async => (await ApiService.orderChat(_code)).messages,
            send: (body) => ApiService.sendOrderChat(_code, body),
          ),
        ],
      ),
    );
  }

  Widget _items(MasColors m, OrderDetail o) {
    // PPN sadar aturan: pesanan baru → PPN 12% (DPP 11/12) DITAMBAHKAN di atas
    // barang; pesanan lama ber-PPN inklusif → tetap abu-abu "Termasuk PPN 12%".
    // Total selalu `o.total` tersimpan, tak pernah dihitung ulang.
    final ppn = barisPpn(o);

    return MasSectionCard(
      title: o.orderCode,
      trailing: MasPill(
        label: orderStatusLabel(o.status),
        tone: orderStatusTone(o.status),
        height: 20,
      ),
      children: [
        for (final it in o.items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: m.ink100)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(it.partNumber,
                        style: masMono(
                            size: 12, weight: FontWeight.w600, color: m.ink900)),
                    const SizedBox(height: 2),
                    Text(it.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: m.ink700)),
                    const SizedBox(height: 2),
                    Text('${formatRupiah(it.price)} × ${it.qty}',
                        style: TextStyle(fontSize: 11.5, color: m.ink500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(formatRupiah(it.lineTotal),
                  style:
                      masMono(size: 13, weight: FontWeight.w600, color: m.ink900)),
            ]),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(children: [
            _sumRow(m, 'Subtotal', formatRupiah(o.subtotal)),
            // Aturan baru — urutan ala Accurate: potongan barang (voucher &
            // poin) dulu, lalu PPN atas barang setelah potongan, lalu ongkir &
            // potongannya. Pesanan lama tetap tata letak semula.
            if (ppn.ditambahkan)
              OrderPotongan(order: o, bagian: PotonganBagian.barang),
            const SizedBox(height: 5),
            _sumRow(m, ppn.label, formatRupiah(ppn.nilai),
                muted: !ppn.ditambahkan),
            const SizedBox(height: 5),
            _sumRow(
              m,
              o.pickup
                  ? 'Ongkir (ambil di toko)'
                  : 'Ongkir${o.courier != null && o.courier!.isNotEmpty ? ' (${o.courier!.toUpperCase()}${o.courierService != null && o.courierService!.isNotEmpty ? ' ${o.courierService}' : ''})' : ''}',
              o.shippingCost > 0 ? formatRupiah(o.shippingCost) : '—',
            ),
            // Potongan voucher/poin + kode voucher — paritas web OrderPotongan.
            // Aturan baru: tinggal potongan ongkir (potongan barang di atas PPN).
            OrderPotongan(
                order: o,
                bagian: ppn.ditambahkan
                    ? PotonganBagian.ongkir
                    : PotonganBagian.semua),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Divider(height: 1, color: m.ink150),
            ),
            Row(children: [
              Expanded(
                child: Text('Total',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: m.ink900)),
              ),
              Text(formatRupiah(o.total),
                  style: masMono(
                      size: 16, weight: FontWeight.w700, color: m.brand700)),
            ]),
          ]),
        ),

        if (o.note != null && o.note!.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: m.ink100)),
            ),
            child: Text('Catatan pembeli: ${o.note}',
                style: TextStyle(fontSize: 12.5, color: m.ink600)),
          ),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            'Dibuat ${fmtDate(o.createdAt)} · oleh ${o.username}'
            '${o.weightGrams > 0 ? ' · ${thousands(o.weightGrams)} g' : ''}',
            style: TextStyle(fontSize: 11, color: m.ink400),
          ),
        ),
      ],
    );
  }

  Widget _sumRow(MasColors m, String label, String value, {bool muted = false}) =>
      Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: muted ? 12.5 : 13,
                  color: muted ? m.ink400 : m.ink500)),
        ),
        Text(value,
            style: masMono(
                size: muted ? 12.5 : 13, color: muted ? m.ink400 : m.ink800)),
      ]);

  Widget _penerima(MasColors m, OrderDetail o) => MasSectionCard(
        title: '📍 Penerima',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${o.recipientName ?? '—'}'
                  '${o.recipientPhone != null && o.recipientPhone!.isNotEmpty ? ' · ${o.recipientPhone}' : ''}',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: m.ink900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${o.recipientAddress ?? '—'}'
                  '${o.recipientPostal != null && o.recipientPostal!.isNotEmpty ? ' (${o.recipientPostal})' : ''}',
                  style: TextStyle(fontSize: 12.5, color: m.ink600, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _pengirim(MasColors m, OrderDetail o) {
    // `pengirim` = gudang FISIK yang mengeluarkan barang; `gudang` = cabang yang
    // MEMPROSES pesanan. Untuk sub-gudang keduanya berbeda — admin perlu tahu
    // keduanya untuk menelusuri barang.
    final beda = o.pengirim.isNotEmpty && o.pengirim != o.gudang;

    return MasSectionCard(
      title: '📦 Gudang',
      children: [
        MasKeyValue(label: 'Gudang pengirim (fisik)', value: o.pengirim.isNotEmpty ? o.pengirim : '—'),
        MasKeyValue(
            label: 'Cabang pemroses',
            value: o.gudang.isNotEmpty ? o.gudang : '—',
            divider: o.gudangPic != null && o.gudangPic!.isNotEmpty),
        if (o.gudangPic != null && o.gudangPic!.isNotEmpty)
          MasKeyValue(
              label: 'PIC gudang', value: o.gudangPic!, mono: true, divider: false),
        if (beda)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Barang dikirim dari gudang fisik di atas, bukan dari cabang pemroses.',
              style: TextStyle(fontSize: 11.5, color: m.ink400, height: 1.4),
            ),
          ),
      ],
    );
  }

  Widget _pengiriman(MasColors m, OrderDetail o) => MasSectionCard(
        title: '🚚 Pengiriman',
        children: [
          MasKeyValue(
            label: 'Kurir',
            value:
                '${(o.courier ?? '—').toUpperCase()}${o.courierService != null && o.courierService!.isNotEmpty ? ' ${o.courierService}' : ''}',
          ),
          MasKeyValue(
              label: 'No. resi',
              value: o.trackingNo!,
              mono: true,
              divider: false),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: GestureDetector(
              onTap: () => _launch(
                  'https://cekresi.com/?noresi=${Uri.encodeComponent(o.trackingNo!)}'),
              child: Text('Lacak paket →',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: m.brand700)),
            ),
          ),
        ],
      );

  Widget _pembayaran(MasColors m, OrderDetail o) {
    final gateway = o.paymentMethod == 'gateway';

    return MasSectionCard(
      title: 'Pembayaran',
      children: [
        MasKeyValue(
          label: 'Metode',
          value: gateway
              ? ((o.paymentChannel ?? '').toLowerCase() == 'snap'
                  ? 'Gateway (Midtrans)'
                  : 'Gateway (RajaOngkir)')
              : o.isTempo
                  ? 'Tempo ${o.tempo?.terminHari ?? 30} hari'
                  : (o.paymentMethod.isNotEmpty ? o.paymentMethod : 'Manual'),
        ),
        // TEMPO (migrasi 048): status tagihan terpisah dari status kirim.
        if (o.isTempo && o.tempo != null) ...[
          MasKeyValue(
            label: 'Tagihan tempo',
            value: o.tempo!.lunas
                ? 'Lunas'
                : o.status == 'batal'
                    ? 'Gugur (pesanan batal)'
                    : 'Sisa ${formatRupiah(o.tempo!.sisaTagihan)}',
            valueColor: o.tempo!.lunas ? m.brand700 : (o.tempo!.tahap == 'lewat' ? m.danger600 : null),
          ),
          if (!o.tempo!.lunas && o.status != 'batal')
            MasKeyValue(
              label: 'Jatuh tempo',
              value: o.tempo!.jatuhTempo != null
                  ? '${tglJatuhTempo(o.tempo!.jatuhTempo)}${o.tempo!.tahap == 'lewat' ? ' (lewat ${o.tempo!.hariLewat} hari)' : ''}'
                  : 'dihitung saat dikirim',
            ),
          if (o.tempo!.potonganRetur > 0)
            MasKeyValue(label: 'Dipotong retur', value: formatRupiah(o.tempo!.potonganRetur)),
        ],
        if (o.paymentChannel != null && o.paymentChannel!.isNotEmpty)
          MasKeyValue(label: 'Kanal', value: labelKanalBayar(o.paymentChannel)),
        if (o.paymentRef != null && o.paymentRef!.isNotEmpty)
          MasKeyValue(label: 'Referensi', value: o.paymentRef!, mono: true),
        if (o.paymentVa != null && o.paymentVa!.isNotEmpty)
          MasKeyValue(label: 'Virtual account', value: o.paymentVa!, mono: true),
        MasKeyValue(
          label: 'Dibayar pada',
          value: o.paidAt != null && o.paidAt!.isNotEmpty ? fmtDate(o.paidAt) : '—',
          divider: false,
        ),

        // Bukti transfer manual hanya relevan bila bukan order gateway, atau
        // pembeli terlanjur mengunggahnya.
        if (!gateway || (o.paymentProofUrl != null && o.paymentProofUrl!.isNotEmpty))
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: m.ink100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bukti transfer',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: m.ink800)),
                const SizedBox(height: 6),
                if (o.paymentProofUrl != null && o.paymentProofUrl!.isNotEmpty)
                  _BuktiTransfer(url: o.paymentProofUrl!, onBuka: _launch)
                else
                  Text('Belum ada bukti transfer.',
                      style: TextStyle(fontSize: 12.5, color: m.ink400)),
              ],
            ),
          ),
      ],
    );
  }

  /// Penawaran Penjualan Accurate yang dibuat otomatis saat pesanan lunas.
  Widget _penawaran(MasColors m, OrderDetail o) {
    final st = o.penawaranStatus!;
    final dibuat = st == 'created';

    return MasSectionCard(
      title: '🧾 Penawaran Accurate',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                MasPill(
                  label: switch (st) {
                    'created' => 'Dibuat',
                    'failed' => 'Gagal',
                    'skip' => 'Dilewati',
                    _ => st,
                  },
                  tone: switch (st) {
                    'created' => MasPillTone.brand,
                    'failed' => MasPillTone.danger,
                    _ => MasPillTone.warn,
                  },
                  height: 20,
                ),
                const SizedBox(width: 8),
                if (dibuat &&
                    o.penawaranNumber != null &&
                    o.penawaranNumber!.isNotEmpty)
                  Expanded(
                    child: Text(o.penawaranNumber!,
                        style: masMono(
                            size: 14,
                            weight: FontWeight.w700,
                            color: m.ink900)),
                  ),
              ]),
              if (o.penawaranNote != null && o.penawaranNote!.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(o.penawaranNote!,
                    style:
                        TextStyle(fontSize: 12, color: m.ink600, height: 1.45)),
              ],
              // Audit S-5/S-21: aplikasi tak menghapus/membuat dokumen lain di
              // Accurate — admin mengerjakannya manual lalu menandainya beres.
              if (o.accuratePerluTutup || o.penawaranPerluManual) ...[
                const SizedBox(height: 10),
                _Alert(
                    o.accuratePerluTutup
                        ? 'Pesanan ini DIBATALKAN, tetapi penawaran '
                            '${o.penawaranNumber ?? ''} masih ada di Accurate. Hapus/batalkan '
                            'penawaran itu — juga Pesanan/Pengiriman/Faktur turunannya bila '
                            'sudah diproses — supaya stok & omzet Accurate tidak salah.'
                        : 'Pesanan sudah LUNAS tetapi belum tercatat di Accurate. Buat '
                            'Pesanan Penjualan manual (catatan ${o.orderCode}, gudang '
                            '${o.pengirim}), lalu isi nomornya.',
                    tone: MasPillTone.danger),
                const SizedBox(height: 8),
                MasButton(
                  label: 'Tandai beres…',
                  primary: false,
                  expand: true,
                  height: 40,
                  loading: _busy,
                  onTap: _busy ? null : () => _accurateBeres(o),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Status berikutnya yang sah dari [status] menurut alur resmi, atau null.
  static String? _langkahBerikut(String status) {
    final i = kOrderFlow.indexOf(status);
    if (i < 0 || i + 1 >= kOrderFlow.length) return null;
    return kOrderFlow[i + 1];
  }

  Widget _aksi(MasColors m, OrderDetail o) => MasSectionCard(
        title: 'Ubah Status',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Jalur cepat: verifikasi bukti transfer manual lalu proses.
                if (o.status == 'menunggu_verifikasi') ...[
                  MasButton(
                    label: '✓ Verifikasi & Proses',
                    expand: true,
                    loading: _busy,
                    onTap: _busy ? null : () => _setStatus('diproses'),
                  ),
                  const SizedBox(height: 10),
                ],

                // Pesanan BELUM DIBAYAR tak boleh didorong maju dari sini (audit
                // 2026-09-28 T-4): "Diproses" dulu = lunas tanpa uang. Pelunasan
                // di luar gateway lewat "Lunasi manual" (bukti + ketik kode).
                // TEMPO: barang sudah diproses, tagihannya belum lunas → tandai
                // lunas lewat alur yang sama (alasan + bukti, gateway dicek dulu).
                if (o.isTempo &&
                    o.tempo != null &&
                    !o.tempo!.lunas &&
                    !['batal', 'menunggu_pembayaran'].contains(o.status)) ...[
                  Text('Tagihan tempo belum lunas (sisa ${formatRupiah(o.tempo!.sisaTagihan)}).',
                      style: TextStyle(fontSize: 12.5, color: m.ink500)),
                  const SizedBox(height: 7),
                  MasButton(
                    label: 'Tandai tagihan tempo lunas…',
                    primary: false,
                    expand: true,
                    height: 40,
                    loading: _busy,
                    onTap: _busy ? null : _lunasiManual,
                  ),
                  const SizedBox(height: 12),
                ],
                if (o.status == 'menunggu_pembayaran') ...[
                  Text('Pesanan belum dibayar.',
                      style: TextStyle(fontSize: 12.5, color: m.ink500)),
                  const SizedBox(height: 7),
                  MasButton(
                    label: 'Lunasi manual…',
                    primary: false,
                    expand: true,
                    height: 40,
                    loading: _busy,
                    onTap: _busy ? null : _lunasiManual,
                  ),
                ] else ...[
                  Text('Alur setelah lunas',
                      style: TextStyle(fontSize: 11.5, color: m.ink500)),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in kOrderFlow)
                        MasButton(
                          label: orderStatusLabel(s),
                          primary: false,
                          height: 36,
                          // Status yang sedang berjalan tak perlu di-set ulang;
                          // dikirim/selesai terkunci selama pengiriman DITAHAN (T-5).
                          onTap: _busy ||
                                  o.status == s ||
                                  // QA e2e 2026-09-29 #26: hanya langkah
                                  // berikutnya yang sah (server
                                  // _ALLOWED_TRANSITIONS: diproses→dikirim→
                                  // selesai); batal/selesai/menunggu_verifikasi
                                  // dulu menawarkan tombol yang pasti ditolak.
                                  _langkahBerikut(o.status) != s ||
                                  (o.tahanKirim && (s == 'dikirim' || s == 'selesai')) ||
                                  // Wajib video packing belum terpenuhi (2026-09-29).
                                  (s == 'dikirim' && !o.pickup &&
                                      (o.packingTahanKirim ?? '').isNotEmpty)
                              ? null
                              : () => _setStatus(s),
                        ),
                    ],
                  ),
                  if (o.status == 'diproses' && !o.pickup &&
                      (o.packingTahanKirim ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('🎥 ${o.packingTahanKirim}',
                        style: TextStyle(fontSize: 12, color: m.danger600, height: 1.4)),
                  ],
                ],
                if (o.status == 'dikirim' && !o.pickup) ...[
                  const SizedBox(height: 8),
                  MasButton(
                    label: '✎ Koreksi resi${(o.trackingNo ?? '').isNotEmpty ? ' (${o.trackingNo})' : ''}',
                    primary: false,
                    expand: true,
                    height: 36,
                    onTap: _busy ? null : _koreksiResi,
                  ),
                ],
                const SizedBox(height: 12),
                Divider(height: 1, color: m.ink150),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed:
                        _busy || o.status == 'batal' ? null : () => _setStatus('batal'),
                    child: Text('Batalkan pesanan',
                        style: TextStyle(fontSize: 13, color: m.danger600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

// ══════════════════════════════════════════════════════════════════════
// 3. Laporan penjualan (admin)
// ══════════════════════════════════════════════════════════════════════

const _namaBulan = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// "2026-07" → "Jul 2026".
String _labelBulan(String m) {
  final p = m.split('-');
  if (p.length < 2) return m;
  final i = int.tryParse(p[1]) ?? 0;
  final nama = (i >= 1 && i <= 12) ? _namaBulan[i - 1] : p[1];
  return '$nama ${p[0]}';
}

class PenjualanScreen extends StatefulWidget {
  const PenjualanScreen({super.key});

  @override
  State<PenjualanScreen> createState() => _PenjualanScreenState();
}

class _PenjualanScreenState extends State<PenjualanScreen> {
  SalesRecap? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.salesRecap();
      if (!mounted) return;
      setState(() {
        _data = d;
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
    final d = _data;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (_error != null) ...[
            _Alert(_error!),
            const SizedBox(height: 14),
          ],

          if (_loading)
            Column(children: [
              for (int i = 0; i < 4; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 84),
                ),
            ])
          else if (d == null)
            const MasEmpty(
              icon: Icons.bar_chart_rounded,
              title: 'Tidak ada data',
              subtitle: 'Rekap penjualan belum bisa dimuat.',
            )
          else ...[
            _statRow([
              _Stat(
                  label: 'Omzet (terjual)',
                  value: formatRupiah(d.omzet),
                  color: m.brand700),
              _Stat(label: 'Pesanan lunas', value: thousands(d.paidOrders)),
            ]),
            const SizedBox(height: 8),
            _statRow([
              _Stat(label: 'Item terjual', value: thousands(d.itemsSold)),
              _Stat(label: 'Total pesanan', value: thousands(d.totalOrders)),
            ]),
            const SizedBox(height: 14),

            _perBulan(m, d),
            const SizedBox(height: 12),

            _perGudang(m, d),
            const SizedBox(height: 12),

            _perStatus(m, d),
            const SizedBox(height: 12),

            _topParts(m, d),
            const SizedBox(height: 14),

            Text(
              'Omzet dihitung dari harga jual barang (subtotal, tanpa ongkir) untuk '
              'pesanan yang sudah dibayar — Diproses, Dikirim, atau Selesai.',
              style: TextStyle(fontSize: 11.5, color: m.ink400, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _perBulan(MasColors m, SalesRecap d) {
    if (d.byMonth.isEmpty) {
      return _kosong(m, 'Omzet per Bulan', 'Belum ada penjualan.');
    }
    // Bar proporsional ke bulan terbaik — supaya bentuk trennya terbaca.
    final maks = d.byMonth
        .map((e) => e.omzet)
        .fold<double>(1, (a, b) => b > a ? b : a);

    return MasSectionCard(
      title: 'Omzet per Bulan',
      children: [
        for (final b in d.byMonth)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text('${_labelBulan(b.month)} · ${b.count} pesanan',
                        style: TextStyle(fontSize: 12.5, color: m.ink600)),
                  ),
                  Text(formatRupiah(b.omzet),
                      style: masMono(size: 12.5, color: m.ink800)),
                ]),
                const SizedBox(height: 5),
                MasBar(value: b.omzet / maks),
              ],
            ),
          ),
      ],
    );
  }

  Widget _perGudang(MasColors m, SalesRecap d) {
    if (d.byGudang.isEmpty) {
      return _kosong(m, 'Penjualan per Cabang', 'Belum ada penjualan.');
    }
    return MasSectionCard(
      title: 'Penjualan per Cabang',
      children: [
        for (final g in d.byGudang)
          MasKeyValue(
            label: '${g.gudang.isNotEmpty ? g.gudang : '—'} · ${g.count} pesanan',
            value: formatRupiah(g.omzet),
            mono: true,
          ),
      ],
    );
  }

  Widget _perStatus(MasColors m, SalesRecap d) {
    if (d.byStatus.isEmpty) {
      return _kosong(m, 'Pesanan per Status', 'Belum ada pesanan.');
    }
    return MasSectionCard(
      title: 'Pesanan per Status',
      children: [
        for (final e in d.byStatus.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: m.ink100)),
            ),
            child: Row(children: [
              MasPill(
                label: orderStatusLabel(e.key),
                tone: orderStatusTone(e.key),
                height: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${e.value.count} pesanan',
                    style: TextStyle(fontSize: 12, color: m.ink500)),
              ),
              Text(formatRupiah(e.value.omzet),
                  style: masMono(size: 12.5, color: m.ink800)),
            ]),
          ),
      ],
    );
  }

  Widget _topParts(MasColors m, SalesRecap d) {
    if (d.topParts.isEmpty) {
      return _kosong(m, 'Part Terlaris', 'Belum ada penjualan.');
    }
    return MasSectionCard(
      title: 'Part Terlaris',
      children: [
        for (final p in d.topParts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: m.ink100)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.partNumber,
                        style: masMono(
                            size: 12, weight: FontWeight.w600, color: m.ink900)),
                    const SizedBox(height: 2),
                    Text(p.name.isNotEmpty ? p.name : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: m.ink500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatRupiah(p.omzet),
                      style: masMono(
                          size: 12.5, weight: FontWeight.w600, color: m.ink900)),
                  const SizedBox(height: 2),
                  Text('${thousands(p.qty)} pcs',
                      style: TextStyle(fontSize: 11, color: m.ink500)),
                ],
              ),
            ]),
          ),
      ],
    );
  }

  Widget _kosong(MasColors m, String title, String msg) => MasSectionCard(
        title: title,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Text(msg, style: TextStyle(fontSize: 12.5, color: m.ink400)),
          ),
        ],
      );
}

/// Bukti transfer yang diunggah pembeli. Gambar ditampilkan INLINE (ikut web)
/// supaya admin bisa memverifikasi tanpa berpindah aplikasi; PDF tak bisa
/// dirender di sini jadi tetap berupa tautan ke pembaca PDF perangkat.
/// Mengetuk gambar membukanya ukuran penuh — nominal di struk sering kecil.
class _BuktiTransfer extends StatelessWidget {
  final String url;
  final Future<void> Function(String) onBuka;
  const _BuktiTransfer({required this.url, required this.onBuka});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    if (url.toLowerCase().endsWith('.pdf')) {
      return GestureDetector(
        onTap: () => onBuka(url),
        child: Text('Buka bukti (PDF) →',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: m.brand700)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () => onBuka(url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MasRadii.card),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 280),
            color: m.ink50,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder: (_, _) => const SizedBox(
                  height: 160, child: Center(child: MasSkeleton(height: 160))),
              // Bukti gagal dimuat BUKAN berarti tidak ada — bisa jadi URL
              // bertanda tangan sudah kedaluwarsa. Sediakan jalan buka manual.
              errorWidget: (_, _, _) => Padding(
                padding: const EdgeInsets.all(14),
                child: Text('Gambar gagal dimuat — ketuk untuk membuka di peramban.',
                    style: TextStyle(fontSize: 12, color: m.ink500)),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () => onBuka(url),
        child: Text('Buka ukuran penuh →',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: m.brand700)),
      ),
    ]);
  }
}

// ── Piutang Tempo (admin, migrasi 048) — paritas web /admin/piutang ──────────
// Umur piutang pesanan TEMPO yang belum dibayar + per pelanggan. "Tandai lunas"
// ada di detail pesanan (alur Lunasi manual: alasan + bukti, gateway dicek dulu).
class PiutangScreen extends StatefulWidget {
  const PiutangScreen({super.key});

  @override
  State<PiutangScreen> createState() => _PiutangScreenState();
}

class _PiutangScreenState extends State<PiutangScreen> {
  PiutangData? _data;
  bool _loading = true;
  String? _error;
  String _filter = '';

  static const _kelompok = <(String, String)>[
    ('belum_kirim', 'Belum dikirim'),
    ('belum_jatuh_tempo', 'Belum jatuh tempo'),
    ('lewat_1_30', 'Lewat 1–30 hari'),
    ('lewat_31_60', 'Lewat 31–60 hari'),
    ('lewat_60_plus', 'Lewat > 60 hari'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.adminPiutang();
      if (!mounted) return;
      setState(() {
        _data = d;
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
    if (_loading && _data == null) return const Center(child: CircularProgressIndicator());
    final d = _data;
    if (d == null) return MasErrorState(message: _error ?? 'Piutang gagal dimuat.', onRetry: _load);
    final pelanggan = [
      for (final p in d.perPelanggan)
        (p, _filter.isEmpty ? p.orders : p.orders.where((o) => o.kelompok == _filter).toList()),
    ].where((e) => _filter.isEmpty || e.$2.isNotEmpty).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          MasCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total piutang', style: TextStyle(fontSize: 11.5, color: m.ink500)),
              Text(formatRupiah(d.ringkasan['total'] ?? 0),
                  style: masMono(size: 18, weight: FontWeight.w700, color: m.ink900)),
              Text('${d.jumlah['total'] ?? 0} pesanan',
                  style: TextStyle(fontSize: 11.5, color: m.ink500)),
            ]),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (k, label) in _kelompok)
              FilterChip(
                label: Text('$label · ${formatRupiah(d.ringkasan[k] ?? 0)}',
                    style: const TextStyle(fontSize: 12)),
                selected: _filter == k,
                onSelected: (_) => setState(() => _filter = _filter == k ? '' : k),
              ),
          ]),
          const SizedBox(height: 12),
          if (pelanggan.isEmpty)
            const MasEmpty(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Tidak ada piutang',
              subtitle: 'Pengaturan tempo per pelanggan ada di Manajemen User (ikon dompet).',
            ),
          for (final (p, orders) in pelanggan)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MasSectionCard(
                title: p.customerName.isNotEmpty ? p.customerName : p.username,
                trailing: p.tempo.beku
                    ? MasPill(
                        label: p.tempo.bekuManual ? 'Dibekukan' : 'Beku · ${p.tempo.lewat} lewat',
                        tone: MasPillTone.danger,
                        height: 20)
                    : null,
                children: [
                  MasKeyValue(
                    label: '@${p.username}',
                    value: 'terpakai ${formatRupiah(p.tempo.terpakai)}'
                        '${p.tempo.aktif ? ' / ${formatRupiah(p.tempo.limit)}' : ''}',
                  ),
                  for (final o in orders)
                    InkWell(
                      onTap: () => nav.go(MasScreen.orderDetail, part: {'order_code': o.orderCode}),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(o.orderCode,
                                  style: masMono(size: 13, weight: FontWeight.w600, color: m.ink900)),
                              Text(
                                  '${orderStatusLabel(o.status)} · '
                                  '${o.jatuhTempo != null ? 'JT ${tglJatuhTempo(o.jatuhTempo)}' : 'belum dikirim'}'
                                  '${o.hariLewat > 0 ? ' · lewat ${o.hariLewat} hari' : ''}',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: o.hariLewat > 0 ? m.danger600 : m.ink500)),
                            ]),
                          ),
                          Text(formatRupiah(o.sisa),
                              style: masMono(size: 13, weight: FontWeight.w700, color: m.ink900)),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, size: 18, color: m.ink400),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
