// lib/screens/retur_screens.dart
// Return / pengembalian barang (migrasi 039) — paritas web:
//   • AjukanReturScreen        ↔ app/pesanan/[code]/retur/page.tsx
//       (pilih barang) → 1. Alasan → 2. Bukti (video unboxing WAJIB + foto)
//       → 3. Solusi → 4. Review → Kirim. Video & foto diunggah langsung saat
//       dipilih (dengan progres), jadi Kirim tinggal mengirim URL.
//   • ReturSayaScreen          ↔ app/retur/page.tsx (Berjalan / Selesai / Semua)
//   • ReturDetailScreen        ↔ app/retur/[code]/page.tsx (stepper, timeline,
//       resi kirim balik, bukti tambahan saat perlu_bukti, batal)
//   • CabangReturScreen / CabangReturDetailScreen ↔ components/ReturKelola.tsx
//       peran "gudang" saja: terima barang / mulai periksa / catatan.
//   ⛔ Layar ADMIN (setujui/tolak/minta bukti/lolos/selesaikan, pengaturan)
//      sengaja TIDAK ada di mobile — admin memakai web.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/mas_ui.dart';
import '../widgets/retur_ui.dart';

const List<String> _kFotoExt = ['jpg', 'jpeg', 'png', 'webp'];

/// Teks WAJIB (aturan pemilik) — jangan diubah tanpa mengubah web. Kalimat
/// pertama ditebalkan seperti web; digabung = teks aturan persis.
const String _kAturanVideo1 =
    'Video unboxing wajib disertakan sebagai bukti pengajuan retur.';
const String _kAturanVideo2 =
    'Pastikan video memperlihatkan kondisi paket dari sebelum dibuka hingga '
    'barang terlihat jelas.';
const String _kPeringatanTanpaVideo1 =
    'Pengajuan retur membutuhkan video unboxing sebagai bukti.';
const String _kPeringatanTanpaVideo2 =
    'Tanpa video unboxing, pengajuan retur dapat ditolak setelah proses verifikasi.';

String _pesan(Object e, String cadangan) =>
    e is ApiException && e.message.isNotEmpty ? e.message : cadangan;

String _extDari(String s) {
  final i = s.lastIndexOf('.');
  if (i < 0 || i == s.length - 1) return '';
  final e = s.substring(i + 1).toLowerCase();
  return e.contains('/') ? '' : e;
}

/// Nama file berekstensi — server menilai format dari ekstensi nama file.
/// Urutan: nama asli → ekstensi path → tebakan dari mimeType → [cadangan].
String _namaFile(XFile f, {String cadangan = ''}) {
  var nama = f.name.trim();
  if (nama.isEmpty) nama = f.path.split('/').last;
  if (_extDari(nama).isNotEmpty) return nama;
  var ext = _extDari(f.path);
  if (ext.isEmpty) {
    final mt = (f.mimeType ?? '').toLowerCase();
    if (mt.contains('quicktime')) {
      ext = 'mov';
    } else if (mt.contains('mp4')) {
      ext = 'mp4';
    } else if (mt == 'image/png') {
      ext = 'png';
    } else if (mt == 'image/webp') {
      ext = 'webp';
    } else if (mt.startsWith('image/')) {
      ext = 'jpg';
    }
  }
  if (ext.isEmpty) ext = cadangan;
  return ext.isEmpty ? nama : '$nama.$ext';
}

String _mb(int byte) => (byte / 1048576).toStringAsFixed(1);

/// Lembar pilihan sumber (kamera / galeri / …).
Future<T?> _pilihDari<T>(
    BuildContext context, String judul, List<(IconData, String, T)> opsi) {
  final m = context.mas;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: m.paper,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MasRadii.sheet))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(judul,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: m.ink900)),
          ),
        ),
        for (final o in opsi)
          ListTile(
            leading: Icon(o.$1, color: m.brand700),
            title: Text(o.$2, style: TextStyle(fontSize: 14, color: m.ink900)),
            onTap: () => Navigator.pop(ctx, o.$3),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

Future<bool> _tanya(BuildContext context, String judul, String isi,
    {String ya = 'Ya'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(judul, style: const TextStyle(fontSize: 16)),
      content: Text(isi, style: const TextStyle(fontSize: 13.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ya)),
      ],
    ),
  );
  return ok == true;
}

/// Pilihan bulat (radio) bergaya kartu — padanan `.rtr-opsi` web.
class _Opsi extends StatelessWidget {
  final bool pilih;
  final bool aktif;
  final Widget isi;
  final VoidCallback onTap;
  const _Opsi({required this.pilih, required this.isi, required this.onTap, this.aktif = true});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Opacity(
      opacity: aktif ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: pilih ? m.brand50 : m.paper,
          borderRadius: BorderRadius.circular(MasRadii.card),
          child: InkWell(
            onTap: aktif ? onTap : null,
            borderRadius: BorderRadius.circular(MasRadii.card),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(MasRadii.card),
                border: Border.all(color: pilih ? m.brand600 : m.ink200, width: pilih ? 1.5 : 1),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: pilih ? m.brand600 : m.ink300, width: pilih ? 5 : 1.5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: isi),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String teks;
  final String? wajib;
  final String? opsional;
  const _Label(this.teks, {this.wajib, this.opsional});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: teks),
          if (wajib != null)
            TextSpan(text: ' $wajib', style: TextStyle(color: m.danger600, fontWeight: FontWeight.w700)),
          if (opsional != null)
            TextSpan(text: ' $opsional', style: TextStyle(color: m.ink400, fontWeight: FontWeight.w400)),
        ]),
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: m.ink800),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool pilih;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.pilih, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Material(
      color: pilih ? m.brand600 : m.paper,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: pilih ? m.brand600 : m.ink200),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: pilih ? Colors.white : m.ink700)),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Ajukan Return
// ══════════════════════════════════════════════════════════════════════

class _VideoBukti {
  final XFile file;
  final String nama;
  final int ukuran;
  final int? lastModifiedMs;
  int pct = 0;
  String? url;
  String? err;
  ReturUnggah? tugas;
  _VideoBukti({required this.file, required this.nama, required this.ukuran, this.lastModifiedMs});
}

class _FotoBukti {
  final Uint8List preview;
  int pct = 0;
  String? url;
  String? err;
  ReturUnggah? tugas;
  _FotoBukti(this.preview);
}

class AjukanReturScreen extends StatefulWidget {
  final Map<String, dynamic> args;
  const AjukanReturScreen({super.key, required this.args});

  @override
  State<AjukanReturScreen> createState() => _AjukanReturScreenState();
}

class _AjukanReturScreenState extends State<AjukanReturScreen> {
  static const _langkahNama = ['Alasan', 'Bukti', 'Solusi', 'Review'];

  OrderDetail? _order;
  ReturConfig? _cfg;
  bool _loaded = false;
  String? _error;

  String _pn = '';
  int _qty = 1;
  int _step = 0;
  String _reason = '';
  String _jenisRusak = '';
  final _detailCtrl = TextEditingController();
  final _pnDipesanCtrl = TextEditingController();
  final _pnDiterimaCtrl = TextEditingController();
  final _deskCtrl = TextEditingController();
  String _solusi = '';
  _VideoBukti? _video;
  final List<_FotoBukti> _fotos = [];
  bool _tanpaVideo = false;
  bool _kirim = false;

  String get _code => '${widget.args['order_code'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _video?.tugas?.batal();
    for (final f in _fotos) {
      if (f.url == null && f.err == null) f.tugas?.batal();
    }
    _detailCtrl.dispose();
    _pnDipesanCtrl.dispose();
    _pnDiterimaCtrl.dispose();
    _deskCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait<Object>(
          [ApiService.order(_code), ApiService.getReturConfig()]);
      if (!mounted) return;
      final o = res[0] as OrderDetail;
      final c = res[1] as ReturConfig;
      final qpn = '${widget.args['pn'] ?? ''}';
      final bisa = (o.retur?.items ?? const <ReturPesananItem>[])
          .where((i) => i.bisa)
          .map((i) => i.partNumber)
          .toList();
      final awal = bisa.contains(qpn) ? qpn : (bisa.length == 1 ? bisa.first : '');
      setState(() {
        _order = o;
        _cfg = c;
        _loaded = true;
      });
      _setPn(awal);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _pesan(e, 'Gagal memuat pesanan');
        _loaded = true;
      });
    }
  }

  void _setPn(String pn) {
    setState(() {
      _pn = pn;
      _qty = 1;
      _pnDipesanCtrl.text = pn;
    });
  }

  OrderItemDetail? get _item {
    for (final it in _order?.items ?? const <OrderItemDetail>[]) {
      if (it.partNumber == _pn) return it;
    }
    return null;
  }

  ReturAlasan? get _alasan {
    for (final a in _cfg?.alasan ?? const <ReturAlasan>[]) {
      if (a.kode == _reason) return a;
    }
    return null;
  }

  String get _detail => _reason == 'rusak' ? _jenisRusak : _detailCtrl.text.trim();

  // ── Unggah video ──

  Future<void> _pilihVideo() async {
    final src = await _pilihDari<ImageSource>(context, 'Video unboxing', const [
      (Icons.videocam_outlined, 'Rekam dengan kamera', ImageSource.camera),
      (Icons.video_library_outlined, 'Pilih dari galeri', ImageSource.gallery),
    ]);
    if (src == null || !mounted) return;
    XFile? f;
    try {
      f = await ImagePicker().pickVideo(source: src);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Tidak bisa membuka ${src == ImageSource.camera ? 'kamera' : 'galeri'}.');
      }
      return;
    }
    if (f == null || !mounted) return;
    await _pasangVideo(f);
  }

  Future<void> _pasangVideo(XFile f) async {
    final cfg = _cfg;
    if (cfg == null) return;
    final nama = _namaFile(f);
    if (!cfg.videoExt.contains(_extDari(nama))) {
      setState(() => _error = 'Format video harus MP4 atau MOV.');
      return;
    }
    final ukuran = await f.length();
    if (!mounted) return;
    if (ukuran > cfg.maksVideoMb * 1024 * 1024) {
      setState(() => _error =
          'Ukuran video ${(ukuran / 1048576).toStringAsFixed(0)} MB — maksimal ${cfg.maksVideoMb} MB. '
          'Potong atau rekam ulang dengan resolusi lebih rendah.');
      return;
    }
    int? ms;
    try {
      ms = (await f.lastModified()).millisecondsSinceEpoch;
    } catch (_) {/* tak semua sumber punya waktu file */}
    if (!mounted) return;
    _video?.tugas?.batal();
    final v = _VideoBukti(file: f, nama: nama, ukuran: ukuran, lastModifiedMs: ms);
    setState(() {
      _error = null;
      _video = v;
      _tanpaVideo = false;
    });
    final up = ApiService.uploadBuktiRetur(
      jenis: 'video',
      stream: f.openRead(),
      length: ukuran,
      filename: nama,
      onProgress: (p) {
        if (mounted && identical(_video, v)) setState(() => v.pct = p);
      },
    );
    v.tugas = up;
    try {
      final url = await up.url;
      if (mounted && identical(_video, v)) {
        setState(() {
          v.url = url;
          v.pct = 100;
        });
      }
    } catch (e) {
      if (mounted && identical(_video, v)) {
        setState(() => v.err = _pesan(e, 'Unggah gagal'));
      }
    }
  }

  void _hapusVideo() {
    _video?.tugas?.batal();
    setState(() => _video = null);
  }

  // ── Unggah foto ──

  Future<void> _pilihFoto() async {
    final cfg = _cfg;
    if (cfg == null) return;
    final sisa = cfg.maksFoto - _fotos.length;
    if (sisa <= 0) return;
    final src = await _pilihDari<ImageSource>(context, 'Foto bukti', const [
      (Icons.photo_camera_outlined, 'Ambil foto', ImageSource.camera),
      (Icons.photo_library_outlined, 'Pilih dari galeri', ImageSource.gallery),
    ]);
    if (src == null || !mounted) return;
    List<XFile> pilih;
    try {
      if (src == ImageSource.camera) {
        final x = await ImagePicker()
            .pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1600);
        pilih = x == null ? const [] : [x];
      } else {
        pilih = await ImagePicker().pickMultiImage(imageQuality: 80, maxWidth: 1600);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Tidak bisa membuka kamera / galeri.');
      return;
    }
    for (final f in pilih.take(sisa)) {
      if (!mounted) return;
      final nama = _namaFile(f, cadangan: 'jpg');
      if (!_kFotoExt.contains(_extDari(nama))) {
        setState(() => _error = 'Foto harus JPG/PNG/WEBP.');
        continue;
      }
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      final foto = _FotoBukti(bytes);
      setState(() => _fotos.add(foto));
      final up = ApiService.uploadBuktiRetur(
        jenis: 'foto',
        stream: f.openRead(),
        length: bytes.length,
        filename: nama,
        onProgress: (p) {
          if (mounted) setState(() => foto.pct = p);
        },
      );
      foto.tugas = up;
      // Tak di-await: foto berikutnya langsung ikut diunggah (paralel, seperti web).
      up.url.then((url) {
        if (mounted) {
          setState(() {
            foto.url = url;
            foto.pct = 100;
          });
        }
      }).catchError((Object e) {
        if (mounted) setState(() => foto.err = _pesan(e, 'Unggah gagal'));
      });
    }
  }

  void _hapusFoto(_FotoBukti f) {
    if (f.url == null && f.err == null) f.tugas?.batal();
    setState(() => _fotos.remove(f));
  }

  // ── Validasi per langkah (persis web) ──

  String? get _salahLangkah {
    final item = _item;
    final alasan = _alasan;
    final video = _video;
    if (_step == 0) {
      if (item == null) return 'Pilih barang yang ingin diretur.';
      if (alasan == null) return 'Pilih alasan return.';
      if (alasan.detail.isNotEmpty && _detail.isEmpty) {
        return 'Isi ${alasan.detail.toLowerCase()}.';
      }
      if (alasan.pn && _pnDiterimaCtrl.text.trim().isEmpty) {
        return 'Isi Part Number yang Anda terima.';
      }
      if (alasan.deskripsiWajib && _deskCtrl.text.trim().length < 10) {
        return 'Jelaskan masalahnya (minimal 10 karakter).';
      }
    }
    if (_step == 1) {
      if (video == null) return 'Video unboxing wajib diunggah.';
      if (video.err != null) return 'Video gagal diunggah — ganti videonya.';
      if (video.url == null) return 'Tunggu video selesai diunggah.';
      if (_fotos.any((f) => f.url == null && f.err == null)) {
        return 'Tunggu foto selesai diunggah.';
      }
      if (alasan != null && alasan.fotoWajib && !_fotos.any((f) => f.url != null)) {
        return 'Alasan "${alasan.label}" wajib disertai minimal 1 foto.';
      }
    }
    if (_step == 2 && _solusi.isEmpty) return 'Pilih solusi yang diinginkan.';
    return null;
  }

  Future<void> _kirimPengajuan() async {
    final item = _item;
    final video = _video;
    final alasan = _alasan;
    if (item == null || video == null || video.url == null) return;
    final nav = AppNav.of(context);
    setState(() {
      _kirim = true;
      _error = null;
    });
    try {
      final r = await ApiService.ajukanRetur(_code, {
        'part_number': item.partNumber,
        'qty': _qty,
        'reason': _reason,
        'reason_detail': _detail,
        'pn_dipesan': alasan?.pn == true ? _pnDipesanCtrl.text.trim().toUpperCase() : '',
        'pn_diterima': alasan?.pn == true ? _pnDiterimaCtrl.text.trim().toUpperCase() : '',
        'description': _deskCtrl.text.trim(),
        'requested_resolution': _solusi,
        'unboxing_video_url': video.url,
        // Durasi TIDAK dikirim: tanpa paket video_player durasi tak terbaca
        // di HP. Waktu file = lastModified salinan yang dipilih (bila ada).
        'video_meta': {
          'ukuran': video.ukuran,
          if (video.lastModifiedMs != null) 'direkam_at': video.lastModifiedMs,
          'nama': video.nama.length > 80 ? video.nama.substring(0, 80) : video.nama,
        },
        'evidence_photo_urls': [
          for (final f in _fotos)
            if (f.url != null) f.url!,
        ],
      });
      if (!mounted) return;
      // Ganti layar form dengan detail (padanan router.replace di web): tombol
      // Kembali dari detail tak boleh membuka form yang sudah terkirim.
      if (nav.canBack) nav.back();
      nav.go(MasScreen.returDetail, part: {'return_code': r.returnCode, 'baru': true});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _pesan(e, 'Pengajuan gagal dikirim.');
        _kirim = false;
      });
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final o = _order;
    final cfg = _cfg;
    final retur = o?.retur;

    Widget isi;
    if (o == null || cfg == null) {
      isi = _loaded
          ? const MasEmpty(
              icon: Icons.receipt_long_outlined,
              title: 'Pesanan tidak ditemukan.',
              subtitle: 'Kode pesanan tidak dikenal atau bukan milik Anda.',
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator(color: m.brand600)),
            );
    } else if (retur == null || !retur.aktif) {
      isi = MasCard(
        child: Text('Fitur return belum aktif. Hubungi admin lewat chat pesanan.',
            style: TextStyle(fontSize: 13, color: m.ink800)),
      );
    } else if (!retur.bisa) {
      isi = MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(retur.alasanTidak.isNotEmpty ? retur.alasanTidak : 'Pesanan ini tidak bisa diretur.',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: m.ink900)),
          const SizedBox(height: 4),
          Text('Batas pengajuan return ${retur.batasHari} hari setelah pesanan diterima.',
              style: TextStyle(fontSize: 12.5, color: m.ink500)),
        ]),
      );
    } else {
      final salah = _step < 3 ? _salahLangkah : null;
      isi = MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _indikator(m),
          const SizedBox(height: 14),
          if (_step == 0) ..._langkahAlasan(m, o, cfg, retur),
          if (_step == 1) ..._langkahBukti(m, cfg),
          if (_step == 2) ..._langkahSolusi(m, cfg),
          if (_step == 3) ..._langkahReview(m, cfg),
          if (salah != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(salah, style: TextStyle(fontSize: 12, color: m.ink500)),
            ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: MasButton(
                label: _step > 0 ? 'Kembali' : 'Batal',
                primary: false,
                expand: true,
                onTap: _kirim
                    ? null
                    : () {
                        if (_step > 0) {
                          setState(() => _step -= 1);
                        } else if (nav.canBack) {
                          nav.back();
                        } else {
                          nav.go(MasScreen.pesananDetail, part: {'order_code': _code});
                        }
                      },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _step < 3
                  ? MasButton(
                      label: 'Lanjut',
                      expand: true,
                      onTap: salah != null ? null : () => setState(() => _step += 1),
                    )
                  : MasButton(
                      label: _kirim ? 'Mengirim…' : 'Kirim Pengajuan Return',
                      expand: true,
                      loading: _kirim,
                      onTap: _kirim ? null : _kirimPengajuan,
                    ),
            ),
          ]),
        ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (_error != null) ...[
          ReturKotak.teks(_error!, tone: MasPillTone.danger),
          const SizedBox(height: 12),
        ],
        isi,
      ],
    );
  }

  Widget _indikator(MasColors m) {
    return Row(children: [
      for (var i = 0; i < _langkahNama.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          child: Column(children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= _step ? m.brand600 : m.ink150,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 5),
            Text('${i + 1}. ${_langkahNama[i]}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: i == _step ? FontWeight.w700 : FontWeight.w500,
                  color: i == _step ? m.brand700 : (i < _step ? m.ink700 : m.ink400),
                )),
          ]),
        ),
      ],
    ]);
  }

  Widget _judul(MasColors m, String teks, [String? sub]) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(teks,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: m.ink900)),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub, style: TextStyle(fontSize: 12.5, color: m.ink500)),
          ],
          const SizedBox(height: 10),
        ],
      );

  // ── 1. Barang + alasan ──
  List<Widget> _langkahAlasan(
      MasColors m, OrderDetail o, ReturConfig cfg, ReturPesanan retur) {
    final item = _item;
    final alasan = _alasan;
    return [
      _judul(m, 'Barang apa yang bermasalah?', 'Satu pengajuan untuk satu barang.'),
      for (final it in o.items) _opsiBarang(m, it, retur),
      if (item != null && item.qty > 1) ...[
        const _Label('Jumlah yang diretur'),
        Row(children: [
          MasButton(
            label: '−',
            primary: false,
            height: 34,
            onTap: _qty > 1 ? () => setState(() => _qty -= 1) : null,
          ),
          SizedBox(
            width: 44,
            child: Text('$_qty',
                textAlign: TextAlign.center,
                style: masMono(size: 15, weight: FontWeight.w700, color: m.ink900)),
          ),
          MasButton(
            label: '+',
            primary: false,
            height: 34,
            onTap: _qty < item.qty ? () => setState(() => _qty += 1) : null,
          ),
          const SizedBox(width: 8),
          Text('dari ${item.qty} pcs', style: TextStyle(fontSize: 12, color: m.ink500)),
        ]),
      ],
      const _Label('Alasan return', wajib: '*'),
      for (final a in cfg.alasan)
        _Opsi(
          pilih: _reason == a.kode,
          onTap: () => setState(() => _reason = a.kode),
          isi: Text(a.label, style: TextStyle(fontSize: 13, color: m.ink900)),
        ),
      if (alasan?.kode == 'rusak') ...[
        const _Label('Jenis kerusakan', wajib: '*'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final j in cfg.jenisRusak)
            _Chip(label: j, pilih: _jenisRusak == j, onTap: () => setState(() => _jenisRusak = j)),
        ]),
      ],
      if (alasan != null && alasan.detail.isNotEmpty && alasan.kode != 'rusak') ...[
        _Label(alasan.detail, wajib: '*'),
        MasInput(
          controller: _detailCtrl,
          hint: 'Mis. ulir baut dudukan aus',
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
      if (alasan != null && alasan.pn) ...[
        const _Label('Part Number yang dipesan'),
        MasInput(
          controller: _pnDipesanCtrl,
          hint: item?.partNumber ?? '',
          mono: true,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
        ),
        const _Label('Part Number yang diterima', wajib: '*'),
        MasInput(
          controller: _pnDiterimaCtrl,
          hint: 'Lihat label / ukiran di barang',
          mono: true,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
        ),
      ],
      if (_reason.isNotEmpty) ...[
        _Label('Deskripsi masalah',
            wajib: alasan?.deskripsiWajib == true ? '*' : null,
            opsional: alasan?.deskripsiWajib == true ? null : '(opsional)'),
        MasInput(
          controller: _deskCtrl,
          hint: 'Ceritakan singkat kondisi barang yang diterima.',
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
        ),
      ],
    ];
  }

  Widget _opsiBarang(MasColors m, OrderItemDetail it, ReturPesanan retur) {
    ReturPesananItem? st;
    for (final x in retur.items) {
      if (x.partNumber == it.partNumber) st = x;
    }
    final berjalan = st?.retur;
    return _Opsi(
      pilih: _pn == it.partNumber,
      aktif: st?.bisa ?? false,
      onTap: () => _setPn(it.partNumber),
      isi: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: it.partNumber,
                  style: masMono(size: 12.5, weight: FontWeight.w700, color: m.ink900)),
              TextSpan(text: ' ${it.name}'),
            ]),
            style: TextStyle(fontSize: 13, color: m.ink900)),
        const SizedBox(height: 2),
        Text(
            '${it.qty} pcs · ${formatRupiah(it.price)}'
            '${berjalan != null ? ' · Return ${berjalan.returnCode}: ${berjalan.statusLabel}' : ''}',
            style: TextStyle(fontSize: 11.5, color: m.ink500)),
      ]),
    );
  }

  // ── 2. Bukti ──
  List<Widget> _langkahBukti(MasColors m, ReturConfig cfg) {
    final video = _video;
    const poin = [
      'Kondisi paket sebelum dibuka',
      'Label / resi pengiriman',
      'Proses membuka paket',
      'Isi paket setelah dibuka',
      'Kondisi barang',
      'Part number / label barang',
      'Kerusakan atau ketidaksesuaian',
    ];
    return [
      _judul(m, 'Bukti Pengajuan Return'),
      ReturKotak(
        tone: MasPillTone.info,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text.rich(TextSpan(children: [
            TextSpan(text: _kAturanVideo1, style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' $_kAturanVideo2'),
          ])),
          const SizedBox(height: 6),
          for (var i = 0; i < poin.length; i++) Text('${i + 1}. ${poin[i]}'),
        ]),
      ),
      const _Label('Video Unboxing', wajib: '* WAJIB'),
      if (video == null)
        Material(
          color: m.ink50,
          borderRadius: BorderRadius.circular(MasRadii.card),
          child: InkWell(
            onTap: _pilihVideo,
            borderRadius: BorderRadius.circular(MasRadii.card),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(MasRadii.card),
                border: Border.all(color: m.ink300),
              ),
              child: Column(children: [
                const Text('🎥', style: TextStyle(fontSize: 26)),
                const SizedBox(height: 4),
                Text('Pilih atau rekam video',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: m.ink900)),
                Text('MP4 / MOV · maks ${cfg.maksVideoMb} MB',
                    style: TextStyle(fontSize: 12, color: m.ink500)),
              ]),
            ),
          ),
        )
      else
        _kartuVideo(m, video),
      if (video == null)
        InkWell(
          onTap: () => setState(() => _tanpaVideo = !_tanpaVideo),
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Checkbox(
                value: _tanpaVideo,
                activeColor: m.brand600,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() => _tanpaVideo = v ?? false),
              ),
              Expanded(
                child: Text('Saya tidak punya video unboxing',
                    style: TextStyle(fontSize: 12.5, color: m.ink600)),
              ),
            ]),
          ),
        ),
      if (_tanpaVideo && video == null) ...[
        const SizedBox(height: 4),
        ReturKotak(
          tone: MasPillTone.warn,
          child: Text.rich(const TextSpan(children: [
            TextSpan(text: _kPeringatanTanpaVideo1, style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' $_kPeringatanTanpaVideo2'),
            TextSpan(
                text: ' Jika punya rekaman lain (mis. video saat barang dicek di bengkel), '
                    'unggah itu dan jelaskan di deskripsi — atau hubungi gudang lewat chat pesanan.'),
          ])),
        ),
      ],
      _Label('Foto Bukti',
          wajib: _alasan?.fotoWajib == true ? '* wajib min. 1' : null,
          opsional: _alasan?.fotoWajib == true ? null : '(opsional)'),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
            'Keseluruhan barang · kerusakan · part number / label barang · label paket · packing',
            style: TextStyle(fontSize: 12, color: m.ink500)),
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in _fotos) _kotakFoto(m, f),
        if (_fotos.length < cfg.maksFoto)
          InkWell(
            onTap: _pilihFoto,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: m.ink50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: m.ink300),
              ),
              child: Text('📷\nTambah foto',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: m.ink600)),
            ),
          ),
      ]),
    ];
  }

  Widget _kartuVideo(MasColors m, _VideoBukti v) {
    Widget status;
    if (v.err != null) {
      status = Text('✕ ${v.err}', style: TextStyle(fontSize: 12.5, color: m.danger600));
    } else if (v.url != null) {
      status = Text('✓ Video sudah diupload',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: m.brand700));
    } else {
      status = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Mengunggah… ${v.pct}%', style: TextStyle(fontSize: 12.5, color: m.ink700)),
        const SizedBox(height: 4),
        MasBar(value: v.pct / 100),
      ]);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: m.ink50,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.ink150),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0F1411),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.movie_outlined, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.nama,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: m.ink900)),
              // Tanpa paket video_player durasi tak bisa dibaca di HP.
              Text('${_mb(v.ukuran)} MB · durasi tidak diketahui',
                  style: TextStyle(fontSize: 11.5, color: m.ink500)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        status,
        const SizedBox(height: 10),
        Row(children: [
          const Spacer(),
          MasButton(label: 'Ganti', primary: false, height: 34, onTap: _pilihVideo),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _hapusVideo,
            child: Text('Hapus', style: TextStyle(color: m.danger600, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }

  Widget _kotakFoto(MasColors m, _FotoBukti f) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(clipBehavior: Clip.none, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Opacity(
            opacity: f.url != null ? 1 : 0.5,
            child: Image.memory(f.preview, width: 84, height: 84, fit: BoxFit.cover),
          ),
        ),
        if (f.url == null && f.err == null)
          Positioned(left: 6, right: 6, bottom: 6, child: MasBar(value: f.pct / 100, height: 5)),
        if (f.err != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: m.danger600,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: const Text('Gagal',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Colors.white)),
            ),
          ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => _hapusFoto(f),
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: m.danger600, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }

  // ── 3. Solusi ──
  List<Widget> _langkahSolusi(MasColors m, ReturConfig cfg) {
    final item = _item;
    return [
      _judul(m, 'Solusi yang Anda inginkan',
          'Keputusan akhir mengikuti hasil verifikasi & pemeriksaan gudang.'),
      for (final s in cfg.solusi)
        _Opsi(
          pilih: _solusi == s.kode,
          onTap: () => setState(() => _solusi = s.kode),
          isi: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.label,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: m.ink900)),
            if (s.ket.isNotEmpty)
              Text(s.ket, style: TextStyle(fontSize: 12, color: m.ink500)),
          ]),
        ),
      if (_solusi == 'refund' && item != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Perkiraan refund: '),
              TextSpan(
                  text: formatRupiah(item.price * _qty),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(
                  text: ' ($_qty × ${formatRupiah(item.price)}). Ongkir & potongan voucher/poin '
                      'dihitung admin saat refund disetujui.'),
            ]),
            style: TextStyle(fontSize: 12.5, color: m.ink600, height: 1.4),
          ),
        ),
    ];
  }

  // ── 4. Review ──
  List<Widget> _langkahReview(MasColors m, ReturConfig cfg) {
    final item = _item;
    if (item == null) return const [];
    final alasan = _alasan;
    final nFoto = _fotos.where((f) => f.url != null).length;
    String solusiLabel = _solusi;
    for (final s in cfg.solusi) {
      if (s.kode == _solusi) solusiLabel = s.label;
    }
    final ok = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: m.brand700);
    final biasa = TextStyle(fontSize: 13, color: m.ink900, height: 1.4);
    final mono = masMono(size: 12.5, weight: FontWeight.w700, color: m.ink900);
    final baris = <(String, Widget)>[
      (
        'Barang',
        Text.rich(TextSpan(children: [
          const TextSpan(text: 'Part Number: '),
          TextSpan(text: item.partNumber, style: mono),
          TextSpan(text: '\n${item.name} · $_qty pcs'),
        ]), style: biasa),
      ),
      ('Alasan', Text('${alasan?.label ?? ''}${_detail.isNotEmpty ? ' — $_detail' : ''}', style: biasa)),
      if (alasan?.pn == true)
        (
          'Part Number',
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'dipesan '),
            TextSpan(
                text: _pnDipesanCtrl.text.trim().isNotEmpty
                    ? _pnDipesanCtrl.text.trim().toUpperCase()
                    : item.partNumber,
                style: mono),
            const TextSpan(text: '\nditerima '),
            TextSpan(text: _pnDiterimaCtrl.text.trim().toUpperCase(), style: mono),
          ]), style: biasa),
        ),
      if (_deskCtrl.text.trim().isNotEmpty)
        ('Deskripsi', Text(_deskCtrl.text.trim(), style: biasa)),
      ('Video Unboxing', Text('✓ Video sudah diupload', style: ok)),
      ('Foto Bukti', nFoto > 0 ? Text('✓ $nFoto foto', style: ok) : Text('—', style: biasa)),
      ('Solusi', Text(solusiLabel, style: biasa)),
    ];
    return [
      _judul(m, 'Periksa Pengajuan Return'),
      for (var i = 0; i < baris.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: i == baris.length - 1 ? null : Border(bottom: BorderSide(color: m.ink100)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 112,
              child: Text(baris[i].$1, style: TextStyle(fontSize: 12.5, color: m.ink500)),
            ),
            Expanded(child: baris[i].$2),
          ]),
        ),
    ];
  }
}

// ══════════════════════════════════════════════════════════════════════
// Kartu ringkas satu return (daftar pembeli & gudang)
// ══════════════════════════════════════════════════════════════════════

class _KartuRetur extends StatelessWidget {
  final ReturRingkas r;
  final bool gudang;
  final VoidCallback onTap;
  const _KartuRetur({required this.r, required this.onTap, this.gudang = false});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return MasCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (gudang)
              Text(r.returnCode,
                  style: masMono(size: 12.5, weight: FontWeight.w700, color: m.ink900)),
            Text(r.name.isNotEmpty ? r.name : r.partNumber,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: m.ink900)),
            Text('${r.partNumber} × ${r.qty}', style: masMono(size: 11.5, color: m.ink500)),
            const SizedBox(height: 3),
            Text(
                gudang
                    ? 'Order ${r.orderCode} · ${r.username} · ${r.reasonLabel}\n'
                        'Solusi: ${r.resolution ?? r.requestedResolution} · ${fmtDate(r.submittedAt)}'
                    : '${r.returnCode} · ${r.reasonLabel} · ${fmtDate(r.submittedAt)}',
                style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.4)),
          ]),
        ),
        const SizedBox(width: 8),
        ReturBadge(status: r.status, label: r.statusLabel),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Return Saya (pembeli)
// ══════════════════════════════════════════════════════════════════════

class ReturSayaScreen extends StatefulWidget {
  const ReturSayaScreen({super.key});

  @override
  State<ReturSayaScreen> createState() => _ReturSayaScreenState();
}

class _ReturSayaScreenState extends State<ReturSayaScreen> {
  static const _tabs = ['Berjalan', 'Selesai', 'Semua'];
  List<ReturRingkas> _rows = [];
  bool _aktif = true;
  bool _loaded = false;
  String? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ApiService.getMyReturns();
      if (!mounted) return;
      setState(() {
        _rows = r.returns;
        _aktif = r.aktif;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _pesan(e, 'Gagal memuat');
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final tampil = _rows
        .where((r) => _tab == 2 ? true : (_tab == 0 ? !r.tamat : r.tamat))
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_error != null) ...[
            ReturKotak.teks(_error!, tone: MasPillTone.danger),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: MasSegmentTabs(
                tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          ),
          const SizedBox(height: 12),
          if (!_loaded)
            ...List.generate(
                3,
                (_) => const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: MasSkeleton(height: 78),
                    ))
          else if (!_aktif)
            MasCard(
              child: Text('Fitur return belum aktif.',
                  style: TextStyle(fontSize: 13, color: m.ink500)),
            )
          else if (tampil.isEmpty)
            MasEmpty(
              icon: Icons.assignment_return_outlined,
              title: 'Belum ada pengajuan return.',
              subtitle: 'Ajukan dari Pesanan Saya → detail pesanan → Ajukan Return.',
              action: MasButton(
                label: 'Pesanan Saya',
                primary: false,
                icon: Icons.receipt_long_outlined,
                onTap: () => nav.go(MasScreen.pesanan),
              ),
            )
          else
            for (final r in tampil)
              _KartuRetur(
                r: r,
                onTap: () => nav.go(MasScreen.returDetail, part: {'return_code': r.returnCode}),
              ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Detail Return (pembeli)
// ══════════════════════════════════════════════════════════════════════

class ReturDetailScreen extends StatefulWidget {
  final Map<String, dynamic> args;
  const ReturDetailScreen({super.key, required this.args});

  @override
  State<ReturDetailScreen> createState() => _ReturDetailScreenState();
}

class _ReturDetailScreenState extends State<ReturDetailScreen> {
  ReturDetail? _r;
  String? _error;
  bool _loaded = false;
  bool _busy = false;
  late final bool _baru = widget.args['baru'] == true;

  final _kurirCtrl = TextEditingController();
  final _resiCtrl = TextEditingController();
  final _catatanCtrl = TextEditingController();

  /// Bukti tambahan yang sudah terunggah (saat status perlu_bukti).
  final List<({String url, String jenis})> _bukti = [];
  int? _unggah; // progres unggah berjalan (null = tidak ada)

  Timer? _poll;

  String get _code => '${widget.args['return_code'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _kurirCtrl.dispose();
    _resiCtrl.dispose();
    _catatanCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ApiService.getRetur(_code);
      if (!mounted) return;
      setState(() {
        _r = r;
        _loaded = true;
      });
      _aturPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _pesan(e, 'Gagal memuat');
        _loaded = true;
      });
    }
  }

  /// Status "realtime": segarkan tiap 30 dtk selama belum selesai & app aktif.
  void _aturPolling() {
    final perlu = _r != null && !_r!.tamat;
    if (perlu && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 30), (_) {
        final st = WidgetsBinding.instance.lifecycleState;
        if (st == null || st == AppLifecycleState.resumed) _load();
      });
    } else if (!perlu) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _jalankan(Future<ReturDetail> Function() fn, {VoidCallback? sukses}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await fn();
      if (!mounted) return;
      setState(() => _r = r);
      sukses?.call();
      _aturPolling();
    } catch (e) {
      if (mounted) setState(() => _error = _pesan(e, 'Gagal'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pilihBukti() async {
    final pilihan = await _pilihDari<String>(context, 'Tambah bukti', const [
      (Icons.photo_library_outlined, 'Foto dari galeri', 'foto_galeri'),
      (Icons.photo_camera_outlined, 'Ambil foto', 'foto_kamera'),
      (Icons.videocam_outlined, 'Rekam video', 'video_kamera'),
      (Icons.video_library_outlined, 'Video dari galeri', 'video_galeri'),
    ]);
    if (pilihan == null || !mounted) return;
    final picker = ImagePicker();
    List<XFile> files;
    try {
      switch (pilihan) {
        case 'foto_galeri':
          files = await picker.pickMultiImage(imageQuality: 80, maxWidth: 1600);
        case 'foto_kamera':
          final x = await picker.pickImage(
              source: ImageSource.camera, imageQuality: 80, maxWidth: 1600);
          files = x == null ? const [] : [x];
        case 'video_kamera':
          final x = await picker.pickVideo(source: ImageSource.camera);
          files = x == null ? const [] : [x];
        default:
          final x = await picker.pickVideo(source: ImageSource.gallery);
          files = x == null ? const [] : [x];
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Tidak bisa membuka kamera / galeri.');
      return;
    }
    final video = pilihan.startsWith('video');
    for (final f in files) {
      if (!mounted) return;
      final nama = _namaFile(f, cadangan: video ? '' : 'jpg');
      final ext = _extDari(nama);
      final jenis = const ['mp4', 'mov', 'm4v'].contains(ext) ? 'video' : 'foto';
      if (jenis == 'foto' && !_kFotoExt.contains(ext)) {
        setState(() => _error = video
            ? 'Format video harus MP4 atau MOV.'
            : 'Foto harus JPG/PNG/WEBP.');
        continue;
      }
      final ukuran = await f.length();
      if (!mounted) return;
      setState(() {
        _unggah = 0;
        _error = null;
      });
      try {
        final up = ApiService.uploadBuktiRetur(
          jenis: jenis,
          stream: f.openRead(),
          length: ukuran,
          filename: nama,
          onProgress: (p) {
            if (mounted) setState(() => _unggah = p);
          },
        );
        final url = await up.url;
        if (mounted) setState(() => _bukti.add((url: url, jenis: jenis)));
      } catch (e) {
        if (mounted) setState(() => _error = _pesan(e, 'Unggah gagal'));
      } finally {
        if (mounted) setState(() => _unggah = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final r = _r;

    if (r == null) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null) ReturKotak.teks(_error!, tone: MasPillTone.danger),
        if (_loaded)
          const MasEmpty(
            icon: Icons.assignment_return_outlined,
            title: 'Pengajuan return tidak ditemukan.',
            subtitle: 'Kode return tidak dikenal atau bukan milik Anda.',
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator(color: m.brand600)),
          ),
      ]);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          if (_error != null) ...[
            ReturKotak.teks(_error!, tone: MasPillTone.danger),
            const SizedBox(height: 12),
          ],
          if (_baru) ...[
            ReturKotak.teks(
                'Pengajuan return #${r.returnCode} berhasil dikirim dan sedang menunggu verifikasi.',
                tone: MasPillTone.brand),
            const SizedBox(height: 12),
          ],

          MasCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text(r.returnCode,
                    style: masMono(size: 14, weight: FontWeight.w700, color: m.ink900)),
                const SizedBox(width: 8),
                ReturBadge(status: r.status, label: r.statusLabel),
                const Spacer(),
              ]),
              const SizedBox(height: 4),
              Text('Diperbarui ${fmtDate(r.updatedAt)}',
                  style: TextStyle(fontSize: 11.5, color: m.ink500)),
              const SizedBox(height: 12),
              ReturStepper(r: r),
            ]),
          ),
          const SizedBox(height: 12),

          // Instruksi sesuai status — hal yang harus dilakukan pembeli sekarang.
          if (r.status == 'ditolak' && r.rejectionReason != null) ...[
            ReturKotak.teks('Alasan: ${r.rejectionReason}',
                tebal: 'Return ditolak.', tone: MasPillTone.danger),
            const SizedBox(height: 12),
          ],
          if (r.status == 'perlu_bukti') ...[
            _kartuPerluBukti(m, r),
            const SizedBox(height: 12),
          ],
          if (r.status == 'menunggu_kirim') ...[
            _kartuKirimBalik(m, r),
            const SizedBox(height: 12),
          ],
          if (r.status == 'diproses') ...[
            ReturKotak.teks(
                r.resolution == 'refund'
                    ? 'Refund ${(r.refundAmount ?? 0) > 0 ? '${formatRupiah(r.refundAmount)} ' : ''}sedang diproses admin.'
                    : 'Barang pengganti sedang disiapkan gudang.',
                tone: MasPillTone.brand),
            const SizedBox(height: 12),
          ],

          MasCard(child: ReturRingkasan(r: r)),
          const SizedBox(height: 12),
          MasCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const ReturJudul('Bukti'),
              ReturBukti(r: r),
            ]),
          ),
          const SizedBox(height: 12),
          MasCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const ReturJudul('Riwayat Status'),
              ReturTimeline(riwayat: r.riwayat),
            ]),
          ),
          const SizedBox(height: 12),
          MasButton(
            label: 'Lihat Pesanan ${r.orderCode}',
            primary: false,
            expand: true,
            onTap: () => nav.go(MasScreen.pesananDetail, part: {'order_code': r.orderCode}),
          ),
          if (r.bisaBatal) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final ok = await _tanya(
                          context, 'Batalkan pengajuan', 'Batalkan pengajuan return ini?');
                      if (ok && mounted) _jalankan(() => ApiService.batalRetur(_code));
                    },
              child: Text('Batalkan Pengajuan',
                  style: TextStyle(color: m.danger600, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kartuTepi(MasColors m, Color tepi, Widget child) => Container(
        decoration: BoxDecoration(
          color: m.paper,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border(
            left: BorderSide(color: tepi, width: 4),
            top: BorderSide(color: m.ink150),
            right: BorderSide(color: m.ink150),
            bottom: BorderSide(color: m.ink150),
          ),
          boxShadow: m.shadow1,
        ),
        padding: const EdgeInsets.all(14),
        child: child,
      );

  Widget _kartuPerluBukti(MasColors m, ReturDetail r) {
    return _kartuTepi(
      m,
      m.warn600,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Admin meminta bukti tambahan',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: m.ink900)),
        if (r.requestNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(r.requestNote!, style: TextStyle(fontSize: 13, color: m.ink800)),
          ),
        const SizedBox(height: 10),
        Row(children: [
          MasButton(
            label: _unggah != null ? 'Mengunggah… $_unggah%' : '+ Foto / Video',
            primary: false,
            height: 36,
            onTap: _unggah != null ? null : _pilihBukti,
          ),
          const SizedBox(width: 10),
          if (_bukti.isNotEmpty)
            Text('✓ ${_bukti.length} file siap',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: m.brand700)),
        ]),
        if (_unggah != null) ...[
          const SizedBox(height: 6),
          MasBar(value: _unggah! / 100),
        ],
        const SizedBox(height: 8),
        MasInput(
          controller: _catatanCtrl,
          hint: 'Catatan untuk admin (opsional)',
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: MasButton(
            label: 'Kirim Bukti Tambahan',
            height: 38,
            loading: _busy,
            onTap: (_busy || _bukti.isEmpty || _unggah != null)
                ? null
                : () => _jalankan(
                      () => ApiService.tambahBuktiRetur(
                        _code,
                        videoUrls: [for (final b in _bukti) if (b.jenis == 'video') b.url],
                        fotoUrls: [for (final b in _bukti) if (b.jenis == 'foto') b.url],
                        catatan: _catatanCtrl.text.trim(),
                      ),
                      sukses: () {
                        _bukti.clear();
                        _catatanCtrl.clear();
                      },
                    ),
          ),
        ),
      ]),
    );
  }

  Widget _kartuKirimBalik(MasColors m, ReturDetail r) {
    final siap = _kurirCtrl.text.trim().isNotEmpty && _resiCtrl.text.trim().length >= 5;
    final teks = TextStyle(fontSize: 13, color: m.ink800, height: 1.55);
    final tebal = const TextStyle(fontWeight: FontWeight.w700);
    return _kartuTepi(
      m,
      m.brand600,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Return disetujui — kirim barang kembali',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: m.ink900)),
        const SizedBox(height: 6),
        Text('1. Kemas barang dengan aman beserta kemasan & label aslinya.', style: teks),
        Text.rich(
            TextSpan(children: [
              const TextSpan(text: '2. Tulis '),
              TextSpan(
                  text: r.returnCode,
                  style: masMono(size: 12.5, weight: FontWeight.w700, color: m.ink900)),
              const TextSpan(text: ' di luar paket.'),
            ]),
            style: teks),
        Text.rich(
            TextSpan(children: [
              const TextSpan(text: '3. Kirim ke '),
              TextSpan(text: 'Gudang ${r.tujuanGudang}', style: tebal),
              if (r.tujuanPic.isNotEmpty) TextSpan(text: ' (PIC ${r.tujuanPic})'),
              const TextSpan(
                  text: ' — alamat lengkap bisa ditanyakan lewat chat pesanan.'),
            ]),
            style: teks),
        Text('4. Isi nama ekspedisi & nomor resi di bawah.', style: teks),
        const SizedBox(height: 10),
        MasInput(
          controller: _kurirCtrl,
          hint: 'Ekspedisi (JNE, J&T, …)',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        MasInput(
          controller: _resiCtrl,
          hint: 'Nomor resi',
          mono: true,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: MasButton(
            label: 'Barang Sudah Dikirim',
            height: 38,
            loading: _busy,
            onTap: (_busy || !siap)
                ? null
                : () => _jalankan(() => ApiService.kirimBalikRetur(
                    _code, _kurirCtrl.text.trim(), _resiCtrl.text.trim().toUpperCase())),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Return Masuk (gudang pemenuh / akun cabang)
// ══════════════════════════════════════════════════════════════════════

/// Filter gudang = FILTER web tanpa "Perlu Pemeriksaan" & "Menunggu Verifikasi".
const List<(String, String)> _kFilterGudang = [
  ('aktif', 'Berjalan'),
  ('menunggu_kirim', 'Menunggu Kiriman'),
  ('dikirim_balik', 'Dikirim Balik'),
  ('diterima_gudang', 'Diterima Gudang'),
  ('diproses', 'Diproses'),
  ('', 'Semua'),
];

class CabangReturScreen extends StatefulWidget {
  const CabangReturScreen({super.key});

  @override
  State<CabangReturScreen> createState() => _CabangReturScreenState();
}

class _CabangReturScreenState extends State<CabangReturScreen> {
  List<ReturRingkas> _rows = [];
  bool _aktif = true;
  bool _loaded = false;
  String? _error;
  String _status = 'aktif';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = _status;
    try {
      final r = await ApiService.branchListReturns(status: status);
      if (!mounted || status != _status) return;
      setState(() {
        _rows = r.returns;
        _aktif = r.aktif;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _pesan(e, 'Gagal memuat');
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_error != null) ...[
            ReturKotak.teks(_error!, tone: MasPillTone.danger),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 34,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final f in _kFilterGudang) ...[
                _Chip(
                  label: f.$2,
                  pilih: _status == f.$1,
                  onTap: () {
                    if (_status == f.$1) return;
                    setState(() {
                      _status = f.$1;
                      _loaded = false;
                    });
                    _load();
                  },
                ),
                const SizedBox(width: 6),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          if (!_loaded)
            ...List.generate(
                3,
                (_) => const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: MasSkeleton(height: 92),
                    ))
          else if (!_aktif)
            MasCard(
              child: Text('Fitur return belum aktif — jalankan migrasi 039_order_returns.sql.',
                  style: TextStyle(fontSize: 13, color: m.ink500)),
            )
          else if (_rows.isEmpty)
            const MasEmpty(
              icon: Icons.assignment_return_outlined,
              title: 'Tidak ada pengajuan return.',
              subtitle: 'Return yang harus diterima & diperiksa gudang ini akan muncul di sini.',
            )
          else
            for (final r in _rows)
              _KartuRetur(
                r: r,
                gudang: true,
                onTap: () =>
                    nav.go(MasScreen.cabangReturDetail, part: {'return_code': r.returnCode}),
              ),
        ],
      ),
    );
  }
}

class CabangReturDetailScreen extends StatefulWidget {
  final Map<String, dynamic> args;
  const CabangReturDetailScreen({super.key, required this.args});

  @override
  State<CabangReturDetailScreen> createState() => _CabangReturDetailScreenState();
}

class _CabangReturDetailScreenState extends State<CabangReturDetailScreen> {
  ReturDetail? _r;
  String? _error;
  bool _loaded = false;
  bool _busy = false;
  bool _catatanBuka = false;
  final _catatanCtrl = TextEditingController();

  String get _code => '${widget.args['return_code'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _catatanCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ApiService.branchGetRetur(_code);
      if (!mounted) return;
      setState(() {
        _r = r;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _pesan(e, 'Gagal memuat');
        _loaded = true;
      });
    }
  }

  Future<void> _aksi(String aksi, {String? note}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ApiService.branchAksiRetur(_code, aksi, note: note);
      if (!mounted) return;
      setState(() {
        _r = r;
        _catatanBuka = false;
        _catatanCtrl.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = _pesan(e, 'Gagal'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final r = _r;

    if (r == null) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null) ReturKotak.teks(_error!, tone: MasPillTone.danger),
        if (_loaded)
          const MasEmpty(
            icon: Icons.assignment_return_outlined,
            title: 'Pengajuan return tidak ditemukan.',
            subtitle: 'Return ini bukan untuk gudang Anda, atau kodenya salah.',
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator(color: m.brand600)),
          ),
      ]);
    }

    final s = r.status;
    // Tombol gudang = ReturKelola web peran "gudang".
    final tombol = <(String, String, bool)>[
      if (s == 'menunggu_kirim' || s == 'dikirim_balik')
        ('terima_barang', '📦 Barang Return Diterima', true),
      if (s == 'diterima_gudang') ('periksa', '🔍 Mulai Pemeriksaan', false),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          if (_error != null) ...[
            ReturKotak.teks(_error!, tone: MasPillTone.danger),
            const SizedBox(height: 12),
          ],
          MasCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text(r.returnCode,
                    style: masMono(size: 15, weight: FontWeight.w700, color: m.ink900)),
                const SizedBox(width: 8),
                ReturBadge(status: r.status, label: r.statusLabel),
              ]),
              const SizedBox(height: 4),
              Text('${r.username} · ${r.gudang}',
                  style: TextStyle(fontSize: 11.5, color: m.ink500)),
              const SizedBox(height: 12),
              ReturStepper(r: r),
            ]),
          ),
          const SizedBox(height: 12),

          // Tindakan
          MasCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const ReturJudul('Tindakan'),
              for (final t in tombol) ...[
                MasButton(
                  label: t.$2,
                  primary: t.$3,
                  expand: true,
                  height: 40,
                  onTap: _busy
                      ? null
                      : () async {
                          final judul = t.$2.replaceFirst(RegExp(r'^\S+\s+'), '');
                          final ok = await _tanya(context, judul, '$judul?');
                          if (ok && mounted) _aksi(t.$1);
                        },
                ),
                const SizedBox(height: 8),
              ],
              MasButton(
                label: '+ Catatan',
                primary: false,
                expand: true,
                height: 40,
                onTap: _busy ? null : () => setState(() => _catatanBuka = !_catatanBuka),
              ),
              if (_catatanBuka) ...[
                const SizedBox(height: 10),
                MasInput(
                  controller: _catatanCtrl,
                  hint: 'Catatan internal (tidak terlihat pembeli)',
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  MasButton(
                    label: _busy ? 'Menyimpan…' : 'Simpan',
                    height: 36,
                    loading: _busy,
                    onTap: (_busy || _catatanCtrl.text.trim().isEmpty)
                        ? null
                        : () => _aksi('catatan', note: _catatanCtrl.text.trim()),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _catatanBuka = false),
                    child: const Text('Batal'),
                  ),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 12),

          MasCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const ReturJudul('🎥 Video Unboxing & Foto Bukti'),
              ReturBukti(r: r),
            ]),
          ),
          const SizedBox(height: 12),
          MasCard(child: ReturRingkasan(r: r)),
          const SizedBox(height: 12),
          MasButton(
            label: 'Lihat Pesanan ${r.orderCode}',
            primary: false,
            expand: true,
            onTap: () =>
                nav.go(MasScreen.cabangPesananDetail, part: {'order_code': r.orderCode}),
          ),
          const SizedBox(height: 12),

          if (r.requestNote != null && s == 'perlu_bukti') ...[
            ReturKotak.teks(r.requestNote!, tebal: 'Diminta:', tone: MasPillTone.warn),
            const SizedBox(height: 12),
          ],
          if (r.rejectionReason != null) ...[
            ReturKotak.teks(r.rejectionReason!, tebal: 'Alasan ditolak:', tone: MasPillTone.danger),
            const SizedBox(height: 12),
          ],
          if (r.adminNote != null) ...[
            MasCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const ReturJudul('Catatan Internal'),
                Text(r.adminNote!, style: TextStyle(fontSize: 12.5, color: m.ink700, height: 1.45)),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          MasCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const ReturJudul('Riwayat Status'),
              ReturTimeline(riwayat: r.riwayat),
            ]),
          ),
        ],
      ),
    );
  }
}
