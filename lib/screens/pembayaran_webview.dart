// lib/screens/pembayaran_webview.dart
// Halaman pembayaran Midtrans Snap di dalam aplikasi.
//
// Snap adalah halaman web — pembeli memilih sendiri metodenya (VA / QRIS /
// e-wallet / kartu) di sana. Kita cukup memuatnya, lalu mengawasi kapan Snap
// mengarahkan pembeli ke URL selesai/gagal dan menutup WebView.
//
// PENTING: hasil yang dikembalikan halaman ini hanya SINYAL, bukan bukti bayar.
// Kebenaran pembayaran selalu datang dari `ApiService.paymentStatus()` (yang
// dikonfirmasi webhook Midtrans di backend) — layar pemanggil wajib polling.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api_service.dart';
import '../theme/mas_theme.dart';

/// Bagaimana pembeli meninggalkan halaman Snap.
enum SnapOutcome {
  /// Snap mengarahkan ke URL "finish" — kemungkinan besar sudah bayar.
  selesai,

  /// Snap mengarahkan ke URL "error"/"unfinish".
  gagal,

  /// Pembeli menutup sendiri halamannya.
  ditutup,
}

class PembayaranWebView extends StatefulWidget {
  final String url;
  final String orderCode;

  const PembayaranWebView({
    super.key,
    required this.url,
    required this.orderCode,
  });

  @override
  State<PembayaranWebView> createState() => _PembayaranWebViewState();
}

class _PembayaranWebViewState extends State<PembayaranWebView> {
  late final WebViewController _ctl;
  bool _loading = true;

  /// Tombol "Sudah Bayar" sedang menanyakan status ke server.
  bool _mengecek = false;

  /// Skema yang tetap dibuka DI DALAM WebView. Selain ini (gojek://,
  /// shopeeid://, intent://, dst.) adalah aplikasi lain.
  static const _skemaWebView = {'http', 'https', 'about', 'data', 'blob', 'javascript'};

  @override
  void initState() {
    super.initState();
    _ctl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (req) {
            final outcome = _outcomeOf(req.url);
            if (outcome != null) {
              _close(outcome);
              return NavigationDecision.prevent;
            }
            // KL-8 (audit 2026-09-28): Snap mengarahkan GoPay/ShopeePay ke
            // skema aplikasi (gojek://, shopeeid://, intent://…). Dulu
            // di-`navigate` → WebView menampilkan halaman galat dan pembayaran
            // e-wallet gagal. Serahkan ke sistem, WebView tetap di Snap.
            final skema = (Uri.tryParse(req.url)?.scheme ?? '').toLowerCase();
            if (skema.isNotEmpty && !_skemaWebView.contains(skema)) {
              _bukaLuar(req.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  /// Buka tautan aplikasi pembayaran di luar WebView. `intent://` (format
  /// Chrome Android) tak bisa dibuka langsung oleh url_launcher → diurai jadi
  /// skema aplikasi aslinya; aplikasi tak terpasang → `browser_fallback_url`
  /// dimuat di WebView, atau Play Store paketnya.
  Future<void> _bukaLuar(String url) async {
    if (url.toLowerCase().startsWith('intent://')) {
      final it = _uraiIntent(url);
      final aplikasi = it.aplikasi;
      if (aplikasi != null && await _luncurkan(aplikasi)) return;
      final cadangan = it.cadangan;
      final uc = cadangan == null ? null : Uri.tryParse(cadangan);
      if (uc != null && (uc.scheme == 'http' || uc.scheme == 'https')) {
        await _ctl.loadRequest(uc);
        return;
      }
      final paket = it.paket;
      if (paket != null &&
          paket.isNotEmpty &&
          await _luncurkan('market://details?id=$paket')) {
        return;
      }
    } else if (await _luncurkan(url)) {
      return;
    }
    _kabari('Aplikasi pembayaran tidak ditemukan di HP ini. Pilih metode lain '
        '(mis. QRIS atau Virtual Account).');
  }

  Future<bool> _luncurkan(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false; // tak ada aplikasi yang menangani skema ini
    }
  }

  /// `intent://HOST/PATH#Intent;scheme=gojek;package=com.gojek.app;
  /// S.browser_fallback_url=https%3A…;end` → skema aplikasi (`gojek://HOST/
  /// PATH`), nama paket, dan URL cadangan.
  ({String? aplikasi, String? paket, String? cadangan}) _uraiIntent(String url) {
    const tanda = '#Intent;';
    final pagar = url.indexOf(tanda);
    final inti = pagar >= 0 ? url.substring(0, pagar) : url;
    final ekor = pagar >= 0 ? url.substring(pagar + tanda.length) : '';
    String? skema;
    String? paket;
    String? cadangan;
    for (final bagian in ekor.split(';')) {
      final i = bagian.indexOf('=');
      if (i <= 0) continue;
      final k = bagian.substring(0, i);
      final v = bagian.substring(i + 1);
      if (k == 'scheme') {
        skema = v;
      } else if (k == 'package') {
        paket = v;
      } else if (k == 'S.browser_fallback_url') {
        try {
          cadangan = Uri.decodeComponent(v);
        } catch (_) {
          cadangan = v;
        }
      }
    }
    final sisa = inti.length > 'intent://'.length
        ? inti.substring('intent://'.length)
        : '';
    return (
      aplikasi: (skema != null && skema.isNotEmpty) ? '$skema://$sisa' : null,
      paket: paket,
      cadangan: cadangan,
    );
  }

  void _kabari(String pesan) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(pesan)));
  }

  /// "Sudah Bayar": tanya server dulu. Lunas → tutup; belum → pembeli tetap
  /// di halaman bayar dengan penjelasan, bukan dilempar keluar tanpa kabar
  /// (audit 2026-09-28 KL-8).
  Future<void> _sudahBayar() async {
    if (_mengecek) return;
    setState(() => _mengecek = true);
    try {
      final r = await ApiService.paymentStatus(widget.orderCode);
      if (!mounted) return;
      if (r.paid) {
        _close(SnapOutcome.selesai);
        return;
      }
      final err = r.error;
      if (err != null && err.isNotEmpty) {
        _kabari(err);
      } else if (r.status == 'batal') {
        _kabari('Pesanan ini sudah dibatalkan — tutup halaman ini.');
      } else {
        _kabari('Pembayaran belum terdeteksi — tunggu beberapa saat. Bila sudah '
            'membayar lewat bank/VA, tutup halaman ini; status diperbarui otomatis.');
      }
    } on ApiException catch (e) {
      _kabari(e.message);
    } catch (_) {
      _kabari('Status pembayaran gagal dicek. Coba lagi.');
    } finally {
      if (mounted) setState(() => _mengecek = false);
    }
  }

  /// Kenali URL pengalihan Snap. Midtrans memakai `transaction_status` /
  /// `status_code` di query saat kembali ke `finish_url`, dan jalur
  /// `/pesanan/<code>` bila backend memasang callback ke aplikasi web.
  SnapOutcome? _outcomeOf(String url) {
    final u = url.toLowerCase();
    if (u.contains('transaction_status=deny') ||
        u.contains('transaction_status=cancel') ||
        u.contains('transaction_status=expire') ||
        u.contains('/unfinish') ||
        u.contains('/error')) {
      return SnapOutcome.gagal;
    }
    if (u.contains('transaction_status=settlement') ||
        u.contains('transaction_status=capture') ||
        u.contains('transaction_status=pending') ||
        u.contains('/finish') ||
        u.contains('/pesanan/')) {
      return SnapOutcome.selesai;
    }
    return null;
  }

  void _close(SnapOutcome outcome) {
    if (!mounted) return;
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(SnapOutcome.ditutup);
      },
      child: Scaffold(
        backgroundColor: m.canvas,
        appBar: AppBar(
          backgroundColor: m.paper,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close_rounded, color: m.ink800),
            onPressed: () => _close(SnapOutcome.ditutup),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Pembayaran',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: m.ink900)),
              Text(widget.orderCode,
                  style: masMono(size: 11, color: m.ink500)),
            ],
          ),
          actions: [
            // Jalan keluar manual: sebagian metode (mis. VA) tidak pernah
            // mengarahkan balik. Status ditanyakan ke server dulu (KL-8).
            TextButton(
              onPressed: _mengecek ? null : _sudahBayar,
              child: Text(_mengecek ? 'Mengecek…' : 'Sudah Bayar',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: m.brand700)),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: m.ink150),
          ),
        ),
        body: Stack(children: [
          WebViewWidget(controller: _ctl),
          if (_loading)
            Container(
              color: m.canvas,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: m.brand600),
                    const SizedBox(height: 14),
                    Text('Membuka halaman pembayaran aman…',
                        style: TextStyle(fontSize: 12.5, color: m.ink500)),
                  ],
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
