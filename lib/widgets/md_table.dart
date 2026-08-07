import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/mas_theme.dart';
import 'mas_ui.dart';

/// Parser TABEL Markdown (GFM) + penyajiannya untuk jawaban Asisten AI.
///
/// ⚠️ PARITAS: bagian PARSER di file ini adalah CERMIN dari
/// `frontend/src/components/mdTable.ts` di repo web. Keduanya mengikuti
/// spesifikasi yang sama persis di bawah; kalau salah satu diubah, ubah yang
/// lain di giliran yang sama (aturan paritas web ↔ Flutter) dan pakai string
/// fixture yang identik di test masing-masing.
///
/// SPESIFIKASI BERSAMA
/// 1. splitCells: buang '|' terdepan/terbelakang, pecah pada '|' yang TIDAK
///    didahului '\', trim, lalu buang sel kosong di EKOR.
/// 2. isSepRow: >=2 sel DAN tiap sel cocok /^:?-+:?$/. Ambang ">=2" itulah yang
///    menjaga '---' polos tetap jadi garis, bukan tabel.
/// 3. Tabel MULAI di baris i bila: lines[i] MENGANDUNG '|' (tak harus diawali
///    '|'), isSepRow(lines[i+1]), dan jumlah kolom header == separator.
/// 4. Baris isi: lanjut selama baris tidak kosong, mengandung '|', bukan
///    sepRow, dan tidak diawali '#'.
/// 5. Alignment GFM: ':---:'→center, '---:'→right, ':---'→left, '---'→null.
/// 6. Heuristik kolom ANGKA (hanya bila alignment null) — per KOLOM, hanya sel
///    body. Netral: '', '-', '—', '–', 'n/a'. Kolom numerik bila >=1 sel numerik
///    DAN 0 sel non-numerik. Kolom semua-netral → numerik bila judulnya kolom
///    angka.
/// 7. Kolom PN = keputusan KOLOM, bukan per sel: judul cocok, atau >=60% sel
///    non-kosong pnLike DAN minimal satu sel mengandung huruf. Kolom numerik
///    tak pernah jadi kolom PN.
/// 8. Normalisasi: nCols = max(header, baris terpanjang); semua dipadatkan.
/// 9. Parser WAJIB TOTAL: tak boleh melempar untuk input separuh jadi apa pun
///    (draf streaming melewatinya tiap token).
///
/// PENYAJIAN (khas mobile, sesuai aturan PROJECT.md "tabel → kartu"):
///   nCols <= 3 → tabel sungguhan, lebar kolom mengikuti isi + bisa digeser;
///   nCols >= 4 → kartu-per-baris (MasSectionCard + MasKeyValue).
/// Ini dikerjakan sendiri, BUKAN lewat flutter_markdown: `MarkdownElementBuilder`
/// untuk tag 'table' tak berpengaruh — builder.dart menimpanya tanpa syarat
/// dengan _buildTable(), dan package itu sendiri sudah discontinued.

enum MdAlign { left, right, center }

/// Ambang kolom: >= ini, tabel disajikan sebagai kartu-per-baris.
const int kMdCardMinCols = 4;

class MdTable {
  final List<String> header;
  final List<List<String>> rows;
  final List<MdAlign?> aligns;
  final Set<int> numCols;
  final int? pnCol;
  const MdTable(this.header, this.rows, this.aligns, this.numCols, this.pnCol);
  int get nCols => header.length;
  bool get pakaiKartu => nCols >= kMdCardMinCols;
}

/// Potongan hasil pemecahan jawaban: teks markdown biasa atau satu tabel.
sealed class MdSeg {
  const MdSeg();
}

class MdText extends MdSeg {
  final String text;
  const MdText(this.text);
}

class MdTab extends MdSeg {
  final MdTable table;
  const MdTab(this.table);
}

final RegExp _sepCell = RegExp(r'^:?-+:?$');
const Set<String> _neutral = {'', '-', '—', '–', 'n/a'};
final RegExp _numPlain = RegExp(r'^[+-]?\d+([.,]\d+)?$');
final RegExp _numThousand = RegExp(r'^(rp\s*)?[+-]?\d{1,3}([.\s]\d{3})+(,\d+)?$', caseSensitive: false);
final RegExp _numRupiah = RegExp(r'^rp\s*[+-]?\d[\d.,\s]*$', caseSensitive: false);
final RegExp _numUnit = RegExp(
    r'^[+-]?\d[\d.,\s]*\s*(pcs|pc|unit|set|ea|kg|gr|g|mm|cm|m|liter|ltr|l|%|x|jam|hari|bh|buah|lembar|pasang)$',
    caseSensitive: false);
final RegExp _headerNum =
    RegExp(r'^(stok|qty|jumlah|harga|price|total|berat|nilai|subtotal|sisa)', caseSensitive: false);
final RegExp _headerPn =
    RegExp(r'(part\s*number|part\s*no\b|^pn$|^p/n$|nomor\s*part)', caseSensitive: false);
final RegExp _pnBentuk = RegExp(r'^[A-Z0-9][A-Z0-9./+\-]*$');
final RegExp _ribuan = RegExp(r'^\d{1,3}([.,]\d{3})+$');

String _strip(String s) => s.replaceAll('**', '').replaceAll(RegExp(r'[*`]'), '').trim();

List<String> splitCells(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|') && !s.endsWith(r'\|')) s = s.substring(0, s.length - 1);
  final out = <String>[];
  final buf = StringBuffer();
  for (var k = 0; k < s.length; k++) {
    final ch = s[k];
    if (ch == r'\' && k + 1 < s.length && s[k + 1] == '|') {
      buf.write('|');
      k++;
      continue;
    }
    if (ch == '|') {
      out.add(buf.toString().trim());
      buf.clear();
      continue;
    }
    buf.write(ch);
  }
  out.add(buf.toString().trim());
  while (out.length > 1 && out.last.isEmpty) {
    out.removeLast();
  }
  return out;
}

bool isSepRow(String line) {
  if (!line.contains('-')) return false;
  final cells = splitCells(line);
  return cells.length >= 2 && cells.every((c) => _sepCell.hasMatch(c));
}

MdAlign? _alignOf(String sepCell) {
  final kiri = sepCell.startsWith(':');
  final kanan = sepCell.endsWith(':');
  if (kiri && kanan) return MdAlign.center;
  if (kanan) return MdAlign.right;
  if (kiri) return MdAlign.left;
  return null;
}

enum _Jenis { neutral, num, other }

_Jenis _jenisSel(String raw) {
  final s = _strip(raw);
  if (_neutral.contains(s.toLowerCase())) return _Jenis.neutral;
  if (_numPlain.hasMatch(s) || _numThousand.hasMatch(s) || _numRupiah.hasMatch(s) || _numUnit.hasMatch(s)) {
    return _Jenis.num;
  }
  return _Jenis.other;
}

/// PN selalu memuat ANGKA — syarat itu yang menjaga nama part beruruf besar
/// ('HANDLE') tidak ikut dianggap Part Number. Suffix varian ('/1', '+003/1')
/// sudah tercakup kelas karakternya.
bool isPnLike(String raw) {
  final s = _strip(raw);
  if (s.length < 5 || s.length > 32) return false;
  if (!_pnBentuk.hasMatch(s)) return false;
  if (!RegExp(r'\d').hasMatch(s)) return false;
  if (_ribuan.hasMatch(s)) return false;
  if (RegExp('^RP', caseSensitive: false).hasMatch(s)) return false;
  return true;
}

Set<int> _hitungNumCols(List<String> header, List<List<String>> rows, List<MdAlign?> aligns, int nCols) {
  final out = <int>{};
  for (var ci = 0; ci < nCols; ci++) {
    final a = aligns[ci];
    if (a == MdAlign.right) {
      out.add(ci);
      continue;
    }
    if (a == MdAlign.center || a == MdAlign.left) continue; // eksplisit — hormati
    var num = 0, other = 0, ada = 0;
    for (final r in rows) {
      final j = _jenisSel(ci < r.length ? r[ci] : '');
      if (j == _Jenis.neutral) continue;
      ada++;
      if (j == _Jenis.num) {
        num++;
      } else {
        other++;
      }
    }
    if (ada == 0) {
      if (_headerNum.hasMatch(_strip(header[ci]))) out.add(ci);
      continue;
    }
    if (num >= 1 && other == 0) out.add(ci);
  }
  return out;
}

int? _cariPnCol(List<String> header, List<List<String>> rows, Set<int> numCols, int nCols) {
  for (var ci = 0; ci < nCols; ci++) {
    if (numCols.contains(ci)) continue;
    if (_headerPn.hasMatch(_strip(header[ci]))) return ci;
  }
  for (var ci = 0; ci < nCols; ci++) {
    if (numCols.contains(ci)) continue;
    var isi = 0, pn = 0;
    var berhuruf = false;
    for (final r in rows) {
      final s = _strip(ci < r.length ? r[ci] : '');
      if (s.isEmpty) continue;
      isi++;
      if (isPnLike(s)) pn++;
      if (RegExp('[A-Z]').hasMatch(s)) berhuruf = true;
    }
    // 'berhuruf' diperiksa di level KOLOM: PN murni-angka (190003962518) tetap
    // dapat font mono karena bertetangga dgn WG9925520270, sedangkan kolom Stok
    // yang seluruhnya angka tak pernah jadi kolom PN.
    if (isi > 0 && berhuruf && pn / isi >= 0.6) return ci;
  }
  return null;
}

/// Hasil parse tabel yang MULAI di `lines[i]`; null bila di situ bukan tabel.
({MdTable table, int next})? parseTableAt(List<String> lines, int i) {
  if (i < 0 || i >= lines.length) return null;
  final head = lines[i];
  if (!head.contains('|')) return null;
  if (i + 1 >= lines.length || !isSepRow(lines[i + 1])) return null;

  final header = splitCells(head);
  final sep = splitCells(lines[i + 1]);
  if (sep.length < 2 || header.length != sep.length) return null;

  final rows = <List<String>>[];
  var j = i + 2;
  while (j < lines.length) {
    final t = lines[j].trim();
    if (t.isEmpty || !t.contains('|') || t.startsWith('#') || isSepRow(lines[j])) break;
    rows.add(splitCells(lines[j]));
    j++;
  }

  var nCols = header.length;
  for (final r in rows) {
    if (r.length > nCols) nCols = r.length;
  }
  List<String> pad(List<String> a) {
    final out = a.length > nCols ? a.sublist(0, nCols) : List<String>.from(a);
    while (out.length < nCols) {
      out.add('');
    }
    return out;
  }

  final h = pad(header);
  final rr = rows.map(pad).toList();
  final aligns = <MdAlign?>[
    for (var ci = 0; ci < nCols; ci++) ci < sep.length ? _alignOf(sep[ci]) : null,
  ];
  final numCols = _hitungNumCols(h, rr, aligns, nCols);
  final pnCol = _cariPnCol(h, rr, numCols, nCols);
  return (table: MdTable(h, rr, aligns, numCols, pnCol), next: j);
}

/// Pecah jawaban jadi segmen teks & tabel (urutan dipertahankan).
List<MdSeg> splitMarkdown(String src) {
  final lines = src.replaceAll('\r\n', '\n').split('\n');
  final out = <MdSeg>[];
  final buf = <String>[];
  void flush() {
    if (buf.isEmpty) return;
    final teks = buf.join('\n').trim();
    if (teks.isNotEmpty) out.add(MdText(teks));
    buf.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final t = parseTableAt(lines, i);
    if (t != null) {
      flush();
      out.add(MdTab(t.table));
      i = t.next;
      continue;
    }
    buf.add(lines[i]);
    i++;
  }
  flush();
  return out;
}

/// Judul kartu (mode >=4 kolom): sel kolom PN, atau kolom 0.
String cardTitle(MdTable t, List<String> row, int ri) {
  final ci = t.pnCol ?? 0;
  final utama = (ci < row.length ? row[ci] : '').trim();
  if (utama.isNotEmpty) return utama;
  for (final c in row) {
    if (c.trim().isNotEmpty) return c.trim();
  }
  return 'Baris ${ri + 1}';
}

// ── Penyajian ───────────────────────────────────────────────────────────────

/// Gaya markdown bersama untuk SEMUA jawaban asisten (chat & riwayat admin).
/// `dense` dipakai layar riwayat yang teksnya lebih kecil.
MarkdownStyleSheet masMdStyle(MasColors m, {bool dense = false}) => MarkdownStyleSheet(
      p: TextStyle(fontSize: dense ? 12.5 : 14, height: 1.5, color: m.ink800),
      strong: TextStyle(fontWeight: FontWeight.w700, color: m.ink900),
      em: TextStyle(fontStyle: FontStyle.italic, color: m.ink700),
      h1: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: m.ink900, height: 1.3),
      h2: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: m.ink900, height: 1.3),
      h3: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: m.ink900, height: 1.3),
      listBullet: TextStyle(fontSize: dense ? 12.5 : 14, color: m.ink800),
      a: TextStyle(color: m.brand700, decoration: TextDecoration.underline),
      code: masMono(size: 12.5, color: m.brand700),
      codeblockPadding: const EdgeInsets.all(10),
      codeblockDecoration: BoxDecoration(
        color: m.ink50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: m.ink150),
      ),
      blockquote: TextStyle(fontSize: dense ? 12.5 : 14, color: m.ink600),
      blockquoteDecoration: BoxDecoration(
        color: m.ink50,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: m.brand500, width: 3)),
      ),
      // Jaring pengaman: tabel yang lolos segmenter (mis. bersarang di dalam
      // list item) tetap dirender flutter_markdown. IntrinsicColumnWidth WAJIB —
      // hanya dgn itu builder.dart mengaktifkan Scrollbar + scroll horizontal;
      // dgn FlexColumnWidth (fallback tema) kolom dipaksa selebar sama & PN
      // terpotong per karakter.
      tableHead: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: m.ink900),
      tableBody: TextStyle(fontSize: 12.5, color: m.ink700),
      tableBorder: TableBorder.all(color: m.ink200),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: m.ink150))),
      blockSpacing: 9,
      listIndent: 20,
    );

/// Satu tabel markdown: kartu-per-baris (>=4 kolom) atau tabel geser (<=3).
class MasMdTable extends StatefulWidget {
  final MdTable table;
  const MasMdTable({super.key, required this.table});

  @override
  State<MasMdTable> createState() => _MasMdTableState();
}

class _MasMdTableState extends State<MasMdTable> {
  final ScrollController _sc = ScrollController();

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.table;
    if (t.rows.isEmpty && t.header.every((h) => h.trim().isEmpty)) {
      return const SizedBox.shrink();
    }
    // Tabel yang baris isinya belum tiba (draf streaming) tetap tampil sbg
    // tabel — jangan melompat ke mode kartu lalu balik lagi.
    return (t.pakaiKartu && t.rows.isNotEmpty) ? _kartu(context, t) : _tabel(context, t);
  }

  Widget _kartu(BuildContext context, MdTable t) {
    final judulCi = t.pnCol ?? 0;
    final kartu = <Widget>[];
    for (var ri = 0; ri < t.rows.length; ri++) {
      final r = t.rows[ri];
      final baris = <Widget>[];
      final isiCi = <int>[];
      for (var ci = 0; ci < t.nCols; ci++) {
        if (ci == judulCi) continue;
        if ((ci < r.length ? r[ci] : '').trim().isEmpty) continue;
        isiCi.add(ci);
      }
      for (var k = 0; k < isiCi.length; k++) {
        final ci = isiCi[k];
        final label = t.header[ci].trim().isEmpty ? 'Kolom ${ci + 1}' : _strip(t.header[ci]);
        baris.add(MasKeyValue(
          label: label,
          value: _strip(r[ci]),
          mono: ci == t.pnCol,
          divider: k != isiCi.length - 1,
        ));
      }
      kartu.add(Padding(
        padding: EdgeInsets.only(top: ri == 0 ? 0 : 8),
        child: MasSectionCard(
          title: _strip(cardTitle(t, r, ri)),
          titleStyle: t.pnCol != null ? masMono(size: 13, weight: FontWeight.w600) : null,
          children: baris,
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kartu),
    );
  }

  Widget _tabel(BuildContext context, MdTable t) {
    final m = context.mas;
    TextStyle gaya(int ci, {required bool head}) {
      if (ci == t.pnCol && !head) {
        return masMono(size: 12.5, weight: FontWeight.w500, color: m.ink900);
      }
      if (head) {
        return TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: m.ink500, letterSpacing: .4);
      }
      return TextStyle(
        fontSize: 12.5,
        color: m.ink800,
        fontFeatures: t.numCols.contains(ci) ? const [FontFeature.tabularFigures()] : null,
      );
    }

    TextAlign rata(int ci) {
      if (t.numCols.contains(ci)) return TextAlign.right;
      if (t.aligns[ci] == MdAlign.center) return TextAlign.center;
      return TextAlign.left;
    }

    Widget sel(String teks, int ci, {required bool head}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            head ? _strip(teks).toUpperCase() : _strip(teks),
            style: gaya(ci, head: head),
            textAlign: rata(ci),
            softWrap: ci != t.pnCol,
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: m.paper,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border.all(color: m.ink200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Scrollbar(
          controller: _sc,
          child: SingleChildScrollView(
            controller: _sc,
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: m.ink100,
                    border: Border(bottom: BorderSide(color: m.ink200)),
                  ),
                  children: [
                    for (var ci = 0; ci < t.nCols; ci++) sel(t.header[ci], ci, head: true),
                  ],
                ),
                for (var ri = 0; ri < t.rows.length; ri++)
                  TableRow(
                    decoration: ri == t.rows.length - 1
                        ? null
                        : BoxDecoration(border: Border(bottom: BorderSide(color: m.ink100))),
                    children: [
                      for (var ci = 0; ci < t.nCols; ci++) sel(t.rows[ri][ci], ci, head: false),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pintu masuk TUNGGAL untuk merender jawaban asisten (teks + tabel).
class MasMarkdown extends StatelessWidget {
  final String data;
  final bool selectable;
  final bool dense;
  const MasMarkdown({
    super.key,
    required this.data,
    this.selectable = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final gaya = masMdStyle(m, dense: dense);
    final segmen = splitMarkdown(data);
    if (segmen.length == 1 && segmen.first is MdText) {
      return MarkdownBody(
        data: (segmen.first as MdText).text,
        selectable: selectable,
        styleSheet: gaya,
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in segmen)
          switch (s) {
            MdText(:final text) => MarkdownBody(
                data: text,
                selectable: selectable,
                styleSheet: gaya,
                extensionSet: md.ExtensionSet.gitHubFlavored,
              ),
            MdTab(:final table) => MasMdTable(table: table),
          },
      ],
    );
  }
}
