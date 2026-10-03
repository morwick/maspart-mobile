// Centang checkout keranjang (pola Shopee, paritas web getPilihan/setPilihan).

import 'package:flutter_test/flutter_test.dart';
import 'package:maspart_mobile/cart.dart';
import 'package:maspart_mobile/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.reset();
  });

  test('pilihan hanya PN yang masih di keranjang, urutan keranjang', () async {
    final c = CartStore.instance;
    await c.load('budi');
    await c.addMany(const [
      CartItem(partNumber: 'A', qty: 1),
      CartItem(partNumber: 'B', qty: 2),
      CartItem(partNumber: 'C', qty: 1),
    ]);
    await c.setPilihan(['C', 'A', 'X', 'A']);
    expect(c.pilihan, ['A', 'C']);
    expect(c.itemsTerpilih.map((i) => i.partNumber), ['A', 'C']);
  });

  test('hapus dari keranjang ikut melepas centang', () async {
    final c = CartStore.instance;
    await c.load('budi');
    await c.addMany(const [
      CartItem(partNumber: 'A'),
      CartItem(partNumber: 'B'),
    ]);
    await c.setPilihan(['A', 'B']);
    await c.removeAll(['A']);
    await c.add(const CartItem(partNumber: 'A'));
    // Dimasukkan lagi → tidak otomatis tercentang.
    expect(c.pilihan, ['B']);
  });

  test('centang disimpan per-username', () async {
    final c = CartStore.instance;
    await c.load('budi');
    await c.add(const CartItem(partNumber: 'A'));
    await c.setPilihan(['A']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('maspart_cart_pilih_budi'), '["A"]');

    c.reset();
    await c.load('ani');
    expect(c.pilihan, isEmpty);

    c.reset();
    await c.load('budi');
    expect(c.pilihan, ['A']);
  });

  test('CartGudangItem membaca foto (nullable)', () {
    expect(CartGudangItem.fromJson({'part_number': 'A', 'foto': null}).foto, isNull);
    expect(CartGudangItem.fromJson({'part_number': 'A'}).foto, isNull);
    expect(CartGudangItem.fromJson({'part_number': 'A', 'foto': '/img/a.jpg'}).foto,
        '/img/a.jpg');
  });
}
