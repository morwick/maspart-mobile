// lib/widgets/rak_editor.dart
// Form ubah "Rak & Kartu Stok" untuk SATU pasangan (part × gudang), plus
// penampil foto kartu stok.
//
// Ditaruh di widgets/ karena dipakai DUA layar (Detail Part & menu Rak & Kartu
// Stok) dengan aturan yang harus persis sama — terutama urutan simpan: kode rak
// dulu, foto belakangan (server menolak foto pada baris yang belum punya rak).
// Menyalin formnya ke dua tempat berarti aturan itu bisa menyimpang diam-diam.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Uint8List (bytes foto sebelum diunggah)
import 'package:image_picker/image_picker.dart';

import '../api_service.dart'; // ikut mengekspor models.dart (RakInfo)
import '../theme/mas_theme.dart';
import 'mas_ui.dart';

/// Hasil editor. `dihapus` = seluruh baris rak dibuang; `info` = baris terbaru
/// menurut server. null (nilai kembalian showRakEditor) = user membatalkan.
typedef RakEditResult = ({bool dihapus, RakInfo? info});

/// Buka form ubah rak sebagai bottom sheet. [awal] null = baris baru.
Future<RakEditResult?> showRakEditor(
  BuildContext context, {
  required String pn,
  required String gudang,
  RakInfo? awal,
}) {
  final m = context.mas;
  return showModalBottomSheet<RakEditResult>(
    context: context,
    backgroundColor: m.paper,
    // Form ini punya dua input teks: tanpa isScrollControlled, keyboard menutupi
    // kolom Catatan dan user mengetik buta.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _RakEditSheet(pn: pn, gudang: gudang, awal: awal),
  );
}

/// Foto kartu stok: thumbnail yang bisa diketuk untuk diperbesar.
/// Kartu stok itu tulisan tangan kecil-kecil — tanpa zoom, thumbnailnya sia-sia.
class RakFotoView extends StatelessWidget {
  final String url;
  final double tinggi;
  const RakFotoView({super.key, required this.url, this.tinggi = 150});

  void _buka(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      pageBuilder: (ctx, _, _) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.black54,
          foregroundColor: Colors.white,
          title: const Text('Kartu stok'),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 6,
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return GestureDetector(
      onTap: () => _buka(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MasRadii.input),
        child: Container(
          height: tinggi,
          width: double.infinity,
          color: m.ink100,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, _) => Center(
              child: CircularProgressIndicator(strokeWidth: 2.2, color: m.brand600),
            ),
            errorWidget: (_, _, _) =>
                const Center(child: HatchBox(label: 'foto gagal dimuat')),
          ),
        ),
      ),
    );
  }
}

/// Timestamp ISO → waktu lokal ringkas. Kolom `updated_at` dikirim server dalam
/// UTC; yang tanpa penanda zona diperlakukan UTC juga (sama seperti fmtWaktu di
/// layar admin AI — sengaja tak diimpor dari sana agar widget ini tak
/// bergantung pada file layar).
String fmtWaktuRak(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final berzona = RegExp(r'([zZ]|[+-]\d{2}:?\d{2})$').hasMatch(iso);
  final d = DateTime.tryParse(berzona ? iso : '${iso}Z');
  if (d == null) return iso;
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}.${two(l.minute)}';
}

/// Baris jejak `diperbarui {siapa} · {kapan}` — tanpa alur approval, jejak ini
/// satu-satunya cara menakar apakah datanya masih bisa dipercaya.
String jejakRak(RakInfo info) {
  final siapa = info.updatedBy.trim();
  final kapan = fmtWaktuRak(info.updatedAt);
  if (siapa.isEmpty && kapan.isEmpty) return '';
  if (siapa.isEmpty) return 'diperbarui $kapan';
  if (kapan.isEmpty) return 'diperbarui $siapa';
  return 'diperbarui $siapa · $kapan';
}

class _RakEditSheet extends StatefulWidget {
  final String pn;
  final String gudang;
  final RakInfo? awal;
  const _RakEditSheet({required this.pn, required this.gudang, this.awal});

  @override
  State<_RakEditSheet> createState() => _RakEditSheetState();
}

class _RakEditSheetState extends State<_RakEditSheet> {
  late final _rakCtrl = TextEditingController(text: widget.awal?.rak ?? '');
  late final _catatanCtrl = TextEditingController(text: widget.awal?.catatan ?? '');

  /// Foto yang baru dipilih tapi BELUM diunggah. Unggahan sengaja ditunda
  /// sampai Simpan: server menolak foto bila baris raknya belum ada, jadi baris
  /// harus tersimpan lebih dulu.
  Uint8List? _fotoBaru;
  String _fotoBaruNama = '';

  /// Foto lama ditandai untuk dilepas — juga baru dieksekusi saat Simpan,
  /// supaya menutup sheet tanpa menyimpan tidak menghapus apa pun.
  bool _lepasFoto = false;

  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _rakCtrl.dispose();
    _catatanCtrl.dispose();
    super.dispose();
  }

  String get _fotoLama => _lepasFoto ? '' : (widget.awal?.fotoUrl ?? '');

  Future<void> _pilihFoto(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        // Kartu stok difoto dari jarak dekat; 1600 px sudah terbaca dan
        // menghemat kuota staf gudang yang memakai data seluler.
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() {
        _fotoBaru = bytes;
        _fotoBaruNama = x.name.isEmpty ? 'kartu.jpg' : x.name;
        _lepasFoto = false;
        _err = null;
      });
    } catch (_) {
      if (mounted) setState(() => _err = 'Tidak dapat mengakses kamera/galeri.');
    }
  }

  void _sheetFoto() {
    final m = context.mas;
    showModalBottomSheet(
      context: context,
      backgroundColor: m.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: m.ink200, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 8),
          // Kamera lebih dulu: use-case aslinya memotret kartu stok sambil
          // berdiri di depan rak, bukan memilih file yang sudah ada.
          ListTile(
            leading: Icon(Icons.photo_camera_outlined, color: m.brand600),
            title: const Text('Ambil dari kamera'),
            onTap: () {
              Navigator.pop(ctx);
              _pilihFoto(ImageSource.camera);
            },
          ),
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: m.brand600),
            title: const Text('Pilih dari galeri'),
            onTap: () {
              Navigator.pop(ctx);
              _pilihFoto(ImageSource.gallery);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _simpan() async {
    final rak = _rakCtrl.text.trim();
    if (rak.isEmpty) {
      setState(() => _err = 'Kode rak wajib diisi.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      // 1) Baris rak dulu — foto tak punya tempat menempel sebelum baris ada.
      var info = await ApiService.saveRak(
        pn: widget.pn,
        gudang: widget.gudang,
        rak: rak,
        catatan: _catatanCtrl.text.trim(),
      );
      // 2) Baru fotonya (ganti / lepas).
      if (_fotoBaru != null) {
        final url = await ApiService.uploadRakFoto(
          pn: widget.pn,
          gudang: widget.gudang,
          bytes: _fotoBaru!,
          filename: _fotoBaruNama,
        );
        info = info.copyWith(fotoUrl: url);
      } else if (_lepasFoto && (widget.awal?.fotoUrl ?? '').isNotEmpty) {
        await ApiService.deleteRakFoto(pn: widget.pn, gudang: widget.gudang);
        info = info.copyWith(fotoUrl: '');
      }
      if (!mounted) return;
      Navigator.pop<RakEditResult>(context, (dihapus: false, info: info));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = e.message;
        });
      }
    }
  }

  Future<void> _hapusBaris() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus data rak?'),
        content: Text(
          'Lokasi rak ${widget.pn} di ${widget.gudang} akan dihapus, '
          'termasuk foto kartu stoknya.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Hapus', style: TextStyle(color: context.mas.danger600)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await ApiService.deleteRak(pn: widget.pn, gudang: widget.gudang);
      if (!mounted) return;
      Navigator.pop<RakEditResult>(context, (dihapus: true, info: null));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final adaFoto = _fotoBaru != null || _fotoLama.isNotEmpty;

    return SafeArea(
      child: Padding(
        // Sisipkan tinggi keyboard supaya tombol Simpan tetap terjangkau.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: m.ink200, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.gudang,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: m.ink900)),
                  const SizedBox(height: 2),
                  Text(widget.pn, style: masMono(size: 12.5, color: m.ink500)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft, child: MasEyebrow('Kode rak')),
            const SizedBox(height: 6),
            MasInput(
              controller: _rakCtrl,
              hint: 'mis. A-12',
              mono: true,
              action: TextInputAction.next,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Barang yang terpecah boleh ditulis apa adanya, mis. "A-12 & C-03".',
                style: TextStyle(fontSize: 11.5, color: m.ink500),
              ),
            ),
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft, child: MasEyebrow('Catatan')),
            const SizedBox(height: 6),
            MasInput(
              controller: _catatanCtrl,
              hint: 'opsional — mis. "rak atas, dus biru"',
              maxLines: 3,
            ),
            const SizedBox(height: 14),
            Align(
                alignment: Alignment.centerLeft,
                child: MasEyebrow('Foto kartu stok')),
            const SizedBox(height: 6),
            if (_fotoBaru != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(MasRadii.input),
                child: Image.memory(_fotoBaru!,
                    height: 150, width: double.infinity, fit: BoxFit.cover),
              )
            else if (_fotoLama.isNotEmpty)
              RakFotoView(url: _fotoLama)
            else
              Text(
                'Belum ada foto. Kartu stok difoto sebagai BUKTI VISUAL — '
                'angka stok yang berlaku tetap dari Accurate.',
                style: TextStyle(fontSize: 12, height: 1.45, color: m.ink500),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: MasButton(
                  label: adaFoto ? 'Ganti foto' : 'Ambil foto',
                  icon: Icons.photo_camera_outlined,
                  primary: false,
                  height: 40,
                  expand: true,
                  onTap: _busy ? null : _sheetFoto,
                ),
              ),
              if (adaFoto) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: MasButton(
                    label: 'Lepas foto',
                    icon: Icons.hide_image_outlined,
                    primary: false,
                    height: 40,
                    expand: true,
                    onTap: _busy
                        ? null
                        : () => setState(() {
                              _fotoBaru = null;
                              _fotoBaruNama = '';
                              _lepasFoto = true;
                            }),
                  ),
                ),
              ],
            ]),
            if (_err != null) ...[
              const SizedBox(height: 12),
              _kotakGalat(m, _err!),
            ],
            const SizedBox(height: 16),
            MasButton(
              label: 'Simpan',
              icon: Icons.check_rounded,
              height: 44,
              expand: true,
              loading: _busy,
              onTap: _simpan,
            ),
            if (widget.awal != null) ...[
              const SizedBox(height: 8),
              MasButton(
                label: 'Hapus data rak',
                icon: Icons.delete_outline_rounded,
                primary: false,
                height: 40,
                expand: true,
                onTap: _busy ? null : _hapusBaris,
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Kotak galat merah — versi lokal (setara _alertBox di layar-layar) supaya
/// widget ini berdiri sendiri.
Widget _kotakGalat(MasColors m, String text) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: m.danger50,
        borderRadius: BorderRadius.circular(MasRadii.input),
        border: Border.all(color: m.dangerBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: 15, color: m.danger600),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 12.5, height: 1.45, color: m.danger600)),
        ),
      ]),
    );
