// lib/screens/pesanan_screen.dart
// "Pesanan Saya" — daftar pesanan milik pembeli.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../invoice_pdf.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
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
  const PesananScreen({super.key});

  @override
  State<PesananScreen> createState() => _PesananScreenState();
}

class _PesananScreenState extends State<PesananScreen> {
  List<OrderSummary> _orders = [];
  bool _loading = true;
  String? _error;
  final Set<String> _invoiceBusy = {}; // kode pesanan yang sedang dibuat invoice-nya

  String _tab = 'all';
  final _searchCtrl = TextEditingController();
  String _q = '';

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

  /// Jumlah pesanan per tab (untuk badge hitungan).
  Map<String, int> get _counts => {
        for (final t in _orderTabs)
          t.key: _orders.where((o) => t.match(o.status)).length,
      };

  /// Pesanan setelah difilter tab + kata kunci (kode / gudang) — persis web.
  List<OrderSummary> get _filtered {
    final t = _orderTabs.firstWhere((e) => e.key == _tab,
        orElse: () => _orderTabs.first);
    final term = _q.trim().toLowerCase();
    return _orders
        .where((o) => t.match(o.status))
        .where((o) =>
            term.isEmpty ||
            o.orderCode.toLowerCase().contains(term) ||
            o.gudang.toLowerCase().contains(term))
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

          if (_loading)
            Column(children: [
              for (int i = 0; i < 4; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 92),
                ),
            ])
          else if (_orders.isEmpty)
            Column(children: [
              const SizedBox(height: 30),
              const MasEmpty(
                icon: Icons.receipt_long_outlined,
                title: 'Belum ada pesanan',
                subtitle: 'Pesanan yang Anda buat akan muncul di sini.',
              ),
              const SizedBox(height: 12),
              Center(
                child: MasButton(
                  label: 'Belanja Part',
                  icon: Icons.storefront_outlined,
                  onTap: () => nav.go(MasScreen.toko),
                ),
              ),
            ])
          else ...[
            _tabBar(m),
            const SizedBox(height: 10),
            MasInput(
              controller: _searchCtrl,
              hint: 'Cari kode pesanan…',
              height: 38,
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 12),
            if (_filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Text('Tidak ada pesanan pada filter ini.',
                      style: TextStyle(fontSize: 13, color: m.ink500)),
                ),
              )
            else
              for (final o in _filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _card(m, nav, o),
                ),
          ],
        ],
      ),
    );
  }

  Widget _tabBar(MasColors m) {
    final counts = _counts;
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
          child: Text(
            count > 0 ? '$label ($count)' : label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : m.ink700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(MasColors m, AppNav nav, OrderSummary o) => MasCard(
        onTap: () => nav.go(MasScreen.pesananDetail,
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
              Icon(Icons.warehouse_outlined, size: 14, color: m.ink400),
              const SizedBox(width: 5),
              Expanded(
                child: Text(o.gudang.isNotEmpty ? o.gudang : '—',
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
              if (_kPaidStatus.contains(o.status))
                InkWell(
                  onTap: _invoiceBusy.contains(o.orderCode)
                      ? null
                      : () => _cetakInvoice(o.orderCode),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_invoiceBusy.contains(o.orderCode))
                        SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: m.brand600),
                        )
                      else
                        Icon(Icons.receipt_long_outlined, size: 14, color: m.brand700),
                      const SizedBox(width: 5),
                      Text('Invoice',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: m.brand700)),
                    ]),
                  ),
                ),
              const SizedBox(width: 6),
              _aksiCepat(m, nav, o),
            ]),
          ],
        ),
      );

  /// Tombol aksi kontekstual — Bayar (belum bayar) / Lacak (dikirim) / Detail.
  /// Semua menuju detail pesanan, persis web.
  Widget _aksiCepat(MasColors m, AppNav nav, OrderSummary o) {
    final belumBayar = o.status == 'menunggu_pembayaran';
    final label = belumBayar ? 'Bayar' : (o.status == 'dikirim' ? 'Lacak' : 'Detail');
    return Material(
      color: belumBayar ? m.brand600 : m.paper,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () =>
            nav.go(MasScreen.pesananDetail, part: {'order_code': o.orderCode}),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: belumBayar ? null : Border.all(color: m.ink200),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: belumBayar ? Colors.white : m.ink700)),
        ),
      ),
    );
  }
}
