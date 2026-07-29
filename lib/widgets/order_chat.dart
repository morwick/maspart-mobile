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

  /// Polling berkala supaya balasan lawan bicara muncul tanpa refresh manual.
  final Duration pollEvery;

  const OrderChat({
    super.key,
    required this.title,
    required this.me,
    required this.fetch,
    required this.send,
    this.pollEvery = const Duration(seconds: 12),
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
      title: widget.title,
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

  Widget _bubble(MasColors m, ChatMessage msg) {
    final mine = msg.senderUsername == widget.me;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: mine ? m.brand600 : m.ink100,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(mine ? 12 : 3),
                  bottomRight: Radius.circular(mine ? 3 : 12),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!mine)
                    Text(
                      // Peran lebih berguna dari username: pembeli ingin tahu
                      // dia sedang bicara dengan gudang atau admin.
                      msg.senderRole.isNotEmpty
                          ? '${msg.senderUsername} · ${msg.senderRole}'
                          : msg.senderUsername,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: m.ink500,
                      ),
                    ),
                  if (!mine) const SizedBox(height: 3),
                  Text(
                    msg.body,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: mine ? Colors.white : m.ink900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    fmtDate(msg.createdAt),
                    style: TextStyle(
                      fontSize: 9.5,
                      color: mine
                          ? Colors.white.withValues(alpha: 0.75)
                          : m.ink400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
