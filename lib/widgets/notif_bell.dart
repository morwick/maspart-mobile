// lib/widgets/notif_bell.dart — lonceng notifikasi pembeli (paritas web
// components/NotifBell.tsx, tabel user_notifications migrasi 039).
//
// Dipakai pertama oleh Return: tiap perubahan status → satu notifikasi.
// Diperbarui tiap 60 detik selama aplikasi aktif; membuka panel menandai semua
// dibaca; ketuk item bertautan /retur/{kode} → Detail Return.
// ⛔ Lonceng tak boleh mengganggu layar: semua galat didiamkan, dan bila fitur
// belum aktif di server (aktif=false) lonceng tidak tampil sama sekali.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';

class NotifBell extends StatefulWidget {
  const NotifBell({super.key});

  @override
  State<NotifBell> createState() => _NotifBellState();
}

class _NotifBellState extends State<NotifBell> {
  bool _aktif = false;
  int _n = 0;
  List<Notifikasi> _list = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _muat();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      final st = WidgetsBinding.instance.lifecycleState;
      if (st == null || st == AppLifecycleState.resumed) _muat();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _muat() async {
    try {
      final r = await ApiService.getNotifikasi();
      if (!mounted) return;
      setState(() {
        _aktif = r.aktif;
        _n = r.belumDibaca;
        _list = r.notifikasi;
      });
    } catch (_) {/* lonceng tak boleh mengganggu halaman */}
  }

  /// Tautan web → layar aplikasi. null = tak dikenali (item tetap bisa dibaca).
  (MasScreen, Map<String, dynamic>)? _tujuan(String? tautan) {
    final t = (tautan ?? '').trim();
    if (t.isEmpty) return null;
    final seg = Uri.tryParse(t)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const [];
    if (seg.length >= 2 && seg[0] == 'retur') {
      return (MasScreen.returDetail, {'return_code': seg[1]});
    }
    if (seg.length >= 3 && seg[0] == 'cabang' && seg[1] == 'retur') {
      return (MasScreen.cabangReturDetail, {'return_code': seg[2]});
    }
    if (seg.length >= 2 && seg[0] == 'pesanan') {
      return (MasScreen.pesananDetail, {'order_code': seg[1]});
    }
    if (seg.length == 1 && seg[0] == 'retur') return (MasScreen.returSaya, {});
    return null;
  }

  Future<void> _buka() async {
    HapticFeedback.selectionClick();
    final nav = AppNav.of(context);
    if (_n > 0) {
      ApiService.bacaNotifikasi().then((_) {
        if (mounted) setState(() => _n = 0);
      }).catchError((_) {});
    }
    final m = context.mas;
    final pilih = await showModalBottomSheet<(MasScreen, Map<String, dynamic>)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: m.paper,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(MasRadii.sheet))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(children: [
                Expanded(
                  child: Text('Notifikasi',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, color: m.ink900)),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: m.ink600),
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.pop(ctx),
                ),
              ]),
            ),
            Divider(height: 1, color: m.ink150),
            if (_list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Text('Belum ada notifikasi.',
                    style: TextStyle(fontSize: 12.5, color: m.ink500)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _list.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: m.ink100),
                  itemBuilder: (_, i) {
                    final x = _list[i];
                    final tujuan = _tujuan(x.tautan);
                    return Material(
                      color: x.dibaca ? m.paper : m.brand50,
                      child: InkWell(
                        onTap: tujuan == null ? null : () => Navigator.pop(ctx, tujuan),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(x.judul,
                                      style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: m.ink900)),
                                  if (x.isi.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(x.isi,
                                        style: TextStyle(
                                            fontSize: 12.5, color: m.ink700, height: 1.4)),
                                  ],
                                  const SizedBox(height: 3),
                                  Text(fmtDate(x.createdAt),
                                      style: TextStyle(fontSize: 11, color: m.ink500)),
                                ],
                              ),
                            ),
                            if (tujuan != null)
                              Icon(Icons.chevron_right_rounded, size: 18, color: m.ink400),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    // Semua sudah terbaca begitu panel dibuka (sama seperti web).
    setState(() => _list = [
          for (final x in _list)
            Notifikasi(
                id: x.id,
                judul: x.judul,
                isi: x.isi,
                tautan: x.tautan,
                dibaca: true,
                createdAt: x.createdAt),
        ]);
    if (pilih != null) nav.go(pilih.$1, part: pilih.$2);
  }

  @override
  Widget build(BuildContext context) {
    if (!_aktif) return const SizedBox.shrink();
    final m = context.mas;
    final btn = Material(
      color: m.paper,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: _buka,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: m.ink200),
          ),
          child: Icon(Icons.notifications_none_rounded, size: 17, color: m.ink700),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: _n > 0 ? 'Notifikasi ($_n baru)' : 'Notifikasi',
        child: Stack(clipBehavior: Clip.none, children: [
          btn,
          if (_n > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                decoration: BoxDecoration(
                  color: m.danger600,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: m.paper, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    _n > 99 ? '99+' : '$_n',
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
