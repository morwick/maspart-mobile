// Invoice PDF (lib/invoice_pdf.dart) — isi yang harus kembar dengan web
// (frontend/src/lib/invoice-format.ts): terbilang, tanggal WIB, urutan biaya.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maspart_mobile/invoice_pdf.dart';
import 'package:maspart_mobile/models.dart';

OrderDetail _order({Map<String, dynamic> lain = const {}}) => OrderDetail.fromJson({
      'order_code': 'MP-20261001-7Q4K',
      'status': 'dikirim',
      'username': 'riski',
      'created_at': '2026-10-01T02:12:00+00:00',
      'paid_at': '2026-10-01T02:20:00+00:00',
      'payment_method': 'gateway',
      'payment_channel': 'va_bca',
      'recipient_name': 'Riski Kurniawan',
      'recipient_phone': '081364392661',
      'recipient_address': 'Jl. Bambu Kuning No. 12, Rumbai Barat, Pekanbaru, Riau',
      'recipient_postal': '28264',
      'gudang': 'Pekanbaru',
      'gudang_pic': 'Andi (0812-7000-1234)',
      'courier': 'jne',
      'courier_service': 'REG',
      'shipping_cost': 56700,
      'tracking_no': 'JNE0123456789',
      'voucher_codes': 'HEMAT10',
      'items': [
        {'part_number': 'WG9725310020', 'name': '62160 Universal joint assembly (Ordinary type)', 'price': 1025000, 'qty': 1, 'line_total': 1025000},
        {'part_number': 'WG9100360910', 'name': '27/27 Brake chamber (L=70)', 'price': 2050000, 'qty': 2, 'line_total': 4100000},
        {'part_number': 'VG1095094002', 'name': '28V / 70A AC generator', 'price': 4150000, 'qty': 1, 'line_total': 4150000},
      ],
      'subtotal': 9275000,
      'voucher_discount': 100000,
      'point_discount': 25000,
      'point_redeemed': 25000,
      'tax': 1006500,
      'shipping_discount': 10000,
      'total': 10203200,
      ...lain,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('terbilang rupiah', () {
    expect(terbilang(0), 'Nol Rupiah');
    expect(terbilang(11), 'Sebelas Rupiah');
    expect(terbilang(1000), 'Seribu Rupiah');
    expect(terbilang(115), 'Seratus Lima Belas Rupiah');
    expect(terbilang(2000000), 'Dua Juta Rupiah');
    expect(terbilang(10203200), 'Sepuluh Juta Dua Ratus Tiga Ribu Dua Ratus Rupiah');
    expect(terbilang(1001000000), 'Satu Miliar Satu Juta Rupiah');
  });

  test('tanggal invoice selalu WIB, apa pun zona HP', () {
    expect(tanggalInvoice('2026-10-01T02:12:00+00:00'), '1 Oktober 2026, 09.12 WIB');
    expect(tanggalInvoice('2026-12-31T20:05:00Z'), '1 Januari 2027, 03.05 WIB');
    expect(tanggalInvoice('2026-10-01T02:12:00'), '1 Oktober 2026, 09.12 WIB'); // tanpa zona = UTC
    expect(tanggalInvoice(null), '-');
  });

  test('urutan biaya PPN ditambahkan: potongan barang → PPN → ongkir → voucher ongkir', () {
    final label = barisBiaya(_order()).map((b) => b.label).toList();
    expect(label, [
      'Subtotal Produk',
      'Voucher Diskon',
      'Potongan Poin (25.000 poin)',
      'PPN 12% (DPP 11/12)',
      'Ongkos Kirim (JNE REG)',
      'Voucher Gratis Ongkir',
    ]);
  });

  test('ambil di toko: ongkir Gratis', () {
    final o = _order(lain: {
      'pickup': true, 'pickup_gudang': 'Pekanbaru', 'courier': null, 'shipping_cost': 0,
      'shipping_discount': 0, 'total': 10156500,
    });
    final ongkir = barisBiaya(o).firstWhere((b) => b.label.startsWith('Ongkos Kirim'));
    expect(ongkir.label, 'Ongkos Kirim (ambil sendiri)');
    expect(ongkir.jumlah, isNull);
    expect(ongkir.teks, 'Gratis');
  });

  test('PDF terbentuk, termasuk pesanan panjang beberapa halaman', () async {
    final pdf = await buildInvoicePdf(_order());
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    final banyak = _order(lain: {
      'items': [
        for (var i = 0; i < 40; i++)
          {'part_number': 'WG97253100$i', 'name': 'Brake chamber assembly kanan (Right, L=40) untuk HOWO A7', 'price': 125000, 'qty': 1, 'line_total': 125000},
      ],
    });
    final pdf2 = await buildInvoicePdf(banyak);
    final keluar = Platform.environment['INVOICE_PDF_OUT'];
    if (keluar != null) {
      File('$keluar/mobile-1.pdf').writeAsBytesSync(pdf);
      File('$keluar/mobile-banyak.pdf').writeAsBytesSync(pdf2);
    }
    expect(pdf2.length, greaterThan(pdf.length));
  });
}
