// lib/widgets/order_chat.dart
// Percakapan pembeli ↔ gudang. Dipakai di detail pesanan (pembeli & cabang)
// dan di chat pra-pesanan, jadi cara mengambil/mengirim pesan disuntikkan
// lewat [fetch]/[send] alih-alih dipaku ke satu endpoint.

import 'dart:async';
import 'package:flutter/material.dart';

import '../api_service.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';

class OrderChat extends StatefulWidget {
  final String title;

  /// Username kita sendiri — untuk menentukan gelembung kiri/kanan.
  final String me;
  final Future<List<ChatMessage>> Function() fetch;
  final Future<void> Function(String body) send;

  /// Polling berkala supaya balasan lawan bicara muncul tanpa refresh manual
  /// (7 detik — sama dengan web `OrderChat.tsx`).
  final Duration pollEvery;

  const OrderChat({
    super.key,
    required this.title,
    required this.me,
    required this.fetch,
    required this.send,
    this.pollEvery = const Duration(seconds: 7),
  });

  @override
  State<OrderChat> createState() => _OrderChatState();
}

class _OrderChatState extends State<OrderChat> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(scrollToEnd: true);
    _poll = Timer.periodic(widget.pollEvery, (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool scrollToEnd = false}) async {
    try {
      final msgs = await widget.fetch();
      if (!mounted) return;
      final tumbuh = msgs.length > _messages.length;
      setState(() {
        _messages = msgs;
        _loading = false;
        _error = null;
      });
      if (scrollToEnd || tumbuh) _scrollToEnd();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final body = _ctl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.send(body);
      _ctl.clear();
      await _load(scrollToEnd: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;

    return MasSectionCard(
      title: widget.title.startsWith('💬') ? widget.title : '💬 ${widget.title}',
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: MasSkeleton(height: 80),
          )
        else if (_messages.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            child: Center(
              child: Text('Belum ada pesan. Mulai percakapan di bawah.',
                  style: TextStyle(fontSize: 12.5, color: m.ink500)),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              controller: _scroll,
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _bubble(m, _messages[i]),
            ),
          ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(_error!,
                style: TextStyle(fontSize: 12, color: m.danger600)),
          ),

        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: m.ink100)),
          ),
          child: Row(children: [
            Expanded(
              child: MasInput(
                controller: _ctl,
                hint: 'Tulis pesan…',
                height: 40,
                action: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 40,
              child: Material(
                color: m.brand600,
                borderRadius: BorderRadius.circular(MasRadii.input),
                child: InkWell(
                  onTap: _sending ? null : _send,
                  borderRadius: BorderRadius.circular(MasRadii.input),
                  child: Center(
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded,
                            size: 17, color: Colors.white),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  /// Nama peran pengirim — sama dengan `roleLabel` web.
  static const _roleLabel = {
    'pembeli': 'Pembeli',
    'gudang': 'Gudang',
    'admin': 'Admin',
  };

  Widget _bubble(MasColors m, ChatMessage msg) {
    final mine =
        msg.senderUsername.toLowerCase() == widget.me.toLowerCase();
    // Label di BAWAH gelembung (seperti web): "Anda" atau nama peran + waktu.
    final siapa = mine
        ? 'Anda'
        : (_roleLabel[msg.senderRole] ??
            (msg.senderRole.isNotEmpty ? msg.senderRole : msg.senderUsername));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: 0.82,
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: mine ? m.brand600 : m.paper,
                  borderRadius: BorderRadius.circular(10),
                  border: mine ? null : Border.all(color: m.ink150),
                ),
                child: Text(
                  msg.body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: mine ? Colors.white : m.ink800,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$siapa · ${fmtDate(msg.createdAt)}',
                style: TextStyle(fontSize: 10, color: m.ink400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
