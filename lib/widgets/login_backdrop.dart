// lib/widgets/login_backdrop.dart — latar panel merek halaman Masuk: medan baut,
// mur & ring yang hanyut pelan. Paritas web frontend/src/components/LoginBackdrop.tsx.
//
// Web memakai three.js; di sini digambar CustomPainter dengan proyeksi
// perspektif yang sama (kamera z=17, fov 38°, kabut 16–38) dan backface culling
// per sisi — tanpa paket 3D, tanpa aset. Susunannya memakai acak BERBENIH yang
// sama dengan web, jadi kedua halaman membuka dengan medan yang serupa.
//
// Pagar: "kurangi animasi" di HP (disableAnimations) → satu bingkai statis,
// ticker tak pernah jalan. TickerMode mematikan loop saat halaman tertutup rute lain.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// --ink-900 web, sama dengan sidebar Command Center.
const loginPanelBg = Color(0xFF0F1411);

const _boundX = 15.0, _boundY = 10.0, _zNear = 4.0, _zFar = -20.0;
const _camZ = 17.0;
final _tanHalfFov = math.tan(19 * math.pi / 180);

const _steel = Color(0xFFB9C0C9);
const _brand = Color(0xFF1EA83A);

class LoginBackdrop extends StatefulWidget {
  const LoginBackdrop({super.key});
  @override
  State<LoginBackdrop> createState() => _LoginBackdropState();
}

class _LoginBackdropState extends State<LoginBackdrop> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  late final _Field _field = _Field();
  Duration _last = Duration.zero;

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : math.min((now - _last).inMicroseconds / 1e6, 0.05);
    _last = now;
    _field.step(dt);
    _frame.value++;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final diam = MediaQuery.of(context).disableAnimations;
    if (diam && _ticker.isActive) {
      _ticker.stop();
    } else if (!diam && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      // Latar cadangan (sama dengan .login-fallback web) — juga dasar di bawah medan.
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.6, -1),
            end: Alignment(0.6, 1),
            colors: [Color(0xFF18201A), loginPanelBg],
            stops: [0, 0.62],
          ),
        ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.4, -0.52),
            radius: 0.9,
            colors: [Color(0xFF16301F), Color(0x0016301F)],
            stops: [0, 0.6],
          ),
        ),
      ),
      RepaintBoundary(child: CustomPaint(painter: _FieldPainter(_field, _frame))),
      // Peredup: gelap di kiri (tempat teks), bening di kanan (tempat gerak terlihat).
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1, -0.18),
            end: Alignment(1, 0.18),
            colors: [Color(0xEB0F1411), Color(0x9E0F1411), Color(0x140F1411)],
            stops: [0, 0.38, 0.78],
          ),
        ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.3,
            colors: [Color(0x000F1411), Color(0x610F1411)],
            stops: [0.45, 1],
          ),
        ),
      ),
    ]);
  }
}

// ── Vektor & rotasi kecil (Euler XYZ, sama dengan three.js) ──

class _V {
  final double x, y, z;
  const _V(this.x, this.y, this.z);
  _V operator +(_V o) => _V(x + o.x, y + o.y, z + o.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  _V operator *(double s) => _V(x * s, y * s, z * s);
  double dot(_V o) => x * o.x + y * o.y + z * o.z;
  _V cross(_V o) => _V(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  _V get unit {
    final l = math.sqrt(dot(this));
    return l == 0 ? this : this * (1 / l);
  }
}

final _keyL = const _V(-6, 8, 9).unit;
final _rimL = const _V(9, -6, -4).unit;
final _half = (_keyL + const _V(0, 0, 1)).unit;

enum _Kind { nut, bolt, washer }

class _Item {
  final _Kind kind;
  final Color base;
  final double scale;
  double x, y, z, rx, ry, rz;
  final double spinX, spinY, spinZ, rise, sway, phase;
  _Item(this.kind, this.base, this.scale, this.x, this.y, this.z, this.rx, this.ry, this.rz,
      this.spinX, this.spinY, this.spinZ, this.rise, this.sway, this.phase);

  /// R = Rx·Ry·Rz diterapkan ke titik lokal.
  _V rot(_V p) {
    final cz = math.cos(rz), sz = math.sin(rz);
    var x1 = p.x * cz - p.y * sz, y1 = p.x * sz + p.y * cz, z1 = p.z;
    final cy = math.cos(ry), sy = math.sin(ry);
    final x2 = x1 * cy + z1 * sy, z2 = -x1 * sy + z1 * cy;
    final cx = math.cos(rx), sx = math.sin(rx);
    return _V(x2, y1 * cx - z2 * sx, y1 * sx + z2 * cx);
  }

  _V world(_V p) => _V(x, y, z) + rot(p) * scale;
}

class _Field {
  final items = <_Item>[];
  int _seed = 20260907;
  double _clock = 0;

  double _rnd() {
    _seed = (_seed * 1664525 + 1013904223) % 4294967296;
    return _seed / 4294967296;
  }

  _Field() {
    // Panel HP kecil → web juga jatuh ke batas bawah 26.
    for (var i = 0; i < 26; i++) {
      final k = _rnd();
      final brand = _rnd() < 0.2;
      final kind = k < 0.42 ? _Kind.nut : (k < 0.74 ? _Kind.bolt : _Kind.washer);
      final scale = 0.34 + _rnd() * 0.72;
      final px = (_rnd() * 2 - 1) * _boundX;
      final py = (_rnd() * 2 - 1) * _boundY;
      final pz = _zFar + _rnd() * (_zNear - _zFar);
      final rx = _rnd() * 6.28, ry = _rnd() * 6.28, rz = _rnd() * 6.28;
      final sx = (_rnd() - 0.5) * 0.34, sy = (_rnd() - 0.5) * 0.34, sz = (_rnd() - 0.5) * 0.24;
      final rise = (0.22 + _rnd() * 0.3) * (0.5 + scale);
      final sway = (_rnd() - 0.5) * 0.16;
      final phase = _rnd() * 6.28;
      items.add(_Item(kind, brand ? _brand : _steel, scale, px, py, pz, rx, ry, rz, sx, sy, sz,
          rise, sway, phase));
    }
  }

  void step(double dt) {
    if (dt <= 0) return;
    _clock += dt;
    for (final it in items) {
      it.rx += it.spinX * dt;
      it.ry += it.spinY * dt;
      it.rz += it.spinZ * dt;
      it.y += it.rise * dt;
      it.x += math.sin(_clock * 0.5 + it.phase) * it.sway * dt;
      if (it.y > _boundY) {
        // keluar lewat atas → masuk lagi dari bawah, kolom acak
        it.y = -_boundY;
        it.x = (_rnd() * 2 - 1) * _boundX;
      }
    }
  }
}

// ── Geometri lokal (satuan dunia, sama dengan web) ──

List<_V> _ring(double r, int n, double z, {double offset = 0}) => [
      for (var i = 0; i < n; i++)
        _V(math.cos(offset + i * 2 * math.pi / n) * r, math.sin(offset + i * 2 * math.pi / n) * r, z)
    ];

class _FieldPainter extends CustomPainter {
  final _Field field;
  _FieldPainter(this.field, Listenable repaint) : super(repaint: repaint);

  late Size _size;
  late double _k0; // piksel per satuan dunia pada jarak 1

  Offset _proj(_V w) {
    final d = _camZ - w.z;
    final k = _k0 / d;
    return Offset(_size.width / 2 + w.x * k, _size.height / 2 - w.y * k);
  }

  Color _shade(Color base, _V n, double fog) {
    final key = math.max(0.0, n.dot(_keyL));
    final rim = math.max(0.0, n.dot(_rimL));
    final spec = math.pow(math.max(0.0, n.dot(_half)), 22).toDouble() * 0.85;
    final b = 0.26 + 0.78 * key;
    int ch(double c, double g) =>
        (c * b + 255 * spec + g * 0.55 * rim).clamp(0, 255).round();
    final lit = Color.fromARGB(
        255, ch(base.r * 255, 30), ch(base.g * 255, 168), ch(base.b * 255, 58));
    return Color.lerp(lit, loginPanelBg, fog)!;
  }

  final _paint = Paint()..isAntiAlias = true;

  void _poly(Canvas c, List<_V> pts, _Item it, double fog, {bool inward = false}) {
    final w = [for (final p in pts) it.world(p)];
    var n = (w[1] - w[0]).cross(w[2] - w[0]).unit;
    if (inward) n = n * -1;
    final toCam = (const _V(0, 0, _camZ) - w[0]);
    if (n.dot(toCam) <= 0) return; // membelakangi kamera
    final path = Path()..addPolygon([for (final p in w) _proj(p)], true);
    _paint.color = _shade(it.base, n, fog);
    c.drawPath(path, _paint);
  }

  /// Prisma (opsional berlubang) dari dua cincin titik: sisi luar, dinding
  /// lubang, lalu tutup yang menghadap kamera.
  void _prism(Canvas c, _Item it, List<_V> outFront, List<_V> outBack, List<_V>? inFront,
      List<_V>? inBack, double fog) {
    final n = outFront.length;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      _poly(c, [outBack[i], outBack[j], outFront[j], outFront[i]], it, fog);
    }
    if (inFront != null && inBack != null) {
      final m = inFront.length;
      for (var i = 0; i < m; i++) {
        final j = (i + 1) % m;
        _poly(c, [inBack[i], inBack[j], inFront[j], inFront[i]], it, fog, inward: true);
      }
    }
    for (final (outer, inner, flip) in [(outFront, inFront, false), (outBack, inBack, true)]) {
      final wo = [for (final p in outer) it.world(p)];
      var nn = (wo[1] - wo[0]).cross(wo[2] - wo[0]).unit;
      if (flip) nn = nn * -1;
      if (nn.dot(const _V(0, 0, _camZ) - wo[0]) <= 0) continue;
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addPolygon([for (final p in wo) _proj(p)], true);
      if (inner != null) path.addPolygon([for (final p in inner) _proj(it.world(p))], true);
      _paint.color = _shade(it.base, nn, fog);
      c.drawPath(path, _paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
    _k0 = (size.height / 2) / _tanHalfFov;
    final sorted = [...field.items]..sort((a, b) => a.z.compareTo(b.z));
    const hexOff = math.pi / 6;
    for (final it in sorted) {
      final d = _camZ - it.z;
      if (d < 1) continue;
      final fog = ((d - 16) / 22).clamp(0.0, 1.0);
      switch (it.kind) {
        case _Kind.nut:
          // Ring titik berlawanan arah jarum jam dilihat dari +z → normal tutup depan = +z.
          _prism(canvas, it, _ring(1.05, 6, 0.36, offset: hexOff), _ring(1.05, 6, -0.36, offset: hexOff),
              _ring(0.55, 16, 0.36), _ring(0.55, 16, -0.36), fog);
        case _Kind.washer:
          _prism(canvas, it, _ring(1.01, 24, 0.19), _ring(1.01, 24, -0.19), _ring(0.63, 18, 0.19),
              _ring(0.63, 18, -0.19), fog);
        case _Kind.bolt:
          void head() => _prism(canvas, it, _ring(0.87, 6, 0.29, offset: hexOff),
              _ring(0.87, 6, -0.29, offset: hexOff), null, null, fog);
          void shaft() => _prism(canvas, it, _ring(0.36, 14, 2.55), _ring(0.36, 14, 0.25), null, null, fog);
          // Batang menghadap kamera → gambar setelah kepala.
          final axis = it.rot(const _V(0, 0, 1));
          final toCam = const _V(0, 0, _camZ) - _V(it.x, it.y, it.z);
          if (axis.dot(toCam) > 0) {
            head();
            shaft();
          } else {
            shaft();
            head();
          }
      }
    }
  }

  @override
  bool shouldRepaint(_FieldPainter old) => old.field != field;
}
