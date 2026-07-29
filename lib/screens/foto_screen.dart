// lib/screens/foto_screen.dart — Cari by Foto (DINOv2 + SIMS), data live.
//
// Setara web (search-image/page.tsx): mode akurat (TTA) default nyala, kartu
// hasil menampilkan stok & harga, info galeri, mode Crop (seret kotak buang
// latar → akurasi naik), dan Galeri Belajar untuk admin ("foto ini = PN ini").
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';
import '../api_service.dart';
import '../app/nav.dart';
import 'login_screen.dart';

class FotoScreen extends StatefulWidget {
  const FotoScreen({super.key});
  @override
  State<FotoScreen> createState() => _FotoScreenState();
}

enum _Phase { idle, analyzing, done }

class _FotoScreenState extends State<FotoScreen> {
  final _picker = ImagePicker();
  Uint8List? _bytes;
  String _filename = 'upload.jpg';
  int _imgW = 0, _imgH = 0; // dimensi natural (untuk crop)
  // Mode akurat (TTA). null = belum di-resolve; default dari config server
  // (`foto.tta_default`) saat build pertama, lalu dikendalikan user.
  bool? _tta;
  _Phase _phase = _Phase.idle;

  List<ImageMatch> _results = [];
  int _galeriTotal = 0;
  int _galeriParts = 0;
  String? _pesan;

  // Crop.
  bool _cropMode = false;
  Rect? _cropSel; // koordinat pada gambar yang ditampilkan (px)
  Offset? _dragStart;
  double _cropScale = 1.0; // px asli per px tampil (di-cache saat layout)

  // Galeri belajar (admin / user "mas").
  String? _learnedPn;
  String? _learnBusy;

  Future<void> _pick(ImageSource source) async {
    try {
      final picked =
          await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1600);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final dim = await _dimensi(bytes);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _filename = picked.name;
        _imgW = dim.$1;
        _imgH = dim.$2;
        _phase = _Phase.idle;
        _results = [];
        _pesan = null;
        _cropMode = false;
        _cropSel = null;
        _learnedPn = null;
      });
    } catch (_) {
      if (mounted) AppNav.of(context).toast('Tidak dapat mengakses kamera/galeri.');
    }
  }

  Future<(int, int)> _dimensi(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return (frame.image.width, frame.image.height);
    } catch (_) {
      return (0, 0);
    }
  }

  void _pickSheet() {
    final m = context.mas;
    showModalBottomSheet(
      context: context,
      backgroundColor: m.paper,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: m.ink200, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.photo_camera_outlined, color: m.brand600),
            title: const Text('Ambil dari kamera'),
            onTap: () { Navigator.pop(ctx); _pick(ImageSource.camera); },
          ),
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: m.brand600),
            title: const Text('Pilih dari galeri'),
            onTap: () { Navigator.pop(ctx); _pick(ImageSource.gallery); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  /// Potong bytes ke seleksi crop (koordinat gambar tampil → dikalikan skala ke
  /// piksel asli), lalu jadikan gambar query baru. Setara `applyCrop` web.
  Future<void> _applyCrop(double scale) async {
    final sel = _cropSel;
    final src = _bytes;
    if (sel == null || src == null || sel.width < 12 || sel.height < 12) return;
    try {
      final codec = await ui.instantiateImageCodec(src);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final sx = (sel.left * scale).round().clamp(0, img.width);
      final sy = (sel.top * scale).round().clamp(0, img.height);
      final sw = (sel.width * scale).round().clamp(1, img.width - sx);
      final sh = (sel.height * scale).round().clamp(1, img.height - sy);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(sx.toDouble(), sy.toDouble(), sw.toDouble(), sh.toDouble()),
        Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
        Paint(),
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(sw, sh);
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || !mounted) return;
      setState(() {
        _bytes = data.buffer.asUint8List();
        _filename = 'crop.png';
        _imgW = sw;
        _imgH = sh;
        _cropMode = false;
        _cropSel = null;
        _results = [];
        _pesan = null;
        _phase = _Phase.idle;
      });
    } catch (_) {
      if (mounted) AppNav.of(context).toast('Gagal memotong gambar.');
    }
  }

  Future<void> _analyze() async {
    if (_bytes == null) {
      _pickSheet();
      return;
    }
    // topK/threshold bisa diatur dari server (config `foto`); fallback 20/0.3.
    final nav = AppNav.of(context);
    setState(() {
      _phase = _Phase.analyzing;
      _results = [];
      _learnedPn = null;
    });
    try {
      final res = await ApiService.searchImage(
          bytes: _bytes!,
          filename: _filename,
          topK: nav.fotoTopK(20),
          threshold: nav.fotoThreshold(0.3),
          useTta: _tta ?? true);
      if (!mounted) return;
      setState(() {
        _results = res.results;
        _galeriTotal = res.galeriTotal;
        _galeriParts = res.galeriParts;
        _pesan = res.pesan;
        _phase = _Phase.done;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
        return;
      }
      setState(() => _phase = _Phase.done);
      AppNav.of(context).toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.done);
      AppNav.of(context).toast('Gagal menganalisis foto. Coba lagi.');
    }
  }

  Future<void> _learn(String pn) async {
    final src = _bytes;
    if (src == null || _learnBusy != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajari galeri', style: TextStyle(fontSize: 16)),
        content: Text(
            'Yakin foto ini memang part $pn? Foto akan diindeks ke galeri '
            '(memperbaiki akurasi pencarian foto berikutnya).',
            style: const TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ya, indeks')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _learnBusy = pn);
    try {
      final res = await ApiService.learnImageMatch(bytes: src, pn: pn, filename: _filename);
      if (!mounted) return;
      setState(() => _learnedPn = res.pn);
    } on ApiException catch (e) {
      if (mounted) AppNav.of(context).toast(e.message);
    } catch (_) {
      if (mounted) AppNav.of(context).toast('Gagal mengindeks foto.');
    } finally {
      if (mounted) setState(() => _learnBusy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    // Resolusi default TTA dari config sekali (sesudahnya dikendalikan user).
    _tta ??= nav.fotoTtaDefault(true);
    final canLearn =
        nav.role == 'admin' || nav.username.toLowerCase() == 'mas';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (_cropMode && _bytes != null)
          _cropArea(m)
        else
          GestureDetector(
            onTap: _pickSheet,
            child: _DashedBox(
              child: AspectRatio(
                aspectRatio: 1.6,
                child: _bytes == null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('📷  Ketuk untuk pilih foto',
                              style: TextStyle(fontSize: 13.5, color: m.ink500, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          Text('atau ambil dari kamera', style: TextStyle(fontSize: 12, color: m.ink400)),
                        ]),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(_bytes!, fit: BoxFit.contain, width: double.infinity),
                      ),
              ),
            ),
          ),

        if (!_cropMode) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: MasButton(
                label: '📸 Kamera',
                primary: false,
                height: 40,
                onTap: () => _pick(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MasButton(
                label: '✂ Crop',
                primary: false,
                height: 40,
                onTap: _bytes == null
                    ? null
                    : () => setState(() {
                          _cropMode = true;
                          _cropSel = null;
                        }),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => setState(() => _tta = !(_tta ?? true)),
            child: Row(children: [
              _check(m, _tta ?? true),
              const SizedBox(width: 8),
              Text('Mode akurat (TTA, lebih lambat)', style: TextStyle(fontSize: 13.5, color: m.ink600)),
            ]),
          ),
          const SizedBox(height: 12),
          MasButton(
            label: _phase == _Phase.analyzing ? 'Menganalisis…' : '🔍  Cari Part Mirip',
            onTap: _phase == _Phase.analyzing ? null : _analyze,
            expand: true,
            height: 44,
            loading: _phase == _Phase.analyzing,
          ),
          if (_galeriTotal > 0) ...[
            const SizedBox(height: 8),
            Text('Galeri: $_galeriTotal foto dari $_galeriParts part.',
                style: TextStyle(fontSize: 12, color: m.ink400)),
          ],
        ],

        if (_learnedPn != null) ...[
          const SizedBox(height: 14),
          _LearnedBanner(pn: _learnedPn!),
        ],

        if (_phase == _Phase.done && !_cropMode) ...[
          const SizedBox(height: 16),
          if (_results.isEmpty)
            MasEmpty(
              icon: Icons.image_search_outlined,
              title: 'Tidak ada kecocokan',
              subtitle: _pesan?.isNotEmpty == true
                  ? _pesan!
                  : 'Coba foto ulang dengan latar polos, atau ✂ Crop ke part-nya saja.',
            )
          else ...[
            Text('${_results.length} part mirip ditemukan',
                style: TextStyle(fontSize: 13.5, color: m.ink500)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.66,
              children: [for (final r in _results) _card(m, r, canLearn)],
            ),
          ],
        ],
      ],
    );
  }

  Widget _cropArea(MasColors m) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, constraints) {
        final boxW = constraints.maxWidth;
        // Gambar dirender selebar box; tingginya ikut rasio natural — jadi
        // koordinat tampil ↔ piksel asli hanya beda satu skala seragam.
        final ratio = _imgH > 0 ? _imgW / _imgH : 1.6;
        final boxH = boxW / ratio;
        // Cache skala tampil→asli untuk dipakai tombol "Terapkan" di bawah.
        _cropScale = _imgW > 0 ? _imgW / boxW : 1.0;
        return GestureDetector(
          onPanStart: (d) => setState(() {
            _dragStart = d.localPosition;
            _cropSel = Rect.fromLTWH(d.localPosition.dx, d.localPosition.dy, 0, 0);
          }),
          onPanUpdate: (d) {
            final s = _dragStart;
            if (s == null) return;
            final p = Offset(
              d.localPosition.dx.clamp(0.0, boxW),
              d.localPosition.dy.clamp(0.0, boxH),
            );
            setState(() => _cropSel = Rect.fromLTRB(
                  s.dx < p.dx ? s.dx : p.dx,
                  s.dy < p.dy ? s.dy : p.dy,
                  s.dx < p.dx ? p.dx : s.dx,
                  s.dy < p.dy ? p.dy : s.dy,
                ));
          },
          onPanEnd: (_) => _dragStart = null,
          child: SizedBox(
            width: boxW,
            height: boxH,
            child: Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(_bytes!, width: boxW, height: boxH, fit: BoxFit.fill),
              ),
              if (_cropSel != null && _cropSel!.width > 2)
                Positioned.fromRect(
                  rect: _cropSel!,
                  child: Container(
                    decoration: BoxDecoration(
                      color: m.brand600.withValues(alpha: 0.15),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ]),
          ),
        );
      }),
      const SizedBox(height: 6),
      Text('Seret kotak mengelilingi PART-nya saja (buang latar) → akurasi naik.',
          style: TextStyle(fontSize: 12, color: m.ink500)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: MasButton(
            label: '✂ Terapkan',
            height: 42,
            onTap: (_cropSel == null || _cropSel!.width < 12)
                ? null
                : () => _applyCrop(_cropScale),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MasButton(
            label: 'Batal',
            primary: false,
            height: 42,
            onTap: () => setState(() {
              _cropMode = false;
              _cropSel = null;
            }),
          ),
        ),
      ]),
    ]);
  }

  Widget _card(MasColors m, ImageMatch r, bool canLearn) {
    final pn = r.partNumber;
    final name = r.partName;
    final pct = r.matchPercent;
    final url = r.simsUrl;
    final learned = _learnedPn == pn;
    return Container(
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.ink150),
        boxShadow: m.shadow1,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => AppNav.of(context).go(MasScreen.part, part: {
            'part_number': pn,
            'part_name': name,
            'sims_url': url,
            'stok': r.stok,
            'harga': r.harga,
          }),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            AspectRatio(
              aspectRatio: 1,
              child: url.isEmpty
                  ? HatchBox(label: pn, radius: 0)
                  : Image.network(ApiService.partImageUrl(url), fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => HatchBox(label: pn, radius: 0)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (name.isNotEmpty)
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: m.ink900)),
                const SizedBox(height: 2),
                Text(pn, maxLines: 1, overflow: TextOverflow.ellipsis, style: masMono(size: 11.5, color: m.ink500)),
                const SizedBox(height: 3),
                // Stok & harga (persis web): ✅ hijau bila tersedia.
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: r.tersedia ? '✅ Stok ${r.stok}' : 'Stok ${r.stok.isEmpty ? '—' : r.stok}',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: r.tersedia ? FontWeight.w600 : FontWeight.w400,
                          color: r.tersedia ? m.brand700 : m.ink400),
                    ),
                    if (r.harga.isNotEmpty && r.harga != '—')
                      TextSpan(text: ' · ${r.harga}', style: TextStyle(fontSize: 11.5, color: m.ink500)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: MasBar(value: pct / 100)),
                  const SizedBox(width: 6),
                  Text('$pct%', style: TextStyle(fontSize: 10.5, color: m.ink500)),
                ]),
              ]),
            ),
          ]),
        ),
        // Galeri Belajar (admin / user "mas"): konfirmasi foto = PN ini.
        if (canLearn && _bytes != null)
          InkWell(
            onTap: (_learnBusy != null || learned) ? null : () => _learn(pn),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: m.ink50,
                border: Border(top: BorderSide(color: m.ink100)),
              ),
              child: Text(
                learned
                    ? '✅ terindeks'
                    : (_learnBusy == pn ? 'mengindeks…' : '✓ benar part ini → ajari galeri'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: learned ? m.brand700 : m.ink500),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _check(MasColors m, bool value) => Container(
        width: 18, height: 18,
        decoration: BoxDecoration(
          color: value ? m.brand600 : m.paper,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: value ? m.brand600 : m.ink300, width: 1.5),
        ),
        child: value ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
      );
}

class _LearnedBanner extends StatelessWidget {
  final String pn;
  const _LearnedBanner({required this.pn});
  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: m.brand50,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.brand100),
      ),
      child: Text('✅ Foto diindeks ke galeri sebagai $pn — pencarian foto serupa berikutnya makin akurat.',
          style: TextStyle(fontSize: 12.5, color: m.brand700, height: 1.4)),
    );
  }
}

class _DashedBox extends StatelessWidget {
  final Widget child;
  const _DashedBox({required this.child});
  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return CustomPaint(
      foregroundPainter: _DashPainter(m.ink300),
      child: Container(
        decoration: BoxDecoration(color: m.paper, borderRadius: BorderRadius.circular(12)),
        child: child,
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2), const Radius.circular(12));
    final path = Path()..addRRect(rrect);
    const dash = 7.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final n = d + dash;
        canvas.drawPath(metric.extractPath(d, n.clamp(0, metric.length)), paint);
        d = n + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}
