// Tautan notifikasi (lonceng & push, termasuk siaran promo /admin/promo-push)
// → layar aplikasi. Path yang tak dikenal harus null (tak membuka apa pun),
// bukan melempar.
import 'package:flutter_test/flutter_test.dart';
import 'package:maspart_mobile/app/nav.dart';

void main() {
  test('tujuan promo dipetakan ke layar pembeli', () {
    expect(tujuanTautan('/toko')?.$1, MasScreen.toko);
    expect(tujuanTautan('/voucher')?.$1, MasScreen.voucher);
    expect(tujuanTautan('/keranjang')?.$1, MasScreen.keranjang);
    expect(tujuanTautan('/keranjang/checkout')?.$1, MasScreen.checkout);
    expect(tujuanTautan('/beli-lagi')?.$1, MasScreen.beliLagi);
    expect(tujuanTautan('/poin')?.$1, MasScreen.poin);
    final part = tujuanTautan('/part/WG%209725520274');
    expect(part?.$1, MasScreen.part);
    expect(part?.$2, {'part_number': 'WG 9725520274'});
  });

  test('tautan lama tetap & tak dikenal = null', () {
    expect(tujuanTautan('/pesanan/PO-1')?.$2, {'order_code': 'PO-1'});
    expect(tujuanTautan('/admin/users'), isNull);
    expect(tujuanTautan(''), isNull);
    expect(tujuanTautan(null), isNull);
  });
}
