// lib/screens/orders_screens.dart
// Tiga layar PESANAN sisi ADMIN, seluruhnya dari API nyata:
//
//   OrdersScreen      — semua pesanan lintas cabang (+ saring status).
//   OrderDetailScreen — satu pesanan: uang, penerima, gudang, aksi & chat.
//   PenjualanScreen   — rekap omzet, per bulan, per gudang, part terlaris.
//
// `OrderChat` ada DUA: model (dari models.dart lewat api_service) dan widget
// percakapan. Model tidak dipakai di sini, jadi disembunyikan supaya nama
// `OrderChat` tegas menunjuk widget-nya.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
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

class _OrdersScreenState extends State<OrdersScreen> {
  List<OrderSummary> _orders = [];
  bool _loading = true;
  String? _error;

  /// '' = semua status.
  String _filter = '';

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
      final o = await ApiService.adminOrders();
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

  List<OrderSummary> get _view =>
      _filter.isEmpty ? _orders : _orders.where((o) => o.status == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);

    // Menunggu verifikasi = satu-satunya status yang menuntut tindakan admin.
    final pending =
        _orders.where((o) => o.status == 'menunggu_verifikasi').length;

    // Hanya tawarkan status yang benar-benar ada datanya, diurut mengikuti
    // alur hidup pesanan (bukan abjad). Status tak dikenal dilempar ke akhir.
    final urutan = kOrderStatus.keys.toList();
    int rank(String s) {
      final i = urutan.indexOf(s);
      return i < 0 ? urutan.length : i;
    }

    final statuses = <String>{for (final o in _orders) o.status}.toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (_error != null) ...[
            _Alert(_error!),
            const SizedBox(height: 14),
          ],

          if (pending > 0) ...[
            Row(children: [
              MasPill(
                label: '$pending menunggu verifikasi',
                tone: MasPillTone.warn,
                dot: true,
              ),
            ]),
            const SizedBox(height: 12),
          ],

          if (statuses.isNotEmpty) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip(m, 'Semua (${_orders.length})', _filter.isEmpty,
                    () => setState(() => _filter = '')),
                for (final s in statuses) ...[
                  const SizedBox(width: 6),
                  _chip(
                    m,
                    '${orderStatusLabel(s)} '
                    '(${_orders.where((o) => o.status == s).length})',
                    _filter == s,
                    () => setState(() => _filter = s),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
          ],

          if (_loading)
            Column(children: [
              for (int i = 0; i < 5; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 96),
                ),
            ])
          else if (_view.isEmpty)
            MasEmpty(
              icon: Icons.shopping_cart_outlined,
              title: _orders.isEmpty
                  ? 'Belum ada pesanan'
                  : 'Tidak ada pesanan pada status ini',
              subtitle: _orders.isEmpty
                  ? 'Pesanan dari pembeli akan muncul di sini.'
                  : 'Pilih status lain atau tampilkan semua.',
            )
          else
            for (final o in _view)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _card(m, nav, o),
              ),
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
              // Bukti transfer manual: penanda cepat bahwa ada yang bisa dicek.
              if (o.paymentProofUrl != null && o.paymentProofUrl!.isNotEmpty)
                const MasPill(
                    label: 'ada bukti', tone: MasPillTone.info, height: 19),
            ]),
            const SizedBox(height: 6),
            Text('Dibuat ${fmtDate(o.createdAt)}',
                style: TextStyle(fontSize: 11, color: m.ink400)),
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

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.setOrderStatus(_code, status);
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
          if (o.paymentNote != null && o.paymentNote!.isNotEmpty) ...[
            _Alert('⚠️ Pembayaran perlu ditindaklanjuti. ${o.paymentNote}',
                tone: MasPillTone.warn),
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

          OrderChat(
            title: 'Chat dengan ${o.username}',
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
          value: gateway ? 'Gateway (Midtrans)' : (o.paymentMethod.isNotEmpty ? o.paymentMethod : 'Manual'),
        ),
        if (o.paymentChannel != null && o.paymentChannel!.isNotEmpty)
          MasKeyValue(label: 'Kanal', value: o.paymentChannel!.toUpperCase()),
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
            ],
          ),
        ),
      ],
    );
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
                        // Status yang sedang berjalan tak perlu di-set ulang.
                        onTap: _busy || o.status == s ? null : () => _setStatus(s),
                      ),
                  ],
                ),
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
