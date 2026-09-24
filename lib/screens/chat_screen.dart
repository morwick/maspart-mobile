// lib/screens/chat_screen.dart
// Chat PRA-PESANAN pembeli ↔ gudang. Pembeli bisa bertanya (stok, kecocokan,
// ongkir) sebelum memutuskan membeli — berbeda dari chat di dalam pesanan yang
// terikat satu order.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';
import '../widgets/chat_thread.dart';

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

  /// Gudang yang RELEVAN saja (sama dengan web /chat): gudang dari tombol
  /// "Chat Gudang" (argumen pembuka) + riwayat chat; gudang milik pembeli
  /// hanya dipakai bila keduanya kosong. ⛔ Jangan kembali mendaftar SEMUA
  /// gudang — pembeli tak punya alasan menyapa gudang yang tak menyimpan
  /// part yang ia cari.
  List<String> _keys = [];

  /// Key gudang dari argumen pembuka (tetap di daftar walau belum ada pesan).
  String? _pre;
  String? _open;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final g = '${widget.args['gudang'] ?? ''}'.trim();
    if (g.isNotEmpty) {
      _pre = g;
      _open = g; // label menyusul saat daftar gudang termuat
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Daftar lokasi hanya untuk LABEL gudang (key → "Jakarta").
      final results = await Future.wait([
        ApiService.buyerChatThreads(),
        ApiService.buyerLocations(),
      ]);
      final threads = results[0] as List<BuyerChatThread>;
      final keys = <String>[];
      void push(String? k) {
        final v = (k ?? '').trim();
        if (v.isNotEmpty && !keys.contains(v)) keys.add(v);
      }

      push(_pre);
      for (final t in threads) {
        push(t.gudangKey);
      }
      if (keys.isEmpty) {
        // Belum ada konteks & belum ada chat → gudang milik pembeli.
        try {
          push((await ApiService.buyerLocation()).key);
        } catch (_) {
          /* tak apa — layar kosong + ajakan belanja */
        }
      }
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _gudang = results[1] as List<BuyerLocation>;
        _keys = keys;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      // Putus jaringan dll. — tanpa ini kerangka memuat berputar selamanya.
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat percakapan. Periksa koneksi Anda.';
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
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
          decoration: BoxDecoration(
            color: m.paper,
            border: Border(bottom: BorderSide(color: m.ink150)),
          ),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, size: 22, color: m.ink800),
              onPressed: () {
                setState(() => _open = null);
                _load(); // pratinjau pesan terakhir di daftar ikut segar
              },
            ),
            const _AvatarGudang.ikon(),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Gudang ${_labelOf(open)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: m.ink900)),
                  Text('Tim gudang MasPart · stok, ongkir & pengiriman',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: m.ink500)),
                ],
              ),
            ),
          ]),
        ),
        Expanded(
          child: ChatThreadView(
            key: ValueKey(open),
            me: nav.username,
            emptyText: 'Tanyakan ketersediaan stok, ongkir, atau estimasi '
                'pengiriman ke gudang ini.',
            quickReplies: _kUsulan,
            fetch: () => ApiService.buyerGudangChat(open),
            send: (body) => ApiService.sendBuyerGudangChat(open, body),
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
          else if (_keys.isEmpty && _error == null)
            MasEmpty(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Belum ada percakapan',
              subtitle: 'Buka detail sebuah part lalu klik Chat Gudang untuk '
                  'menanyakan ketersediaan stok langsung ke tim gudang.',
              action: MasButton(
                label: 'Mulai belanja',
                height: 38,
                onTap: () => nav.go(MasScreen.toko),
              ),
            )
          else if (_keys.isNotEmpty)
            MasSectionCard(
              title: 'Percakapan',
              children: [
                for (final k in _keys) _threadRow(m, k),
              ],
            ),
        ],
      ),
    );
  }

  Widget _threadRow(MasColors m, String key) {
    final label = _labelOf(key);
    BuyerChatThread? t;
    for (final x in _threads) {
      if (x.gudangKey == key) {
        t = x;
        break;
      }
    }
    return InkWell(
      onTap: () => setState(() => _open = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: m.ink100)),
        ),
        child: Row(children: [
          _AvatarGudang(label: label),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(
                    child: Text('Gudang $label',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: m.ink900)),
                  ),
                  const SizedBox(width: 8),
                  Text(_waktuRingkas(t?.createdAt ?? ''),
                      style: TextStyle(fontSize: 11, color: m.ink400)),
                ]),
                const SizedBox(height: 3),
                Text(
                    (t?.last ?? '').isNotEmpty ? t!.last : 'Belum ada pesan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: m.ink500,
                        fontStyle: (t?.last ?? '').isNotEmpty
                            ? FontStyle.normal
                            : FontStyle.italic)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Usulan pesan pembuka — sama dengan web `app/chat/page.tsx`.
const _kUsulan = [
  'Apakah part ini ready stok?',
  'Bisa dikirim hari ini?',
  'Berapa lama estimasi pengiriman?',
  'Ada part alternatif/pengganti?',
];

/// Waktu ringkas di daftar: jam bila hari ini, "Kemarin", atau tanggal.
String _waktuRingkas(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final kini = DateTime.now();
  final hari = DateTime(kini.year, kini.month, kini.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (hari == 0) {
    String dua(int n) => n.toString().padLeft(2, '0');
    return '${dua(d.hour)}.${dua(d.minute)}';
  }
  if (hari == 1) return 'Kemarin';
  const bulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  return '${d.day} ${bulan[d.month - 1]}';
}

/// Avatar bulat hijau: inisial gudang ("Pekanbaru" → "PE"), atau ikon gudang
/// di kepala percakapan.
class _AvatarGudang extends StatelessWidget {
  final String label;
  final bool ikon;
  const _AvatarGudang({this.label = ''}) : ikon = false;
  const _AvatarGudang.ikon()
      : label = '',
        ikon = true;

  String get _inisial {
    final kata = label.trim().split(RegExp(r'\s+')).where((k) => k.isNotEmpty).toList();
    if (kata.length >= 2) return (kata[0][0] + kata[1][0]).toUpperCase();
    final k = kata.isEmpty ? '?' : kata[0];
    return (k.length >= 2 ? k.substring(0, 2) : k).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF03A318), Color(0xFF015A0B)],
        ),
      ),
      child: ikon
          ? const Icon(Icons.warehouse_outlined, size: 20, color: Colors.white)
          : Text(_inisial,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
    );
  }
}
