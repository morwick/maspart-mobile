// lib/invoice_pdf.dart — buat & buka Invoice PDF pesanan LUNAS.
//
// Setara halaman invoice web (`frontend/src/app/pesanan/[code]/invoice`): lembar
// invoice dirender dari data OrderDetail lalu diunduh sebagai PDF. Di sini PDF
// dibuat sepenuhnya di sisi klien (paket `pdf`, murni Dart — tanpa plugin
// native), disimpan ke folder sementara, lalu dibuka dengan penampil sistem.
//
// PPN sadar aturan (lihat `ppnDitambahkan` di order_ui.dart): pesanan baru →
// PPN 12% (DPP 11/12) DITAMBAHKAN di atas barang (ikut Accurate); pesanan lama
// ber-PPN inklusif → tetap "Subtotal Produk (termasuk PPN)" seperti dulu.
// TOTAL selalu `o.total` tersimpan, tak pernah dihitung ulang.
//
// Tata letak KEMBAR dengan web (frontend/src/lib/invoice-pdf.ts): kop surat
// resmi PT. Mas Automobil Sejahtera → judul + cap LUNAS → info pembayaran →
// pihak → tabel barang → terbilang & ringkasan → catatan; kaki halaman +
// tanda air di tiap halaman. Ubah keduanya bersamaan.

import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';
import 'order_ui.dart';
import 'perusahaan.dart';
import 'utils.dart';

/// Status pesanan yang dianggap LUNAS — invoice hanya sah setelahnya.
const _paid = {'diproses', 'dikirim', 'selesai'};

bool invoiceTersedia(OrderDetail o) => _paid.contains(o.status);

/// Label metode pembayaran (persis web `labelBayar`).
String _payLabel(OrderDetail o) {
  if (o.paymentMethod == 'manual') return 'Transfer Manual';
  final ch = (o.paymentChannel ?? '').toLowerCase();
  if (ch.isEmpty) return '-';
  // 'snap' = halaman Midtrans (pesanan lama); 'qris' / 'va_<bank>' = RajaOngkir.
  // Satu sumber label dengan layar pesanan (paritas web `labelKanalBayar`).
  return labelKanalBayar(ch);
}

String _courierLabel(OrderDetail o) {
  // Pesanan ambil sendiri tak berkurir — sebut gudang pengambilannya (harus
  // berbunyi sama dengan invoice web). '-' biasa, bukan '—': Helvetica bawaan
  // PDF (Latin-1) tak punya glyph em dash.
  if (o.pickup) {
    final g = (o.pickupGudang ?? '').trim();
    return 'Ambil di Toko${g.isEmpty ? '' : ' - Gudang $g'}';
  }
  final c = (o.courier ?? '').trim();
  if (c.isEmpty) return '-';
  final s = (o.courierService ?? '').trim();
  return c.toUpperCase() + (s.isEmpty ? '' : ' $s');
}

const _bulan = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

/// "1 Oktober 2026, 09.12 WIB" — jam dinding kantor (Pekanbaru, WIB), tak
/// tergantung zona waktu HP pembeli (paritas web `tanggalInvoice`).
String tanggalInvoice(String? s) {
  if (s == null || s.isEmpty) return '-';
  final adaZona =
      RegExp(r'[zZ]$').hasMatch(s) || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
  final d = DateTime.tryParse(adaZona ? s : '${s}Z');
  if (d == null) return '-';
  final w = d.toUtc().add(const Duration(hours: 7));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${w.day} ${_bulan[w.month - 1]} ${w.year}, ${two(w.hour)}.${two(w.minute)} WIB';
}

// ── Terbilang (paritas web `terbilang`) ────────────────────────────────────
const _satuan = [
  '', 'satu', 'dua', 'tiga', 'empat', 'lima', 'enam', 'tujuh', 'delapan',
  'sembilan', 'sepuluh', 'sebelas',
];

String _eja(int n) {
  if (n < 12) return _satuan[n];
  if (n < 20) return '${_eja(n - 10)} belas';
  if (n < 100) return '${_eja(n ~/ 10)} puluh ${_eja(n % 10)}';
  if (n < 200) return 'seratus ${_eja(n - 100)}';
  if (n < 1000) return '${_eja(n ~/ 100)} ratus ${_eja(n % 100)}';
  if (n < 2000) return 'seribu ${_eja(n - 1000)}';
  if (n < 1000000) return '${_eja(n ~/ 1000)} ribu ${_eja(n % 1000)}';
  for (final (nilai, nama) in const [
    (1000000000000, 'triliun'),
    (1000000000, 'miliar'),
    (1000000, 'juta'),
  ]) {
    if (n >= nilai) return '${_eja(n ~/ nilai)} $nama ${_eja(n % nilai)}';
  }
  return '';
}

/// 10203200 → "Sepuluh Juta Dua Ratus Tiga Ribu Dua Ratus Rupiah".
String terbilang(num n) {
  final bulat = n.abs().round();
  final kata = bulat == 0 ? 'nol' : _eja(bulat);
  return '$kata rupiah'
      .split(RegExp(r'\s+'))
      .where((k) => k.isNotEmpty)
      .map((k) => k[0].toUpperCase() + k.substring(1))
      .join(' ');
}

/// Baris ringkasan di atas TOTAL, berurutan (paritas web `barisBiaya`).
/// [jumlah] null → tampilkan [teks] apa adanya.
List<({String label, num? jumlah, String teks, bool potongan})> barisBiaya(
    OrderDetail o) {
  final ppn = barisPpn(o);
  final voucher = [
    if (o.voucherDiscount > 0)
      (label: 'Voucher Diskon', jumlah: o.voucherDiscount as num?, teks: '', potongan: true),
  ];
  final poin = [
    if (o.pointDiscount > 0)
      (
        label: 'Potongan Poin (${thousands(o.pointRedeemed)} poin)',
        jumlah: o.pointDiscount as num?,
        teks: '',
        potongan: true,
      ),
  ];
  final ongkir = (
    label:
        'Ongkos Kirim${o.pickup ? ' (ambil sendiri)' : (o.courier ?? '').isNotEmpty ? ' (${_courierLabel(o)})' : ''}',
    jumlah: o.pickup || o.shippingCost <= 0 ? null : o.shippingCost as num?,
    teks: o.pickup ? 'Gratis' : '-',
    potongan: false,
  );
  final vOngkir = [
    if (o.shippingDiscount > 0)
      (label: 'Voucher Gratis Ongkir', jumlah: o.shippingDiscount as num?, teks: '', potongan: true),
  ];
  if (ppn.ditambahkan) {
    // Urutan ala Accurate: potongan barang (voucher & poin) dulu, lalu PPN
    // atas barang setelah potongan, lalu ongkir & voucher ongkir.
    return [
      (label: 'Subtotal Produk', jumlah: o.subtotal, teks: '', potongan: false),
      ...voucher,
      ...poin,
      (label: 'PPN 12% (DPP 11/12)', jumlah: ppn.nilai, teks: '', potongan: false),
      ongkir,
      ...vOngkir,
    ];
  }
  // Pesanan lama (PPN inklusif) — label & tata letak semula.
  return [
    (label: 'Subtotal Produk (termasuk PPN)', jumlah: o.subtotal, teks: '', potongan: false),
    if (ppn.nilai > 0)
      (label: 'di dalamnya PPN 12%', jumlah: ppn.nilai, teks: '', potongan: false),
    ongkir,
    ...voucher,
    ...vOngkir,
    ...poin,
  ];
}

Future<pw.MemoryImage?> _aset(String path) async {
  try {
    return pw.MemoryImage((await rootBundle.load(path)).buffer.asUint8List());
  } catch (_) {
    return null; // PDF tetap jadi, tanpa logo
  }
}

/// Bangun byte PDF invoice dari [o]. Dipisah agar bisa diuji tanpa I/O.
Future<List<int>> buildInvoicePdf(OrderDetail o) async {
  final doc = pw.Document(title: 'Invoice ${o.orderCode}', author: Perusahaan.nama);
  final logo = await _aset(Perusahaan.logo);
  final tandaAir = await _aset(Perusahaan.tandaAir);

  // Warna selaras design system MasPart (sama dengan PDF web).
  const brand = PdfColor.fromInt(0xFF026A0E);
  const brand50 = PdfColor.fromInt(0xFFECF6EE);
  const ink900 = PdfColor.fromInt(0xFF0F1411);
  const ink600 = PdfColor.fromInt(0xFF535B56);
  const ink400 = PdfColor.fromInt(0xFF8C948F);
  const line = PdfColor.fromInt(0xFFE1E4E1);
  const zebra = PdfColor.fromInt(0xFFF8FAF8);
  const putih = PdfColors.white;

  pw.TextStyle gaya(double size,
          {bool bold = false, bool italic = false, PdfColor color = ink900}) =>
      pw.TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
      );

  pw.Widget labelKecil(String s, {PdfColor color = ink400}) =>
      pw.Text(s.toUpperCase(), style: gaya(6.5, bold: true, color: color));

  // ── Kop surat ──────────────────────────────────────────────────────────
  final kop = pw.Column(children: [
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      if (logo != null) ...[
        pw.Image(logo, width: 113), // 40 mm
        pw.SizedBox(width: 17),
      ],
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(Perusahaan.nama, style: gaya(15, bold: true)),
          pw.SizedBox(height: 3),
          pw.Text(Perusahaan.alamat, style: gaya(8.5, color: ink600)),
          pw.Text(Perusahaan.kota, style: gaya(8.5, color: ink600)),
          pw.Text('Telp. ${Perusahaan.telepon}   ·   Email: ${Perusahaan.email}',
              style: gaya(8.5, color: ink600)),
        ]),
      ),
    ]),
    pw.SizedBox(height: 8),
    // Garis ganda (tebal + tipis) khas kop surat.
    pw.Container(height: 2, color: ink900),
    pw.SizedBox(height: 1.2),
    pw.Container(height: 0.6, color: ink900),
  ]);

  // ── Judul + cap LUNAS ──────────────────────────────────────────────────
  final judul = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('INVOICE', style: gaya(20, bold: true, color: brand)),
        pw.SizedBox(height: 3),
        pw.Text('No. ${o.orderCode}', style: gaya(10, color: ink600)),
      ]),
      // Cap LUNAS: bingkai ganda gaya stempel. Radius kecil — ⛔ JANGAN
      // circular(999): paket `pdf` tak membatasi radius ke setengah tinggi
      // kotak → busur raksasa menutupi kepala invoice.
      pw.Container(
        padding: const pw.EdgeInsets.all(2.5),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: brand, width: 1.7),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Container(
          width: 74,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: brand, width: 0.6),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Text('LUNAS', style: gaya(12, bold: true, color: brand)),
        ),
      ),
    ],
  );

  // ── Info pembayaran ────────────────────────────────────────────────────
  pw.Widget info(String k, String v) => pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          labelKecil(k),
          pw.SizedBox(height: 3),
          pw.Text(v, style: gaya(9.5, bold: true)),
        ]),
      );
  final kotakInfo = pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: pw.BoxDecoration(color: brand50, borderRadius: pw.BorderRadius.circular(4)),
    child: pw.Row(children: [
      info('Tanggal Pesanan', tanggalInvoice(o.createdAt)),
      info('Tanggal Bayar', tanggalInvoice(o.paidAt)),
      info('Metode Pembayaran', _payLabel(o)),
    ]),
  );

  // ── Pihak ──────────────────────────────────────────────────────────────
  pw.Widget pihak(String judul, List<String> baris) => pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          labelKecil(judul, color: brand),
          pw.SizedBox(height: 3),
          pw.Container(height: 1.1, color: brand),
          pw.SizedBox(height: 6),
          for (var i = 0; i < baris.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1.5),
              child: pw.Text(baris[i],
                  style: i == 0 ? gaya(10.5, bold: true) : gaya(9, color: ink600)),
            ),
        ]),
      );
  final namaPenerima = (o.recipientName ?? '').isNotEmpty
      ? o.recipientName!
      : (o.username.isNotEmpty ? o.username : '-');
  final kotakPihak = pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pihak('Ditagihkan kepada', [
      namaPenerima,
      if ((o.recipientPhone ?? '').isNotEmpty) o.recipientPhone!,
      if ((o.recipientAddress ?? '').isNotEmpty)
        [o.recipientAddress!, if ((o.recipientPostal ?? '').isNotEmpty) o.recipientPostal!]
            .join(', '),
    ]),
    pw.SizedBox(width: 23),
    pihak(o.pickup ? 'Diambil di' : 'Dikirim dari', [
      'Gudang ${o.gudang.isEmpty ? '-' : o.gudang}',
      if ((o.gudangPic ?? '').isNotEmpty) 'PIC: ${o.gudangPic}',
      o.pickup ? 'Diambil sendiri oleh pembeli' : 'Ekspedisi: ${_courierLabel(o)}',
      if ((o.trackingNo ?? '').isNotEmpty) 'No. Resi: ${o.trackingNo}',
    ]),
  ]);

  // ── Tabel barang ───────────────────────────────────────────────────────
  pw.Widget sel(String s,
          {pw.TextAlign align = pw.TextAlign.left,
          bool bold = false,
          bool mono = false,
          PdfColor color = ink900}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 7),
        child: pw.Text(s,
            textAlign: align,
            style: mono
                ? pw.TextStyle(font: pw.Font.courier(), fontSize: 8.6, color: color)
                : gaya(8.8, bold: bold, color: color)),
      );
  const c = pw.TextAlign.center, r = pw.TextAlign.right;
  final tabel = pw.Table(
    columnWidths: const {
      0: pw.FixedColumnWidth(28),
      1: pw.FixedColumnWidth(96),
      2: pw.FlexColumnWidth(),
      3: pw.FixedColumnWidth(37),
      4: pw.FixedColumnWidth(85),
      5: pw.FixedColumnWidth(91),
    },
    border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: line, width: 0.6),
        bottom: pw.BorderSide(color: line, width: 0.6)),
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: [
      // repeat: kepala tabel muncul lagi di halaman lanjutan.
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: brand),
        children: [
          sel('No', align: c, bold: true, color: putih),
          sel('Part Number', bold: true, color: putih),
          sel('Nama Barang', bold: true, color: putih),
          sel('Qty', align: c, bold: true, color: putih),
          sel('Harga Satuan', align: r, bold: true, color: putih),
          sel('Jumlah', align: r, bold: true, color: putih),
        ],
      ),
      for (var i = 0; i < o.items.length; i++)
        pw.TableRow(
          decoration: i.isOdd ? const pw.BoxDecoration(color: zebra) : null,
          children: [
            sel('${i + 1}', align: c),
            sel(o.items[i].partNumber, mono: true),
            sel(o.items[i].name),
            sel('${o.items[i].qty}', align: c),
            sel(formatRupiah(o.items[i].price), align: r),
            sel(formatRupiah(o.items[i].lineTotal), align: r, bold: true),
          ],
        ),
    ],
  );

  // ── Terbilang ↔ ringkasan ──────────────────────────────────────────────
  final kode = (o.voucherCodes ?? '')
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .join(', ');
  final kiri = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    labelKecil('Terbilang'),
    pw.SizedBox(height: 4),
    pw.Text('# ${terbilang(o.total)} #', style: gaya(9, bold: true, italic: true)),
    if (kode.isNotEmpty) ...[
      pw.SizedBox(height: 9),
      labelKecil('Kode voucher'),
      pw.SizedBox(height: 3),
      pw.Text(kode, style: gaya(9, color: ink600)),
    ],
  ]);
  final kanan = pw.Column(children: [
    for (final b in barisBiaya(o))
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.6),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Expanded(child: pw.Text(b.label, style: gaya(9, color: ink600))),
          // Minus pakai '-' biasa: Helvetica bawaan PDF tak punya glyph U+2212.
          pw.Text(
              b.jumlah == null
                  ? b.teks
                  : '${b.potongan ? '-' : ''}${formatRupiah(b.jumlah)}',
              style: gaya(9, color: b.potongan ? brand : ink900)),
        ]),
      ),
    pw.SizedBox(height: 6),
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: pw.BoxDecoration(color: brand, borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('TOTAL PEMBAYARAN', style: gaya(9.5, bold: true, color: putih)),
        pw.Text(formatRupiah(o.total), style: gaya(11.5, bold: true, color: putih)),
      ]),
    ),
  ]);
  final ringkasan = pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Expanded(child: kiri),
    pw.SizedBox(width: 28),
    pw.SizedBox(width: 247, child: kanan), // ~87 mm
  ]);

  final catatan = pw.Container(
    padding: const pw.EdgeInsets.only(top: 8),
    decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: line, width: 0.6))),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(
          'Invoice ini diterbitkan secara elektronik oleh sistem MASPART dan sah tanpa '
          'tanda tangan maupun stempel basah.',
          style: gaya(8, italic: true, color: ink600)),
      pw.SizedBox(height: 3),
      pw.Text('Terima kasih telah berbelanja di MASPART.',
          style: gaya(8, bold: true, color: brand)),
    ]),
  );

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(45, 34, 45, 28),
        // Tanda air logo MAS (seperti kop surat Word) — di bawah isi.
        buildBackground: tandaAir == null
            ? null
            : (ctx) => pw.Center(
                  child: pw.Opacity(
                    opacity: 0.05,
                    child: pw.Image(tandaAir, width: 368), // 130 mm
                  ),
                ),
      ),
      footer: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: brand, width: 1.4))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('${Perusahaan.nama}  ·  ${Perusahaan.web}', style: gaya(7.5, color: ink400)),
          pw.Text('Invoice ${o.orderCode}  ·  Halaman ${ctx.pageNumber} dari ${ctx.pagesCount}',
              style: gaya(7.5, color: ink400)),
        ]),
      ),
      build: (ctx) => [
        kop,
        pw.SizedBox(height: 22),
        judul,
        pw.SizedBox(height: 14),
        kotakInfo,
        pw.SizedBox(height: 18),
        kotakPihak,
        pw.SizedBox(height: 12),
        tabel,
        pw.SizedBox(height: 18),
        // Ringkasan + catatan tak dipisah halaman di tengah jalan.
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [ringkasan, pw.SizedBox(height: 26), catatan],
        ),
      ],
    ),
  );

  return doc.save();
}

/// Buat PDF invoice lalu buka dengan penampil sistem (setara "Download PDF" web).
/// Melempar [Exception] bila pesanan belum lunas atau file gagal dibuka.
Future<void> downloadInvoicePdf(OrderDetail o) async {
  if (!invoiceTersedia(o)) {
    throw Exception('Invoice baru tersedia setelah pesanan lunas.');
  }
  final bytes = await buildInvoicePdf(o);
  final dir = await getTemporaryDirectory();
  final safe = o.orderCode.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final file = File('${dir.path}/Invoice-$safe.pdf');
  await file.writeAsBytes(bytes, flush: true);
  final res = await OpenFilex.open(file.path, type: 'application/pdf');
  if (res.type != ResultType.done) {
    throw Exception('Tidak bisa membuka PDF: ${res.message}');
  }
}
