// lib/gudang_docs_pdf.dart — dokumen kerja GUDANG PEMENUH untuk satu pesanan.
//
// Paritas web `frontend/src/lib/gudang-docs-pdf.ts`:
//   1. Daftar Ambil Barang — urut per rak, kolom centang; untuk staf pengambil.
//   2. Surat Jalan         — TANPA harga, ikut di dalam paket; tanda tangan
//                            pengirim/kurir/penerima. Pesanan ambil sendiri →
//                            "Tanda Terima Barang" (ditandatangani pembeli).
//   3. Label Paket (A6)    — alamat penerima + pengirim untuk ditempel di dus.
//                            BUKAN label resi: resi & label kurir tetap dari gerai
//                            ekspedisi (paket RajaOngkir kita tak bisa booking).
// Invoice memakai downloadInvoicePdf yang sama dengan pembeli.
//
// Font bawaan PDF (Helvetica, WinAnsi) tak punya emoji / U+2212 → teks polos.

import 'dart:io';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';
import 'order_ui.dart';

const _brand = PdfColor.fromInt(0xFF028912);
const _ink900 = PdfColor.fromInt(0xFF11201A);
const _ink600 = PdfColor.fromInt(0xFF55605A);
const _ink400 = PdfColor.fromInt(0xFF8A938E);
const _line = PdfColor.fromInt(0xFFDDE3DF);
const _head = PdfColor.fromInt(0xFFF2F5F3);

String _kurir(OrderDetail o) {
  if (o.pickup) return 'AMBIL SENDIRI';
  final c = (o.courier ?? '').trim();
  if (c.isEmpty) return '-';
  final s = (o.courierService ?? '').trim();
  return c.toUpperCase() + (s.isEmpty ? '' : ' $s');
}

String _gudangFisik(OrderDetail o) {
  if (o.gudangFisik.isNotEmpty) return o.gudangFisik;
  if ((o.pickupGudang ?? '').isNotEmpty) return o.pickupGudang!;
  return o.gudang.isEmpty ? '-' : o.gudang;
}

List<String> _pengirim(OrderDetail o) => [
      'MASPART - Gudang ${_gudangFisik(o)}',
      if (o.gudangFisikPic.isNotEmpty) 'Telp: ${o.gudangFisikPic}',
      if (o.gudangFisikPostal.isNotEmpty) 'Kode pos ${o.gudangFisikPostal}',
    ];

List<String> _penerima(OrderDetail o) => [
      (o.recipientName ?? '').isNotEmpty
          ? o.recipientName!
          : (o.username.isNotEmpty ? o.username : '-'),
      if ((o.recipientPhone ?? '').isNotEmpty) o.recipientPhone!,
      if ((o.recipientAddress ?? '').isNotEmpty)
        '${o.recipientAddress}'
            '${(o.recipientPostal ?? '').isNotEmpty ? ' (${o.recipientPostal})' : ''}',
    ];

String _berat(OrderDetail o) {
  final g = o.weightGrams;
  if (g <= 0) return '-';
  if (g < 1000) return '$g g';
  final kg = g / 1000;
  return '${kg.toStringAsFixed(kg == kg.roundToDouble() ? 0 : 2).replaceAll('.', ',')} kg';
}

int _totalQty(OrderDetail o) => o.items.fold<int>(0, (n, it) => n + it.qty);

/// Urut ambil: per kode rak (yang belum punya rak di akhir), lalu PN.
List<OrderItemDetail> urutAmbil(List<OrderItemDetail> items) {
  final l = [...items];
  l.sort((a, b) {
    final ra = a.rak.trim(), rb = b.rak.trim();
    if (ra.isEmpty != rb.isEmpty) return ra.isEmpty ? 1 : -1;
    final c = ra.toLowerCase().compareTo(rb.toLowerCase());
    return c != 0 ? c : a.partNumber.compareTo(b.partNumber);
  });
  return l;
}

pw.Widget _kepala(String judul, OrderDetail o) => pw.Column(children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('MASPART',
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold, color: _brand)),
            pw.Text('Penyedia Suku Cadang',
                style: const pw.TextStyle(fontSize: 9, color: _ink600)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(judul,
                style: pw.TextStyle(
                    fontSize: 15, fontWeight: pw.FontWeight.bold, color: _ink900)),
            pw.Text('No. Pesanan ${o.orderCode}',
                style: const pw.TextStyle(fontSize: 10, color: _ink600)),
          ]),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Divider(color: _line, height: 1),
      pw.SizedBox(height: 10),
    ]);

pw.Widget _meta(List<List<String>> pairs) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final p in pairs)
          pw.Expanded(
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(p[0], style: const pw.TextStyle(fontSize: 8, color: _ink400)),
                  pw.SizedBox(height: 2),
                  pw.Text(p[1].isEmpty ? '-' : p[1],
                      style: pw.TextStyle(
                          fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _ink900)),
                ]),
          ),
      ],
    );

pw.Widget _pihak(String head, List<String> lines) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(head,
            style: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold, color: _ink400)),
        pw.SizedBox(height: 3),
        for (int i = 0; i < lines.length; i++)
          pw.Text(lines[i],
              style: pw.TextStyle(
                  fontSize: i == 0 ? 10 : 9,
                  fontWeight: i == 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: i == 0 ? _ink900 : _ink600)),
      ],
    );

pw.Widget _cell(String s, {bool center = false, bool bold = false, double h = 0}) =>
    pw.Container(
      constraints: h > 0 ? pw.BoxConstraints(minHeight: h) : null,
      alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(s,
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: _ink900)),
    );

pw.Widget _tandaTangan(List<String> peran) => pw.Row(children: [
      for (final p in peran)
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14),
            child: pw.Column(children: [
              pw.Text(p, style: const pw.TextStyle(fontSize: 9, color: _ink600)),
              pw.SizedBox(height: 50),
              pw.Divider(color: _ink400, height: 1),
              pw.SizedBox(height: 2),
              pw.Text('Nama & tanda tangan',
                  style: const pw.TextStyle(fontSize: 7.5, color: _ink400)),
            ]),
          ),
        ),
    ]);

pw.Widget _catatan(List<String> baris) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final b in baris)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text('- $b',
                style: const pw.TextStyle(fontSize: 8.5, color: _ink600)),
          ),
      ],
    );

// ── 1. Daftar Ambil Barang ───────────────────────────────────────────
Future<List<int>> buildDaftarAmbil(OrderDetail o) async {
  final doc = pw.Document();
  final rows = urutAmbil(o.items);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (ctx) => [
      _kepala('DAFTAR AMBIL BARANG', o),
      _meta([
        ['Gudang', _gudangFisik(o)],
        ['Tanggal Pesanan', fmtDate(o.createdAt)],
        ['Pengiriman', _kurir(o)],
        ['Jumlah', '${o.items.length} baris / ${_totalQty(o)} pcs'],
      ]),
      pw.SizedBox(height: 12),
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(24),
          1: const pw.FixedColumnWidth(60),
          2: const pw.FixedColumnWidth(110),
          3: const pw.FlexColumnWidth(3),
          4: const pw.FixedColumnWidth(32),
          5: const pw.FixedColumnWidth(46),
          6: const pw.FixedColumnWidth(46),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _head),
            children: [
              _cell('No', bold: true),
              _cell('Rak', bold: true),
              _cell('Part Number', bold: true),
              _cell('Nama Barang', bold: true),
              _cell('Qty', bold: true, center: true),
              _cell('Diambil', bold: true),
              _cell('Dicek', bold: true),
            ],
          ),
          for (int i = 0; i < rows.length; i++)
            pw.TableRow(children: [
              _cell('${i + 1}', h: 24),
              _cell(rows[i].rak.isEmpty ? '-' : rows[i].rak, bold: true, h: 24),
              _cell(rows[i].partNumber, bold: true, h: 24),
              _cell(rows[i].name, h: 24),
              _cell('${rows[i].qty}', bold: true, center: true, h: 24),
              _cell('', h: 24),
              _cell('', h: 24),
            ]),
        ],
      ),
      pw.SizedBox(height: 10),
      _catatan([
        "Centang 'Diambil' saat barang diambil dari rak; 'Dicek' oleh pemeriksa kedua (PN & qty cocok, kondisi baik).",
        "Rak '-' = lokasi belum dicatat. Setelah ketemu, isi lewat menu Rak & Kartu Stok agar pesanan berikutnya lebih cepat.",
        'Barang kurang / rusak? JANGAN kirim sebagian - kabari pembeli lewat chat pesanan dan admin.',
      ]),
      if ((o.note ?? '').isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Text('Catatan pembeli: ${o.note}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
      pw.SizedBox(height: 18),
      _tandaTangan(['Diambil oleh', 'Diperiksa oleh']),
    ],
  ));
  return doc.save();
}

// ── 2. Surat Jalan / Tanda Terima Barang ─────────────────────────────
Future<List<int>> buildSuratJalan(OrderDetail o) async {
  final doc = pw.Document();
  final pickup = o.pickup;
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (ctx) => [
      _kepala(pickup ? 'TANDA TERIMA BARANG' : 'SURAT JALAN', o),
      _meta([
        ['Tanggal', fmtDate(DateTime.now().toIso8601String())],
        ['Pengiriman', _kurir(o)],
        pickup
            ? ['Diambil di', 'Gudang ${_gudangFisik(o)}']
            : ['No. Resi', (o.trackingNo ?? '').isNotEmpty ? o.trackingNo! : '(diisi setelah setor)'],
        ['Berat', _berat(o)],
      ]),
      pw.SizedBox(height: 12),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: _pihak('PENGIRIM', _pengirim(o))),
        pw.SizedBox(width: 12),
        pw.Expanded(child: _pihak(pickup ? 'DIAMBIL OLEH' : 'PENERIMA', _penerima(o))),
      ]),
      pw.SizedBox(height: 12),
      // Sengaja TANPA harga: surat jalan ikut di dalam paket & dibaca kurir.
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(24),
          1: const pw.FixedColumnWidth(115),
          2: const pw.FlexColumnWidth(3),
          3: const pw.FixedColumnWidth(32),
          4: const pw.FixedColumnWidth(90),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _head),
            children: [
              _cell('No', bold: true),
              _cell('Part Number', bold: true),
              _cell('Nama Barang', bold: true),
              _cell('Qty', bold: true, center: true),
              _cell('Keterangan', bold: true),
            ],
          ),
          for (int i = 0; i < o.items.length; i++)
            pw.TableRow(children: [
              _cell('${i + 1}'),
              _cell(o.items[i].partNumber, bold: true),
              _cell(o.items[i].name),
              _cell('${o.items[i].qty}', center: true),
              _cell(''),
            ]),
          pw.TableRow(children: [
            _cell(''),
            _cell(''),
            _cell('Total', bold: true),
            _cell('${_totalQty(o)}', bold: true, center: true),
            _cell(''),
          ]),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Text(
        pickup
            ? 'Barang di atas telah diterima dalam keadaan baik dan jumlah sesuai. Periksa sebelum menandatangani - keluhan setelah barang dibawa pulang sulit diproses.'
            : 'Harap periksa barang saat diterima. Bila ada kekurangan/kerusakan, foto paket & isinya lalu laporkan lewat chat pesanan di aplikasi MASPART paling lambat 2x24 jam.',
        style: const pw.TextStyle(fontSize: 8.5, color: _ink600),
      ),
      pw.SizedBox(height: 18),
      _tandaTangan(pickup
          ? ['Diserahkan (gudang)', 'Diterima (pembeli)']
          : ['Pengirim (gudang)', 'Kurir / Ekspedisi', 'Penerima']),
    ],
  ));
  return doc.save();
}

// ── 3. Label Paket (A6, tempel di dus) ───────────────────────────────
Future<List<int>> buildLabelPaket(OrderDetail o) async {
  final doc = pw.Document();
  final p = _penerima(o);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a6,
    margin: const pw.EdgeInsets.all(16),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('MASPART',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold, color: _brand)),
          pw.Text(_kurir(o),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.Divider(color: _ink900, thickness: 1.2, height: 10),
        pw.Text('KEPADA:',
            style: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold, color: _ink600)),
        pw.SizedBox(height: 3),
        pw.Text(p.first,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        if ((o.recipientPhone ?? '').isNotEmpty)
          pw.Text(o.recipientPhone!,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        if ((o.recipientAddress ?? '').isNotEmpty)
          pw.Text(o.recipientAddress!, style: const pw.TextStyle(fontSize: 10)),
        if ((o.recipientPostal ?? '').isNotEmpty)
          pw.Text('Kode Pos ${o.recipientPostal}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.Divider(color: _line, height: 12),
        pw.Text('DARI:',
            style: pw.TextStyle(
                fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _ink600)),
        for (final l in _pengirim(o))
          pw.Text(l, style: const pw.TextStyle(fontSize: 8.5)),
        pw.Divider(color: _line, height: 12),
        pw.Row(children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('No. Pesanan', style: const pw.TextStyle(fontSize: 8.5, color: _ink600)),
              pw.Text(o.orderCode,
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Berat', style: const pw.TextStyle(fontSize: 8.5, color: _ink600)),
              pw.Text(_berat(o),
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
        ]),
        pw.SizedBox(height: 4),
        pw.Text('Isi: ${o.items.length} jenis / ${_totalQty(o)} pcs suku cadang',
            style: const pw.TextStyle(fontSize: 8.5, color: _ink600)),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text('JANGAN DIBANTING - SUKU CADANG',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Spacer(),
        pw.Center(
          child: pw.Text(
              'Label alamat MASPART. Resi & label ekspedisi tetap dari gerai kurir.',
              style: const pw.TextStyle(fontSize: 7, color: _ink400)),
        ),
      ],
    ),
  ));
  return doc.save();
}

/// Tulis [bytes] ke folder sementara lalu buka dengan penampil PDF sistem
/// (dari sana staf bisa cetak / bagikan ke printer Bluetooth).
Future<void> bukaPdf(String nama, OrderDetail o, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final safe = o.orderCode.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final file = File('${dir.path}/$nama-$safe.pdf');
  await file.writeAsBytes(bytes, flush: true);
  final res = await OpenFilex.open(file.path, type: 'application/pdf');
  if (res.type != ResultType.done) {
    throw Exception('Tidak bisa membuka PDF: ${res.message}');
  }
}

Future<void> downloadDaftarAmbil(OrderDetail o) async =>
    bukaPdf('Daftar-Ambil', o, await buildDaftarAmbil(o));

Future<void> downloadSuratJalan(OrderDetail o) async =>
    bukaPdf(o.pickup ? 'Tanda-Terima' : 'Surat-Jalan', o, await buildSuratJalan(o));

Future<void> downloadLabelPaket(OrderDetail o) async =>
    bukaPdf('Label-Paket', o, await buildLabelPaket(o));
