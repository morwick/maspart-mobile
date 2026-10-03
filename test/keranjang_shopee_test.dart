// Keranjang ala Shopee (2026-10-03, paritas web /keranjang): daftar per gudang +
// centang, SATU pesanan = SATU gudang, lalu Checkout hanya membawa yang dicentang.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maspart_mobile/app/nav.dart';
import 'package:maspart_mobile/auth_storage.dart';
import 'package:maspart_mobile/cart.dart';
import 'package:maspart_mobile/screens/checkout_screen.dart';
import 'package:maspart_mobile/screens/keranjang_screen.dart';
import 'package:maspart_mobile/theme/mas_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Server tiruan: A & B di gudang Jakarta, C di gudang Surabaya.
final _client = MockClient((req) async {
  http.Response json(Object o, [int code = 200]) =>
      http.Response(jsonEncode(o), code, headers: {'content-type': 'application/json'});
  final p = req.url.path;
  if (p == '/api/buyer/alamat') {
    return json({
      'alamat': [
        {'id': 1, 'nama_penerima': 'Uji', 'telepon': '081234567890',
         'kode_pos': '10110', 'alamat': 'Jl. Uji No. 1', 'kota': 'Jakarta',
         'is_default': true},
      ],
    });
  }
  if (p == '/api/cart/gudang') {
    final body = jsonDecode(req.body) as Map;
    final g = {'A': 'Jakarta', 'B': 'Jakarta', 'C': 'Surabaya'};
    return json({
      'items': [
        for (final it in (body['items'] as List).cast<Map>())
          {
            'part_number': it['part_number'],
            'gudang': g[it['part_number']] ?? '',
            'harga': 10000,
            'harga_display': 'Rp 10.000',
            'berat': 1000,
            'bisa_dibeli': true,
            'alasan': '',
            'stok': 5,
            'foto': null,
          },
      ],
      'utama': 'Jakarta',
      'multi': true,
    });
  }
  if (p == '/api/payments/methods') {
    return json({'gateway_available': true, 'provider': 'midtrans', 'channels': []});
  }
  return json({'detail': 'tak ada di server tiruan'}, 404);
});

void main() {
  late List<MasScreen> tujuan;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'MasPart', packageName: 'uji', version: '1.0.0', buildNumber: '1',
        buildSignature: '');
    await AuthStorage.saveToken('tok-uji');
    tujuan = [];
    final c = CartStore.instance..reset();
    await c.load('uji_ui');
    await c.addMany(const [
      CartItem(partNumber: 'A', name: 'Filter Oli', harga: 'Rp 10.000', qty: 2),
      CartItem(partNumber: 'B', name: 'Filter Solar', harga: 'Rp 10.000'),
      CartItem(partNumber: 'C', name: 'Filter Udara', harga: 'Rp 10.000'),
    ]);
  });

  Widget app(Widget child) => MaterialApp(
        theme: buildMasTheme(Brightness.light),
        home: Builder(
          builder: (context) => AppNav(
            screen: MasScreen.keranjang,
            selectedPart: null,
            username: 'uji_ui',
            role: 'pembeli',
            accessible: const {},
            go: (s, {part}) => tujuan.add(s),
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

  Future<void> jalankan(WidgetTester tester, Widget layar, Future<void> Function() body) async {
    // Ukuran HP kecil — memastikan baris & bilah bawah tak meluap.
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(app(layar));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450)); // debounce /cart/gudang
      await tester.pump();
      await body();
      await tester.pumpWidget(const SizedBox());
    }, () => _client);
  }

  testWidgets('dikelompokkan per gudang; centang gudang lain melepas gudang lama',
      (tester) async {
    await jalankan(tester, const KeranjangScreen(), () async {
      expect(find.text('Gudang Jakarta'), findsOneWidget);
      expect(find.text('Gudang Surabaya', skipOffstage: false), findsOneWidget);
      expect(find.text('Pilih per gudang'), findsOneWidget);
      // Default Shopee: belum ada yang dicentang.
      expect(find.text('Checkout'), findsOneWidget);

      // Centang semua Jakarta (checkbox kepala grup pertama).
      final cek = find.byType(Checkbox);
      await tester.tap(cek.at(0));
      await tester.pump();
      expect(CartStore.instance.pilihan, ['A', 'B']);
      expect(find.text('Checkout (2)'), findsOneWidget);
      expect(find.text('Total (2 produk, 3 pcs)'), findsOneWidget);

      // Centang C (Surabaya) → centang Jakarta dilepas + info.
      final surabaya = find.text('Gudang Surabaya', skipOffstage: false);
      await tester.ensureVisible(surabaya);
      await tester.pump();
      final cekS = find.descendant(
          of: find.ancestor(of: surabaya, matching: find.byType(Row)).first,
          matching: find.byType(Checkbox));
      await tester.tap(cekS);
      await tester.pump();
      expect(CartStore.instance.pilihan, ['C']);
      // Info ada di puncak daftar — gulir kembali ke atas.
      await tester.drag(find.byType(ListView), const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(find.textContaining('Satu pesanan hanya dari satu gudang', skipOffstage: false),
          findsOneWidget);

      await tester.tap(find.text('Checkout (1)'));
      await tester.pump();
      expect(tujuan, [MasScreen.checkout]);
    });
  });

  testWidgets('checkout hanya menampilkan part yang dicentang (hanya-baca)',
      (tester) async {
    await CartStore.instance.setPilihan(['B']);
    await jalankan(tester, const CheckoutScreen(), () async {
      expect(find.text('Produk Dipesan'), findsOneWidget);
      expect(find.text('Filter Solar'), findsOneWidget);
      expect(find.text('Filter Oli'), findsNothing);
      expect(find.text('Filter Udara'), findsNothing);
      expect(find.text('Kembali ke Keranjang'), findsOneWidget);
    });
  });

  testWidgets('checkout tanpa centang → arahkan kembali ke keranjang', (tester) async {
    await jalankan(tester, const CheckoutScreen(), () async {
      expect(find.text('Belum ada part yang dipilih untuk checkout.'), findsOneWidget);
      await tester.tap(find.text('Pilih di Keranjang'));
      await tester.pump();
      expect(tujuan, [MasScreen.keranjang]);
    });
  });
}
