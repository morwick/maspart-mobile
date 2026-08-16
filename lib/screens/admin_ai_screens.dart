// lib/screens/admin_ai_screens.dart
// Lima layar admin untuk MERAWAT ASISTEN AI, semuanya bersumber dari API nyata:
//
//   FeedbackScreen  — 👍/👎 user atas jawaban asisten (antrean perbaikan).
//   ChatLogScreen   — observabilitas: latensi, guard, tool gagal.
//   MissesScreen    — query yang 0 hasil (umpan untuk Kamus Sinonim).
//   SinonimScreen   — kamus istilah lapangan → kata kunci katalog + usulan LLM.
//   MaksudScreen    — rute frasa khas bengkel → TOOL yang dipakai asisten.
//
// Semuanya membentuk satu lingkaran perbaikan: user memberi 👎 / mencari
// istilah yang nihil → admin melihatnya di Umpan Balik & Pencarian Nihil →
// dipetakan jadi sinonim → asisten langsung lebih pintar (kamus dibaca ulang
// per-mtime, tanpa restart server). Rute Maksud menutup sisi yang tak bisa
// disentuh kamus: bukan KATA yang dicari, melainkan ALAT yang dipakai.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/mas_ui.dart';
import '../widgets/md_table.dart';

// ══════════════════════════════════════════════════════════════════════
// Potongan UI bersama keempat layar
// ══════════════════════════════════════════════════════════════════════

/// Kotak pesan berwarna (error / info / sukses / peringatan).
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

/// Kartu angka ringkas (KPI). [hint] = baris kecil di bawah nilai.
class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final Color? color;
  const _Stat({required this.label, required this.value, this.hint, this.color});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return MasCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: m.ink500)),
          const SizedBox(height: 3),
          Text(value,
              style: masMono(
                  size: 19, weight: FontWeight.w700, color: color ?? m.ink900)),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: m.ink400)),
          ],
        ],
      ),
    );
  }
}

/// Baris KPI: tiap kartu berbagi lebar rata & tinggi sama. IntrinsicHeight
/// wajib — di dalam ListView tinggi tak terbatas, dan Row bertingkah `stretch`
/// pada tinggi tak terbatas akan meledak.
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

/// Chip kecil untuk daftar istilah / kata kunci / sumber.
class _Chip extends StatelessWidget {
  final String label;
  final MasPillTone tone;

  /// Kata kunci yang DIBUANG validator backend — dicoret supaya admin paham
  /// kenapa usulan LLM tidak seluruhnya masuk kamus.
  final bool struck;
  const _Chip(this.label, {this.tone = MasPillTone.neutral, this.struck = false});

  @override
  Widget build(BuildContext context) {
    if (!struck) return MasPill(label: label, tone: tone, height: 20);

    final m = context.mas;
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: m.ink100,
        borderRadius: BorderRadius.circular(MasRadii.pill),
        border: Border.all(color: m.ink200),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: m.ink400,
          decoration: TextDecoration.lineThrough,
          decorationColor: m.ink400,
        ),
      ),
    );
  }
}

/// Dialog konfirmasi ya/tidak.
Future<bool> _confirm(BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(body, style: const TextStyle(fontSize: 13.5)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true), child: const Text('Ya')),
      ],
    ),
  );
  return ok == true;
}

/// Pecah input daftar (koma / titik-koma / baris baru) jadi istilah bersih.
List<String> _splitTerms(String raw) => raw
    .split(RegExp(r'[\n,;]+'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

// ══════════════════════════════════════════════════════════════════════
// 1. Umpan Balik AI
// ══════════════════════════════════════════════════════════════════════

/// Filter daftar umpan balik. `down` jadi default: 👎 yang belum ditangani
/// adalah satu-satunya yang menuntut tindakan admin.
enum _FbFilter { down, up, all }

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  AIFeedbackList? _data;
  _FbFilter _filter = _FbFilter.down;
  bool _onlyOpen = true;
  bool _loading = true;
  String? _error;

  /// Id baris yang sedang dikirim ke server (tombol dikunci sementara).
  int? _busyId;

  /// Baris yang jawabannya sedang dibentangkan.
  final Set<int> _expanded = {};

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
      final d = await ApiService.listAiFeedback(
        rating: _filter == _FbFilter.all ? null : _filter.name,
        // "Belum ditangani" tidak relevan untuk 👍 — tidak ada yang perlu
        // ditangani di sana, jadi jangan sampai daftarnya kosong tanpa sebab.
        onlyOpen: _filter == _FbFilter.up ? false : _onlyOpen,
      );
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

  Future<void> _toggleResolved(AIFeedbackRow row) async {
    setState(() {
      _busyId = row.id;
      _error = null;
    });
    try {
      await ApiService.resolveAiFeedback(row.id, resolved: !row.resolved);
      if (!mounted) return;
      setState(() => _busyId = null);
      // Muat ulang: ringkasan (jumlah "belum ditangani") ikut berubah, dan
      // baris bisa lenyap dari daftar bila filter "hanya belum ditangani".
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busyId = null;
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
          Text(
            'Tiap 👍/👎 dari user tersimpan lengkap dengan pertanyaan, jawaban, '
            'dan tool yang dipakai asisten. Fokuskan pada 👎 yang belum '
            'ditangani — itulah antrean perbaikan.',
            style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
          ),
          const SizedBox(height: 14),

          if (d != null) ...[
            _statRow([
              _Stat(label: 'Total', value: thousands(d.total)),
              _Stat(label: '👍 Bagus', value: thousands(d.up), color: m.brand700),
            ]),
            const SizedBox(height: 8),
            _statRow([
              _Stat(
                  label: '👎 Perlu perbaikan',
                  value: thousands(d.down),
                  color: m.warn600),
              _Stat(
                  label: '👎 Belum ditangani',
                  value: thousands(d.downBelumDitangani),
                  color: m.danger600),
            ]),
            const SizedBox(height: 14),
          ],

          Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: MasSegmentTabs(
                  tabs: const ['👎 Perlu perbaikan', '👍 Bagus', 'Semua'],
                  index: _FbFilter.values.indexOf(_filter),
                  onChanged: (i) {
                    setState(() => _filter = _FbFilter.values[i]);
                    _load();
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.refresh_rounded, size: 20, color: m.ink600),
              tooltip: 'Muat ulang',
              onPressed: _loading ? null : _load,
            ),
          ]),

          if (_filter != _FbFilter.up)
            InkWell(
              onTap: () {
                setState(() => _onlyOpen = !_onlyOpen);
                _load();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Icon(
                    _onlyOpen
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 18,
                    color: _onlyOpen ? m.brand600 : m.ink400,
                  ),
                  const SizedBox(width: 7),
                  Text('Sembunyikan yang sudah ditangani',
                      style: TextStyle(fontSize: 12.5, color: m.ink600)),
                ]),
              ),
            ),
          const SizedBox(height: 6),

          if (_error != null) ...[
            _Alert(_error!),
            const SizedBox(height: 14),
          ],

          if (_loading)
            Column(children: [
              for (int i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 96),
                ),
            ])
          else if (d == null || d.feedback.isEmpty)
            MasEmpty(
              icon: Icons.forum_outlined,
              title: _filter == _FbFilter.down
                  ? 'Tidak ada 👎 yang menunggu'
                  : 'Belum ada umpan balik',
              subtitle: _filter == _FbFilter.down
                  ? 'Semua penilaian buruk sudah ditangani. 🎉'
                  : 'Belum ada penilaian user pada filter ini.',
            )
          else
            for (final row in d.feedback)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _card(m, row),
              ),
        ],
      ),
    );
  }

  Widget _card(MasColors m, AIFeedbackRow row) {
    final down = row.rating == 'down';
    final open = _expanded.contains(row.id);

    return Opacity(
      // Yang sudah ditangani diredupkan supaya mata langsung tertuju ke antrean.
      opacity: row.resolved ? 0.62 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: m.paper,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border.all(color: m.ink150),
          boxShadow: m.shadow1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Garis kiri berwarna: penanda cepat 👍 vs 👎.
            Container(
              padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                      color: down ? m.warn600 : m.brand600, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(down ? '👎' : '👍',
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.question?.isNotEmpty == true
                            ? row.question!
                            : '(pertanyaan tidak tercatat)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: row.question?.isNotEmpty == true
                              ? m.ink900
                              : m.ink400,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ]),

                  if (row.note != null && row.note!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: m.warn50,
                        borderRadius: BorderRadius.circular(MasRadii.input),
                        border: Border.all(color: m.warnBorder),
                      ),
                      child: Text('Catatan user: “${row.note}”',
                          style: TextStyle(
                              fontSize: 12, color: m.warn600, height: 1.4)),
                    ),
                  ],

                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setState(() {
                      if (open) {
                        _expanded.remove(row.id);
                      } else {
                        _expanded.add(row.id);
                      }
                    }),
                    child: Text(
                      open ? '▾ Sembunyikan jawaban' : '▸ Lihat jawaban asisten',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: m.brand700),
                    ),
                  ),

                  if (open) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 320),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: m.ink50,
                        borderRadius: BorderRadius.circular(MasRadii.input),
                        border: Border.all(color: m.ink150),
                      ),
                      // Jawaban di sini = jawaban asisten yang SAMA dgn di chat,
                      // jadi ia memakai renderer yang sama (dulu stylesheet
                      // ad-hoc TANPA properti tabel sama sekali).
                      child: SingleChildScrollView(
                        child: MasMarkdown(
                          data: row.answer?.isNotEmpty == true
                              ? row.answer!
                              : '(jawaban tidak tercatat)',
                          dense: true,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(fmtWaktu(row.createdAt),
                          style: TextStyle(fontSize: 11, color: m.ink500)),
                      if (row.username != null && row.username!.isNotEmpty)
                        _Chip(row.role != null && row.role!.isNotEmpty
                            ? '${row.username} · ${row.role}'
                            : row.username!),
                      if (row.tools != null && row.tools!.isNotEmpty)
                        Text('🔧 ${row.tools}',
                            style: TextStyle(fontSize: 10.5, color: m.ink400)),
                    ],
                  ),

                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: MasButton(
                      label: row.resolved ? 'Buka lagi' : '✓ Sudah ditangani',
                      primary: !row.resolved,
                      height: 34,
                      loading: _busyId == row.id,
                      onTap: _busyId != null ? null : () => _toggleResolved(row),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Format timestamp ISO → waktu lokal ringkas. Dipakai layar-layar admin AI.
/// (Kolom `created_at` di tabel AI dikirim polos tanpa zona, jadi diperlakukan
/// sebagai UTC — sama seperti `fmtDate` di order_ui.)
String fmtWaktu(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final berzona =
      RegExp(r'[zZ]$').hasMatch(iso) || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(iso);
  final d = DateTime.tryParse(berzona ? iso : '${iso}Z');
  if (d == null) return iso;
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}.${two(l.minute)}';
}

// ══════════════════════════════════════════════════════════════════════
// 2. Observabilitas AI (chat log)
// ══════════════════════════════════════════════════════════════════════

class ChatLogScreen extends StatefulWidget {
  const ChatLogScreen({super.key});

  @override
  State<ChatLogScreen> createState() => _ChatLogScreenState();
}

class _ChatLogScreenState extends State<ChatLogScreen> {
  ChatLogSummary? _ringkasan;
  List<ChatLogRow> _log = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  /// Saring per akun — ketuk nama di daftar penanya untuk menyorot satu user.
  String _filterUser = '';

  /// Baris log yang sedang dibuka (menampilkan jawaban AI). null = tak ada.
  int? _openId;

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
      final r = await ApiService.chatLog(limit: 200);
      if (!mounted) return;
      setState(() {
        _ringkasan = r.ringkasan;
        _log = r.log;
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

  /// [beforeDays] null = hapus SEMUA. Selalu konfirmasi dulu: penghapusan log
  /// tidak bisa dibatalkan.
  Future<void> _hapus(int? beforeDays) async {
    final ok = await _confirm(
      context,
      beforeDays == null ? 'Hapus semua log' : 'Hapus log lama',
      beforeDays == null
          ? 'Hapus SELURUH log observabilitas AI? Tindakan ini tidak bisa dibatalkan.'
          : 'Hapus log yang lebih tua dari $beforeDays hari?',
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final n = await ApiService.deleteChatLog(beforeDays: beforeDays);
      if (!mounted) return;
      setState(() {
        _notice = '${thousands(n)} baris log dihapus.';
        _busy = false;
      });
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  /// Menu hapus: pilih rentang, lalu konfirmasi.
  Future<void> _menuHapus() async {
    final pilihan = await showModalBottomSheet<int?>(
      context: context,
      backgroundColor: context.mas.paper,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(MasRadii.sheet)),
      ),
      builder: (ctx) {
        final m = ctx.mas;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text('Hapus log observabilitas',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: m.ink900)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'Log yang lebih tua dari 30 hari juga terhapus otomatis '
                  '(retensi harian di server).',
                  style: TextStyle(fontSize: 12, color: m.ink500, height: 1.45),
                ),
              ),
              ListTile(
                leading: Icon(Icons.cleaning_services_rounded,
                    size: 20, color: m.ink600),
                title: Text('Lebih tua dari 30 hari',
                    style: TextStyle(fontSize: 13.5, color: m.ink900)),
                onTap: () => Navigator.pop(ctx, 30),
              ),
              ListTile(
                leading: Icon(Icons.cleaning_services_rounded,
                    size: 20, color: m.ink600),
                title: Text('Lebih tua dari 7 hari',
                    style: TextStyle(fontSize: 13.5, color: m.ink900)),
                onTap: () => Navigator.pop(ctx, 7),
              ),
              ListTile(
                leading:
                    Icon(Icons.delete_outline_rounded, size: 20, color: m.danger600),
                title: Text('Hapus semua log',
                    style: TextStyle(fontSize: 13.5, color: m.danger600)),
                // -1 sebagai penanda "semua" — dibedakan dari null (batal).
                onTap: () => Navigator.pop(ctx, -1),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (pilihan == null || !mounted) return;
    await _hapus(pilihan < 0 ? null : pilihan);
  }

  /// Siapa yang paling sering bertanya (dari baris yang dimuat).
  List<({String user, int count})> get _perUser {
    final n = <String, int>{};
    for (final r in _log) {
      final u = r.username.isNotEmpty ? r.username : '(tanpa nama)';
      n[u] = (n[u] ?? 0) + 1;
    }
    final out = n.entries.map((e) => (user: e.key, count: e.value)).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final s = _ringkasan;
    final rows =
        _filterUser.isEmpty ? _log : _log.where((r) => r.username == _filterUser).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(children: [
            Expanded(
              child: Text(
                'Metrik tiap giliran chat asisten — pantau latensi, seberapa '
                'sering guard anti-halusinasi menyala, dan tool mana yang paling '
                'dipakai.',
                style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
              ),
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, size: 20, color: m.ink600),
              tooltip: 'Muat ulang',
              onPressed: _loading || _busy ? null : _load,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  size: 20, color: m.danger600),
              tooltip: 'Hapus log',
              onPressed: _loading || _busy ? null : _menuHapus,
            ),
          ]),
          const SizedBox(height: 10),

          if (_notice != null) ...[
            _Alert(_notice!, tone: MasPillTone.brand),
            const SizedBox(height: 12),
          ],
          if (_error != null) ...[
            _Alert(_error!),
            const SizedBox(height: 12),
          ],

          if (_loading)
            Column(children: [
              for (int i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 80),
                ),
            ])
          else if (s == null || s.total == 0)
            const MasEmpty(
              icon: Icons.monitor_heart_outlined,
              title: 'Belum ada log',
              subtitle:
                  'Log terisi otomatis setiap user memakai Asisten AI. Coba beberapa '
                  'percakapan lalu muat ulang halaman ini.',
            )
          else ...[
            _statRow([
              _Stat(label: 'Giliran tercatat', value: thousands(s.total)),
              _Stat(
                label: 'Latensi p50',
                value: '${(s.latensiP50 / 1000).toStringAsFixed(1)}s',
                hint: 'p90 ${(s.latensiP90 / 1000).toStringAsFixed(1)}s · '
                    'maks ${(s.latensiMaks / 1000).toStringAsFixed(1)}s',
              ),
            ]),
            const SizedBox(height: 8),
            _statRow([
              _Stat(
                label: 'Guard menyala',
                value: '${s.guardRasioPersen}%',
                hint: '${thousands(s.guardMenyala)} giliran',
                color: s.guardMenyala > 0 ? m.warn600 : null,
              ),
              _Stat(
                label: 'Tool gagal',
                value: '${s.toolGagalRasioPersen}%',
                hint: '${thousands(s.toolGagal)} giliran',
                color: s.toolGagal > 0 ? m.danger600 : null,
              ),
            ]),
            const SizedBox(height: 8),
            // Biaya DeepSeek per pesan: rata-rata token masuk+keluar per giliran.
            _statRow([
              _Stat(
                label: 'Token / pesan',
                value: s.tokenGiliranTerukur > 0
                    ? _fmtTok(s.tokenRata2In + s.tokenRata2Out)
                    : '—',
                hint: s.tokenGiliranTerukur > 0
                    ? 'in ${_fmtTok(s.tokenRata2In)} · out ${_fmtTok(s.tokenRata2Out)} · '
                        'cache ${s.tokenCacheHitPersen}%'
                    : 'belum ada data (migrasi 021)',
              ),
            ]),
            const SizedBox(height: 14),

            if (s.toolTersering.isNotEmpty) ...[
              _toolTersering(m, s),
              const SizedBox(height: 12),
            ],

            if (s.toolGagalTersering.isNotEmpty) ...[
              MasSectionCard(
                title: 'Tool paling sering gagal',
                children: [
                  for (final t in s.toolGagalTersering)
                    MasKeyValue(
                      label: t.tool,
                      // ✕ = lookup jujur nihil (data memang tak ada), ⚠ =
                      // error/infra, ⛔ = ditolak rem anti-loop (belum dicek).
                      // Membedakannya penting: yang pertama wajar, yang kedua
                      // perlu ditindak, yang ketiga adalah plafon KITA sendiri.
                      value: '${thousands(t.count)} (${t.pct}%'
                          '${t.nf > 0 || t.err > 0 || t.brake > 0 ? " · ${t.nf}✕/${t.err}⚠"
                              "${t.brake > 0 ? "/${t.brake}⛔" : ""}" : ""})',
                      mono: true,
                    ),
                  if (s.toolGagalRincian case final r?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '✕ tak ketemu: ${thousands(r.nf)} · ⚠ error: ${thousands(r.err)}'
                        '${r.brake > 0 ? " · ⛔ ditolak rem: ${thousands(r.brake)}" : ""}'
                        '${r.legacy > 0 ? " · lama: ${thousands(r.legacy)}" : ""}',
                        style: TextStyle(fontSize: 11, color: m.ink500),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Sebab guard — memisahkan dugaan KARANGAN (pn/angka) dari
            // SUBSTITUSI (subst) dan guard wajib-tool (dtc/epc/excel). Dulu
            // semuanya cuma satu angka, sehingga guard paling berharga (dtc)
            // tak terlihat sama sekali. Paritas dgn web (migrasi 026).
            if (s.guardSebab.isNotEmpty) ...[
              MasSectionCard(
                title: 'Sebab guard menyala',
                children: [
                  for (final e in (s.guardSebab.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value))))
                    MasKeyValue(
                        label: e.key, value: thousands(e.value), mono: true),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'pn/angka = dugaan karangan · subst = PN per-model '
                      'menyalip EPC · dtc/epc/excel/ajar = jawaban tanpa tool '
                      'wajib · rem = plafon panggilan tool tercapai (ada item '
                      'yang belum dicek)',
                      style: TextStyle(fontSize: 11, color: m.ink500, height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (s.outcome.isNotEmpty) ...[
              MasSectionCard(
                title: 'Outcome jawaban',
                children: [
                  for (final e in s.outcome.entries)
                    MasKeyValue(
                        label: e.key, value: thousands(e.value), mono: true),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (_perUser.isNotEmpty) ...[
              _penanya(m),
              const SizedBox(height: 12),
            ],

            MasSectionCard(
              title: _filterUser.isEmpty
                  ? 'Log giliran (${thousands(rows.length)})'
                  : 'Log $_filterUser (${thousands(rows.length)})',
              trailing: _filterUser.isEmpty
                  ? null
                  : GestureDetector(
                      onTap: () => setState(() => _filterUser = ''),
                      child: Text('Tampilkan semua',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: m.brand700)),
                    ),
              children: [
                for (final r in rows) _logRow(m, r),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _toolTersering(MasColors m, ChatLogSummary s) {
    // Bar proporsional ke tool yang paling sering — bukan ke total, supaya
    // perbedaan antar tool tetap terbaca meski totalnya kecil.
    final maks = s.toolTersering
        .map((t) => t.count)
        .fold<int>(1, (a, b) => b > a ? b : a);

    return MasSectionCard(
      title: 'Tool tersering',
      children: [
        for (final t in s.toolTersering)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(t.tool,
                        style: masMono(size: 12, color: m.ink800)),
                  ),
                  Text(thousands(t.count),
                      style: TextStyle(fontSize: 12, color: m.ink500)),
                ]),
                const SizedBox(height: 5),
                MasBar(value: t.count / maks),
              ],
            ),
          ),
      ],
    );
  }

  Widget _penanya(MasColors m) => MasSectionCard(
        title: 'Penanya tersering',
        children: [
          for (final u in _perUser.take(8))
            InkWell(
              // Ketuk = saring tabel di bawah ke akun ini; ketuk lagi = semua.
              onTap: () => setState(
                  () => _filterUser = _filterUser == u.user ? '' : u.user),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _filterUser == u.user ? m.brand50 : null,
                  border: Border(bottom: BorderSide(color: m.ink100)),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(u.user,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _filterUser == u.user
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color:
                              _filterUser == u.user ? m.brand700 : m.ink800,
                        )),
                  ),
                  Text(thousands(u.count),
                      style: TextStyle(fontSize: 12, color: m.ink500)),
                ]),
              ),
            ),
        ],
      );

  Widget _logRow(MasColors m, ChatLogRow r) {
    final open = _openId == r.id;
    final hasTok = r.tokensIn > 0 || r.tokensOut > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() => _openId = open ? null : r.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: m.ink100)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    r.question.isNotEmpty ? r.question : '—',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: m.ink900, height: 1.4),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${(r.latencyMs / 1000).toStringAsFixed(1)}s',
                    style: masMono(
                        size: 12,
                        weight: FontWeight.w600,
                        // Latensi >20s terasa lambat bagi user — tandai.
                        color: r.latencyMs > 20000 ? m.warn600 : m.ink700)),
                const SizedBox(width: 6),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 18, color: m.ink400),
              ]),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(fmtWaktu(r.createdAt),
                      style: TextStyle(fontSize: 10.5, color: m.ink400)),
                  Text(
                    r.username.isNotEmpty
                        ? (r.role.isNotEmpty
                            ? '${r.username} · ${r.role}'
                            : r.username)
                        : '—',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, color: m.ink600),
                  ),
                  if (r.toolsCount > 0)
                    Text('🔧 ${r.tools.isNotEmpty ? r.tools : '${r.toolsCount} tool'}',
                        style: TextStyle(fontSize: 10.5, color: m.ink500)),
                  Text('${r.rounds} ronde',
                      style: TextStyle(fontSize: 10.5, color: m.ink400)),
                  if (hasTok)
                    Text('🪙 ${_fmtTok(r.tokensIn)}/${_fmtTok(r.tokensOut)} tok',
                        style: TextStyle(fontSize: 10.5, color: m.ink500)),
                  if (r.outcome.isNotEmpty) _Chip(r.outcome),
                  if (r.guardHit) const _Chip('guard', tone: MasPillTone.warn),
                  if (r.toolFailed)
                    const _Chip('tool gagal', tone: MasPillTone.danger),
                ],
              ),
            ],
          ),
        ),
      ),
      if (open) _logExpanded(m, r),
    ]);
  }

  /// Panel jawaban AI (dibuka saat baris diketuk) — untuk memantau apa yang
  /// sebenarnya dijawab asisten. Setara panel expand di web.
  Widget _logExpanded(MasColors m, ChatLogRow r) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: m.ink50,
          border: Border(bottom: BorderSide(color: m.ink100)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pertanyaan',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: m.ink500)),
          const SizedBox(height: 3),
          SelectableText(r.question.isNotEmpty ? r.question : '—',
              style: TextStyle(fontSize: 12.5, color: m.ink700, height: 1.45)),
          if (r.toolsFailed.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: 'Tool gagal: ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: m.danger600)),
              // Suffix `:nf`/`:err` dari server dieja agar terbaca admin.
              TextSpan(
                  text: r.toolsFailed
                      .replaceAll(':nf', ' (tak ketemu)')
                      .replaceAll(':err', ' (error)'),
                  style: masMono(size: 11.5, color: m.danger600)),
            ])),
          ],
          const SizedBox(height: 10),
          Text('Jawaban AI',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: m.ink500)),
          const SizedBox(height: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: SelectableText(
                r.reply.isNotEmpty
                    ? r.reply
                    : '— (jawaban tak tersimpan untuk giliran ini — hanya giliran '
                        'setelah fitur ini aktif yang menyimpan teks jawaban)',
                style: TextStyle(fontSize: 12.5, color: m.ink800, height: 1.5),
              ),
            ),
          ),
        ]),
      );
}

/// Angka token ringkas: 1234 → "1,2rb", 1234567 → "1,2jt" (sama dengan web).
String _fmtTok(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')}jt';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1).replaceAll('.', ',')}rb';
  return '$n';
}

// ══════════════════════════════════════════════════════════════════════
// 3. Pencarian Nihil
// ══════════════════════════════════════════════════════════════════════

class MissesScreen extends StatefulWidget {
  const MissesScreen({super.key});

  @override
  State<MissesScreen> createState() => _MissesScreenState();
}

class _MissesScreenState extends State<MissesScreen> {
  List<SearchMiss> _misses = [];
  int _total = 0;
  bool _loading = true;
  String? _error;

  /// Query yang sedang di-resolve (tombolnya dikunci).
  String? _busyQuery;

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
      final r = await ApiService.searchMisses();
      if (!mounted) return;
      setState(() {
        _misses = r.misses;
        _total = r.total;
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

  Future<void> _resolve(SearchMiss miss) async {
    setState(() {
      _busyQuery = miss.query;
      _error = null;
    });
    try {
      await ApiService.resolveSearchMiss(miss.query);
      if (!mounted) return;
      setState(() {
        _misses = _misses.where((x) => x.query != miss.query).toList();
        _total = _total > 0 ? _total - 1 : 0;
        _busyQuery = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busyQuery = null;
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(children: [
            Expanded(
              child: Text(
                'Istilah yang dicari user (di Cari Part & Asisten AI) tapi TIDAK '
                'menemukan apa pun. Daftar ini adalah umpan untuk Kamus Sinonim: '
                'petakan istilah lapangan di sini ke kata kunci katalog, dan '
                'pencarian berikutnya akan berhasil.',
                style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
              ),
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, size: 20, color: m.ink600),
              tooltip: 'Muat ulang',
              onPressed: _loading ? null : _load,
            ),
          ]),
          const SizedBox(height: 10),

          Row(children: [
            Expanded(
              child: Text('$_total istilah unik belum ketemu',
                  style: TextStyle(fontSize: 12.5, color: m.ink600)),
            ),
            MasButton(
              label: 'Kamus Sinonim',
              icon: Icons.menu_book_outlined,
              primary: false,
              height: 34,
              onTap: () => nav.go(MasScreen.sinonim),
            ),
          ]),
          const SizedBox(height: 12),

          if (_error != null) ...[
            _Alert(_error!),
            const SizedBox(height: 12),
          ],

          if (_loading)
            Column(children: [
              for (int i = 0; i < 4; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 74),
                ),
            ])
          else if (_misses.isEmpty)
            const MasEmpty(
              icon: Icons.search_off_rounded,
              title: 'Tidak ada pencarian nihil',
              subtitle:
                  'Semua query user menemukan hasil, atau sudah ditandai selesai. 🎉',
            )
          else
            MasSectionCard(
              title: 'Query 0 hasil (terbanyak dulu)',
              children: [
                for (final miss in _misses) _row(m, miss),
              ],
            ),
        ],
      ),
    );
  }

  Widget _row(MasColors m, SearchMiss miss) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: m.ink100)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(miss.query,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: m.ink900)),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Frekuensi = seberapa mendesak istilah ini dipetakan.
                    _Chip('${miss.count}×', tone: MasPillTone.info),
                    for (final s in miss.sources) _Chip(s),
                    for (final mode in miss.modes) _Chip(mode),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(mainAxisSize: MainAxisSize.min, children: [
            // Jalur utama layar ini: istilah nihil → petakan ke kata kunci
            // katalog. Membawa querynya sekalian agar tak perlu diketik ulang.
            MasButton(
              label: '+ Sinonim',
              height: 32,
              onTap: _busyQuery != null
                  ? null
                  : () => AppNav.of(context).go(MasScreen.sinonim,
                      part: {'trigger': miss.query}),
            ),
            const SizedBox(height: 6),
            MasButton(
              label: 'Selesai',
              primary: false,
              height: 32,
              loading: _busyQuery == miss.query,
              onTap: _busyQuery != null ? null : () => _resolve(miss),
            ),
          ]),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════
// 4. Kamus Sinonim
// ══════════════════════════════════════════════════════════════════════

class SinonimScreen extends StatefulWidget {
  /// Argumen navigasi. `trigger` = istilah yang langsung diisikan ke form
  /// tambah — dipakai tombol "+ Sinonim" di layar Pencarian Nihil, supaya
  /// admin tak perlu mengetik ulang istilah yang barusan dilihatnya.
  final Map<String, dynamic> args;
  const SinonimScreen({super.key, this.args = const {}});

  @override
  State<SinonimScreen> createState() => _SinonimScreenState();
}

class _SinonimScreenState extends State<SinonimScreen> {
  int _tab = 0; // 0 = Kamus, 1 = Usulan

  // ── Kamus ──
  List<SinonimEntry> _entries = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _notice;

  final _filterCtl = TextEditingController();
  final _grupCtl = TextEditingController();
  final _trigCtl = TextEditingController();
  final _kwCtl = TextEditingController();

  /// null = mode tambah; selain itu = indeks entri yang sedang diedit.
  int? _editIdx;

  // ── Usulan ──
  List<SinonimUsulan> _usulan = [];
  bool _generating = false;

  /// Id usulan yang sedang disetujui/ditolak.
  String? _busyId;

  @override
  void initState() {
    super.initState();
    final trigger = '${widget.args['trigger'] ?? ''}'.trim();
    if (trigger.isNotEmpty) {
      _trigCtl.text = trigger;
      _tab = 0; // form tambah ada di tab Kamus — pastikan yang terbuka itu
      _notice = 'Istilah "$trigger" diisikan dari Pencarian Nihil. Lengkapi '
          'kata kunci katalognya, lalu Simpan.';
    }
    _load();
  }

  @override
  void dispose() {
    _filterCtl.dispose();
    _grupCtl.dispose();
    _trigCtl.dispose();
    _kwCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await ApiService.sinonim();
      final usulan = await ApiService.sinonimUsulan();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _usulan = usulan;
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

  void _resetForm() {
    _editIdx = null;
    _grupCtl.clear();
    _trigCtl.clear();
    _kwCtl.clear();
  }

  void _startEdit(int idx) {
    final e = _entries[idx];
    setState(() {
      _editIdx = idx;
      _grupCtl.text = e.grup;
      _trigCtl.text = e.triggers.join(', ');
      _kwCtl.text = e.keywords.join(', ');
      _notice = null;
    });
  }

  Future<void> _save() async {
    final entry = SinonimEntry(
      grup: _grupCtl.text.trim(),
      triggers: _splitTerms(_trigCtl.text),
      keywords: _splitTerms(_kwCtl.text),
    );
    if (entry.triggers.isEmpty || entry.keywords.isEmpty) {
      setState(() => _error =
          'Isi minimal satu istilah lapangan dan satu kata kunci katalog.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      if (_editIdx == null) {
        await ApiService.addSinonim(entry);
      } else {
        await ApiService.updateSinonim(_editIdx!, entry);
      }
      if (!mounted) return;
      setState(() {
        _notice = 'Tersimpan: "${entry.triggers.first}" → '
            '${entry.keywords.join(', ')}. Asisten AI langsung memakai kamus '
            'baru — tanpa restart.';
        _saving = false;
        _resetForm();
      });
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  Future<void> _delete(int idx) async {
    final e = _entries[idx];
    final ok = await _confirm(
      context,
      'Hapus entri sinonim',
      'Hapus "${e.triggers.join(', ')}" → ${e.keywords.join(', ')}?',
    );
    if (!ok || !mounted) return;

    setState(() => _error = null);
    try {
      await ApiService.deleteSinonim(idx);
      if (!mounted) return;
      if (_editIdx == idx) setState(_resetForm);
      await _load();
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message);
    }
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
      _notice = null;
    });
    try {
      final r = await ApiService.generateSinonimUsulan(limit: 10);
      if (!mounted) return;
      setState(() {
        _generating = false;
        if (r.error != null && r.error!.isNotEmpty) {
          _error = r.error;
        } else if (r.dibuat == 0) {
          _notice = r.catatan?.isNotEmpty == true
              ? r.catatan
              : 'Tidak ada usulan baru — AI tidak menemukan istilah yang bisa '
                  'dipetakan ke katalog.';
        } else {
          _notice = 'AI membuat ${r.dibuat} usulan baru — tinjau lalu '
              'Setujui/Tolak di bawah.';
        }
        _tab = 1;
      });
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _generating = false;
      });
    }
  }

  Future<void> _decide(SinonimUsulan u, bool setuju) async {
    setState(() {
      _busyId = u.id;
      _error = null;
      _notice = null;
    });
    try {
      if (setuju) {
        await ApiService.approveSinonimUsulan(u.id);
      } else {
        await ApiService.rejectSinonimUsulan(u.id);
      }
      if (!mounted) return;
      setState(() {
        _usulan = _usulan.where((x) => x.id != u.id).toList();
        _busyId = null;
        _notice = setuju
            ? 'Usulan disetujui & masuk kamus — asisten langsung memakainya.'
            : 'Usulan ditolak.';
      });
      // Approve menambah entri kamus, jadi kamusnya perlu disegarkan.
      if (setuju) await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busyId = null;
      });
    }
  }

  /// Entri yang lolos saringan, tetap membawa indeks aslinya — API CRUD
  /// memakai indeks di kamus utuh, bukan indeks hasil saring.
  List<({SinonimEntry entry, int idx})> get _view {
    final q = _filterCtl.text.trim().toLowerCase();
    final all = [
      for (int i = 0; i < _entries.length; i++) (entry: _entries[i], idx: i),
    ];
    if (q.isEmpty) return all;
    return all.where((e) {
      final x = e.entry;
      return x.grup.toLowerCase().contains(q) ||
          x.triggers.any((t) => t.toLowerCase().contains(q)) ||
          x.keywords.any((k) => k.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Istilah bengkel/Indonesia di sebelah kiri membuat Asisten AI & Cari '
            'Part otomatis mencari kata kunci katalog (Inggris) di sebelah kanan. '
            'Contoh: “tapak shoe” → “track plate”.',
            style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
          ),
          const SizedBox(height: 10),
          const _Alert(
            'Perubahan kamus LANGSUNG dipakai Asisten AI — server membaca ulang '
            'berkas kamus begitu berubah, tanpa perlu restart.',
            tone: MasPillTone.info,
          ),
          const SizedBox(height: 14),

          Row(children: [
            Expanded(
              child: MasSegmentTabs(
                tabs: [
                  'Kamus (${_entries.length})',
                  'Usulan AI (${_usulan.length})',
                ],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, size: 20, color: m.ink600),
              tooltip: 'Muat ulang',
              onPressed: _loading ? null : _load,
            ),
          ]),
          const SizedBox(height: 12),

          if (_error != null) ...[
            _Alert(_error!),
            const SizedBox(height: 12),
          ],
          if (_notice != null) ...[
            _Alert(_notice!, tone: MasPillTone.brand),
            const SizedBox(height: 12),
          ],

          if (_loading)
            Column(children: [
              for (int i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 90),
                ),
            ])
          else if (_tab == 0)
            ..._kamus(m)
          else
            ..._usulanTab(m),
        ],
      ),
    );
  }

  // ── Tab: Kamus ──────────────────────────────────────────────────────

  List<Widget> _kamus(MasColors m) {
    final view = _view;

    return [
      MasSectionCard(
        title: _editIdx == null
            ? '➕ Tambah sinonim'
            : '✏️ Edit entri #${_editIdx! + 1}',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(m, 'Istilah lapangan (Indonesia/slang) — pisah koma'),
                const SizedBox(height: 6),
                MasInput(
                  controller: _trigCtl,
                  hint: 'tapak shoe, tapak sepatu',
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _label(m, 'Kata kunci katalog (Inggris) — pisah koma'),
                const SizedBox(height: 6),
                MasInput(
                  controller: _kwCtl,
                  hint: 'track plate, track shoe',
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _label(m, 'Grup (opsional)'),
                const SizedBox(height: 6),
                MasInput(controller: _grupCtl, hint: 'undercarriage'),
                const SizedBox(height: 14),
                Row(children: [
                  if (_editIdx != null) ...[
                    Expanded(
                      child: MasButton(
                        label: 'Batal edit',
                        primary: false,
                        expand: true,
                        onTap: _saving ? null : () => setState(_resetForm),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: MasButton(
                      label: _editIdx == null
                          ? 'Simpan sinonim'
                          : 'Simpan perubahan',
                      expand: true,
                      loading: _saving,
                      onTap: _saving ? null : _save,
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),

      MasInput(
        controller: _filterCtl,
        hint: 'Saring: istilah, kata kunci, atau grup…',
        prefix: Icon(Icons.search_rounded, size: 17, color: m.ink400),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 6),
      Text('${view.length} dari ${_entries.length} entri',
          style: TextStyle(fontSize: 12, color: m.ink500)),
      const SizedBox(height: 10),

      if (view.isEmpty)
        MasEmpty(
          icon: Icons.menu_book_outlined,
          title: _entries.isEmpty ? 'Kamus masih kosong' : 'Tidak ada yang cocok',
          subtitle: _entries.isEmpty
              ? 'Tambah sinonim pertama lewat formulir di atas.'
              : 'Tidak ada entri yang cocok dengan saringan.',
        )
      else
        for (final v in view)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _entryCard(m, v.entry, v.idx),
          ),
    ];
  }

  Widget _label(MasColors m, String text) => Text(text,
      style: TextStyle(
          fontSize: 12.5, fontWeight: FontWeight.w600, color: m.ink700));

  Widget _entryCard(MasColors m, SinonimEntry e, int idx) => MasCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _Chip(e.grup.isNotEmpty ? e.grup : 'umum'),
              const Spacer(),
              GestureDetector(
                onTap: () => _startEdit(idx),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.edit_outlined, size: 17, color: m.ink600),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _delete(idx),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.delete_outline_rounded,
                      size: 18, color: m.danger600),
                ),
              ),
            ]),
            const SizedBox(height: 9),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final t in e.triggers) _Chip(t, tone: MasPillTone.brand),
              ],
            ),
            const SizedBox(height: 7),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.arrow_forward_rounded, size: 14, color: m.ink400),
              const SizedBox(width: 6),
              Expanded(
                child: Text(e.keywords.join(', '),
                    style: TextStyle(fontSize: 12.5, color: m.ink700, height: 1.4)),
              ),
            ]),
          ],
        ),
      );

  // ── Tab: Usulan AI ──────────────────────────────────────────────────

  List<Widget> _usulanTab(MasColors m) => [
        Text(
          'LLM membaca daftar Pencarian Nihil lalu memetakan istilah lapangan '
          'yang gagal ke kata kunci katalog. Setiap kata kunci divalidasi ke '
          'katalog nyata di server — yang tidak ditemukan dicoret dan dibuang.',
          style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
        ),
        const SizedBox(height: 10),
        MasButton(
          label: _generating ? 'AI sedang menyusun…' : '🤖 Usulkan sinonim (AI)',
          icon: Icons.auto_awesome_rounded,
          expand: true,
          loading: _generating,
          onTap: _generating ? null : _generate,
        ),
        const SizedBox(height: 14),

        if (_usulan.isEmpty)
          const MasEmpty(
            icon: Icons.auto_awesome_outlined,
            title: 'Belum ada usulan',
            subtitle:
                'Tekan "Usulkan sinonim (AI)" untuk memetakan pencarian nihil '
                'menjadi kandidat entri kamus.',
          )
        else
          for (final u in _usulan)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _usulanCard(m, u),
            ),
      ];

  Widget _usulanCard(MasColors m, SinonimUsulan u) {
    final persen = (u.confidence * 100).round();

    return MasCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                u.triggers.isNotEmpty ? u.triggers.join(', ') : u.query,
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: m.ink900),
              ),
            ),
            const SizedBox(width: 8),
            // Keyakinan rendah bukan berarti salah — tapi layak dibaca ulang.
            _Chip('$persen%',
                tone: persen >= 70 ? MasPillTone.brand : MasPillTone.warn),
          ]),

          if (u.countMiss > 0) ...[
            const SizedBox(height: 4),
            Text('Dicari ${u.countMiss}× tanpa hasil',
                style: TextStyle(fontSize: 11.5, color: m.ink500)),
          ],

          if (u.alasan != null && u.alasan!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(u.alasan!,
                style: TextStyle(fontSize: 12, color: m.ink600, height: 1.45)),
          ],

          const SizedBox(height: 9),
          Text('Kata kunci katalog (tervalidasi)',
              style: TextStyle(fontSize: 11, color: m.ink500)),
          const SizedBox(height: 5),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final k in u.keywords) _Chip(k, tone: MasPillTone.brand),
              for (final k in u.keywordsDibuang) _Chip(k, struck: true),
            ],
          ),

          if (u.grup.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Grup: ${u.grup}',
                style: TextStyle(fontSize: 11.5, color: m.ink500)),
          ],

          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: MasButton(
                label: '✓ Setujui',
                expand: true,
                height: 36,
                loading: _busyId == u.id,
                onTap: _busyId != null ? null : () => _decide(u, true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MasButton(
                label: '✕ Tolak',
                primary: false,
                expand: true,
                height: 36,
                onTap: _busyId != null ? null : () => _decide(u, false),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 5. Rute Maksud (frasa user → TOOL)
// ══════════════════════════════════════════════════════════════════════

/// Saudara Kamus Sinonim, tapi mengendalikan PEMILIHAN ALAT.
///
/// Kamus sinonim menjawab "kata apa yang dicari di katalog"; rute menjawab
/// "alat mana yang dipakai". Sebelum store ini ada (2026-08-01), aturan seperti
/// "kalau user minta gambar teknis, itu maksudnya exploded view" hanya bisa
/// ditulis di berkas prompt server — artinya butuh deploy tiap kali.
class MaksudScreen extends StatefulWidget {
  const MaksudScreen({super.key});

  @override
  State<MaksudScreen> createState() => _MaksudScreenState();
}

class _MaksudScreenState extends State<MaksudScreen> {
  List<MaksudEntry> _entries = [];

  /// Nama tool yang SAH — datang dari server (sumber kebenaran sama dengan yang
  /// ditawarkan ke model), supaya rute tak pernah menunjuk tool yang tak ada.
  List<String> _tools = [];
  int _maks = 60;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _notice;

  final _filterCtl = TextEditingController();
  final _frasaCtl = TextEditingController();
  final _catatanCtl = TextEditingController();
  String _tool = '';

  /// null = mode tambah; selain itu = indeks rute yang sedang diedit.
  int? _editIdx;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _filterCtl.dispose();
    _frasaCtl.dispose();
    _catatanCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ApiService.maksud();
      if (!mounted) return;
      setState(() {
        _entries = r.entries;
        _tools = r.tools;
        _maks = r.maks;
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

  void _resetForm() {
    _editIdx = null;
    _frasaCtl.clear();
    _catatanCtl.clear();
    _tool = '';
  }

  void _startEdit(int idx) {
    final e = _entries[idx];
    setState(() {
      _editIdx = idx;
      _frasaCtl.text = e.frasa.join(', ');
      _catatanCtl.text = e.catatan;
      _tool = e.tool;
      _notice = null;
    });
  }

  /// Pemilih alat: daftarnya panjang, jadi ada kolom saring di atasnya.
  Future<void> _pilihTool() async {
    final cariCtl = TextEditingController();
    final pilih = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.mas.paper,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(MasRadii.sheet)),
      ),
      builder: (ctx) {
        final m = ctx.mas;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final q = cariCtl.text.trim().toLowerCase();
            final view = q.isEmpty
                ? _tools
                : _tools.where((t) => t.toLowerCase().contains(q)).toList();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.7,
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('Pilih alat tujuan',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: m.ink900)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: MasInput(
                        controller: cariCtl,
                        hint: 'Cari nama alat…',
                        prefix: Icon(Icons.search_rounded,
                            size: 17, color: m.ink400),
                        onChanged: (_) => setSheet(() {}),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: view.length,
                        itemBuilder: (ctx, i) => ListTile(
                          dense: true,
                          title: Text(view[i],
                              style: TextStyle(fontSize: 13, color: m.ink900)),
                          onTap: () => Navigator.pop(ctx, view[i]),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            );
          },
        );
      },
    );
    cariCtl.dispose();
    if (pilih != null && mounted) setState(() => _tool = pilih);
  }

  Future<void> _save() async {
    final entry = MaksudEntry(
      frasa: _splitTerms(_frasaCtl.text),
      tool: _tool.trim(),
      catatan: _catatanCtl.text.trim(),
    );
    if (entry.frasa.isEmpty || entry.tool.isEmpty) {
      setState(
          () => _error = 'Isi minimal satu frasa dan pilih alat tujuannya.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      if (_editIdx == null) {
        await ApiService.addMaksud(entry);
      } else {
        await ApiService.updateMaksud(_editIdx!, entry);
      }
      if (!mounted) return;
      setState(() {
        _notice = 'Tersimpan: "${entry.frasa.first}" → ${entry.tool}. '
            'Asisten AI langsung mematuhinya — tanpa restart.';
        _saving = false;
        _resetForm();
      });
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  Future<void> _delete(int idx) async {
    final e = _entries[idx];
    final ok = await _confirm(
      context,
      'Hapus rute maksud',
      'Hapus "${e.frasa.join(', ')}" → ${e.tool}?',
    );
    if (!ok || !mounted) return;

    setState(() => _error = null);
    try {
      await ApiService.deleteMaksud(idx);
      if (!mounted) return;
      if (_editIdx == idx) setState(_resetForm);
      await _load();
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message);
    }
  }

  /// Rute yang lolos saringan, tetap membawa indeks aslinya — API CRUD memakai
  /// indeks di store utuh, bukan indeks hasil saring.
  List<({MaksudEntry entry, int idx})> get _view {
    final q = _filterCtl.text.trim().toLowerCase();
    final all = [
      for (int i = 0; i < _entries.length; i++) (entry: _entries[i], idx: i),
    ];
    if (q.isEmpty) return all;
    return all.where((e) {
      final x = e.entry;
      return x.tool.toLowerCase().contains(q) ||
          x.catatan.toLowerCase().contains(q) ||
          x.frasa.any((f) => f.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final view = _view;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Kalau di tempat Anda sebuah istilah punya arti khusus, daftarkan di '
            'sini supaya Asisten AI langsung memakai ALAT yang benar. Contoh: '
            '“gambar teknis” → gambar_exploded. Bedanya dengan Kamus Sinonim: '
            'kamus mengubah kata yang DICARI, rute mengubah alat yang DIPAKAI.',
            style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
          ),
          const SizedBox(height: 10),
          const _Alert(
            'Hindari kata yang terlalu umum ("gambar", "part", "cek") — rute '
            'seperti itu ikut campur di percakapan lain dan akan ditolak server. '
            'Rute adalah arahan KUAT, bukan paksaan: asisten tetap boleh memilih '
            'lain bila kalimat user jelas berkata lain.',
            tone: MasPillTone.warn,
          ),
          const SizedBox(height: 10),
          const _Alert(
            'Rute juga bisa dibuat langsung dari chat: "ingat ya, kalau saya '
            'minta gambar teknis itu maksudnya exploded view".',
            tone: MasPillTone.info,
          ),
          const SizedBox(height: 14),
          if (_error != null) ...[
            _Alert(_error!),
            const SizedBox(height: 12),
          ],
          if (_notice != null) ...[
            _Alert(_notice!, tone: MasPillTone.brand),
            const SizedBox(height: 12),
          ],
          if (_loading)
            Column(children: [
              for (int i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: MasSkeleton(height: 90),
                ),
            ])
          else ...[
            MasSectionCard(
              title: _editIdx == null
                  ? '➕ Tambah rute'
                  : '✏️ Edit rute #${_editIdx! + 1}',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label(m, 'Frasa yang dipakai user — pisah koma'),
                      const SizedBox(height: 6),
                      MasInput(
                        controller: _frasaCtl,
                        hint: 'gambar teknis, gambar urai',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      _label(m, 'Alat tujuan'),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _tools.isEmpty ? null : _pilihTool,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 13),
                          decoration: BoxDecoration(
                            border: Border.all(color: m.ink200),
                            borderRadius:
                                BorderRadius.circular(MasRadii.input),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                _tool.isEmpty ? '— pilih alat —' : _tool,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: _tool.isEmpty ? m.ink400 : m.ink900),
                              ),
                            ),
                            Icon(Icons.expand_more_rounded,
                                size: 18, color: m.ink500),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _label(m, 'Catatan pembeda (opsional, maks 160 huruf)'),
                      const SizedBox(height: 6),
                      MasInput(
                        controller: _catatanCtl,
                        hint: 'maksudnya exploded view, bukan foto part',
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        if (_editIdx != null) ...[
                          Expanded(
                            child: MasButton(
                              label: 'Batal edit',
                              primary: false,
                              expand: true,
                              onTap:
                                  _saving ? null : () => setState(_resetForm),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: MasButton(
                            label: _editIdx == null
                                ? 'Simpan rute'
                                : 'Simpan perubahan',
                            expand: true,
                            loading: _saving,
                            onTap: _saving ? null : _save,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            MasInput(
              controller: _filterCtl,
              hint: 'Saring: frasa, alat, atau catatan…',
              prefix: Icon(Icons.search_rounded, size: 17, color: m.ink400),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            Text('${view.length} dari ${_entries.length} rute (plafon $_maks)',
                style: TextStyle(fontSize: 12, color: m.ink500)),
            const SizedBox(height: 10),
            if (view.isEmpty)
              MasEmpty(
                icon: Icons.alt_route_rounded,
                title: _entries.isEmpty
                    ? 'Belum ada rute'
                    : 'Tidak ada yang cocok',
                subtitle: _entries.isEmpty
                    ? 'Tambah rute pertama lewat formulir di atas.'
                    : 'Tidak ada rute yang cocok dengan saringan.',
              )
            else
              for (final v in view)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ruteCard(m, v.entry, v.idx),
                ),
          ],
        ],
      ),
    );
  }

  Widget _label(MasColors m, String text) => Text(text,
      style: TextStyle(
          fontSize: 12.5, fontWeight: FontWeight.w600, color: m.ink700));

  Widget _ruteCard(MasColors m, MaksudEntry e, int idx) => MasCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final f in e.frasa) _Chip(f, tone: MasPillTone.brand),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _startEdit(idx),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.edit_outlined, size: 17, color: m.ink600),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _delete(idx),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.delete_outline_rounded,
                      size: 18, color: m.danger600),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.arrow_forward_rounded, size: 14, color: m.ink400),
              const SizedBox(width: 6),
              Expanded(
                child: Text(e.tool,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: m.ink900)),
              ),
            ]),
            if (e.catatan.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(e.catatan,
                  style:
                      TextStyle(fontSize: 12, color: m.ink600, height: 1.45)),
            ],
          ],
        ),
      );
}
