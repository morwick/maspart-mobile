// lib/screens/admin_chat_screen.dart
// Chat Pembeli (admin) — masukan penguji 2026-09-29: admin membaca & membalas
// SEMUA chat pra-pesanan pembeli ↔ gudang lintas gudang. Dulu endpoint-nya
// require_branch → admin 403, jadi pertanyaan ke gudang tanpa akun cabang
// aktif tak terbaca siapa pun. Paritas web `app/admin/chat/page.tsx`; pola
// tampilan meniru CabangChatScreen.

import 'dart:async';

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../widgets/chat_thread.dart';
import '../widgets/mas_ui.dart';

class AdminChatScreen extends StatefulWidget {
  /// `gudang` + `buyer` = thread yang langsung dibuka (tautan notifikasi).
  final Map<String, dynamic> args;
  const AdminChatScreen({super.key, this.args = const {}});

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  List<AdminChatThread> _threads = [];

  /// Thread yang sedang dibuka: (gudang_key, buyer); null = daftar.
  (String, String)? _open;

  /// Saring per gudang ('' = semua gudang).
  String _filter = '';
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final g = '${widget.args['gudang'] ?? ''}'.trim().toLowerCase();
    final b = '${widget.args['buyer'] ?? ''}'.trim().toLowerCase();
    if (g.isNotEmpty && b.isNotEmpty) _open = (g, b);
    _load();
    // Sama dengan web: daftar disegarkan tiap 15 detik.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load(diam: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool diam = false}) async {
    if (!diam) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final t = await ApiService.adminChatThreads();
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
    } catch (_) {
      if (!mounted || diam) return;
      setState(() {
        _error = 'Gagal memuat percakapan. Periksa koneksi Anda.';
        _loading = false;
      });
    }
  }

  String _labelGudang(String key) {
    for (final t in _threads) {
      if (t.gudangKey == key && t.gudangLabel.isNotEmpty) return t.gudangLabel;
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final open = _open;

    if (open != null) {
      final gudang = open.$1;
      final buyer = open.$2;
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
              onPressed: () {
                setState(() => _open = null);
                _load();
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Pembeli $buyer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: m.ink900)),
                  Text('Gudang ${_labelGudang(gudang)} · balas sebagai Admin MasPart',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: m.ink500)),
                ],
              ),
            ),
          ]),
        ),
        Expanded(
          child: ChatThreadView(
            key: ValueKey('$gudang|$buyer'),
            me: nav.username,
            fetch: () => ApiService.adminChat(gudang, buyer),
            send: (body) => ApiService.sendAdminChat(gudang, buyer, body),
          ),
        ),
      ]);
    }

    final gudangOpsi = <String, String>{};
    for (final t in _threads) {
      gudangOpsi[t.gudangKey] =
          t.gudangLabel.isNotEmpty ? t.gudangLabel : t.gudangKey;
    }
    final tampil = _filter.isEmpty
        ? _threads
        : _threads.where((t) => t.gudangKey == _filter).toList();

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
          if (gudangOpsi.length > 1) ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              ChoiceChip(
                label: const Text('Semua gudang', style: TextStyle(fontSize: 12.5)),
                selected: _filter.isEmpty,
                onSelected: (_) => setState(() => _filter = ''),
              ),
              for (final e in gudangOpsi.entries)
                ChoiceChip(
                  label: Text(e.value, style: const TextStyle(fontSize: 12.5)),
                  selected: _filter == e.key,
                  onSelected: (_) => setState(() => _filter = e.key),
                ),
            ]),
            const SizedBox(height: 12),
          ],
          if (_loading)
            Column(children: [
              for (int i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 64),
                ),
            ])
          else if (tampil.isEmpty)
            const MasEmpty(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Belum ada chat',
              subtitle: 'Pertanyaan pembeli ke gudang mana pun akan muncul di sini.',
            )
          else
            MasSectionCard(
              title: 'Percakapan (${tampil.length})',
              children: [
                for (final t in tampil) _threadRow(m, t),
              ],
            ),
        ],
      ),
    );
  }

  Widget _threadRow(MasColors m, AdminChatThread t) => InkWell(
        onTap: () => setState(() => _open = (t.gudangKey, t.buyerUsername)),
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
                  Row(children: [
                    Flexible(
                      child: Text(t.buyerUsername,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: m.ink900)),
                    ),
                    if (t.lastRole == 'pembeli') ...[
                      const SizedBox(width: 6),
                      // Pesan terakhir dari pembeli = belum dibalas.
                      const MasPill(
                          label: 'menunggu', tone: MasPillTone.warn, height: 18),
                    ],
                  ]),
                  Text('Gudang ${t.gudangLabel.isNotEmpty ? t.gudangLabel : t.gudangKey}',
                      style: TextStyle(fontSize: 11, color: m.ink500)),
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
