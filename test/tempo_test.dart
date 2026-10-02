// Pembayaran TEMPO (TOP + limit kredit, migrasi 048) — paritas web.
// Status bayar pesanan tempo terpisah dari status kirim: pesanan bisa sudah
// dikirim/selesai padahal tagihannya belum lunas.
import 'package:flutter_test/flutter_test.dart';
import 'package:maspart_mobile/app/nav.dart';
import 'package:maspart_mobile/invoice_pdf.dart';
import 'package:maspart_mobile/models.dart';
import 'package:maspart_mobile/order_ui.dart';
import 'package:maspart_mobile/widgets/mas_ui.dart';

Map<String, dynamic> _tempo({bool lunas = false, String tahap = 'berjalan'}) => {
      'termin_hari': 30,
      'jatuh_tempo': '2026-11-01',
      'hari_lewat': 0,
      'hari_lagi': 30,
      'potongan_retur': 0,
      'sisa_tagihan': lunas ? 0 : 1110000,
      'lunas': lunas,
      'tahap': lunas ? 'lunas' : tahap,
      'bisa_bayar_online': !lunas,
    };

OrderDetail _order({String status = 'dikirim', bool lunas = false, bool tempo = true}) =>
    OrderDetail.fromJson({
      'order_code': 'PO-TEMPO1',
      'status': status,
      'total': 1110000,
      'payment_method': tempo ? 'tempo' : 'gateway',
      'paid_at': lunas ? '2026-10-20T03:00:00+00:00' : null,
      'lunas': tempo ? lunas : true,
      if (tempo) 'tempo': _tempo(lunas: lunas),
      'items': const [],
    });

void main() {
  group('status bayar tempo', () {
    test('tempo dikirim belum lunas → bukan lunas; gateway dikirim → lunas', () {
      expect(sudahLunas(_order()), isFalse);
      expect(sudahLunas(_order(lunas: true)), isTrue);
      expect(sudahLunas(_order(tempo: false)), isTrue);
    });

    test('backend lama tanpa field tempo tetap terbaca', () {
      final o = OrderDetail.fromJson({'order_code': 'PO-LAMA', 'status': 'diproses', 'items': const []});
      expect(o.isTempo, isFalse);
      expect(o.tempo, isNull);
      expect(sudahLunas(o), isTrue);
    });

    test('daftar pesanan: lunas hanya dikirim untuk baris tempo', () {
      final s = OrderSummary.fromJson({
        'order_code': 'PO-X', 'status': 'selesai', 'payment_method': 'tempo',
        'lunas': false, 'tempo': _tempo(tahap: 'lewat'),
      });
      expect(s.isTempo, isTrue);
      expect(s.lunasTempo, isFalse);
      expect(lencanaTempo(s.tempo)!.$2, MasPillTone.danger);
    });
  });

  group('stepper', () {
    test('tempo: Pesanan Tempo → Dikirim → Selesai → Lunas', () {
      final p = orderProgress('selesai', tempoLunas: false);
      expect(p.map((x) => x.label).toList(), ['Pesanan Tempo', 'Dikirim', 'Selesai', 'Lunas']);
      expect(p.last.done, isFalse);
      expect(orderProgress('dikirim', tempoLunas: true).last.done, isTrue);
    });

    test('bukan tempo: urutan lama tak berubah', () {
      expect(orderProgress('diproses').first.label, 'Dibayar');
    });
  });

  group('invoice', () {
    test('tempo belum lunas → cap BELUM LUNAS + baris jatuh tempo', () {
      final o = _order();
      expect(invoiceTersedia(o), isTrue);
      expect(capInvoice(o), 'BELUM LUNAS');
      expect(infoBayar(o).$1, 'Jatuh Tempo');
      expect(infoBayar(o).$2, '1 November 2026');
    });

    test('tempo lunas → cap LUNAS + tanggal bayar', () {
      final o = _order(lunas: true);
      expect(capInvoice(o), 'LUNAS');
      expect(infoBayar(o).$1, 'Tanggal Bayar');
    });
  });

  group('navigasi', () {
    test('menu Tagihan Tempo hanya untuk akun tempo', () {
      bool ada(bool tempo) => buildNavSections(role: 'pembeli', allowed: null, tempoAktif: tempo)
          .expand((s) => s.items)
          .any((it) => it.screen == MasScreen.tagihanTempo);
      expect(ada(false), isFalse);
      expect(ada(true), isTrue);
    });

    test('layar Tagihan Tempo tetap bisa dibuka dari notifikasi walau menu tersembunyi', () {
      final akses = accessibleScreens(buildNavSections(role: 'pembeli', allowed: null));
      expect(akses.contains(MasScreen.tagihanTempo), isTrue);
    });

    test('tautan pengingat jatuh tempo & piutang admin', () {
      expect(tujuanTautan('/tagihan-tempo')!.$1, MasScreen.tagihanTempo);
      expect(tujuanTautan('/admin/piutang')!.$1, MasScreen.piutang);
    });

    test('Piutang Tempo ada di menu Penjualan admin', () {
      final s = buildNavSections(role: 'admin', allowed: null);
      expect(s.expand((x) => x.items).any((it) => it.screen == MasScreen.piutang), isTrue);
    });
  });
}
