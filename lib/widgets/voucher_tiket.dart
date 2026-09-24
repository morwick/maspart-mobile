// lib/widgets/voucher_tiket.dart
// Kartu voucher bergaya TIKET + lembar "Pilih Voucher" untuk keranjang.
// Paritas dengan web `components/VoucherTiket.tsx` & `VoucherPicker.tsx`:
// teal = gratis ongkir, oranye = diskon; voucher yang tak bisa dipakai tetap
// tampil abu-abu beserta alasannya.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';

const kTealVoucher = Color(0xFF0F9D8A);
const kTealVoucher2 = Color(0xFF0B7D6E);
const kOranyeVoucher = Color(0xFFEE6A1F);
const kOranyeVoucher2 = Color(0xFFC9530F);

/// "Berakhir dalam 5 jam" / "Berakhir dalam 3 hari" / "s/d 30 Sep 2026".
({String teks, bool mendesak}) sisaWaktuVoucher(String iso) {
  final akhir = DateTime.tryParse(iso)?.toLocal();
  if (akhir == null) return (teks: '', mendesak: false);
  final sisa = akhir.difference(DateTime.now());
  if (sisa.isNegative) return (teks: 'Sudah berakhir', mendesak: true);
  if (sisa.inHours < 1) {
    final mnt = sisa.inMinutes < 1 ? 1 : sisa.inMinutes;
    return (teks: 'Berakhir dalam $mnt menit', mendesak: true);
  }
  if (sisa.inHours < 24) {
    return (teks: 'Berakhir dalam ${sisa.inHours} jam', mendesak: true);
  }
  if (sisa.inDays <= 3) {
    return (teks: 'Berakhir dalam ${sisa.inDays} hari', mendesak: false);
  }
  const bulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  return (
    teks: 's/d ${akhir.day} ${bulan[akhir.month - 1]} ${akhir.year}',
    mendesak: false
  );
}

class VoucherTiket extends StatelessWidget {
  final Voucher v;
  final Widget? aksi;
  final bool redup;
  final bool terpilih;
  final String? catatan;
  final VoidCallback? onTap;

  const VoucherTiket({
    super.key,
    required this.v,
    this.aksi,
    this.redup = false,
    this.terpilih = false,
    this.catatan,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final w1 = v.ongkir ? kTealVoucher : kOranyeVoucher;
    final w2 = v.ongkir ? kTealVoucher2 : kOranyeVoucher2;
    final waktu = sisaWaktuVoucher(v.berakhir);
    final pct = (v.kuota != null && v.kuota! > 0 && v.klaimId == null)
        ? (((v.kuota! - (v.sisaKuota ?? 0)) / v.kuota!) * 100).clamp(0, 100).round()
        : null;

    return Material(
      color: m.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: terpilih ? w1 : m.ink150, width: terpilih ? 1.6 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Sobekan kiri
            Container(
              width: 84,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                gradient: redup
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [w1, w2],
                      ),
                color: redup ? m.ink300 : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      v.ongkir
                          ? Icons.local_shipping_outlined
                          : Icons.local_offer_outlined,
                      color: Colors.white,
                      size: 24),
                  const SizedBox(height: 6),
                  Text(v.ongkir ? 'GRATIS\nONGKIR' : 'DISKON',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4)),
                ],
              ),
            ),
            // Garis perforasi
            SizedBox(
              width: 6,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  7,
                  (_) => Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: m.ink200),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 11, 8, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(v.label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            color: redup ? m.ink500 : m.ink900)),
                    const SizedBox(height: 2),
                    Text(
                        v.minBelanja > 0
                            ? 'Min. belanja ${formatRupiah(v.minBelanja)}'
                            : 'Tanpa minimal belanja',
                        style: TextStyle(
                            fontSize: 12,
                            color: redup ? m.ink500 : m.ink600)),
                    // Judul promo (mis. "Promo Gajian") hanya bila beda dari
                    // label — paritas web VoucherTiket.tsx.
                    if (v.judul.isNotEmpty && v.judul != v.label) ...[
                      const SizedBox(height: 2),
                      Text(v.judul,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: redup ? m.ink400 : m.ink500)),
                    ],
                    if (pct != null) ...[
                      const SizedBox(height: 5),
                      Row(children: [
                        SizedBox(
                          width: 90,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: pct / 100,
                              minHeight: 5,
                              backgroundColor: m.ink100,
                              color: w1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(pct >= 100 ? 'Habis' : '$pct% terklaim',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: w2)),
                      ]),
                    ],
                    const SizedBox(height: 3),
                    Text(waktu.teks,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: waktu.mendesak
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: waktu.mendesak ? m.danger600 : m.ink500)),
                    if (catatan != null && catatan!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(catatan!,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight:
                                  redup ? FontWeight.w400 : FontWeight.w600,
                              color: redup ? m.danger600 : w2)),
                    ],
                  ],
                ),
              ),
            ),
            if (aksi != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Center(child: aksi),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Tombol kecil di sisi kanan tiket (Klaim / Pakai / Habis).
class VoucherTombol extends StatelessWidget {
  final String label;
  final bool ongkir;
  final bool garis;
  final VoidCallback? onTap;
  const VoucherTombol({
    super.key,
    required this.label,
    required this.ongkir,
    this.garis = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final w1 = ongkir ? kTealVoucher : kOranyeVoucher;
    final w2 = ongkir ? kTealVoucher2 : kOranyeVoucher2;
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: garis ? Colors.transparent : w1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: garis ? BorderSide(color: w1) : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            constraints: const BoxConstraints(minWidth: 64),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: garis ? w2 : Colors.white)),
          ),
        ),
      ),
    );
  }
}

/// Buka lembar "Pilih Voucher". Return pilihan baru `{jenis: code}` bila
/// pembeli menekan Pakai Voucher, `null` bila ditutup. [onMuatUlang]
/// dipanggil setelah klaim kode berhasil (keranjang menilai ulang voucher)
/// dan mengembalikan daftar yang baru.
Future<Map<String, String>?> showVoucherPicker(
  BuildContext context, {
  required List<Voucher> items,
  required Map<String, String> pilihan,
  required Future<List<Voucher>> Function() onMuatUlang,
}) {
  // AppNav ada di dalam Scaffold AppShell — BUKAN leluhur rute lembar bawah —
  // jadi diambil dari context pemanggil (keranjang) sebelum lembar dibuka.
  final nav = context.getInheritedWidgetOfExactType<AppNav>();
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VoucherSheet(
      items: items,
      pilihan: pilihan,
      onMuatUlang: onMuatUlang,
      onKeVoucher: nav == null ? null : () => nav.go(MasScreen.voucher),
    ),
  );
}

class _VoucherSheet extends StatefulWidget {
  final List<Voucher> items;
  final Map<String, String> pilihan;
  final Future<List<Voucher>> Function() onMuatUlang;

  /// Pindah ke layar Voucher (klaim) — null bila navigasi tak tersedia.
  final VoidCallback? onKeVoucher;
  const _VoucherSheet(
      {required this.items,
      required this.pilihan,
      required this.onMuatUlang,
      this.onKeVoucher});

  @override
  State<_VoucherSheet> createState() => _VoucherSheetState();
}

class _VoucherSheetState extends State<_VoucherSheet> {
  late List<Voucher> _items = widget.items;
  late final Map<String, String> _draf = {...widget.pilihan};
  final _kode = TextEditingController();
  bool _sibuk = false;
  String? _pesan;
  bool _pesanOk = true;

  @override
  void initState() {
    super.initState();
    // Tombol "Pakai" hidup/mati mengikuti isian kode (paritas web).
    _kode.addListener(_onKode);
  }

  void _onKode() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _kode.removeListener(_onKode);
    _kode.dispose();
    super.dispose();
  }

  Future<void> _tukar() async {
    final c = _kode.text.trim().toUpperCase();
    if (c.isEmpty) return;
    setState(() {
      _sibuk = true;
      _pesan = null;
    });
    try {
      final p = await ApiService.klaimKodeVoucher(c);
      final baru = await widget.onMuatUlang();
      if (!mounted) return;
      setState(() {
        _items = baru;
        _pesan = p;
        _pesanOk = true;
        _kode.clear();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _pesan = e.message;
        _pesanOk = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pesan = 'Gagal memakai kode. Periksa koneksi Anda.';
        _pesanOk = false;
      });
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  int get _hemat {
    var n = 0;
    for (final e in _draf.entries) {
      for (final v in _items) {
        if (v.code == e.value && v.bisa) n += v.potongan;
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final tinggi = MediaQuery.of(context).size.height * 0.88;

    Widget bagian(String jenis, String judul) {
      final list = _items.where((v) => v.jenis == jenis).toList();
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(judul,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: m.ink900)),
            ),
            Text('Pilih 1', style: TextStyle(fontSize: 11.5, color: m.ink500)),
          ]),
          const SizedBox(height: 8),
          if (list.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: m.ink50, borderRadius: BorderRadius.circular(8)),
              child: Text(
                  'Belum ada voucher ${jenis == 'ongkir' ? 'gratis ongkir' : 'diskon'} di Voucher Saya.',
                  style: TextStyle(fontSize: 12.5, color: m.ink500)),
            )
          else
            for (final v in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: VoucherTiket(
                  v: v,
                  redup: !v.bisa,
                  terpilih: _draf[jenis] == v.code,
                  catatan: v.bisa
                      ? 'Hemat ${formatRupiah(v.potongan)}'
                      : v.alasan,
                  onTap: v.bisa
                      ? () => setState(() {
                            if (_draf[jenis] == v.code) {
                              _draf.remove(jenis);
                            } else {
                              _draf[jenis] = v.code;
                            }
                          })
                      : null,
                  aksi: v.bisa
                      ? Icon(
                          _draf[jenis] == v.code
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: _draf[jenis] == v.code
                              ? (v.ongkir ? kTealVoucher : kOranyeVoucher)
                              : m.ink300,
                        )
                      : null,
                ),
              ),
        ]),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: tinggi),
        decoration: BoxDecoration(
          color: m.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: m.ink200, borderRadius: BorderRadius.circular(99)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text('Pilih Voucher',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: m.ink900)),
              ),
              IconButton(
                icon: Icon(Icons.close, color: m.ink600),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _kode,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(fontSize: 15, color: m.ink900),
                  decoration: InputDecoration(
                    hintText: 'Masukkan kode voucher',
                    hintStyle: TextStyle(color: m.ink400),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: m.ink200)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: m.ink200)),
                  ),
                  onSubmitted: (_) => _tukar(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 42,
                child: FilledButton(
                  onPressed:
                      (_sibuk || _kode.text.trim().isEmpty) ? null : _tukar,
                  style: FilledButton.styleFrom(
                    backgroundColor: m.brand600,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(_sibuk ? '…' : 'Pakai'),
                ),
              ),
            ]),
          ),
          if (_pesan != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_pesan!,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: _pesanOk ? m.brand700 : m.danger600)),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              children: _items.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.only(top: 28, bottom: 8),
                        child: Text(
                          'Voucher Saya masih kosong. Klaim voucher dulu, '
                          'lalu kembali ke keranjang.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: m.ink500, height: 1.5),
                        ),
                      ),
                      if (widget.onKeVoucher != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Center(
                            child: TextButton(
                              onPressed: () {
                                // Tutup lembar dulu, baru pindah layar.
                                Navigator.pop(context);
                                widget.onKeVoucher!();
                              },
                              child: const Text('Klaim voucher dulu',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: kOranyeVoucher2)),
                            ),
                          ),
                        ),
                    ]
                  : [bagian('ongkir', 'Gratis Ongkir'), bagian('diskon', 'Diskon')],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                18, 10, 18, 10 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
                border: Border(top: BorderSide(color: m.ink150))),
            child: Row(children: [
              Expanded(
                child: _hemat > 0
                    ? Text.rich(TextSpan(children: [
                        TextSpan(
                            text: 'Hemat ',
                            style: TextStyle(color: m.ink700, fontSize: 13.5)),
                        TextSpan(
                            text: formatRupiah(_hemat),
                            style: const TextStyle(
                                color: kOranyeVoucher2,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ]))
                    : Text('Belum ada voucher dipilih',
                        style: TextStyle(fontSize: 13, color: m.ink400)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, {..._draf}),
                style: FilledButton.styleFrom(
                  backgroundColor: m.brand600,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Pakai Voucher'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
