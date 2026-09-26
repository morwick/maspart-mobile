// lib/screens/viewer_3d_screen.dart — Model 3D part (CAD resmi EPC, .pvz).
//
// Paritas `Viewer3D.tsx` web. Render dilakukan engine ThingView WASM (PTC Creo
// View) di dalam WebView — engine yang SAMA dengan web, dimuat dari server web
// (/viewer3d/*), jadi tak ada engine 3D kedua yang harus dirawat. Halaman
// pembungkusnya aset lokal `assets/viewer3d/viewer.html`.
//
// Byte model (.pvz) diunduh FLUTTER lewat proxy ber-auth `/api/parts/epc-file`
// lalu dikirim ke halaman dalam potongan base64. Token login dengan begitu tak
// pernah masuk ke WebView, dan jalur ini sama saja untuk backend lokal maupun
// produksi (engine selalu dari origin web).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../api_service.dart';
import '../config.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';

/// Origin tempat engine /viewer3d/* dilayani. Engine (.wasm 12,8 MB) hanya ada
/// di server web — di git ia di-gitignore — jadi saat aplikasi diarahkan ke
/// backend LOKAL (http://10.0.2.2:8001) engine tetap diambil dari produksi.
String get _originEngine => AppConfig.apiBaseUrl.startsWith('https://')
    ? AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')
    : 'https://maspart.tech';

/// Potongan base64 per panggilan runJavaScript. ±256 KB: cukup sedikit
/// panggilan untuk file 1-10 MB, tapi tak satu string raksasa yang membuat
/// jembatan platform tersedak.
const int _ukuranPotong = 192 * 1024;

enum _Fase { engine, siapkan, unduhModel, model, siap, gagal }

class Viewer3DScreen extends StatefulWidget {
  final Part3d info;
  const Viewer3DScreen({super.key, required this.info});

  @override
  State<Viewer3DScreen> createState() => _Viewer3DScreenState();
}

class _Viewer3DScreenState extends State<Viewer3DScreen> {
  WebViewController? _ctl;
  _Fase _fase = _Fase.engine;
  String _galat = '';
  int _byte = 0;
  int _total = 0;
  bool _engineSiap = false;
  Uint8List? _pvz;
  bool _pvzTerkirim = false;
  bool _infoTerbuka = false;
  bool _dimulai = false;

  @override
  void initState() {
    super.initState();
    // Dua jalur paralel: engine dimuat WebView, model diunduh Flutter. Model
    // dikirim ke halaman begitu KEDUANYA siap (lihat _kirimModelBilaSiap).
    WidgetsBinding.instance.addPostFrameCallback((_) => _mulai());
  }

  Future<void> _mulai() async {
    final m = context.mas;
    final bg = m.isDark ? '#1b211c' : '#f5f7fa';
    setState(() {
      _fase = _Fase.engine;
      _galat = '';
      _byte = 0;
      _total = 0;
      _engineSiap = false;
      _pvzTerkirim = false;
    });
    // Build debug: halaman bisa diperiksa lewat chrome://inspect (galat
    // WebGL/engine tak kelihatan dari Flutter).
    if (kDebugMode && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(AndroidWebViewController.enableDebugging(true));
    }
    final html = await rootBundle.loadString('assets/viewer3d/viewer.html');
    if (!mounted) return;
    final ctl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Color(int.parse('ff${bg.substring(1)}', radix: 16)))
      ..addJavaScriptChannel('Mas3D', onMessageReceived: (msg) => _pesan(msg.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          // Sekali per pemuatan — onPageFinished bisa terpanggil ulang.
          if (_dimulai) return;
          _dimulai = true;
          _ctl?.runJavaScript('window.__mulai(${jsonEncode({'bg': bg})});');
        },
      ));
    _dimulai = false;
    setState(() => _ctl = ctl);
    await ctl.loadHtmlString(html, baseUrl: '$_originEngine/');
    if (_pvz == null) unawaited(_unduhModel());
  }

  Future<void> _unduhModel() async {
    try {
      final b = await ApiService.epcFile(widget.info.d3s.first);
      if (!mounted) return;
      _pvz = b;
      _kirimModelBilaSiap();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.gagal;
        _galat = e is ApiException
            ? e.message
            : 'Model 3D tak bisa diunduh dari EPC. Coba lagi sebentar.';
      });
    }
  }

  Future<void> _kirimModelBilaSiap() async {
    final ctl = _ctl, pvz = _pvz;
    if (ctl == null || pvz == null || !_engineSiap || _pvzTerkirim) return;
    _pvzTerkirim = true;
    setState(() => _fase = _Fase.model);
    await ctl.runJavaScript('window.__pvzMulai();');
    for (var i = 0; i < pvz.length; i += _ukuranPotong) {
      final akhir = (i + _ukuranPotong < pvz.length) ? i + _ukuranPotong : pvz.length;
      final b64 = base64Encode(Uint8List.sublistView(pvz, i, akhir));
      await ctl.runJavaScript("window.__pvzPotong('$b64');");
    }
    await ctl.runJavaScript('window.__pvzSelesai();');
  }

  void _pesan(String raw) {
    if (!mounted) return;
    Map<String, dynamic> o;
    try {
      o = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (o['t']) {
      case 'engine':
        setState(() {
          _fase = _Fase.engine;
          _byte = (o['b'] as num?)?.toInt() ?? 0;
          _total = (o['total'] as num?)?.toInt() ?? 0;
        });
      case 'siapkan':
        setState(() => _fase = _Fase.siapkan);
      case 'engineSiap':
        _engineSiap = true;
        if (_pvz == null) {
          setState(() => _fase = _Fase.unduhModel);
        } else {
          _kirimModelBilaSiap();
        }
      case 'model':
        setState(() => _fase = _Fase.model);
      case 'siap':
        setState(() => _fase = _Fase.siap);
      case 'log':
        debugPrint('[viewer3d] ${o['m']}');
      case 'gagal':
        setState(() {
          _fase = _Fase.gagal;
          _galat = '${o['m'] ?? 'Engine 3D gagal.'}';
        });
    }
  }

  String _mb(int b) => (b / 1048576).toStringAsFixed(1).replaceAll('.', ',');

  String get _teksStatus => switch (_fase) {
        _Fase.engine => _total > 0
            ? 'Memuat engine 3D… ${_mb(_byte)} / ${_mb(_total)} MB\n(sekali saja, lalu tersimpan di HP)'
            : 'Memuat engine 3D… (sekali saja, ±13 MB)',
        _Fase.siapkan => 'Menyiapkan engine 3D…',
        _Fase.unduhModel => 'Mengunduh model 3D dari EPC…',
        _Fase.model => 'Membuka model 3D…',
        _Fase.siap => '',
        _Fase.gagal => _galat,
      };

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final info = widget.info;
    final ctl = _ctl;
    return Scaffold(
      backgroundColor: m.canvas,
      appBar: AppBar(
        backgroundColor: m.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: m.ink900,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Model 3D',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: m.ink900)),
          Text(info.partNumber,
              style: masMono(size: 11.5, color: m.ink500)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Muat semua ke layar',
            icon: const Icon(Icons.fit_screen_rounded),
            onPressed: _fase == _Fase.siap
                ? () => _ctl?.runJavaScript('window.__zoomSemua();')
                : null,
          ),
          IconButton(
            tooltip: 'Info model',
            icon: Icon(_infoTerbuka ? Icons.info_rounded : Icons.info_outline_rounded),
            onPressed: () => setState(() => _infoTerbuka = !_infoTerbuka),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: m.ink150),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            if (ctl != null) Positioned.fill(child: WebViewWidget(controller: ctl)),
            if (_fase != _Fase.siap) Positioned.fill(child: _lapisStatus(m)),
            if (_fase == _Fase.siap)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: m.paper.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: m.ink150),
                      ),
                      child: Text('1 jari = putar  ·  cubit = zoom',
                          style: TextStyle(fontSize: 11.5, color: m.ink600)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        if (_infoTerbuka) _panelInfo(m, info),
      ]),
    );
  }

  Widget _lapisStatus(MasColors m) {
    final gagal = _fase == _Fase.gagal;
    final persen = (_fase == _Fase.engine && _total > 0) ? (_byte / _total).clamp(0.0, 1.0) : null;
    return Container(
      color: m.canvas,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (gagal)
          Icon(Icons.view_in_ar_rounded, size: 40, color: m.ink300)
        else
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
                strokeWidth: 3, value: persen?.toDouble(), color: m.brand600),
          ),
        const SizedBox(height: 14),
        Text(_teksStatus,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, height: 1.5, color: gagal ? m.danger600 : m.ink600)),
        if (gagal) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              _pvz = null;
              _mulai();
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Coba lagi'),
          ),
        ],
      ]),
    );
  }

  Widget _panelInfo(MasColors m, Part3d info) {
    Widget baris(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$k  ', style: TextStyle(color: m.ink500)),
              TextSpan(text: v, style: TextStyle(color: m.ink900, fontWeight: FontWeight.w500)),
            ]),
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
        );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: m.paper,
        border: Border(top: BorderSide(color: m.ink150)),
      ),
      child: SelectionArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (info.figureNama != null)
            baris('Figure', '${info.figureNama}${info.figurePn != null ? ' (${info.figurePn})' : ''}'),
          if (info.namaItem != null) baris('Item', info.namaItem!),
          if (info.balon != null) baris('Balon', info.balon!),
          if (info.sumberModel != null) baris('Dari model', info.sumberModel!),
          if (info.d3s.length > 1) baris('File', '${info.d3s.length} file, ditampilkan yang pertama'),
          const SizedBox(height: 4),
          Text(
            // Peringatan lintas-model — sama dengan web: figure memuat PN ini,
            // tapi dari model mana pun, bukan unit tertentu.
            '⚠️ Model CAD resmi EPC dari salah satu model pemakai'
            '${info.jumlahModelPemakai != null ? ' (${thousands(info.jumlahModelPemakai!)} model memakai part ini)' : ''}'
            ' — bentuk umum part, bukan jaminan untuk unit tertentu. '
            'Diunduh ulang dari EPC tiap dibuka.',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: m.ink500),
          ),
        ]),
      ),
    );
  }
}
