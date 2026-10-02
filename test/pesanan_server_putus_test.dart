// Detail pesanan saat server API MATI lalu pulih (uji 2026-10-02: pembeli bayar
// tepat saat server down → uangnya tetap masuk & dilunasi server begitu pulih).
// Layar tak boleh bilang "Pesanan tidak ditemukan" untuk pesanan yang ADA, harus
// pulih SENDIRI tanpa pembeli menekan apa pun, dan tak menyisakan banner galat.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maspart_mobile/app/nav.dart';
import 'package:maspart_mobile/auth_storage.dart';
import 'package:maspart_mobile/screens/pesanan_detail_screen.dart';
import 'package:maspart_mobile/theme/mas_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _kode = 'PO-UJIUI001';

/// Server tiruan: [hidup] false = koneksi ditolak (seperti server mati).
class _Server {
  bool hidup = true;
  bool ada = true;
  String status = 'menunggu_pembayaran';
  bool paid = false;

  Map<String, dynamic> get _order => {
        'order_code': _kode, 'username': 'uji_ui', 'gudang': '', 'total': 25000,
        'subtotal': 25000, 'status': status, 'created_at': '2026-10-02T03:00:00Z',
        'payment_method': 'gateway', 'payment_channel': 'va_bni',
        'payment_va': '8808123456789', 'payment_expiry': '2099-10-03T03:00:00Z',
        'items': [
          {'part_number': '612600081335', 'name': 'Filter Oli', 'price': 25000,
           'qty': 1, 'line_total': 25000},
        ],
      };

  late final client = MockClient((req) async {
    if (!hidup) throw http.ClientException('Connection refused', req.url);
    final p = req.url.path;
    http.Response json(Object o, [int code = 200]) =>
        http.Response(jsonEncode(o), code, headers: {'content-type': 'application/json'});
    if (p == '/api/orders/$_kode') {
      return ada ? json(_order) : json({'detail': 'Pesanan tidak ditemukan.'}, 404);
    }
    if (p.endsWith('/payment/status')) return json({'status': status, 'paid': paid});
    if (p.endsWith('/chat')) {
      return json({'role': 'pembeli', 'gudang': '', 'buyer': 'uji_ui', 'messages': []});
    }
    return json({'detail': 'tak ada di server tiruan'}, 404);
  });
}

Widget _app(Widget child) => MaterialApp(
      theme: buildMasTheme(Brightness.light),
      home: Builder(
        builder: (context) => AppNav(
          screen: MasScreen.pesanan,
          selectedPart: const {'order_code': _kode},
          username: 'uji_ui',
          role: 'pembeli',
          accessible: const {},
          go: (_, {part}) {},
          back: () {},
          canBack: false,
          openDrawer: () {},
          closeDrawer: () {},
          toast: (_, {actionLabel, onAction}) {},
          logout: () {},
          child: Scaffold(body: child),
        ),
      ),
    );

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'MasPart', packageName: 'uji', version: '1.0.0', buildNumber: '1',
        buildSignature: '');
    await AuthStorage.saveToken('tok-uji');
  });

  Future<void> jalankan(WidgetTester tester, _Server s, Future<void> Function() body) =>
      http.runWithClient(() async {
        await tester.pumpWidget(_app(const PesananDetailScreen(args: {'order_code': _kode})));
        await tester.pump();
        await tester.pump();
        await body();
        // Bongkar layar → semua Timer polling ikut dibatalkan.
        await tester.pumpWidget(const SizedBox());
      }, () => s.client);

  testWidgets('dibuka saat server mati → bukan "tidak ditemukan", pulih sendiri', (tester) async {
    final s = _Server()..hidup = false;
    await jalankan(tester, s, () async {
      expect(find.text('Tidak bisa terhubung ke server'), findsOneWidget);
      expect(find.text('Pesanan tidak ditemukan'), findsNothing);

      // Pembeli membayar selama server mati; server lalu hidup & sudah melunasi.
      s
        ..hidup = true
        ..status = 'diproses'
        ..paid = true;
      await tester.pump(const Duration(seconds: 9));   // muat ulang otomatis (8 dtk)
      await tester.pump();
      expect(find.textContaining('Pembayaran terverifikasi'), findsOneWidget);
      expect(find.textContaining('terputus'), findsNothing);   // tak ada banner sisa
    });
  });

  testWidgets('tombol Coba Lagi memuat ulang', (tester) async {
    final s = _Server()..hidup = false;
    await jalankan(tester, s, () async {
      s.hidup = true;
      await tester.tap(find.text('Coba Lagi'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Tidak bisa terhubung ke server'), findsNothing);
      expect(find.text('PO-UJIUI001'), findsWidgets);
    });
  });

  testWidgets('polling saat server mati → pesan netral; pulih → lunas & pesan hilang',
      (tester) async {
    final s = _Server();
    await jalankan(tester, s, () async {
      expect(find.text('PO-UJIUI001'), findsWidgets);
      s.hidup = false;
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      expect(find.textContaining('Koneksi ke server MasPart terputus'), findsOneWidget);
      expect(find.textContaining('periksa internet'), findsNothing);

      s
        ..hidup = true
        ..status = 'diproses'
        ..paid = true;
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Pembayaran terverifikasi'), findsOneWidget);
      expect(find.textContaining('terputus'), findsNothing);
    });
  });

  testWidgets('404 sungguhan tetap "Pesanan tidak ditemukan"', (tester) async {
    final s = _Server()..ada = false;
    await jalankan(tester, s, () async {
      expect(find.text('Pesanan tidak ditemukan'), findsOneWidget);
      expect(find.text('Tidak bisa terhubung ke server'), findsNothing);
    });
  });
}
