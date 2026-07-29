// lib/screens/chat_screen.dart
// Chat PRA-PESANAN pembeli ↔ gudang. Pembeli bisa bertanya (stok, kecocokan,
// ongkir) sebelum memutuskan membeli — berbeda dari chat di dalam pesanan yang
// terikat satu order.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';
import '../widgets/order_chat.dart';

class ChatScreen extends StatefulWidget {
  /// Argumen navigasi. `gudang` = key gudang yang percakapannya langsung
  /// dibuka — dipakai tombol "Chat Gudang" di Detail Part, supaya pembeli tidak
  /// perlu mencari sendiri gudang yang menyimpan part tadi.
  final Map<String, dynamic> args;
  const ChatScreen({super.key, this.args = const {}});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<BuyerChatThread> _threads = [];
  List<BuyerLocation> _gudang = [];
  String? _open;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final g = '${widget.args['gudang'] ?? ''}'.trim();
    if (g.isNotEmpty) _open = g; // label menyusul saat daftar gudang termuat
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Daftar gudang dibutuhkan supaya pembeli bisa MEMULAI percakapan baru,
      // bukan cuma membalas yang sudah ada.
      final results = await Future.wait([
        ApiService.buyerChatThreads(),
        ApiService.buyerLocations(),
      ]);
      if (!mounted) return;
      setState(() {
        _threads = results[0] as List<BuyerChatThread>;
        _gudang = results[1] as List<BuyerLocation>;
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

  /// Label gudang yang enak dibaca; fallback ke key bila belum dikenal.
  String _labelOf(String key) {
    for (final g in _gudang) {
      if (g.key == key) return g.label;
    }
    return key;
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
              onPressed: () => setState(() => _open = null),
            ),
            Expanded(
              child: Text('Gudang ${_labelOf(open)}',
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
              title: 'Percakapan',
              me: nav.username,
              fetch: () => ApiService.buyerGudangChat(open),
              send: (body) => ApiService.sendBuyerGudangChat(open, body),
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
              for (int i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 64),
                ),
            ])
          else ...[
            if (_threads.isNotEmpty) ...[
              MasSectionCard(
                title: 'Percakapan',
                children: [
                  for (final t in _threads) _threadRow(m, t),
                ],
              ),
              const SizedBox(height: 16),
            ],

            MasSectionCard(
              title: _threads.isEmpty ? 'Mulai Chat' : 'Gudang Lain',
              children: [
                if (_gudang.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Belum ada gudang yang bisa dihubungi.',
                        style: TextStyle(fontSize: 12.5, color: m.ink500)),
                  )
                else
                  for (final g in _gudang)
                    if (!_threads.any((t) => t.gudangKey == g.key))
                      _gudangRow(m, g),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _threadRow(MasColors m, BuyerChatThread t) => InkWell(
        onTap: () => setState(() => _open = t.gudangKey),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: m.ink100)),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: m.brand50,
              child: Icon(Icons.warehouse_outlined, size: 17, color: m.brand700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Gudang ${_labelOf(t.gudangKey)}',
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

  Widget _gudangRow(MasColors m, BuyerLocation g) => InkWell(
        onTap: () => setState(() => _open = g.key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: m.ink100)),
          ),
          child: Row(children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 17, color: m.ink400),
            const SizedBox(width: 12),
            Expanded(
              child: Text(g.label,
                  style: TextStyle(fontSize: 13, color: m.ink900)),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: m.ink300),
          ]),
        ),
      );
}
