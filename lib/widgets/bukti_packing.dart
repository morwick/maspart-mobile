// lib/widgets/bukti_packing.dart — Bukti packing (foto/video) pesanan kirim kurir.
//
// Masukan penguji 2026-09-29 (migrasi 046): "barang dengan nominal di atas nilai
// tertentu wajib divideo dari sebelum packaging hingga selesai packaging, dan
// bukti di-upload ke system". Paritas web `components/BuktiPacking.tsx`.
// Dipakai panel proses gudang (langkah 3 "Kemas paket") dan detail pesanan
// admin. Ambang & syarat dari SERVER (packingBuktiMin / Wajib / TahanKirim).
//
// Aplikasi belum punya pemutar video bawaan (video_player tak dipasang) — sama
// dengan bukti retur, video dibuka di pemutar HP lewat bukaUrlLuar.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import 'mas_ui.dart';
import 'retur_ui.dart' show bukaUrlLuar, lihatFotoPenuh;

const int _maksFotoMb = 8;
const int _maksVideoMb = 50;

class BuktiPackingPanel extends StatefulWidget {
  final OrderDetail order;

  /// true = endpoint admin (tanpa pagar gudang); false = endpoint cabang.
  final bool admin;

  /// Dipanggil setelah unggah/hapus berhasil — muat ulang pesanan.
  final Future<void> Function() onChanged;

  const BuktiPackingPanel({
    super.key,
    required this.order,
    required this.admin,
    required this.onChanged,
  });

  @override
  State<BuktiPackingPanel> createState() => _BuktiPackingPanelState();
}

class _BuktiPackingPanelState extends State<BuktiPackingPanel> {
  int? _pct; // progres unggah; null = tidak sedang mengunggah
  String? _err;
  String? _hapus; // URL yang sedang dihapus
  ReturUnggah? _tugas;

  @override
  void dispose() {
    _tugas?.batal();
    super.dispose();
  }

  OrderDetail get _o => widget.order;
  bool get _bisaUbah => _o.packingBuktiAktif && _o.status == 'diproses';
  bool get _sibuk => _pct != null || _hapus != null;
  bool get _adaVideo => _o.packingBukti.any((b) => b.video);

  Future<void> _pilih() async {
    final m = context.mas;
    final pilihan = await showModalBottomSheet<(bool, ImageSource)>(
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
          for (final (ikon, label, nilai) in <(IconData, String, (bool, ImageSource))>[
            (Icons.videocam_outlined, 'Rekam video packing', (true, ImageSource.camera)),
            (Icons.video_library_outlined, 'Pilih video dari galeri', (true, ImageSource.gallery)),
            (Icons.photo_camera_outlined, 'Foto dari kamera', (false, ImageSource.camera)),
            (Icons.photo_library_outlined, 'Foto dari galeri', (false, ImageSource.gallery)),
          ])
            ListTile(
              leading: Icon(ikon, color: m.brand600),
              title: Text(label),
              onTap: () => Navigator.pop(ctx, nilai),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (pilihan == null || !mounted) return;
    final (video, sumber) = pilihan;
    XFile? f;
    try {
      f = video
          ? await ImagePicker().pickVideo(source: sumber)
          // Foto dikompres di HP (JPEG) — batas server 8 MB.
          : await ImagePicker().pickImage(source: sumber, imageQuality: 85, maxWidth: 1920);
    } catch (_) {
      if (mounted) {
        setState(() => _err =
            'Tidak bisa membuka ${sumber == ImageSource.camera ? 'kamera' : 'galeri'}.');
      }
      return;
    }
    if (f == null || !mounted) return;
    await _unggah(f, video);
  }

  Future<void> _unggah(XFile f, bool video) async {
    final ukuran = await f.length();
    if (!mounted) return;
    final batas = video ? _maksVideoMb : _maksFotoMb;
    if (ukuran > batas * 1024 * 1024) {
      setState(() => _err =
          '${video ? 'Video' : 'Foto'} ${(ukuran / 1048576).toStringAsFixed(0)} MB — maksimal $batas MB.'
          '${video ? ' Rekam dengan resolusi lebih rendah (mis. 720p).' : ''}');
      return;
    }
    if (_o.packingBukti.length >= _o.packingBuktiMaks) {
      setState(() => _err = 'Maksimal ${_o.packingBuktiMaks} bukti — hapus salah satu dulu.');
      return;
    }
    final nama = f.name.isNotEmpty ? f.name : (video ? 'packing.mp4' : 'packing.jpg');
    setState(() {
      _err = null;
      _pct = 0;
    });
    final up = ApiService.unggahBuktiPacking(
      _o.orderCode,
      admin: widget.admin,
      stream: f.openRead(),
      length: ukuran,
      filename: nama,
      onProgress: (p) {
        if (mounted) setState(() => _pct = p);
      },
    );
    _tugas = up;
    try {
      await up.url;
      if (!mounted) return;
      AppNav.of(context).toast('Bukti packing tersimpan.');
      await widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (_) {
      if (mounted) setState(() => _err = 'Unggah gagal. Periksa koneksi lalu coba lagi.');
    } finally {
      _tugas = null;
      if (mounted) setState(() => _pct = null);
    }
  }

  Future<void> _buang(String url) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus bukti packing?', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _hapus = url;
      _err = null;
    });
    try {
      await ApiService.hapusBuktiPacking(_o.orderCode, url, admin: widget.admin);
      await widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (_) {
      if (mounted) setState(() => _err = 'Gagal menghapus bukti. Coba lagi.');
    } finally {
      if (mounted) setState(() => _hapus = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final o = _o;
    final bukti = o.packingBukti;
    if (!o.packingBuktiAktif) {
      // Migrasi 046 belum jalan: syarat tak dipaksakan — cukup beri tahu gudang.
      return o.status == 'diproses' && !widget.admin
          ? Text('Unggah bukti packing belum aktif (migrasi 046 belum dijalankan).',
              style: TextStyle(fontSize: 11.5, color: m.ink500))
          : const SizedBox.shrink();
    }
    if (!_bisaUbah && bukti.isEmpty) {
      return o.status == 'diproses'
          ? const SizedBox.shrink()
          : Text('Tidak ada bukti packing.', style: TextStyle(fontSize: 12, color: m.ink500));
    }
    final wajibBelum = o.packingBuktiWajib && !_adaVideo;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: m.ink150),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('🎥 Bukti packing',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: m.ink800)),
          const SizedBox(width: 6),
          Flexible(
            child: o.packingBuktiWajib
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: wajibBelum ? m.danger50 : m.brand50,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${wajibBelum ? '' : '✓ '}WAJIB video (total ≥ ${formatRupiah(o.packingBuktiMin)})',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: wajibBelum ? m.danger600 : m.brand700),
                    ),
                  )
                : Text('opsional', style: TextStyle(fontSize: 11, color: m.ink500)),
          ),
          const Spacer(),
          Text('${bukti.length}/${o.packingBuktiMaks}',
              style: TextStyle(fontSize: 11, color: m.ink400)),
        ]),
        if (_bisaUbah) ...[
          const SizedBox(height: 6),
          Text(
            '${o.packingBuktiWajib ? 'Rekam SATU video tanpa putus: barang + PN terlihat sebelum dikemas, '
                'proses mengemas, sampai paket tertutup & berlabel.' : 'Foto/video barang sebelum & '
                'sesudah dikemas — bukti bila pembeli mengaku barang kurang/rusak.'} '
            'Foto maks $_maksFotoMb MB, video MP4/MOV maks $_maksVideoMb MB.',
            style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.4),
          ),
        ],
        if (bukti.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in bukti) _kartu(m, b),
          ]),
        ],
        if (_bisaUbah) ...[
          const SizedBox(height: 8),
          if (_pct != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (_pct ?? 0) / 100,
                minHeight: 6,
                backgroundColor: m.ink150,
                color: m.brand600,
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Text('Mengunggah… $_pct%', style: TextStyle(fontSize: 11.5, color: m.ink600)),
              const Spacer(),
              TextButton(
                onPressed: () => _tugas?.batal(),
                child: Text('Batal', style: TextStyle(fontSize: 12, color: m.ink600)),
              ),
            ]),
          ] else
            MasButton(
              label: wajibBelum ? '🎥 Unggah Video Packing' : '＋ Unggah Foto / Video',
              primary: wajibBelum,
              expand: true,
              height: 40,
              onTap: _sibuk || bukti.length >= o.packingBuktiMaks ? null : _pilih,
            ),
        ],
        if (_err != null) ...[
          const SizedBox(height: 6),
          Text(_err!, style: TextStyle(fontSize: 12, color: m.danger600, height: 1.4)),
        ],
      ]),
    );
  }

  Widget _kartu(MasColors m, BuktiPacking b) {
    final gambar = b.video
        ? Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: const Color(0xFF0F1411),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
              Text('Video', style: TextStyle(fontSize: 11, color: Colors.white70)),
            ]),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(b.url,
                width: 84,
                height: 84,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(width: 84, height: 84, color: m.ink100)),
          );
    return SizedBox(
      width: 84,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => b.video ? bukaUrlLuar(context, b.url) : lihatFotoPenuh(context, b.url),
          child: gambar,
        ),
        if (_bisaUbah)
          SizedBox(
            height: 26,
            child: TextButton(
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero, minimumSize: const Size(84, 26)),
              onPressed: _sibuk ? null : () => _buang(b.url),
              child: Text(_hapus == b.url ? '…' : 'Hapus',
                  style: TextStyle(fontSize: 11.5, color: m.danger600)),
            ),
          ),
      ]),
    );
  }
}
