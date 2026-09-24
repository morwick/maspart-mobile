// lib/widgets/penilaian.dart — penilaian pembeli ala Shopee/Tokopedia.
//
// Paritas web:
//   • Bintang / BintangInput      ↔ components/Bintang.tsx
//   • showNilaiSheet              ↔ components/NilaiPesanan.tsx (modal Nilai Produk)
//   • PenilaianPesananCard        ↔ components/PenilaianPesanan.tsx (pembeli/gudang/admin)
//   • UlasanProdukSection         ↔ components/UlasanProduk.tsx (halaman part)
//   • RatingRingkas               ↔ RatingRingkas (baris ★ di bawah judul part)

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import 'mas_ui.dart';

const Color kBintang = Color(0xFFF5A623);

Color _bintangKosong(MasColors m) =>
    m.isDark ? const Color(0xFF4A504C) : const Color(0xFFD9DCD9);
Color _bintangTeks(MasColors m) =>
    m.isDark ? const Color(0xFFF5B64A) : const Color(0xFFB36F00);

/// 1.234 → "1,2rb" seperti e-commerce.
String terjualLabel(int n) {
  if (n < 1000) return '$n';
  final v = (n / 1000);
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${s.replaceAll('.', ',')}rb';
}

String fmtRating(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

String samarkanNama(String u) {
  if (u.length <= 2) return '${u.isEmpty ? '*' : u[0]}***';
  final bintang = '*' * ((u.length - 2) < 5 ? (u.length - 2) : 5);
  return '${u[0]}$bintang${u[u.length - 1]}';
}

// ══════════════════════════════════════════════════════════════════════
// Bintang
// ══════════════════════════════════════════════════════════════════════

/// Tampilan bintang, boleh pecahan (4,6 → 4 penuh + 0,6).
class Bintang extends StatelessWidget {
  final double nilai;
  final double ukuran;
  const Bintang({super.key, required this.nilai, this.ukuran = 14});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 5; i++)
        _SatuBintang(isi: (nilai - i).clamp(0.0, 1.0), ukuran: ukuran, kosong: _bintangKosong(m)),
    ]);
  }
}

class _SatuBintang extends StatelessWidget {
  final double isi;
  final double ukuran;
  final Color kosong;
  const _SatuBintang({required this.isi, required this.ukuran, required this.kosong});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ukuran,
      height: ukuran,
      child: Stack(children: [
        Icon(Icons.star_rounded, size: ukuran, color: kosong),
        ClipRect(
          clipper: _ClipLebar(isi),
          child: Icon(Icons.star_rounded, size: ukuran, color: kBintang),
        ),
      ]),
    );
  }
}

class _ClipLebar extends CustomClipper<Rect> {
  final double f;
  _ClipLebar(this.f);
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * f, size.height);
  @override
  bool shouldReclip(_ClipLebar old) => old.f != f;
}

/// Masukan bintang 1–5 (ketuk).
class BintangInput extends StatelessWidget {
  final int nilai;
  final ValueChanged<int> onChanged;
  final double ukuran;
  const BintangInput({super.key, required this.nilai, required this.onChanged, this.ukuran = 32});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var n = 1; n <= 5; n++)
        Semantics(
          button: true,
          label: '$n bintang',
          selected: nilai == n,
          child: InkResponse(
            onTap: () => onChanged(n),
            radius: ukuran * 0.7,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.star_rounded,
                  size: ukuran, color: nilai >= n ? kBintang : _bintangKosong(m)),
            ),
          ),
        ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════
// Sheet "Nilai Produk"
// ══════════════════════════════════════════════════════════════════════

/// Buka bottom sheet Nilai Produk. `penilaian` terisi & sudah = mode UBAH (sekali).
/// Kembalian: true bila penilaian tersimpan.
Future<bool> showNilaiSheet(BuildContext context, OrderDetail order,
    {Penilaian? penilaian}) async {
  final hasil = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.mas.paper,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _NilaiSheet(order: order, penilaian: penilaian),
  );
  return hasil == true;
}

class _Draf {
  int rating;
  List<String> tags;
  final TextEditingController komentar;
  List<String> foto;
  _Draf({this.rating = 5, List<String>? tags, String komentar = '', List<String>? foto})
      : tags = tags ?? [],
        komentar = TextEditingController(text: komentar),
        foto = foto ?? [];
}

class _NilaiSheet extends StatefulWidget {
  final OrderDetail order;
  final Penilaian? penilaian;
  const _NilaiSheet({required this.order, this.penilaian});

  @override
  State<_NilaiSheet> createState() => _NilaiSheetState();
}

class _NilaiSheetState extends State<_NilaiSheet> {
  ReviewConfig _cfg = const ReviewConfig();
  late final Map<String, _Draf> _draf;
  late int _layanan;
  late int _kirim;
  late bool _anonim;
  bool _sibuk = false;
  String? _unggah; // PN yang sedang mengunggah foto
  String? _error;

  bool get _ubah => widget.penilaian?.sudah ?? false;

  @override
  void initState() {
    super.initState();
    final lama = {for (final p in widget.penilaian?.produk ?? const <UlasanProdukRow>[]) p.partNumber: p};
    _draf = {
      for (final it in widget.order.items)
        it.partNumber: lama[it.partNumber] != null
            ? _Draf(
                rating: lama[it.partNumber]!.rating,
                tags: [...lama[it.partNumber]!.tags],
                komentar: lama[it.partNumber]!.komentar,
                foto: [...lama[it.partNumber]!.foto],
              )
            : _Draf(),
    };
    final l = widget.penilaian?.layanan;
    _layanan = (l?.ratingLayanan ?? 0) > 0 ? l!.ratingLayanan : 5;
    _kirim = l?.ratingKirim ?? 5;
    _anonim = l?.anonim ?? false;
    ApiService.reviewConfig().then((c) {
      if (mounted) setState(() => _cfg = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final d in _draf.values) {
      d.komentar.dispose();
    }
    super.dispose();
  }

  void _setRating(String pn, int n) {
    // Tag positif/negatif berganti menurut bintang — buang tag kelompok lain.
    final boleh = (n >= 4 ? _cfg.tagPositif : _cfg.tagNegatif).toSet();
    setState(() {
      _draf[pn]!.rating = n;
      _draf[pn]!.tags = _draf[pn]!.tags.where(boleh.contains).toList();
    });
  }

  Future<void> _tambahFoto(String pn) async {
    final d = _draf[pn]!;
    final sisa = _cfg.maksFoto - d.foto.length;
    if (sisa <= 0) return;
    final List<XFile> pilih;
    try {
      pilih = await ImagePicker().pickMultiImage(imageQuality: 80, maxWidth: 1600);
    } catch (_) {
      return;
    }
    if (pilih.isEmpty) return;
    setState(() {
      _unggah = pn;
      _error = null;
    });
    try {
      for (final f in pilih.take(sisa)) {
        final nama = f.name.contains('.') ? f.name : '${f.name}.jpg';
        final url = await ApiService.uploadReviewPhoto(
            bytes: await f.readAsBytes(), filename: nama);
        if (url.isNotEmpty && mounted) setState(() => d.foto.add(url));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _unggah = null);
    }
  }

  Future<void> _kirimNilai() async {
    if (_ubah) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ubah penilaian', style: TextStyle(fontSize: 16)),
          content: const Text('Penilaian hanya bisa diubah 1 kali. Simpan perubahan ini?',
              style: TextStyle(fontSize: 13.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _sibuk = true;
      _error = null;
    });
    try {
      await ApiService.submitReview(widget.order.orderCode, {
        'rating_layanan': _layanan,
        'rating_kirim': widget.order.pickup ? null : _kirim,
        'anonim': _anonim,
        'produk': [
          for (final it in widget.order.items)
            {
              'part_number': it.partNumber,
              'rating': _draf[it.partNumber]!.rating,
              'tags': _draf[it.partNumber]!.tags,
              'komentar': _draf[it.partNumber]!.komentar.text.trim(),
              'foto': _draf[it.partNumber]!.foto,
            },
        ],
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final username = AppNav.of(context).username;
    final label = TextStyle(fontSize: 13, color: m.ink700);
    final labelBintang = TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, color: _bintangTeks(m));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
            child: Row(children: [
              Expanded(
                child: Text(_ubah ? 'Ubah Penilaian' : 'Nilai Produk',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: m.ink900)),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: m.ink500),
                onPressed: _sibuk ? null : () => Navigator.pop(context, false),
              ),
            ]),
          ),
          Divider(height: 1, color: m.ink150),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
              children: [
                if (_ubah)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: m.info50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: m.infoBorder),
                    ),
                    child: Text('Penilaian hanya bisa diubah 1 kali.',
                        style: TextStyle(fontSize: 12.5, color: m.info600)),
                  ),
                for (final it in widget.order.items) _produk(m, it, label, labelBintang),
                // Layanan penjual + kecepatan kirim
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: m.ink50, borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Layanan Penjual', style: label),
                    Row(children: [
                      BintangInput(nilai: _layanan, ukuran: 26, onChanged: (n) => setState(() => _layanan = n)),
                      const SizedBox(width: 8),
                      Text(_cfg.labelBintang(_layanan), style: labelBintang),
                    ]),
                    if (!widget.order.pickup) ...[
                      const SizedBox(height: 8),
                      Text('Kecepatan Pengiriman', style: label),
                      Row(children: [
                        BintangInput(nilai: _kirim, ukuran: 26, onChanged: (n) => setState(() => _kirim = n)),
                        const SizedBox(width: 8),
                        Text(_cfg.labelBintang(_kirim), style: labelBintang),
                      ]),
                    ],
                  ]),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => setState(() => _anonim = !_anonim),
                  child: Row(children: [
                    Checkbox(value: _anonim, onChanged: (v) => setState(() => _anonim = v ?? false)),
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: 'Sembunyikan nama saya', style: label),
                        if (username.isNotEmpty)
                          TextSpan(
                            text: ' — tampil sebagai ${_anonim ? samarkanNama(username) : username}',
                            style: TextStyle(fontSize: 12.5, color: m.ink500),
                          ),
                      ])),
                    ),
                  ]),
                ),
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: m.danger50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: m.dangerBorder),
                    ),
                    child: Text(_error!, style: TextStyle(fontSize: 12.5, color: m.danger600)),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: m.ink150),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            child: Row(children: [
              Expanded(
                child: MasButton(
                  label: 'Nanti Saja',
                  primary: false,
                  expand: true,
                  onTap: _sibuk ? null : () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MasButton(
                  label: _sibuk ? 'Mengirim…' : (_ubah ? 'Simpan Perubahan' : 'Kirim'),
                  expand: true,
                  loading: _sibuk,
                  onTap: (_sibuk || _unggah != null) ? null : _kirimNilai,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _produk(MasColors m, OrderItemDetail it, TextStyle label, TextStyle labelBintang) {
    final d = _draf[it.partNumber]!;
    final tags = d.rating >= 4 ? _cfg.tagPositif : _cfg.tagNegatif;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: m.ink100))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: m.ink50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: m.ink150),
            ),
            child: Icon(Icons.settings_outlined, color: m.ink400, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.name.isEmpty ? it.partNumber : it.name,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: m.ink900)),
              Text('${it.partNumber} · ${it.qty} pcs',
                  style: masMono(size: 11.5, color: m.ink500)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Text('Kualitas Produk', style: label),
        Row(children: [
          BintangInput(nilai: d.rating, onChanged: (n) => _setRating(it.partNumber, n)),
          const SizedBox(width: 8),
          Text(_cfg.labelBintang(d.rating), style: labelBintang),
        ]),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in tags)
              ChoiceChip(
                label: Text(t, style: const TextStyle(fontSize: 12)),
                selected: d.tags.contains(t),
                onSelected: (on) => setState(() {
                  on ? d.tags.add(t) : d.tags.remove(t);
                }),
              ),
          ]),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: d.komentar,
          maxLength: _cfg.maksKomentar,
          minLines: 3,
          maxLines: 6,
          style: const TextStyle(fontSize: 14),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Bagikan pendapatmu tentang produk ini: kualitas, kecocokan di unit, '
                'kemasan… untuk membantu pembeli lain.',
            hintStyle: TextStyle(fontSize: 12.5, color: m.ink400),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final u in d.foto)
            Stack(clipBehavior: Clip.none, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(u, width: 66, height: 66, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(width: 66, height: 66, color: m.ink100)),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => setState(() => d.foto.remove(u)),
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        color: Color(0xBF0F1411), shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 13, color: Colors.white),
                  ),
                ),
              ),
            ]),
          if (d.foto.length < _cfg.maksFoto)
            InkWell(
              onTap: _unggah != null ? null : () => _tambahFoto(it.partNumber),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 66,
                height: 66,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: m.brand50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: m.brand600, width: 1.2),
                ),
                child: _unggah == it.partNumber
                    ? SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: m.brand600))
                    : Text('📷\nTambah Foto\n${d.foto.length}/${_cfg.maksFoto}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, height: 1.25, color: m.brand700)),
              ),
            ),
        ]),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Kartu penilaian di detail pesanan (pembeli / gudang / admin)
// ══════════════════════════════════════════════════════════════════════

enum PeranPenilaian { pembeli, gudang, admin }

class PenilaianPesananCard extends StatefulWidget {
  final OrderDetail order;
  final PeranPenilaian peran;
  final VoidCallback onChange;

  /// Langsung buka sheet Nilai (setelah pembeli menekan "Pesanan Diterima"
  /// atau datang dari tombol "⭐ Nilai" di daftar pesanan).
  final bool bukaOtomatis;

  const PenilaianPesananCard({
    super.key,
    required this.order,
    required this.peran,
    required this.onChange,
    this.bukaOtomatis = false,
  });

  @override
  State<PenilaianPesananCard> createState() => _PenilaianPesananCardState();
}

class _PenilaianPesananCardState extends State<PenilaianPesananCard> {
  bool _sudahBuka = false;

  @override
  void initState() {
    super.initState();
    _cekBukaOtomatis();
  }

  @override
  void didUpdateWidget(covariant PenilaianPesananCard old) {
    super.didUpdateWidget(old);
    _cekBukaOtomatis();
  }

  void _cekBukaOtomatis() {
    final p = widget.order.penilaian;
    if (_sudahBuka || !widget.bukaOtomatis || widget.peran != PeranPenilaian.pembeli) return;
    if (p == null || !p.bisaNilai) return;
    _sudahBuka = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _buka();
    });
  }

  Future<void> _buka() async {
    final p = widget.order.penilaian;
    final ok = await showNilaiSheet(context, widget.order,
        penilaian: (p?.sudah ?? false) ? p : null);
    if (ok) {
      if (mounted) AppNav.of(context).toast('Terima kasih! Penilaianmu sudah terkirim.');
      widget.onChange();
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final o = widget.order;
    final p = o.penilaian;
    if (p == null || o.status != 'selesai') return const SizedBox.shrink();
    final pembeli = widget.peran == PeranPenilaian.pembeli;

    Widget isi;
    if (!p.aktif) {
      if (pembeli) return const SizedBox.shrink();
      isi = Text('Fitur penilaian belum aktif (migrasi 038 belum dijalankan).',
          style: TextStyle(fontSize: 12.5, color: m.ink500));
    } else if (!p.sudah) {
      if (!pembeli) {
        isi = Text('Pembeli belum memberi penilaian.',
            style: TextStyle(fontSize: 12.5, color: m.ink500));
      } else if (p.bisaNilai) {
        isi = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'Bagaimana barangnya? Penilaianmu membantu pembeli lain memilih part yang tepat.'
            '${p.batas != null ? ' Nilai sebelum ${fmtDate(p.batas)}.' : ''}',
            style: TextStyle(fontSize: 13, color: m.ink600, height: 1.45),
          ),
          const SizedBox(height: 10),
          MasButton(label: '⭐ Nilai Pesanan', expand: true, onTap: _buka),
        ]);
      } else {
        isi = Text('Batas waktu penilaian sudah lewat.',
            style: TextStyle(fontSize: 12.5, color: m.ink500));
      }
    } else {
      final l = p.layanan;
      isi = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (l != null) ...[
          _barisBintang(m, 'Layanan Penjual', l.ratingLayanan.toDouble()),
          if (l.ratingKirim != null)
            _barisBintang(m, 'Kecepatan Pengiriman', l.ratingKirim!.toDouble()),
          if (l.anonim)
            Text('Pembeli memilih tampil anonim.',
                style: TextStyle(fontSize: 12, color: m.ink400)),
        ],
        for (final r in p.produk)
          _UlasanBaris(r: r, bisaBalas: widget.peran == PeranPenilaian.gudang, onChange: widget.onChange),
        if (pembeli && p.bisaUbah) ...[
          const SizedBox(height: 10),
          MasButton(label: '✏️ Ubah Penilaian (1x)', primary: false, height: 36, onTap: _buka),
        ],
      ]);
    }

    return MasSectionCard(
      title: '⭐ Penilaian${p.layanan?.diubah == true ? ' · diubah' : ''}',
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), child: isi),
      ],
    );
  }

  Widget _barisBintang(MasColors m, String label, double v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(
              width: 150,
              child: Text(label, style: TextStyle(fontSize: 12.5, color: m.ink600))),
          Bintang(nilai: v),
        ]),
      );
}

class _UlasanBaris extends StatefulWidget {
  final UlasanProdukRow r;
  final bool bisaBalas;
  final VoidCallback onChange;
  const _UlasanBaris({required this.r, required this.bisaBalas, required this.onChange});

  @override
  State<_UlasanBaris> createState() => _UlasanBarisState();
}

class _UlasanBarisState extends State<_UlasanBaris> {
  bool _buka = false;
  bool _sibuk = false;
  String? _err;
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _kirim() async {
    final teks = _ctl.text.trim();
    if (teks.isEmpty) return;
    setState(() {
      _sibuk = true;
      _err = null;
    });
    try {
      await ApiService.replyReview(widget.r.id, teks);
      if (mounted) setState(() => _buka = false);
      widget.onChange();
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final r = widget.r;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: m.ink100))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.name.isEmpty ? r.partNumber : r.name,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: m.ink900)),
        const SizedBox(height: 3),
        Row(children: [
          Bintang(nilai: r.rating.toDouble()),
          const SizedBox(width: 8),
          Flexible(child: Text(r.partNumber, style: masMono(size: 11, color: m.ink400))),
        ]),
        if (r.tags.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in r.tags) MasPill(label: t, tone: MasPillTone.brand, height: 22),
          ]),
        ],
        if (r.komentar.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(r.komentar, style: TextStyle(fontSize: 13, color: m.ink700, height: 1.4)),
        ],
        if (r.foto.isNotEmpty) ...[
          const SizedBox(height: 8),
          FotoUlasanStrip(urls: r.foto),
        ],
        if (r.balasan != null)
          _KotakBalasan(teks: r.balasan!)
        else if (widget.bisaBalas)
          _buka
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    MasInput(
                      controller: _ctl,
                      hint: 'Terima kasih sudah berbelanja…',
                      maxLines: 3,
                      height: 80,
                    ),
                    if (_err != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_err!, style: TextStyle(fontSize: 12, color: m.danger600)),
                      ),
                    const SizedBox(height: 6),
                    Row(children: [
                      MasButton(
                          label: _sibuk ? 'Mengirim…' : 'Kirim Balasan',
                          height: 34,
                          loading: _sibuk,
                          onTap: _sibuk ? null : _kirim),
                      const SizedBox(width: 6),
                      MasButton(
                          label: 'Batal',
                          primary: false,
                          height: 34,
                          onTap: _sibuk ? null : () => setState(() => _buka = false)),
                    ]),
                    const SizedBox(height: 4),
                    Text('Balasan hanya bisa dikirim sekali & tampil publik di halaman produk.',
                        style: TextStyle(fontSize: 11, color: m.ink400)),
                  ]),
                )
              : TextButton(
                  onPressed: () => setState(() => _buka = true),
                  child: Text('💬 Balas ulasan',
                      style: TextStyle(fontSize: 12.5, color: m.brand700)),
                ),
      ]),
    );
  }
}

class _KotakBalasan extends StatelessWidget {
  final String teks;
  final String judul;
  const _KotakBalasan({required this.teks, this.judul = 'Balasan Penjual'});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: m.ink50, borderRadius: BorderRadius.circular(8)),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: '$judul: ',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: m.ink800)),
        TextSpan(text: teks, style: TextStyle(fontSize: 12.5, color: m.ink700)),
      ])),
    );
  }
}

/// Deretan foto ulasan (ketuk → lihat penuh).
class FotoUlasanStrip extends StatelessWidget {
  final List<String> urls;
  const FotoUlasanStrip({super.key, required this.urls});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final u in urls)
        GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (ctx) => Dialog(
              insetPadding: const EdgeInsets.all(12),
              child: InteractiveViewer(child: Image.network(u, fit: BoxFit.contain)),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(u, width: 70, height: 70, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(width: 70, height: 70, color: m.ink100)),
          ),
        ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════
// Halaman part: ringkasan + daftar ulasan
// ══════════════════════════════════════════════════════════════════════

/// Baris ringkas "4,8 ★★★★★ | 12 Penilaian" di bawah judul produk.
class RatingRingkas extends StatelessWidget {
  final double rata;
  final int jumlah;
  final int terjual;
  const RatingRingkas({super.key, required this.rata, required this.jumlah, this.terjual = 0});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    if (jumlah == 0 && terjual == 0) return const SizedBox.shrink();
    final sep = Text('  |  ', style: TextStyle(fontSize: 13, color: m.ink300));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (jumlah > 0) ...[
        Text(fmtRating(rata),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _bintangTeks(m),
                decoration: TextDecoration.underline)),
        const SizedBox(width: 4),
        Bintang(nilai: rata, ukuran: 13),
        sep,
        Text('$jumlah Penilaian', style: TextStyle(fontSize: 13, color: m.ink600)),
      ],
      if (terjual > 0) ...[
        if (jumlah > 0) sep,
        Text('${terjualLabel(terjual)} Terjual', style: TextStyle(fontSize: 13, color: m.ink600)),
      ],
    ]);
  }
}

class UlasanProdukSection extends StatefulWidget {
  final String pn;

  /// Dipanggil saat ringkasan (tanpa filter) termuat — untuk baris ★ di atas.
  final void Function(double rata, int jumlah)? onRingkas;
  const UlasanProdukSection({super.key, required this.pn, this.onRingkas});

  @override
  State<UlasanProdukSection> createState() => _UlasanProdukSectionState();
}

class _UlasanProdukSectionState extends State<UlasanProdukSection> {
  ProdukUlasan? _data;
  List<UlasanPublik> _daftar = [];
  int? _bintang;
  String _filter = '';
  int _page = 1;
  bool _memuat = false;

  @override
  void initState() {
    super.initState();
    _muat(1);
  }

  @override
  void didUpdateWidget(covariant UlasanProdukSection old) {
    super.didUpdateWidget(old);
    if (old.pn != widget.pn) {
      _bintang = null;
      _filter = '';
      _muat(1);
    }
  }

  Future<void> _muat(int page) async {
    if (widget.pn.isEmpty) return;
    setState(() => _memuat = true);
    try {
      final r = await ApiService.productReviews(widget.pn,
          bintang: _bintang, filter: _filter, page: page);
      if (!mounted) return;
      setState(() {
        _page = page;
        _data = page == 1 || _data == null
            ? r
            : ProdukUlasan(
                rata: _data!.rata,
                jumlah: _data!.jumlah,
                distribusi: _data!.distribusi,
                denganFoto: _data!.denganFoto,
                denganKomentar: _data!.denganKomentar,
                ulasan: r.ulasan,
                page: r.page,
                adaLagi: r.adaLagi,
              );
        _daftar = page == 1 ? r.ulasan : [..._daftar, ...r.ulasan];
      });
      if (page == 1 && _bintang == null && _filter.isEmpty) {
        widget.onRingkas?.call(r.rata, r.jumlah);
      }
    } catch (_) {
      // ulasan gagal dimuat → bagian ini cukup tak tampil
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  void _pilih(int? bintang, String filter) {
    setState(() {
      _bintang = bintang;
      _filter = filter;
    });
    _muat(1);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final kosongTotal = d.jumlah == 0 && _bintang == null && _filter.isEmpty;

    Widget chip(String label, int? bintang, String filter) => ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: _bintang == bintang && _filter == filter,
          onSelected: (_) => _pilih(bintang, filter),
        );

    return MasSectionCard(
      title: 'Penilaian Produk',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: kosongTotal
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: Text('Belum ada penilaian untuk produk ini.',
                        style: TextStyle(fontSize: 13, color: m.ink500)),
                  ),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Kotak kuning ala Shopee: angka + bintang + filter
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: m.isDark ? const Color(0xFF2A2517) : const Color(0xFFFFFBF0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: m.isDark ? const Color(0xFF4A3F22) : const Color(0xFFF3E3BD)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(fmtRating(d.rata),
                            style: TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w700, color: _bintangTeks(m))),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text('dari 5',
                              style: TextStyle(fontSize: 13, color: _bintangTeks(m))),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Bintang(nilai: d.rata, ukuran: 18),
                        ),
                      ]),
                      Text('${d.jumlah} penilaian',
                          style: TextStyle(fontSize: 11.5, color: m.ink500)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        chip('Semua', null, ''),
                        for (final n in [5, 4, 3, 2, 1])
                          chip('$n Bintang (${d.distribusi['$n'] ?? 0})', n, ''),
                        chip('Dengan Komentar (${d.denganKomentar})', null, 'komentar'),
                        chip('Dengan Foto (${d.denganFoto})', null, 'foto'),
                      ]),
                    ]),
                  ),
                  if (_daftar.isEmpty && !_memuat)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text('Tidak ada penilaian untuk filter ini.',
                            style: TextStyle(fontSize: 13, color: m.ink500)),
                      ),
                    ),
                  for (final u in _daftar) _ulasan(m, u),
                  if (d.adaLagi) ...[
                    const SizedBox(height: 10),
                    MasButton(
                      label: _memuat ? 'Memuat…' : 'Lihat penilaian lainnya',
                      primary: false,
                      height: 36,
                      loading: _memuat,
                      onTap: _memuat ? null : () => _muat(_page + 1),
                    ),
                  ],
                ]),
        ),
      ],
    );
  }

  Widget _ulasan(MasColors m, UlasanPublik u) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: m.ink100))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: m.brand50,
            child: Text(u.nama.isEmpty ? '?' : u.nama[0].toUpperCase(),
                style: TextStyle(fontWeight: FontWeight.w700, color: m.brand700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.nama, style: TextStyle(fontSize: 12.5, color: m.ink800)),
              const SizedBox(height: 2),
              Bintang(nilai: u.rating.toDouble(), ukuran: 12),
              const SizedBox(height: 2),
              Text('${fmtDate(u.createdAt)}${u.diubah ? ' · diubah' : ''}',
                  style: TextStyle(fontSize: 11, color: m.ink400)),
              if (u.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(u.tags.join(' · '), style: TextStyle(fontSize: 12.5, color: m.ink600)),
              ],
              if (u.komentar.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(u.komentar, style: TextStyle(fontSize: 13.5, color: m.ink800, height: 1.4)),
              ],
              if (u.foto.isNotEmpty) ...[
                const SizedBox(height: 8),
                FotoUlasanStrip(urls: u.foto),
              ],
              if (u.balasan != null) _KotakBalasan(teks: u.balasan!, judul: 'Respon Penjual'),
            ]),
          ),
        ]),
      );
}
