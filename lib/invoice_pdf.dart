// lib/invoice_pdf.dart — buat & buka Invoice PDF pesanan LUNAS.
//
// Setara halaman invoice web (`frontend/src/app/pesanan/[code]/invoice`): lembar
// invoice dirender dari data OrderDetail lalu diunduh sebagai PDF. Di sini PDF
// dibuat sepenuhnya di sisi klien (paket `pdf`, murni Dart — tanpa plugin
// native), disimpan ke folder sementara, lalu dibuka dengan penampil sistem.
//
// PPN 12% INKLUSIF: sudah terkandung di subtotal (ikut Accurate), bukan tambahan.

import 'dart:io';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';
import 'order_ui.dart';
import 'utils.dart';

/// Status pesanan yang dianggap LUNAS — invoice hanya sah setelahnya.
const _paid = {'diproses', 'dikirim', 'selesai'};

bool invoiceTersedia(OrderDetail o) => _paid.contains(o.status);

/// Label metode pembayaran (persis web `payLabel`).
String _payLabel(OrderDetail o) {
  if (o.paymentMethod == 'manual') return 'Transfer Manual';
  final ch = (o.paymentChannel ?? '').toLowerCase();
  if (ch.isEmpty) return '—';
  if (ch == 'qris') return 'QRIS';
  if (ch.startsWith('va_')) return 'Virtual Account ${ch.substring(3).toUpperCase()}';
  return ch.toUpperCase();
}

String _courierLabel(OrderDetail o) {
  final c = (o.courier ?? '').trim();
  if (c.isEmpty) return '—';
  final s = (o.courierService ?? '').trim();
  return c.toUpperCase() + (s.isEmpty ? '' : ' $s');
}

/// Bangun byte PDF invoice dari [o]. Dipisah agar bisa diuji tanpa I/O.
Future<List<int>> buildInvoicePdf(OrderDetail o) async {
  final doc = pw.Document();
  final ppn = (o.tax?.round()) ?? ppnOf(o.subtotal);

  const brand = PdfColor.fromInt(0xFF028912);
  const ink900 = PdfColor.fromInt(0xFF11201A);
  const ink600 = PdfColor.fromInt(0xFF55605A);
  const ink400 = PdfColor.fromInt(0xFF8A938E);
  const line = PdfColor.fromInt(0xFFDDE3DF);

  pw.Widget kv(String k, String v) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(k, style: const pw.TextStyle(fontSize: 8, color: ink400)),
          pw.SizedBox(height: 2),
          pw.Text(v, style: const pw.TextStyle(fontSize: 10, color: ink900)),
        ],
      );

  pw.Widget totalRow(String label, String value, {bool grand = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: grand ? 11 : 9.5,
                    fontWeight: grand ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: grand ? ink900 : ink600)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: grand ? 12 : 9.5,
                    fontWeight: grand ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: grand ? brand : ink900)),
          ],
        ),
      );

  pw.Widget cell(String s, {bool num = false, bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(s,
            textAlign: num ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: ink900)),
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Header
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('MASPART',
                    style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: brand)),
                pw.Text('Penyedia Suku Cadang',
                    style: const pw.TextStyle(fontSize: 9, color: ink600)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('INVOICE',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: ink900)),
                pw.Text('No. ${o.orderCode}', style: const pw.TextStyle(fontSize: 10, color: ink600)),
                pw.SizedBox(height: 3),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFE6F4E9),
                    borderRadius: pw.BorderRadius.circular(999),
                  ),
                  child: pw.Text('● LUNAS',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: brand)),
                ),
              ]),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(color: line, height: 1),
          pw.SizedBox(height: 10),

          // Meta pembayaran
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              kv('Tanggal Pesanan', fmtDate(o.createdAt)),
              kv('Tanggal Bayar', o.paidAt != null ? fmtDate(o.paidAt) : '—'),
              kv('Metode Pembayaran', _payLabel(o)),
            ],
          ),
          pw.SizedBox(height: 14),

          // Penjual ↔ Penerima
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('DIKIRIM DARI',
                      style: const pw.TextStyle(fontSize: 8, color: ink400)),
                  pw.SizedBox(height: 3),
                  pw.Text('Gudang ${o.gudang.isEmpty ? '—' : o.gudang}',
                      style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
                  if ((o.gudangPic ?? '').isNotEmpty)
                    pw.Text('PIC: ${o.gudangPic}', style: const pw.TextStyle(fontSize: 9, color: ink600)),
                ]),
              ),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('DITERIMA OLEH',
                      style: const pw.TextStyle(fontSize: 8, color: ink400)),
                  pw.SizedBox(height: 3),
                  pw.Text(
                      (o.recipientName ?? '').isNotEmpty
                          ? o.recipientName!
                          : (o.username.isNotEmpty ? o.username : '—'),
                      style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
                  if ((o.recipientPhone ?? '').isNotEmpty)
                    pw.Text(o.recipientPhone!, style: const pw.TextStyle(fontSize: 9, color: ink600)),
                  if ((o.recipientAddress ?? '').isNotEmpty)
                    pw.Text(
                        '${o.recipientAddress}'
                        '${(o.recipientPostal ?? '').isNotEmpty ? ' (${o.recipientPostal})' : ''}',
                        style: const pw.TextStyle(fontSize: 9, color: ink600)),
                ]),
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // Tabel item
          pw.Table(
            border: pw.TableBorder.all(color: line, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(3),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FixedColumnWidth(30),
              5: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF2F5F3)),
                children: [
                  cell('No', bold: true),
                  cell('Part Number', bold: true),
                  cell('Nama Barang', bold: true),
                  cell('Harga', num: true, bold: true),
                  cell('Qty', num: true, bold: true),
                  cell('Total', num: true, bold: true),
                ],
              ),
              for (int i = 0; i < o.items.length; i++)
                pw.TableRow(children: [
                  cell('${i + 1}', num: true),
                  cell(o.items[i].partNumber),
                  cell(o.items[i].name),
                  cell(formatRupiah(o.items[i].price), num: true),
                  cell('${o.items[i].qty}', num: true),
                  cell(formatRupiah(o.items[i].lineTotal), num: true),
                ]),
            ],
          ),
          pw.SizedBox(height: 12),

          // Ringkasan
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 260,
              child: pw.Column(children: [
                totalRow('Subtotal Produk (termasuk PPN)', formatRupiah(o.subtotal)),
                if (ppn > 0) totalRow('— di dalamnya PPN 12%', formatRupiah(ppn)),
                totalRow(
                    'Ongkos Kirim${(o.courier ?? '').isNotEmpty ? ' (${_courierLabel(o)})' : ''}',
                    o.shippingCost > 0 ? formatRupiah(o.shippingCost) : '—'),
                pw.Divider(color: line, height: 10),
                totalRow('TOTAL PEMBAYARAN', formatRupiah(o.total), grand: true),
              ]),
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Divider(color: line, height: 1),
          pw.SizedBox(height: 8),

          // Pengiriman
          pw.Row(children: [
            pw.Text('Jasa Kirim: ', style: const pw.TextStyle(fontSize: 9, color: ink600)),
            pw.Text(_courierLabel(o),
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            if ((o.trackingNo ?? '').isNotEmpty) ...[
              pw.SizedBox(width: 16),
              pw.Text('No. Resi: ', style: const pw.TextStyle(fontSize: 9, color: ink600)),
              pw.Text(o.trackingNo!, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ]),
          pw.SizedBox(height: 18),
          pw.Center(
            child: pw.Text('Invoice ini sah dan diproses oleh komputer.',
                style: const pw.TextStyle(fontSize: 8, color: ink400)),
          ),
        ],
      ),
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
