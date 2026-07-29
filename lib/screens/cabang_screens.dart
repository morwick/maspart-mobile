// lib/screens/cabang_screens.dart
// Layar peran CABANG (akun gudang) — cerminan `frontend/src/app/cabang/*`:
// pesanan masuk, detail + proses pesanan, rekap penjualan, dan chat pembeli.
//
// Sudut pandangnya kebalikan dari layar pembeli: di sini cabang-lah yang
// MEMENUHI pesanan. Semua data diambil dari endpoint `/api/branch/*` yang sudah
// di-scope backend ke gudang milik akun yang login — jadi tak ada filter gudang
// di sisi klien.
//
// Catatan impor: `api_service.dart` mengekspor model bernama `OrderChat` yang
// bentrok dengan WIDGET `OrderChat`. Modelnya tidak pernah disebut namanya di
// sini, jadi cukup disembunyikan supaya widget-nya yang menang.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/mas_ui.dart';
import '../widgets/order_chat.dart';

// ══════════════════════════════════════════════════════════════════════
// Helper bersama
// ══════════════════════════════════════════════════════════════════════

/// Kotak pesan berwarna (error/info/sukses/peringatan).
Widget _alert(MasColors m, String msg, {MasPillTone tone = MasPillTone.danger}) {
  late Color bg, fg, bd;
  switch (tone) {
    case MasPillTone.brand:
      bg = m.brand50; fg = m.brand700; bd = m.brand100;
    case MasPillTone.warn:
      bg = m.warn50; fg = m.warn600; bd = m.warnBorder;
    case MasPillTone.info:
      bg = m.info50; fg = m.info600; bd = m.infoBorder;
    default:
      bg = m.danger50; fg = m.danger600; bd = m.dangerBorder;
  }
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(MasRadii.card),
      border: Border.all(color: bd),
    ),
    child: Text(msg, style: TextStyle(fontSize: 12.5, color: fg, height: 1.45)),
  );
}

/// Status berikutnya menurut alur resmi (`kOrderFlow`): diproses → dikirim →
/// selesai. null = tidak ada langkah lanjutan (selesai / belum dibayar / batal).
String? _nextStatus(String status) {
  final i = kOrderFlow.indexOf(status);
  if (i < 0 || i + 1 >= kOrderFlow.length) return null;
  return kOrderFlow[i + 1];
}

// ══════════════════════════════════════════════════════════════════════
// 1. Pesanan Masuk
// ══════════════════════════════════════════════════════════════════════

/// Satu tab filter: label + penentu status mana yang masuk.
typedef _Filter = ({String label, bool Function(String status) match});

const List<_Filter> _kFilters = [
  (label: 'Semua', match: _matchAll),
  (label: 'Belum Bayar', match: _matchBelum),
  (label: 'Perlu Dikirim', match: _matchDiproses),
  (label: 'Dikirim', match: _matchDikirim),
  (label: 'Selesai', match: _matchSelesai),
  (label: 'Batal', match: _matchBatal),
];

bool _matchAll(String s) => true;
bool _matchBelum(String s) =>
    s == 'menunggu_pembayaran' || s == 'menunggu_verifikasi';
bool _matchDiproses(String s) => s == 'diproses';
bool _matchDikirim(String s) => s == 'dikirim';
bool _matchSelesai(String s) => s == 'selesai';
bool _matchBatal(String s) => s == 'batal';

class CabangPesananScreen extends StatefulWidget {
  const CabangPesananScreen({super.key});

  @override
  State<CabangPesananScreen> createState() => _CabangPesananScreenState();
}

class _CabangPesananScreenState extends State<CabangPesananScreen> {
  String _branch = '';
  List<OrderSummary> _orders = [];
  bool _loading = true;
  String? _error;

  /// Default ke "Perlu Dikirim" — itulah pekerjaan yang menunggu cabang.
  int _tab = 2;
  final _searchCtrl = TextEditingController();
  String _q = '';
  String? _busyCode; // kode pesanan yang statusnya sedang diubah

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Ubah status cepat dari daftar (Kirim/Selesai) — persis web `quickStatus`.
  Future<void> _quickStatus(String code, String status) async {
    setState(() {
      _busyCode = code;
      _error = null;
    });
    try {
      await ApiService.setBranchOrderStatus(code, status);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyCode = null);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.branchOrders();
      if (!mounted) return;
      setState(() {
        _branch = d.branch;
        _orders = d.orders;
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

  int _count(_Filter f) => _orders.where((o) => f.match(o.status)).length;

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final term = _q.trim().toLowerCase();
    final filtered = _orders
        .where((o) => _kFilters[_tab].match(o.status))
        .where((o) =>
            term.isEmpty ||
            o.orderCode.toLowerCase().contains(term) ||
            o.username.toLowerCase().contains(term))
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_error != null) ...[
            _alert(m, _error!),
            const SizedBox(height: 14),
          ],

          Row(children: [
            Icon(Icons.warehouse_outlined, size: 16, color: m.ink400),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _branch.isNotEmpty ? 'Gudang $_branch' : 'Gudang cabang Anda',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: m.ink900),
              ),
            ),
            Text('${_orders.length} pesanan',
                style: TextStyle(fontSize: 11.5, color: m.ink500)),
          ]),
          const SizedBox(height: 12),

          // Tab tak muat selebar layar ponsel → digeser mendatar.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: MasSegmentTabs(
              tabs: [
                for (final f in _kFilters)
                  _count(f) > 0 ? '${f.label} (${_count(f)})' : f.label,
              ],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          const SizedBox(height: 10),
          MasInput(
            controller: _searchCtrl,
            hint: 'Cari kode / pemesan…',
            height: 38,
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 14),

          if (_loading)
            Column(children: [
              for (int i = 0; i < 4; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 92),
                ),
            ])
          else if (filtered.isEmpty)
            MasEmpty(
              icon: Icons.inbox_outlined,
              title: _orders.isEmpty
                  ? 'Belum ada pesanan masuk'
                  : 'Tidak ada pesanan',
              subtitle: _orders.isEmpty
                  ? 'Pesanan pembeli untuk gudang ini akan muncul di sini.'
                  : 'Tidak ada pesanan pada filter "${_kFilters[_tab].label}".',
            )
          else
            for (final o in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _card(m, nav, o),
              ),
        ],
      ),
    );
  }

  Widget _card(MasColors m, AppNav nav, OrderSummary o) => MasCard(
        onTap: () => nav.go(MasScreen.cabangPesananDetail,
            part: {'order_code': o.orderCode}),
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
                    style: TextStyle(fontSize: 12, color: m.ink600)),
              ),
              Text(formatRupiah(o.total),
                  style: masMono(
                      size: 14, weight: FontWeight.w700, color: m.brand700)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text('Dibuat ${fmtDate(o.createdAt)}',
                    style: TextStyle(fontSize: 11, color: m.ink400)),
              ),
              _aksiCepat(m, nav, o),
            ]),
          ],
        ),
      );

  /// Aksi cepat dari daftar — Kirim (diproses→dikirim) / Selesai
  /// (dikirim→selesai) / Detail. Persis web `cabang/pesanan`.
  Widget _aksiCepat(MasColors m, AppNav nav, OrderSummary o) {
    final busy = _busyCode == o.orderCode;
    if (o.status == 'diproses') {
      return _aksiBtn(m, busy ? '…' : 'Kirim', primary: true,
          onTap: busy ? null : () => _quickStatus(o.orderCode, 'dikirim'));
    }
    if (o.status == 'dikirim') {
      return _aksiBtn(m, busy ? '…' : 'Selesai', primary: false,
          onTap: busy ? null : () => _quickStatus(o.orderCode, 'selesai'));
    }
    return _aksiBtn(m, 'Detail', primary: false,
        onTap: () => nav.go(MasScreen.cabangPesananDetail,
            part: {'order_code': o.orderCode}));
  }

  Widget _aksiBtn(MasColors m, String label,
      {required bool primary, required VoidCallback? onTap}) {
    return Material(
      color: primary ? m.brand600 : m.paper,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: primary ? null : Border.all(color: m.ink200),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primary ? Colors.white : m.ink700)),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 2. Detail Pesanan (sisi cabang)
// ══════════════════════════════════════════════════════════════════════

class CabangPesananDetailScreen extends StatefulWidget {
  final Map<String, dynamic> args;
  const CabangPesananDetailScreen({super.key, required this.args});

  @override
  State<CabangPesananDetailScreen> createState() =>
      _CabangPesananDetailScreenState();
}

class _CabangPesananDetailScreenState extends State<CabangPesananDetailScreen> {
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
      final o = await ApiService.branchOrder(_code);
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

  Future<void> _setStatus(String status, {String? trackingNo}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.setBranchOrderStatus(_code, status,
          trackingNo: trackingNo);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 16)),
          content: Text(body, style: const TextStyle(fontSize: 13.5)),
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

  /// Dialog nomor resi. Tanpa resi, pembeli tidak bisa melacak paketnya —
  /// jadi untuk pesanan berkurir tombolnya baru aktif setelah resi diisi.
  /// Pesanan tanpa kurir (mis. ambil di tempat) boleh dikirim tanpa resi.
  ///
  /// Kembalian: null = batal, '' = lanjut tanpa resi, selain itu = nomor resi.
  Future<String?> _askResi(OrderDetail o) async {
    final ctl = TextEditingController();
    final kurir = (o.courier ?? '').toUpperCase();
    final wajib = kurir.isNotEmpty;

    final hasil = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final m = ctx.mas;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final resi = ctl.text.trim();
            final boleh = !wajib || resi.isNotEmpty;
            return AlertDialog(
              title: const Text('Tandai Dikirim', style: TextStyle(fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stok aplikasi ditahan sampai status berubah jadi "dikirim";
                  // setelah itu angka stok mengikuti Accurate — maka penawaran
                  // di Accurate harus diproses lebih dulu.
                  _alert(
                    m,
                    'Proses penawaran di Accurate dulu. Begitu ditandai dikirim, '
                    'tahanan stok aplikasi dilepas dan stok mengikuti Accurate.',
                    tone: MasPillTone.warn,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    wajib ? 'Nomor resi ($kurir)' : 'Nomor resi (opsional)',
                    style: TextStyle(fontSize: 12, color: m.ink600),
                  ),
                  const SizedBox(height: 5),
                  MasInput(
                    controller: ctl,
                    hint: 'mis. JX1234567890',
                    mono: true,
                    height: 40,
                    onChanged: (_) => setLocal(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Batal')),
                TextButton(
                  onPressed: boleh ? () => Navigator.pop(ctx, resi) : null,
                  child: const Text('Tandai Dikirim'),
                ),
              ],
            );
          },
        );
      },
    );

    ctl.dispose();
    return hasil;
  }

  /// Jalankan langkah berikutnya di `kOrderFlow`.
  Future<void> _lanjutkan(OrderDetail o) async {
    final next = _nextStatus(o.status);
    if (next == null) return;

    if (next == 'dikirim') {
      final resi = await _askResi(o);
      if (resi == null) return; // dibatalkan
      await _setStatus('dikirim', trackingNo: resi.isEmpty ? null : resi);
      return;
    }

    final ok = await _confirm(
      'Tandai ${orderStatusLabel(next)}',
      'Ubah status pesanan $_code menjadi "${orderStatusLabel(next)}"?',
    );
    if (ok != true) return;
    await _setStatus(next);
  }

  Future<void> _batalkan() async {
    final ok = await _confirm(
      'Batalkan pesanan',
      'Batalkan pesanan $_code? Pembeli akan melihat pesanannya dibatalkan '
          'dan dana yang sudah masuk perlu dikembalikan manual.',
    );
    if (ok != true) return;
    await _setStatus('batal');
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppNav.of(context).toast('$label disalin');
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
                subtitle: _error ??
                    'Kode pesanan tidak dikenal atau bukan milik gudang ini.',
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
            _alert(m, _error!),
            const SizedBox(height: 14),
          ],

          MasCard(child: OrderStepper(status: o.status)),
          const SizedBox(height: 14),

          _items(m, o),
          const SizedBox(height: 14),

          if (o.recipientName != null || o.recipientAddress != null) ...[
            _penerima(m, o),
            const SizedBox(height: 14),
          ],

          _pengiriman(m, o),
          const SizedBox(height: 14),

          _aksi(m, o),
          const SizedBox(height: 14),

          OrderChat(
            title: 'Chat dengan Pembeli ${o.username}',
            me: nav.username,
            fetch: () async => (await ApiService.orderChat(_code)).messages,
            send: (body) => ApiService.sendOrderChat(_code, body),
          ),
        ],
      ),
    );
  }

  Widget _items(MasColors m, OrderDetail o) {
    // PPN 12% INKLUSIF: `subtotal` SUDAH mengandung pajak (ikut Accurate), jadi
    // PPN cuma dipecah sebagai komponen — JANGAN dijumlahkan ke subtotal.
    // Total = subtotal + ongkir.
    final ppn = o.tax?.round() ?? ppnOf(o.subtotal);
    final jumlahItem = o.items.fold<int>(0, (n, it) => n + it.qty);

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
                  style: masMono(
                      size: 13, weight: FontWeight.w600, color: m.ink900)),
            ]),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(children: [
            _sumRow(m, 'Subtotal', formatRupiah(o.subtotal)),
            const SizedBox(height: 5),
            _sumRow(m, 'Termasuk PPN 12%', formatRupiah(ppn), muted: true),
            const SizedBox(height: 5),
            _sumRow(
              m,
              'Ongkir${_kurirLabel(o).isNotEmpty ? ' (${_kurirLabel(o)})' : ''}',
              o.shippingCost > 0 ? formatRupiah(o.shippingCost) : '—',
            ),
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
            '$jumlahItem item · ${o.username} · dibuat ${fmtDate(o.createdAt)}',
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

  /// "JNE REG" — kurir + layanan, kosong bila pesanan tanpa kurir.
  String _kurirLabel(OrderDetail o) {
    final kurir = (o.courier ?? '').toUpperCase();
    if (kurir.isEmpty) return '';
    final layanan = o.courierService ?? '';
    return layanan.isEmpty ? kurir : '$kurir $layanan';
  }

  Widget _penerima(MasColors m, OrderDetail o) => MasSectionCard(
        title: '📍 Penerima',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${o.recipientName ?? o.username}'
                  '${o.recipientPhone != null && o.recipientPhone!.isNotEmpty ? ' · ${o.recipientPhone}' : ''}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: m.ink900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${o.recipientAddress ?? '—'}'
                  '${o.recipientPostal != null && o.recipientPostal!.isNotEmpty ? ' (${o.recipientPostal})' : ''}',
                  style:
                      TextStyle(fontSize: 12.5, color: m.ink600, height: 1.45),
                ),
                if (o.recipientAddress != null &&
                    o.recipientAddress!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  // Alamat harus disalin apa adanya ke label paket — mengetik
                  // ulang alamat panjang adalah sumber salah kirim.
                  GestureDetector(
                    onTap: () => _copy(o.recipientAddress!, 'Alamat penerima'),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.copy_rounded, size: 14, color: m.brand700),
                      const SizedBox(width: 5),
                      Text('Salin alamat',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: m.brand700)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ],
      );

  Widget _pengiriman(MasColors m, OrderDetail o) {
    final kurir = _kurirLabel(o);
    final resi = o.trackingNo ?? '';

    return MasSectionCard(
      title: '🚚 Pengiriman',
      children: [
        MasKeyValue(label: 'Kurir', value: kurir.isNotEmpty ? kurir : '—'),
        MasKeyValue(
          label: 'Berat',
          value: o.weightGrams > 0 ? '${thousands(o.weightGrams)} g' : '—',
          mono: true,
        ),
        if (resi.isEmpty)
          MasKeyValue(
            label: 'No. Resi',
            value: 'Belum ada',
            divider: false,
            valueColor: m.ink400,
          )
        else
          Container(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(children: [
              Expanded(
                child: Text('No. Resi',
                    style: TextStyle(fontSize: 13, color: m.ink600)),
              ),
              Flexible(
                child: Text(resi,
                    overflow: TextOverflow.ellipsis,
                    style: masMono(
                        size: 13, weight: FontWeight.w700, color: m.ink900)),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded, size: 16, color: m.ink500),
                visualDensity: VisualDensity.compact,
                onPressed: () => _copy(resi, 'No. resi'),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _aksi(MasColors m, OrderDetail o) {
    final next = _nextStatus(o.status);
    final belumBayar =
        ['menunggu_pembayaran', 'menunggu_verifikasi'].contains(o.status);

    return MasSectionCard(
      title: 'Proses Pesanan',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (belumBayar)
                _alert(
                  m,
                  'Menunggu pembayaran pembeli. Siapkan barang, tapi jangan '
                  'dikirim sebelum lunas.',
                  tone: MasPillTone.info,
                ),

              if (o.status == 'diproses') ...[
                Text(
                  'Pembayaran lunas. Kemas barang, lalu tandai dikirim beserta '
                  'nomor resi.',
                  style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.45),
                ),
                const SizedBox(height: 10),
              ],

              if (o.status == 'dikirim') ...[
                Text(
                  o.trackingNo != null && o.trackingNo!.isNotEmpty
                      ? 'Sudah dikirim · resi ${o.trackingNo}. Tandai selesai '
                          'setelah barang diterima pembeli.'
                      : 'Sudah dikirim. Tandai selesai setelah barang diterima '
                          'pembeli.',
                  style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.45),
                ),
                const SizedBox(height: 10),
              ],

              if (next != null)
                MasButton(
                  label: _busy
                      ? 'Memproses…'
                      : (next == 'dikirim'
                          ? '🚚 Tandai Dikirim'
                          : '✓ Tandai Selesai'),
                  expand: true,
                  loading: _busy,
                  onTap: _busy ? null : () => _lanjutkan(o),
                ),

              if (o.status == 'diproses') ...[
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : _batalkan,
                    child: Text('Batalkan pesanan',
                        style: TextStyle(fontSize: 13, color: m.danger600)),
                  ),
                ),
              ],

              if (o.status == 'selesai')
                _alert(m, 'Pesanan selesai. Terima kasih!',
                    tone: MasPillTone.brand),

              if (o.status == 'batal') _alert(m, 'Pesanan dibatalkan.'),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 3. Laporan Penjualan Cabang
// ══════════════════════════════════════════════════════════════════════

const List<String> _kBulan = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// '2026-07' → 'Jul 2026'.
String _labelBulan(String m) {
  final p = m.split('-');
  if (p.length != 2) return m;
  final i = int.tryParse(p[1]) ?? 0;
  final nama = (i >= 1 && i <= 12) ? _kBulan[i - 1] : p[1];
  return '$nama ${p[0]}';
}

class CabangPenjualanScreen extends StatefulWidget {
  const CabangPenjualanScreen({super.key});

  @override
  State<CabangPenjualanScreen> createState() => _CabangPenjualanScreenState();
}

class _CabangPenjualanScreenState extends State<CabangPenjualanScreen> {
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
      // Rekap sudah di-scope backend ke gudang akun cabang ini.
      final d = await ApiService.branchSales();
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_error != null) ...[
            _alert(m, _error!),
            const SizedBox(height: 14),
          ],

          if (_loading)
            Column(children: [
              for (int i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: MasSkeleton(height: 96),
                ),
            ])
          else if (d == null)
            const MasEmpty(
              icon: Icons.bar_chart_rounded,
              title: 'Rekap tidak tersedia',
              subtitle: 'Data penjualan cabang belum bisa dimuat.',
            )
          else ...[
            if (d.byGudang.isNotEmpty) ...[
              Row(children: [
                Icon(Icons.warehouse_outlined, size: 16, color: m.ink400),
                const SizedBox(width: 6),
                Text('Gudang ${d.byGudang.first.gudang}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: m.ink900)),
              ]),
              const SizedBox(height: 12),
            ],

            Row(children: [
              Expanded(
                child: _stat(m, 'Omzet (terjual)', formatRupiah(d.omzet),
                    highlight: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _stat(m, 'Pesanan Lunas', thousands(d.paidOrders)),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _stat(m, 'Total Pesanan', thousands(d.totalOrders)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _stat(m, 'Item Terjual', thousands(d.itemsSold)),
              ),
            ]),
            const SizedBox(height: 14),

            _perBulan(m, d),
            const SizedBox(height: 14),

            _perStatus(m, d),
            const SizedBox(height: 14),

            _topParts(m, d),
            const SizedBox(height: 12),

            Text(
              'Omzet dihitung dari harga jual barang (subtotal, tanpa ongkir) '
              'untuk pesanan yang sudah dibayar (Diproses/Dikirim/Selesai).',
              style: TextStyle(fontSize: 11.5, color: m.ink400, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(MasColors m, String label, String value,
          {bool highlight = false}) =>
      MasCard(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: m.ink500)),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: masMono(
                      size: 17,
                      weight: FontWeight.w700,
                      color: highlight ? m.brand700 : m.ink900)),
            ),
          ],
        ),
      );

  Widget _perBulan(MasColors m, SalesRecap d) {
    // Bar dinormalkan ke bulan TERBESAR supaya panjangnya bisa dibandingkan
    // antar bulan; minimal 1 agar tak pernah membagi nol.
    final maks = d.byMonth.fold<double>(
        1, (mx, e) => e.omzet > mx ? e.omzet : mx);

    return MasSectionCard(
      title: 'Omzet per Bulan',
      children: [
        if (d.byMonth.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Belum ada penjualan.',
                style: TextStyle(fontSize: 12.5, color: m.ink500)),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(children: [
              for (final b in d.byMonth) ...[
                Row(children: [
                  Expanded(
                    child: Text(
                        '${_labelBulan(b.month)} · ${b.count} pesanan',
                        style: TextStyle(fontSize: 12.5, color: m.ink600)),
                  ),
                  Text(formatRupiah(b.omzet),
                      style: masMono(size: 12.5, color: m.ink900)),
                ]),
                const SizedBox(height: 4),
                MasBar(value: b.omzet / maks),
                const SizedBox(height: 10),
              ],
            ]),
          ),
      ],
    );
  }

  Widget _perStatus(MasColors m, SalesRecap d) => MasSectionCard(
        title: 'Pesanan per Status',
        children: [
          if (d.byStatus.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Belum ada pesanan.',
                  style: TextStyle(fontSize: 12.5, color: m.ink500)),
            )
          else
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${e.value.count} pesanan',
                        style: TextStyle(fontSize: 12.5, color: m.ink500)),
                  ),
                  Text(formatRupiah(e.value.omzet),
                      style: masMono(size: 12.5, color: m.ink900)),
                ]),
              ),
        ],
      );

  Widget _topParts(MasColors m, SalesRecap d) => MasSectionCard(
        title: 'Part Terlaris',
        children: [
          if (d.topParts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Belum ada penjualan.',
                  style: TextStyle(fontSize: 12.5, color: m.ink500)),
            )
          else
            for (final p in d.topParts)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: m.ink100)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(p.partNumber,
                              style: masMono(
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: m.ink900)),
                          const SizedBox(height: 2),
                          Text(p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: m.ink500)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(formatRupiah(p.omzet),
                            style: masMono(
                                size: 12.5,
                                weight: FontWeight.w600,
                                color: m.ink900)),
                        const SizedBox(height: 2),
                        Text('${p.qty} pcs',
                            style: TextStyle(fontSize: 11, color: m.ink500)),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      );
}

// ══════════════════════════════════════════════════════════════════════
// 4. Chat Pembeli (sisi cabang)
// ══════════════════════════════════════════════════════════════════════

/// Selang auto-refresh daftar percakapan — sama dengan web (15 detik).
const Duration _cabangChatRefresh = Duration(seconds: 15);

class CabangChatScreen extends StatefulWidget {
  const CabangChatScreen({super.key});

  @override
  State<CabangChatScreen> createState() => _CabangChatScreenState();
}

class _CabangChatScreenState extends State<CabangChatScreen> {
  List<ChatThreadSummary> _threads = [];

  /// Username pembeli yang percakapannya sedang dibuka; null = daftar thread.
  String? _open;
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Ikut web: daftar percakapan disegarkan tiap 15 detik supaya pertanyaan
    // pembeli yang baru masuk terlihat tanpa perlu tarik-untuk-muat-ulang.
    // Isi percakapan yang sedang DIBUKA punya polling sendiri di OrderChat.
    _poll = Timer.periodic(_cabangChatRefresh, (_) => _load(diam: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// [diam] = refresh latar: tanpa skeleton, dan kegagalan sesaat tidak
  /// menimpa daftar yang sudah tampil.
  Future<void> _load({bool diam = false}) async {
    if (!diam) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final t = await ApiService.branchChatThreads();
      if (!mounted) return;
      setState(() {
        _threads = t;
        _loading = false;
        if (diam) _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || diam) return;
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
    final open = _open;

    if (open != null) {
      return Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: m.paper,
            border: Border(bottom: BorderSide(color: m.ink150)),
          ),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, size: 20, color: m.ink800),
              // Kembali ke daftar juga menyegarkan cuplikan pesan terakhir.
              onPressed: () {
                setState(() => _open = null);
                _load();
              },
            ),
            Expanded(
              child: Text('Pembeli $open',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: m.ink900)),
            ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: OrderChat(
              title: 'Pembeli $open',
              me: nav.username,
              fetch: () => ApiService.branchChat(open),
              send: (body) => ApiService.sendBranchChat(open, body),
            ),
          ),
        ),
      ]);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_error != null) ...[
            _alert(m, _error!),
            const SizedBox(height: 14),
          ],

          if (_loading)
            Column(children: [
              for (int i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 64),
                ),
            ])
          else if (_threads.isEmpty)
            const MasEmpty(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Belum ada chat',
              subtitle:
                  'Pertanyaan pembeli untuk gudang ini akan muncul di sini. '
                  'Percakapan hanya bisa dimulai oleh pembeli.',
            )
          else
            MasSectionCard(
              title: 'Pembeli',
              children: [
                for (final t in _threads) _threadRow(m, t),
              ],
            ),
        ],
      ),
    );
  }

  Widget _threadRow(MasColors m, ChatThreadSummary t) => InkWell(
        onTap: () => setState(() => _open = t.buyerUsername),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: m.ink100)),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: m.brand50,
              child: Icon(Icons.person_outline_rounded,
                  size: 17, color: m.brand700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.buyerUsername,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: m.ink900)),
                  const SizedBox(height: 2),
                  Text(t.last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: m.ink500)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(fmtDate(t.createdAt),
                style: TextStyle(fontSize: 10, color: m.ink400)),
          ]),
        ),
      );
}
