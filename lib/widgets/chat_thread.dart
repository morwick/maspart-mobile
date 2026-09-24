// lib/widgets/chat_thread.dart
// Percakapan LAYAR PENUH (chat pra-pesanan pembeli ↔ gudang). Paritas dengan
// web `frontend/src/components/ChatThread.tsx` (+ chat-thread.css):
// pemisah tanggal, gelembung beruntun digabung, jam di pojok gelembung,
// usulan pesan pembuka, kotak ketik bulat yang tumbuh.
//
// Berbeda dari [OrderChat] (kartu kecil di dalam detail pesanan) — widget ini
// mengisi seluruh tinggi induknya, jadi induk wajib memberi batas tinggi
// (mis. di dalam Expanded).

import 'dart:async';
import 'package:flutter/material.dart';

import '../api_service.dart';
import '../theme/mas_theme.dart';

const _kRole = {'pembeli': 'Pembeli', 'gudang': 'Gudang', 'admin': 'Admin'};

/// Pesan beruntun dari pengirim sama dalam jarak ini = satu kelompok.
const _kGroup = Duration(minutes: 5);

const _kBulan = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
];
const _kHari = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

DateTime? _waktu(String iso) => DateTime.tryParse(iso)?.toLocal();

String _jam(String iso) {
  final d = _waktu(iso);
  if (d == null) return '';
  String dua(int n) => n.toString().padLeft(2, '0');
  return '${dua(d.hour)}.${dua(d.minute)}';
}

bool _hariSama(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Hari ini" / "Kemarin" / "Senin, 21 Sep 2026".
String labelHari(String iso) {
  final d = _waktu(iso);
  if (d == null) return iso.length >= 10 ? iso.substring(0, 10) : iso;
  final kini = DateTime.now();
  if (_hariSama(d, kini)) return 'Hari ini';
  if (_hariSama(d, kini.subtract(const Duration(days: 1)))) return 'Kemarin';
  return '${_kHari[d.weekday - 1]}, ${d.day} ${_kBulan[d.month - 1]} ${d.year}';
}

class ChatThreadView extends StatefulWidget {
  /// Username kita sendiri — untuk menentukan gelembung kiri/kanan.
  final String me;
  final Future<List<ChatMessage>> Function() fetch;
  final Future<void> Function(String body) send;
  final String emptyText;

  /// Usulan pesan pembuka; mengisi kotak ketik saat thread masih kosong.
  final List<String> quickReplies;
  final Duration pollEvery;

  const ChatThreadView({
    super.key,
    required this.me,
    required this.fetch,
    required this.send,
    this.emptyText = 'Belum ada pesan. Mulai percakapan.',
    this.quickReplies = const [],
    this.pollEvery = const Duration(seconds: 7),
  });

  @override
  State<ChatThreadView> createState() => _ChatThreadViewState();
}

class _ChatThreadViewState extends State<ChatThreadView> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _poll;

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() => setState(() {})); // tombol kirim aktif/nonaktif
    _load(scrollToEnd: true);
    _poll = Timer.periodic(widget.pollEvery, (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Hanya ikut turun bila user memang sedang di dasar — jangan menyeret dia
  /// ke bawah saat sedang membaca pesan lama (sama dengan web).
  bool get _diDasar =>
      !_scroll.hasClients ||
      _scroll.position.maxScrollExtent - _scroll.position.pixels < 120;

  Future<void> _load({bool scrollToEnd = false}) async {
    final ikut = scrollToEnd || _diDasar;
    try {
      final msgs = await widget.fetch();
      if (!mounted) return;
      final tumbuh = msgs.length != _messages.length;
      setState(() {
        _messages = msgs;
        _loading = false;
        _error = null;
      });
      if (tumbuh && ikut) _scrollToEnd();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
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
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.send(body);
      _ctl.clear();
      await _load(scrollToEnd: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal kirim. Periksa koneksi Anda.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _mine(ChatMessage x) =>
      x.senderUsername.toLowerCase() == widget.me.toLowerCase();

  bool _sekelompok(ChatMessage a, ChatMessage? b) {
    if (b == null || a.senderUsername != b.senderUsername) return false;
    final da = _waktu(a.createdAt), db = _waktu(b.createdAt);
    if (da == null || db == null) return false;
    return _hariSama(da, db) && da.difference(db).abs() < _kGroup;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Column(children: [
      Expanded(
        child: Container(
          color: m.ink50,
          child: _loading
              ? Center(
                  child: Text('Memuat pesan…',
                      style: TextStyle(fontSize: 13, color: m.ink500)))
              : _messages.isEmpty
                  ? _kosong(m)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _item(m, i),
                    ),
        ),
      ),
      if (_error != null)
        Container(
          width: double.infinity,
          color: m.danger50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(_error!,
              style: TextStyle(fontSize: 12, color: m.danger600)),
        ),
      _composer(m),
    ]);
  }

  Widget _kosong(MasColors m) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(shape: BoxShape.circle, color: m.brand50),
              child: Icon(Icons.chat_bubble_outline_rounded,
                  size: 26, color: m.isDark ? m.brand700 : m.brand600),
            ),
            const SizedBox(height: 12),
            Text('Mulai percakapan',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: m.ink900)),
            const SizedBox(height: 4),
            Text(widget.emptyText,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.5, color: m.ink500)),
            if (widget.quickReplies.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in widget.quickReplies)
                    Material(
                      color: m.paper,
                      shape: StadiumBorder(side: BorderSide(color: m.brand100)),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () {
                          _ctl.text = q;
                          _ctl.selection =
                              TextSelection.collapsed(offset: q.length);
                          _focus.requestFocus();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          child: Text(q,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: m.brand700)),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ]),
        ),
      );

  Widget _item(MasColors m, int i) {
    final msg = _messages[i];
    final prev = i > 0 ? _messages[i - 1] : null;
    final next = i + 1 < _messages.length ? _messages[i + 1] : null;
    final dMsg = _waktu(msg.createdAt);
    final dPrev = prev == null ? null : _waktu(prev.createdAt);
    final hariBaru =
        prev == null || dMsg == null || dPrev == null || !_hariSama(dMsg, dPrev);
    final awal = hariBaru || !_sekelompok(msg, prev);
    final akhir = !_sekelompok(msg, next);
    final mine = _mine(msg);

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (hariBaru)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: m.paper,
                borderRadius: BorderRadius.circular(MasRadii.pill),
                border: Border.all(color: m.ink150),
              ),
              child: Text(labelHari(msg.createdAt),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: m.ink600)),
            ),
          ),
        if (awal && !mine)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8, bottom: 3),
            child: Text(_kRole[msg.senderRole] ?? msg.senderRole,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: m.ink500)),
          ),
        Padding(
          padding: EdgeInsets.only(top: awal && mine ? 10 : 2),
          child: _bubble(m, msg, mine, awal, akhir),
        ),
      ],
    );
  }

  Widget _bubble(
      MasColors m, ChatMessage msg, bool mine, bool awal, bool akhir) {
    const besar = Radius.circular(16);
    const kecil = Radius.circular(6);
    const ekor = Radius.circular(4);
    final radius = mine
        ? BorderRadius.only(
            topLeft: besar,
            bottomLeft: besar,
            topRight: awal ? besar : kecil,
            bottomRight: akhir ? ekor : kecil)
        : BorderRadius.only(
            topRight: besar,
            bottomRight: besar,
            topLeft: awal ? besar : kecil,
            bottomLeft: akhir ? ekor : kecil);
    final hijau = m.isDark ? const Color(0xFF0F7A1D) : m.brand600;
    final warnaTeks = mine ? Colors.white : m.ink900;

    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
        decoration: BoxDecoration(
          color: mine ? hijau : m.paper,
          borderRadius: radius,
          border: mine ? null : Border.all(color: m.ink150),
        ),
        // Jam "mengapung" di pojok kanan bawah: Wrap menaruhnya di baris yang
        // sama bila muat, atau turun ke baris baru bila teks panjang.
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 10,
          children: [
            Text(msg.body,
                style: TextStyle(fontSize: 14, height: 1.4, color: warnaTeks)),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_jam(msg.createdAt),
                  style: TextStyle(
                      fontSize: 10.5,
                      color: mine
                          ? Colors.white.withValues(alpha: 0.7)
                          : m.ink500)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(MasColors m) {
    final bisa = _ctl.text.trim().isNotEmpty && !_sending;
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: m.paper,
        border: Border(top: BorderSide(color: m.ink150)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: _ctl,
            focusNode: _focus,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            style: TextStyle(fontSize: 15, color: m.ink900),
            decoration: InputDecoration(
              hintText: 'Tulis pesan…',
              hintStyle: TextStyle(color: m.ink400),
              isDense: true,
              filled: true,
              fillColor: m.ink50,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: m.ink200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: m.ink200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: m.brand500, width: 1.4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          height: 44,
          child: Material(
            color: bisa || _sending
                ? m.brand600
                : m.brand600.withValues(alpha: 0.4),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: bisa ? _send : null,
              child: Center(
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        size: 19, color: Colors.white),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
