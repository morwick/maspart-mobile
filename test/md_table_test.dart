// Uji parser & penyajian tabel markdown jawaban Asisten AI.
//
// ⚠️ PARITAS: fixture di bawah IDENTIK dengan yang dipakai di repo web
// (frontend/src/components/mdTable.ts). Kalau salah satu sisi berubah, sisi
// lain wajib ikut di giliran yang sama — kesamaan fixture inilah yang membuat
// paritas web ↔ Flutter bisa diaudit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maspart_mobile/theme/mas_theme.dart';
import 'package:maspart_mobile/widgets/mas_ui.dart';
import 'package:maspart_mobile/widgets/md_table.dart';

List<String> L(String s) => s.trim().split('\n');

void main() {
  group('parser — deteksi & struktur', () {
    test('A. 3 kolom: PN murni-angka ikut kolom PN, Stok rata kanan', () {
      final r = parseTableAt(
          L('''
| Part Number | Nama | Stok |
|---|---|---:|
| WG9925520270 | Front spring bushing | 12 |
| AZ9925520277 | Rear spring bushing | 0 |
| 190003962518 | Bolt M12x1.25 | 1250 |
'''),
          0)!;
      expect(r.table.nCols, 3);
      expect(r.table.pnCol, 0);
      expect(r.table.numCols, {2});
      expect(r.table.rows.length, 3);
      expect(r.table.pakaiKartu, isFalse);
    });

    test('B. 6 kolom → mode kartu; "—" netral tak menggugurkan kolom angka', () {
      final r = parseTableAt(
          L('''
| Part Number | Nama | Unit | Stok | Harga | Satuan |
|---|---|---|---:|---:|---|
| WG9925520270 | Front spring bushing | NX360 6X4 (LZZ1BLSG) | 12 | Rp 1.250.000 | pcs |
| VG1246080051+003/1 | Fuel injector | NX280 4X2 MT (LZZ1CCSD) | 0 | Rp 4.780.000 | pcs |
| AZ9925520277 | Rear spring bushing | NX440 6X4 AMT (LZZ1BLMJ) | — | — | pcs |
'''),
          0)!;
      expect(r.table.nCols, 6);
      expect(r.table.pakaiKartu, isTrue);
      expect(r.table.pnCol, 0);
      expect(r.table.numCols, {3, 4});
      expect(cardTitle(r.table, r.table.rows[1], 1), 'VG1246080051+003/1');
      expect(r.table.rows[2][4], '—'); // dipertahankan: "belum ada data"
    });

    test('C. TANPA pipa pembuka tetap terdeteksi', () {
      final r = parseTableAt(
          L('''
Part Number | Nama | Stok
--- | --- | ---:
WG9925520270 | Front spring bushing | 12
AZ9925520277 | Rear spring bushing | 0
'''),
          0);
      expect(r, isNotNull);
      expect(r!.table.nCols, 3);
      expect(r.table.numCols, {2});
    });

    test('D. baris tak seragam → tak ada sel yang hilang', () {
      final r = parseTableAt(
          L('''
| PN | Stok | Harga |
|---|---:|---:|
| WG9925520270 | 12 | Rp 1.250.000 | catatan ekstra |
| AZ9925520277 | 0 |
'''),
          0)!;
      expect(r.table.nCols, 4);
      expect(r.table.rows[0][3], 'catatan ekstra');
      expect(r.table.rows[1], ['AZ9925520277', '0', '', '']);
    });

    test('E. REGRESI: "---" polos tetap garis, bukan tabel', () {
      expect(
          parseTableAt(
              L('''
Ringkasan stok | per gudang
---
Teks berikutnya.
'''),
              0),
          isNull);
      expect(isSepRow('---'), isFalse);
      expect(isSepRow('|---|---|'), isTrue);
    });

    test('F. streaming separuh jadi tidak melempar & tidak salah deteksi', () {
      expect(parseTableAt(L('| Part Number | Nama | Stok |'), 0), isNull);
      // separator belum cukup kolomnya
      expect(parseTableAt('| Part Number | Nama | Stok |\n|---|--'.split('\n'), 0), isNull);
      // '|---|---|--' SUDAH separator 3 kolom yang sah → tabel header-saja
      final b = parseTableAt('| Part Number | Nama | Stok |\n|---|---|--'.split('\n'), 0);
      expect(b, isNotNull);
      expect(b!.table.rows, isEmpty);
      // sel terakhir separuh
      final c = parseTableAt(
          '| Part Number | Nama | Stok |\n|---|---|---:|\n| WG9925520270 | Front spring'.split('\n'), 0);
      expect(c!.table.rows.length, 1);
      expect(parseTableAt('| A | B |\n|---|---|'.split('\n'), 0)!.table.rows, isEmpty);
    });

    test('G. penanda guard tak merusak struktur tabel', () {
      final r = parseTableAt(
          L('''
| Part Number | Stok |
|---|---:|
| ⟨PN tak terverifikasi⟩ | 0 |
| WG9925520270 | 12 |
'''),
          0)!;
      expect(r.table.rows.length, 2);
      expect(r.table.numCols, {1});
    });

    test('pipa ter-escape tidak memecah sel', () {
      expect(splitCells(r'| a \| b | c |'), ['a | b', 'c']);
    });
  });

  group('heuristik kolom (tanpa penanda alignment)', () {
    test('kolom angka terdeteksi tanpa "---:"', () {
      final r = parseTableAt(
          L('''
| Part Number | Stok | Harga |
| --- | --- | --- |
| WG9925520270 | 12 | Rp 1.250.000 |
| AZ9925520277 | 0 | Rp 950.000 |
'''),
          0)!;
      expect(r.table.numCols, {1, 2});
    });

    test('kolom angka murni BUKAN kolom PN', () {
      final r = parseTableAt(
          L('''
| Kode | Nama |
| --- | --- |
| 12500 | Seher |
| 950 | Ring |
'''),
          0)!;
      expect(r.table.pnCol, isNull);
      expect(r.table.numCols, {0});
    });

    test('nama part beruruf besar BUKAN Part Number', () {
      final r = parseTableAt(
          L('''
| Barang | Jumlah |
| --- | --- |
| HANDLE | 3 |
| LOCK | 4 |
'''),
          0)!;
      expect(r.table.pnCol, isNull);
    });

    test('kolom campur teks BUKAN kolom angka', () {
      final r = parseTableAt(
          L('''
| Item | Qty |
| --- | --- |
| KOSONG (0 pcs) | 2 |
| 12 pcs | 3 |
'''),
          0)!;
      expect(r.table.numCols.contains(0), isFalse);
    });

    test('kolom semua-netral → judul yang memutuskan', () {
      final r = parseTableAt(
          L('''
| Part Number | Stok |
| --- | --- |
| — | — |
| — | — |
'''),
          0)!;
      expect(r.table.numCols, {1});
    });

    test('alignment GFM terbaca', () {
      final r = parseTableAt(
          L('''
| Nama | Nilai |
|:---|:---:|
| a | b |
'''),
          0)!;
      expect(r.table.aligns[0], MdAlign.left);
      expect(r.table.aligns[1], MdAlign.center);
    });

    test('isPnLike menolak format ribuan & Rp', () {
      expect(isPnLike('WG9925520270'), isTrue);
      expect(isPnLike('VG1246080051+003/1'), isTrue);
      expect(isPnLike('1.250.000'), isFalse);
      expect(isPnLike('Rp 950.000'), isFalse);
      expect(isPnLike('HANDLE'), isFalse); // tanpa angka
    });
  });

  group('segmentasi', () {
    test('teks + tabel + teks urutannya terjaga', () {
      final segs = splitMarkdown('''
Berikut hasilnya:

| PN | Stok |
|---|---:|
| WG9925520270 | 12 |

Catatan: stok bisa berubah.
''');
      expect(segs.length, 3);
      expect(segs[0], isA<MdText>());
      expect(segs[1], isA<MdTab>());
      expect(segs[2], isA<MdText>());
    });

    test('tanpa tabel → satu segmen teks', () {
      final segs = splitMarkdown('Halo, ini jawaban biasa.\n\n- satu\n- dua');
      expect(segs.length, 1);
      expect(segs.first, isA<MdText>());
    });
  });

  group('penyajian', () {
    Widget bungkus(Widget child) => MaterialApp(
          theme: buildMasTheme(Brightness.light),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );

    testWidgets('>=4 kolom → kartu (MasKeyValue), bukan Table', (t) async {
      final tab = parseTableAt(
          L('''
| Part Number | Nama | Unit | Stok |
|---|---|---|---:|
| WG9925520270 | Front spring bushing | NX360 6X4 (LZZ1BLSG) | 12 |
'''),
          0)!;
      await t.pumpWidget(bungkus(MasMdTable(table: tab.table)));
      expect(find.byType(MasKeyValue), findsWidgets);
      expect(find.byType(MasSectionCard), findsOneWidget);
      expect(find.byType(Table), findsNothing);
    });

    testWidgets('<=3 kolom → Table sungguhan', (t) async {
      final tab = parseTableAt(
          L('''
| Part Number | Stok |
|---|---:|
| WG9925520270 | 12 |
'''),
          0)!;
      await t.pumpWidget(bungkus(MasMdTable(table: tab.table)));
      expect(find.byType(Table), findsOneWidget);
      expect(find.byType(MasKeyValue), findsNothing);
    });

    testWidgets('MasMarkdown merender teks & tabel sekaligus', (t) async {
      await t.pumpWidget(bungkus(const MasMarkdown(data: '''
Berikut hasilnya:

| Part Number | Stok |
|---|---:|
| WG9925520270 | 12 |
''')));
      expect(find.byType(Table), findsOneWidget);
      expect(find.textContaining('Berikut hasilnya'), findsOneWidget);
    });
  });
}
