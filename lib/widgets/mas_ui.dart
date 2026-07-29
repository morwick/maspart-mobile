// lib/widgets/mas_ui.dart
// Komponen UI bersama MasPart — bahasa visual dari desain "MasPart Mobile.dc".
// Semua widget theme-aware lewat context.mas (light/dark).

import 'package:flutter/material.dart';
import '../theme/mas_theme.dart';

/// Kartu dasar: paper, border ink150, radius 10, shadow-1.
class MasCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool shadow;
  final EdgeInsetsGeometry? margin;
  const MasCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.shadow = true,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.ink150),
        boxShadow: shadow ? m.shadow1 : null,
      ),
      child: child,
    );
    final card = onTap == null
        ? content
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(MasRadii.card),
            child: content,
          );
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

/// Kartu bagian dengan judul header + daftar baris (dipisah garis ink100/150).
class MasSectionCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  const MasSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.ink150),
        boxShadow: m.shadow1,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: m.ink150)),
            ),
            child: Row(children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: m.ink900)),
              ),
              ?trailing,
            ]),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// Baris key–value (dipakai di spesifikasi, stok gudang, dll).
class MasKeyValue extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final Color? valueColor;
  final bool divider;
  const MasKeyValue({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.valueColor,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: divider ? Border(bottom: BorderSide(color: m.ink100)) : null,
      ),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: m.ink600))),
        mono
            ? Text(value,
                style: masMono(size: 13, weight: FontWeight.w600, color: valueColor ?? m.ink900))
            : Text(value,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor ?? m.ink900)),
      ]),
    );
  }
}

enum MasPillTone { brand, neutral, warn, info, danger }

/// Pill status kecil dengan dot opsional.
class MasPill extends StatelessWidget {
  final String label;
  final MasPillTone tone;
  final bool dot;
  final double height;
  const MasPill({
    super.key,
    required this.label,
    this.tone = MasPillTone.neutral,
    this.dot = false,
    this.height = 22,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    late Color bg, fg, bd;
    switch (tone) {
      case MasPillTone.brand:
        bg = m.brand50; fg = m.brand700; bd = m.brand100; break;
      case MasPillTone.warn:
        bg = m.warn50; fg = m.warn600; bd = m.warnBorder; break;
      case MasPillTone.info:
        bg = m.info50; fg = m.info600; bd = m.infoBorder; break;
      case MasPillTone.danger:
        bg = m.danger50; fg = m.danger600; bd = m.dangerBorder; break;
      case MasPillTone.neutral:
        bg = m.ink100; fg = m.ink700; bd = m.ink200; break;
    }
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: dot ? 8 : 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MasRadii.pill),
        border: Border.all(color: bd),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

/// Input teks bergaya desain (h44 default).
class MasInput extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final bool mono;
  final bool obscure;
  final double height;
  final Widget? prefix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? action;
  final int? maxLines;
  final FocusNode? focusNode;
  const MasInput({
    super.key,
    this.controller,
    required this.hint,
    this.mono = false,
    this.obscure = false,
    this.height = 44,
    this.prefix,
    this.onChanged,
    this.onSubmitted,
    this.action,
    this.maxLines = 1,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final multiline = (maxLines ?? 1) > 1;
    return Container(
      height: multiline ? null : height,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: multiline ? 10 : 0),
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.input),
        border: Border.all(color: m.ink200),
      ),
      alignment: multiline ? null : Alignment.center,
      child: Row(children: [
        if (prefix != null) ...[prefix!, const SizedBox(width: 8)],
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscure,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            textInputAction: action,
            maxLines: maxLines,
            minLines: multiline ? maxLines : 1,
            style: mono
                ? masMono(size: 14, color: m.ink900)
                : TextStyle(fontSize: 14, color: m.ink900),
            cursorColor: m.brand600,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: TextStyle(
                color: m.ink400,
                fontFamily: mono ? masMono().fontFamily : null,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Tombol utama (hijau) / sekunder (outline).
class MasButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final IconData? icon;
  final double height;
  final bool expand;
  final bool loading;
  const MasButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = true,
    this.icon,
    this.height = 44,
    this.expand = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final fg = primary ? Colors.white : m.ink800;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
        else ...[
          if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 7)],
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
        ],
      ],
    );
    return Material(
      color: primary ? m.brand600 : m.paper,
      borderRadius: BorderRadius.circular(MasRadii.input),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(MasRadii.input),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MasRadii.input),
            border: primary ? null : Border.all(color: m.ink200),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

/// Tab garis-bawah (Part Number / Part Name).
class MasUnderlineTabs extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  const MasUnderlineTabs({super.key, required this.tabs, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: m.ink200))),
      child: Row(children: [
        for (int i = 0; i < tabs.length; i++)
          GestureDetector(
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: i == index ? m.brand600 : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(tabs[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: i == index ? m.brand700 : m.ink600,
                  )),
            ),
          ),
      ]),
    );
  }
}

/// Tab segmented (pill) — dipakai di Harga.
class MasSegmentTabs extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  const MasSegmentTabs({super.key, required this.tabs, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: m.ink100, borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < tabs.length; i++)
          GestureDetector(
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: i == index ? m.paper : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                boxShadow: i == index ? m.shadow1 : null,
              ),
              child: Text(tabs[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: i == index ? m.brand700 : m.ink600,
                  )),
            ),
          ),
      ]),
    );
  }
}

/// Kotak arsir diagonal — placeholder foto part (sesuai desain).
class HatchBox extends StatelessWidget {
  final String? label;
  final double? width;
  final double? height;
  final double aspectRatio;
  final double radius;
  const HatchBox({
    super.key,
    this.label,
    this.width,
    this.height,
    this.aspectRatio = 1,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    Widget box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: m.ink200),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _HatchPainter(m.ink100, m.ink150),
        child: label == null
            ? const SizedBox.expand()
            : Center(
                child: Text(label!, style: masMono(size: 10.5, color: m.ink500)),
              ),
      ),
    );
    if (width == null && height == null) {
      box = AspectRatio(aspectRatio: aspectRatio, child: box);
    }
    return box;
  }
}

class _HatchPainter extends CustomPainter {
  final Color a, b;
  _HatchPainter(this.a, this.b);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = a);
    final p = Paint()
      ..color = b
      ..strokeWidth = 6;
    const step = 12.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _HatchPainter old) => old.a != a || old.b != b;
}

/// Bar progres tipis (kecocokan foto, omzet bulanan).
class MasBar extends StatelessWidget {
  final double value; // 0..1
  final double height;
  const MasBar({super.key, required this.value, this.height = 6});
  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return ClipRRect(
      borderRadius: BorderRadius.circular(MasRadii.pill),
      child: Container(
        height: height,
        color: m.ink100,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0, 1),
          child: Container(color: m.brand600),
        ),
      ),
    );
  }
}

/// Label eyebrow uppercase (mis. "SENIN, 6 JULI 2026", "USER ONLINE").
class MasEyebrow extends StatelessWidget {
  final String text;
  const MasEyebrow(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Text(text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: m.ink500,
          letterSpacing: 0.6,
        ));
  }
}

/// Tampilan kosong sederhana.
class MasEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const MasEmpty({super.key, required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: m.ink100, borderRadius: BorderRadius.circular(18)),
          child: Icon(icon, size: 30, color: m.ink400),
        ),
        const SizedBox(height: 14),
        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: m.ink900)),
        const SizedBox(height: 5),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5)),
      ]),
    );
  }
}

/// Kartu skeleton loading.
class MasSkeleton extends StatefulWidget {
  final double height;
  const MasSkeleton({super.key, this.height = 64});
  @override
  State<MasSkeleton> createState() => _MasSkeletonState();
}

class _MasSkeletonState extends State<MasSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = _c.value;
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MasRadii.card),
            gradient: LinearGradient(
              begin: Alignment(-1 + t * 2, 0),
              end: Alignment(1 + t * 2, 0),
              colors: [m.ink100, m.ink50, m.ink100],
            ),
          ),
        );
      },
    );
  }
}
