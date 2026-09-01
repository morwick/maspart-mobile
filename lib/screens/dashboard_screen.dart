// lib/screens/dashboard_screen.dart — ringkasan, akses cepat, aktivitas.
import 'package:flutter/material.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';
import '../api_service.dart';
import '../order_ui.dart';
import '../utils.dart';
import '../app/nav.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool? _aiOn;

  // Angka kartu & aktivitas HANYA dari server (persis dashboard web). Null =
  // belum termuat / gagal → tampilkan "—", jangan pernah tebak angka.
  int? _online;
  int? _indexed;
  List<MonitoringActivity>? _activity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Muat ulang semua angka. Dipakai saat layar dibuka DAN saat user menarik
  /// layar ke bawah — dashboard yang gagal memuat sekali dulu menampilkan "—"
  /// selamanya sampai aplikasi dibuka ulang.
  Future<void> _load() async {
    await Future.wait<void>([
      ApiService.aiStatus().then((v) {
        if (mounted) setState(() => _aiOn = v);
      }).catchError((_) {}),
      // monitoring & index-status khusus admin — untuk peran lain endpoint
      // menolak (403) dan kartunya memang tak dirender, jadi cukup diabaikan.
      ApiService.monitoring().then((d) {
        if (!mounted) return;
        setState(() {
          _online = d.onlineCount;
          _activity = d.recentActivity.take(6).toList();
        });
      }).catchError((_) {}),
      ApiService.indexStatus().then((d) {
        if (mounted) setState(() => _indexed = d.totalIndexed);
      }).catchError((_) {}),
    ]);
  }

  String _activityText(MonitoringActivity a) {
    final t = (a.target ?? '').trim();
    return '${a.username} — ${a.action}${t.isEmpty ? '' : ' $t'}';
  }

  static const _days = ['SENIN', 'SELASA', 'RABU', 'KAMIS', 'JUMAT', 'SABTU', 'MINGGU'];
  static const _months = [
    'JANUARI', 'FEBRUARI', 'MARET', 'APRIL', 'MEI', 'JUNI',
    'JULI', 'AGUSTUS', 'SEPTEMBER', 'OKTOBER', 'NOVEMBER', 'DESEMBER'
  ];

  String get _dateLabel {
    final n = DateTime.now();
    return '${_days[n.weekday - 1]}, ${n.day} ${_months[n.month - 1]} ${n.year}';
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 11) return 'Selamat pagi';
    if (h < 15) return 'Selamat siang';
    if (h < 19) return 'Selamat sore';
    return 'Selamat malam';
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final isAdmin = nav.role == 'admin';
    final quickAll = <(String, String, IconData, MasScreen)>[
      ('Cari Part', 'Part number / nama', Icons.search_rounded, MasScreen.search),
      ('Tanya Asisten', 'Stok, harga, BOM per-VIN', Icons.smart_toy_rounded, MasScreen.asisten),
      ('Cari by Foto', 'Kenali part dari gambar', Icons.photo_camera_outlined, MasScreen.foto),
      ('Populasi Unit', 'Armada terdaftar', Icons.local_shipping_outlined, MasScreen.populasi),
      ('Harga', 'Daftar & batch harga', Icons.payments_outlined, MasScreen.harga),
      ('Bandingkan Part', 'Dua part berdampingan', Icons.compare_arrows_rounded, MasScreen.compare),
    ];
    // Hanya menu yang boleh diakses akun ini (persis gating drawer).
    final quick = quickAll.where((q) => nav.accessible.contains(q.$4)).toList();
    final canAsisten = nav.accessible.contains(MasScreen.asisten);

    return RefreshIndicator(
      onRefresh: _load,
      color: m.brand600,
      backgroundColor: m.paper,
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        MasEyebrow(_dateLabel),
        const SizedBox(height: 4),
        Text('$_greeting, ${nav.username} 👷',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: m.ink900, letterSpacing: -0.4)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: MasButton(label: 'Cari Part', icon: Icons.search_rounded, expand: true, onTap: () => nav.go(MasScreen.search))),
          if (canAsisten) ...[
            const SizedBox(width: 8),
            Expanded(child: MasButton(label: 'Tanya Asisten', primary: false, expand: true, onTap: () => nav.go(MasScreen.asisten))),
          ],
        ]),
        const SizedBox(height: 18),
        if (isAdmin) ...[
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _statCard('USER ONLINE', _online == null ? '—' : thousands(_online!), 'aktif ≤ 5 menit', Icons.group_outlined, MasPillTone.brand)),
              const SizedBox(width: 12),
              Expanded(child: _statCard('PART TERINDEKS', _indexed == null ? '—' : thousands(_indexed!), 'galeri cari-by-foto', Icons.grid_view_rounded, MasPillTone.info)),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        MasCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                MasEyebrow('Asisten AI'),
                const SizedBox(height: 6),
                Text(_aiOn == null ? '…' : (_aiOn! ? 'Aktif' : 'Nonaktif'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: m.ink900)),
                const SizedBox(height: 2),
                Text('DeepSeek + tool live', style: TextStyle(fontSize: 11.5, color: m.ink500)),
              ]),
            ),
            _iconChip(Icons.smart_toy_rounded, MasPillTone.brand),
          ]),
        ),
        if (quick.isNotEmpty) ...[
          const SizedBox(height: 14),
          MasSectionCard(
            title: 'Akses cepat',
            children: [_quickGrid(quick, nav)],
          ),
        ],
        if (isAdmin) ...[
          const SizedBox(height: 14),
          MasSectionCard(
            title: 'Aktivitas terbaru',
            children: [
              if (_activity == null)
                const Padding(padding: EdgeInsets.all(16), child: MasSkeleton(height: 20))
              else if (_activity!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Text('Belum ada aktivitas terbaru.',
                      style: TextStyle(fontSize: 12.5, color: m.ink500)),
                )
              else
                for (final a in _activity!)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: m.ink100))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _iconChip(Icons.show_chart_rounded, MasPillTone.info, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(_activityText(a), style: TextStyle(fontSize: 12.5, color: m.ink800, height: 1.45)),
                        if ((a.createdAt ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(fmtDate(a.createdAt), style: TextStyle(fontSize: 11, color: m.ink400)),
                        ],
                      ]),
                    ),
                  ]),
                ),
            ],
          ),
        ],
      ],
      ),
    );
  }

  Widget _statCard(String label, String value, String sub, IconData icon, MasPillTone tone) {
    final m = context.mas;
    return MasCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: MasEyebrow(label)),
          _iconChip(icon, tone),
        ]),
        const SizedBox(height: 8),
        Text(value, style: masMono(size: 26, weight: FontWeight.w700, color: m.ink900, letterSpacing: -0.5)),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(fontSize: 11.5, color: m.ink500)),
      ]),
    );
  }

  Widget _iconChip(IconData icon, MasPillTone tone, {double size = 26}) {
    final m = context.mas;
    final (bg, fg) = tone == MasPillTone.info ? (m.info50, m.info600) : (m.brand50, m.brand700);
    return Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, size: size * 0.54, color: fg),
    );
  }

  Widget _quickGrid(List<(String, String, IconData, MasScreen)> items, AppNav nav) {
    final m = context.mas;
    return Container(
      color: m.ink150,
      child: Column(
        children: [
          for (int r = 0; r < items.length; r += 2)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _quickCell(items[r], nav)),
                Container(width: 1, color: m.ink150),
                Expanded(child: r + 1 < items.length ? _quickCell(items[r + 1], nav) : Container(color: m.paper)),
              ]),
            ),
        ]
            .expand((w) => [w, Container(height: 1, color: m.ink150)])
            .toList()
          ..removeLast(),
      ),
    );
  }

  Widget _quickCell((String, String, IconData, MasScreen) it, AppNav nav) {
    final m = context.mas;
    return Material(
      color: m.paper,
      child: InkWell(
        onTap: () => nav.go(it.$4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(children: [
            Container(
              width: 34, height: 34, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: m.brand50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: m.brand100),
              ),
              child: Icon(it.$3, size: 15, color: m.brand700),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(it.$1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: m.ink900)),
                Text(it.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: m.ink500)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
