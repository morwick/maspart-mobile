// lib/app/mas_drawer.dart
// Drawer "Command Center" — selalu bertema gelap sesuai desain (bg #0f1411).

import 'package:flutter/material.dart';
import '../theme/mas_theme.dart';
import 'nav.dart';

class MasDrawer extends StatelessWidget {
  final MasScreen current;
  final String username;
  final String role;
  final List<NavSection> sections;
  final void Function(MasScreen) onGo;
  final VoidCallback onLogout;
  const MasDrawer({
    super.key,
    required this.current,
    required this.username,
    required this.role,
    required this.sections,
    required this.onGo,
    required this.onLogout,
  });

  static const _bg = Color(0xFF0F1411);
  static const _panel = Color(0xFF1B211D);
  static const _muted = Color(0xFF767E79);
  static const _text = Color(0xFFC5CAC6);
  static const _brand = Color(0xFF028912);
  static const _brand500 = Color(0xFF1EA83A);

  String get _initials {
    final p = username.trim().split(RegExp(r'[\s._-]+')).where((e) => e.isNotEmpty).toList();
    if (p.isEmpty) return 'MP';
    if (p.length == 1) return p.first.substring(0, p.first.length >= 2 ? 2 : 1).toUpperCase();
    return (p[0][0] + p[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      width: 272,
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, top + 18, 16, 12),
            child: Row(children: [
              Container(
                width: 32, height: 32, alignment: Alignment.center,
                decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(8)),
                child: Text('M', style: masMono(size: 15, weight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('MASPART',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Colors.white, letterSpacing: -0.2)),
                const SizedBox(height: 2),
                Text('COMMAND CENTER',
                    style: TextStyle(fontSize: 9.5, color: _muted, letterSpacing: 1.4, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                for (final sec in sections) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
                    child: Text(sec.label.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10, color: _muted, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                  ),
                  for (final it in sec.items) _item(it),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.of(context).padding.bottom),
            child: Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _panel))),
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Container(
                    width: 30, height: 30, alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Color(0xFF026A0E), shape: BoxShape.circle),
                    child: Text(_initials,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFD3EDD7))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(username,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFF3F5F3))),
                      Text(role.isEmpty ? 'user' : role,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: _muted)),
                    ]),
                  ),
                  IconButton(
                    onPressed: onLogout,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.logout_rounded, size: 17, color: _muted),
                    tooltip: 'Keluar',
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(NavItem it) {
    final active = it.screen == current;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? _panel : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: () => onGo(it.screen),
          borderRadius: BorderRadius.circular(7),
          child: Stack(children: [
            if (active)
              Positioned(
                left: 0, top: 7, bottom: 7,
                child: Container(
                  width: 3,
                  decoration: const BoxDecoration(
                    color: _brand500,
                    borderRadius: BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                ),
              ),
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                Icon(it.icon, size: 16, color: active ? Colors.white : _text.withValues(alpha: 0.85)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(it.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: active ? Colors.white : _text,
                      )),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
