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
import 'package:webview_flutter/webview_flutter.dart';

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
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
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
            // mengarahkan balik — pembeli menutup sendiri lalu kita polling.
            TextButton(
              onPressed: () => _close(SnapOutcome.selesai),
              child: Text('Sudah Bayar',
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
