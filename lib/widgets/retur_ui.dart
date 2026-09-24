// lib/widgets/retur_ui.dart — potongan tampilan Return / pengembalian barang.
//
// Paritas web:
//   • ReturBadge / ReturStepper / ReturTimeline / ReturBukti / ReturRingkasan
//       ↔ components/ReturUI.tsx
//   • ReturPesananCard ↔ components/ReturPesanan.tsx (bagian "Pengembalian
//       Barang" di detail pesanan pembeli & daftar return di detail cabang)
// Satu sumber supaya layar pembeli dan gudang tak berbeda bahasa.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import 'mas_ui.dart';

/// Nada pill per status return — sama dengan PILL di ReturUI.tsx.
const Map<String, MasPillTone> kReturTone = {
  'menunggu_verifikasi': MasPillTone.warn,
  'perlu_bukti': MasPillTone.warn,
  'ditolak': MasPillTone.danger,
  'menunggu_kirim': MasPillTone.info,
  'dikirim_balik': MasPillTone.info,
  'diterima_gudang': MasPillTone.info,
  'diperiksa': MasPillTone.info,
  'diproses': MasPillTone.brand,
  'selesai': MasPillTone.brand,
  'dibatalkan': MasPillTone.neutral,
};

/// Langkah baku bila server lama belum mengirim `langkah`.
const List<String> kReturLangkah = [
  'Diajukan', 'Verifikasi', 'Disetujui', 'Kirim Balik', 'Diterima Gudang',
  'Diperiksa', 'Refund / Pengganti', 'Selesai',
];

class ReturBadge extends StatelessWidget {
  final String status;
  final String label;
  const ReturBadge({super.key, required this.status, required this.label});

  @override
  Widget build(BuildContext context) => MasPill(
        label: label.isEmpty ? status : label,
        tone: kReturTone[status] ?? MasPillTone.neutral,
        height: 20,
      );
}

/// Kotak pesan berwarna (alert) — dipakai layar return.
class ReturKotak extends StatelessWidget {
  final Widget child;
  final MasPillTone tone;
  const ReturKotak({super.key, required this.child, this.tone = MasPillTone.info});

  /// Teks polos, opsional dengan awalan tebal.
  factory ReturKotak.teks(String teks,
          {String? tebal, MasPillTone tone = MasPillTone.info}) =>
      ReturKotak(tone: tone, child: _TeksTebal(tebal: tebal, teks: teks));

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final (bg, fg, bd) = warnaNada(m, tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: bd),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 12.5, color: fg, height: 1.45),
        child: child,
      ),
    );
  }

  /// (latar, teks, garis) per nada.
  static (Color, Color, Color) warnaNada(MasColors m, MasPillTone t) =>
      switch (t) {
        MasPillTone.danger => (m.danger50, m.danger600, m.dangerBorder),
        MasPillTone.brand => (m.brand50, m.brand700, m.brand100),
        MasPillTone.warn => (m.warn50, m.warn600, m.warnBorder),
        MasPillTone.neutral => (m.ink100, m.ink700, m.ink200),
        MasPillTone.info => (m.info50, m.info600, m.infoBorder),
      };
}

class _TeksTebal extends StatelessWidget {
  final String? tebal;
  final String teks;
  const _TeksTebal({this.tebal, required this.teks});

  @override
  Widget build(BuildContext context) {
    if (tebal == null) return Text(teks);
    return Text.rich(TextSpan(children: [
      TextSpan(text: tebal, style: const TextStyle(fontWeight: FontWeight.w700)),
      TextSpan(text: teks.isEmpty ? '' : ' $teks'),
    ]));
  }
}

/// Judul kecil di dalam kartu (setara `fontWeight 600, marginBottom 10`).
class ReturJudul extends StatelessWidget {
  final String teks;
  const ReturJudul(this.teks, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(teks,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: context.mas.ink900)),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Stepper
// ══════════════════════════════════════════════════════════════════════

/// Diajukan → … → Selesai. Ditolak/dibatalkan = titik merah setelah langkah
/// terakhir yang dicapai (logika sama persis dengan web).
class ReturStepper extends StatelessWidget {
  final ReturDetail r;
  const ReturStepper({super.key, required this.r});

  static const Map<String, int> _peta = {
    'menunggu_verifikasi': 1, 'perlu_bukti': 1, 'menunggu_kirim': 3,
    'dikirim_balik': 3, 'diterima_gudang': 4, 'diperiksa': 5, 'diproses': 6,
  };

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final dasar = r.langkah.isEmpty ? kReturLangkah : r.langkah;
    final gagal = r.status == 'ditolak' || r.status == 'dibatalkan';
    var ke = r.langkahKe;
    if (gagal) {
      ReturRiwayat? sebelum;
      for (final h in r.riwayat.reversed) {
        if (h.newStatus != r.status) {
          sebelum = h;
          break;
        }
      }
      ke = sebelum == null ? 1 : (_peta[sebelum.newStatus] ?? 1);
      if (ke > dasar.length) ke = dasar.length;
    }
    final langkah = gagal
        ? [...dasar.take(ke), r.status == 'ditolak' ? 'Ditolak' : 'Dibatalkan']
        : dasar;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < langkah.length; i++) ...[
          if (i > 0)
            Container(
              width: 18,
              height: 2,
              margin: const EdgeInsets.only(top: 11),
              color: i <= ke && !(gagal && i == langkah.length - 1)
                  ? m.brand600
                  : m.ink150,
            ),
          _langkah(m, langkah[i], i, ke, gagal && i == langkah.length - 1),
        ],
      ]),
    );
  }

  Widget _langkah(MasColors m, String label, int i, int ke, bool tolak) {
    final lewat = !tolak && i < ke;
    final kini = !tolak && i == ke;
    final Color isi = tolak
        ? m.danger600
        : lewat
            ? m.brand600
            : kini
                ? m.brand50
                : m.paper;
    final Color garis = tolak
        ? m.danger600
        : (lewat || kini)
            ? m.brand600
            : m.ink200;
    return SizedBox(
      width: 66,
      child: Column(children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isi,
            shape: BoxShape.circle,
            border: Border.all(color: garis, width: kini ? 2 : 1),
          ),
          child: tolak
              ? const Icon(Icons.close_rounded, size: 14, color: Colors.white)
              : lewat
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kini ? m.brand700 : m.ink500)),
        ),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.25,
              fontWeight: kini || tolak ? FontWeight.w700 : FontWeight.w500,
              color: tolak
                  ? m.danger600
                  : kini || lewat
                      ? m.brand700
                      : m.ink500,
            )),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Timeline riwayat
// ══════════════════════════════════════════════════════════════════════

class ReturTimeline extends StatelessWidget {
  final List<ReturRiwayat> riwayat;
  const ReturTimeline({super.key, required this.riwayat});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final urut = riwayat.reversed.toList();
    if (urut.isEmpty) {
      return Text('Belum ada riwayat.',
          style: TextStyle(fontSize: 12.5, color: m.ink500));
    }
    return Column(children: [
      for (var i = 0; i < urut.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 18,
              child: Column(children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: i == 0 ? m.brand600 : m.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: i == 0 ? m.brand600 : m.ink300, width: 2),
                  ),
                ),
                if (i < urut.length - 1)
                  Expanded(child: Container(width: 2, color: m.ink150)),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(urut[i].label,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: m.ink900)),
                    Text(
                        '${fmtDate(urut[i].createdAt)}'
                        '${urut[i].changedBy.isNotEmpty ? ' · ${urut[i].changedBy}' : ''}',
                        style: TextStyle(fontSize: 11.5, color: m.ink500)),
                    if (urut[i].note != null) ...[
                      const SizedBox(height: 3),
                      Text(urut[i].note!,
                          style: TextStyle(fontSize: 12.5, color: m.ink700, height: 1.4)),
                    ],
                  ],
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════
// Bukti (video + foto)
// ══════════════════════════════════════════════════════════════════════

Future<void> bukaUrlLuar(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) AppNav.of(context).toast('Tidak bisa membuka $url');
}

/// Lihat foto penuh (ketuk → zoom).
void lihatFotoPenuh(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
    ),
  );
}

/// Video unboxing + video tambahan + foto bukti. Aplikasi belum punya pemutar
/// video bawaan (paket video_player tidak dipasang), jadi video dibuka di
/// pemutar HP lewat tombol "Buka / unduh ↗".
class ReturBukti extends StatelessWidget {
  final ReturDetail r;
  const ReturBukti({super.key, required this.r});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final videos = [r.unboxingVideoUrl, ...r.extraVideoUrls]
        .where((v) => v.trim().isNotEmpty)
        .toList();
    final durasi = r.videoMeta.durasi;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < videos.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: m.ink50,
            borderRadius: BorderRadius.circular(MasRadii.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(MasRadii.card),
              onTap: () => bukaUrlLuar(context, videos[i]),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(MasRadii.card),
                  border: Border.all(color: m.ink150),
                ),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1411),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i == 0 ? '🎥 Video unboxing' : '🎥 Video tambahan $i',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600, color: m.ink900)),
                        if (i == 0 && durasi != null && durasi > 0)
                          Text('${durasi.round()} detik',
                              style: TextStyle(fontSize: 11.5, color: m.ink500)),
                      ],
                    ),
                  ),
                  Text('Buka / unduh ↗',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: m.brand700)),
                ]),
              ),
            ),
          ),
        ),
      if (r.evidencePhotoUrls.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final u in r.evidencePhotoUrls)
            GestureDetector(
              onTap: () => lihatFotoPenuh(context, u),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(u,
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Container(width: 84, height: 84, color: m.ink100)),
              ),
            ),
        ]),
      if (videos.isEmpty && r.evidencePhotoUrls.isEmpty)
        Text('Belum ada bukti.', style: TextStyle(fontSize: 12.5, color: m.ink500)),
    ]);
  }
}

/// Daftar temuan anti-fraud (hanya dipakai bila server mengirimnya).
class ReturPeringatanList extends StatelessWidget {
  final List<ReturPeringatan> list;
  const ReturPeringatanList({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    if (list.isEmpty) {
      return Text('Tidak ada temuan.', style: TextStyle(fontSize: 12.5, color: m.ink500));
    }
    final urut = [...list]..sort((a, b) =>
        a.level == b.level ? 0 : (a.level == 'warn' ? -1 : 1));
    return Column(children: [
      for (final p in urut)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: p.level == 'warn' ? m.danger50 : m.info50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('${p.level == 'warn' ? '⚠️ ' : 'ℹ️ '}${p.pesan}',
              style: TextStyle(
                  fontSize: 12.5,
                  color: p.level == 'warn' ? m.danger600 : m.info600)),
        ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════
// Ringkasan isi pengajuan
// ══════════════════════════════════════════════════════════════════════

class ReturRingkasan extends StatelessWidget {
  final ReturDetail r;
  const ReturRingkasan({super.key, required this.r});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    TextStyle mono({bool tebal = false}) => masMono(
        size: 12.5, weight: tebal ? FontWeight.w600 : FontWeight.w400, color: m.ink900);
    final biasa = TextStyle(fontSize: 13, color: m.ink900, height: 1.4);

    final baris = <(String, Widget)>[
      (
        'Barang',
        Text.rich(TextSpan(children: [
          TextSpan(text: r.partNumber, style: mono(tebal: true)),
          TextSpan(text: ' ${r.name} × ${r.qty}'),
        ]), style: biasa),
      ),
      ('Pesanan', Text(r.orderCode, style: mono())),
      (
        'Alasan',
        Text('${r.reasonLabel}${r.reasonDetail.isNotEmpty ? ' — ${r.reasonDetail}' : ''}',
            style: biasa),
      ),
      if (r.pnDiterima != null)
        (
          'Part Number',
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'dipesan '),
            TextSpan(text: r.pnDipesan ?? r.partNumber, style: mono(tebal: true)),
            const TextSpan(text: ' · diterima '),
            TextSpan(text: r.pnDiterima, style: mono(tebal: true)),
          ]), style: biasa),
        ),
      if (r.description.trim().isNotEmpty)
        ('Deskripsi', Text(r.description, style: biasa)),
      ('Solusi diminta', Text(r.requestedLabel, style: biasa)),
      if (r.resolution != null && r.resolution != r.requestedResolution)
        ('Solusi disetujui', Text(r.solusiLabel, style: biasa)),
      if ((r.refundAmount ?? 0) > 0)
        (
          'Refund',
          Text(formatRupiah(r.refundAmount),
              style: biasa.copyWith(fontWeight: FontWeight.w700)),
        ),
      if (r.returnTrackingNo != null)
        ('Resi return', Text('${r.returnCourier ?? ''} · ${r.returnTrackingNo}', style: mono())),
      if (r.replacementTrackingNo != null)
        ('Resi pengganti', Text(r.replacementTrackingNo!, style: mono())),
      ('Diajukan', Text(fmtDate(r.submittedAt), style: biasa)),
    ];

    return Column(children: [
      for (var i = 0; i < baris.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: i == baris.length - 1
                ? null
                : Border(bottom: BorderSide(color: m.ink100)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 112,
              child: Text(baris[i].$1, style: TextStyle(fontSize: 12.5, color: m.ink500)),
            ),
            Expanded(child: baris[i].$2),
          ]),
        ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════
// Bagian "Pengembalian Barang" di detail pesanan
// ══════════════════════════════════════════════════════════════════════

enum PeranRetur { pembeli, gudang }

/// Pembeli: per barang tombol "Ajukan Return" / status return yang berjalan.
/// Gudang: daftar return pesanan ini → detail pengelolaannya.
class ReturPesananCard extends StatelessWidget {
  final OrderDetail order;
  final PeranRetur peran;
  const ReturPesananCard({super.key, required this.order, required this.peran});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final rt = order.retur;
    if (rt == null || !rt.aktif) return const SizedBox.shrink();

    if (peran == PeranRetur.gudang) {
      if (rt.returns.isEmpty) return const SizedBox.shrink();
      return MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ReturJudul('↩️ Return pada pesanan ini'),
          for (final r in rt.returns)
            InkWell(
              onTap: () => nav.go(MasScreen.cabangReturDetail,
                  part: {'return_code': r.returnCode}),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.returnCode,
                            style: masMono(
                                size: 12.5, weight: FontWeight.w700, color: m.ink900)),
                        Text('${r.partNumber} × ${r.qty} · ${r.reasonLabel}',
                            style: TextStyle(fontSize: 11.5, color: m.ink500)),
                      ],
                    ),
                  ),
                  ReturBadge(status: r.status, label: r.statusLabel),
                  Icon(Icons.chevron_right_rounded, size: 18, color: m.ink400),
                ]),
              ),
            ),
        ]),
      );
    }

    final riwayat =
        rt.returns.where((r) => r.status == 'ditolak' || r.status == 'dibatalkan').toList();

    return MasCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('↩️ Pengembalian Barang',
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: m.ink900)),
          ),
          if (rt.bisa && rt.batas != null)
            Text('Ajukan sebelum ${fmtDate(rt.batas)}',
                style: TextStyle(fontSize: 11.5, color: m.ink500)),
        ]),
        const SizedBox(height: 6),
        if (!rt.bisa)
          Text(rt.alasanTidak.isNotEmpty ? rt.alasanTidak : 'Pesanan ini tidak bisa diretur.',
              style: TextStyle(fontSize: 13, color: m.ink500))
        else
          Text.rich(
            const TextSpan(children: [
              TextSpan(
                  text:
                      'Barang rusak, salah kirim, atau Part Number tidak sesuai? Ajukan return dengan '),
              TextSpan(text: 'video unboxing', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' sebagai bukti.'),
            ]),
            style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.4),
          ),
        const SizedBox(height: 6),
        for (final it in rt.items) _barisBarang(context, m, nav, rt, it),
        if (riwayat.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Riwayat:', style: TextStyle(fontSize: 12, color: m.ink500)),
            for (final r in riwayat)
              GestureDetector(
                onTap: () =>
                    nav.go(MasScreen.returDetail, part: {'return_code': r.returnCode}),
                child: Text('${r.returnCode} (${r.statusLabel})',
                    style: masMono(size: 11.5, color: m.brand700)),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _barisBarang(BuildContext context, MasColors m, AppNav nav, ReturPesanan rt,
      ReturPesananItem it) {
    OrderItemDetail? item;
    for (final x in order.items) {
      if (x.partNumber == it.partNumber) {
        item = x;
        break;
      }
    }
    final nama = (item?.name ?? '').isNotEmpty ? item!.name : it.partNumber;

    Widget aksi;
    final retur = it.retur;
    if (retur != null) {
      aksi = InkWell(
        onTap: () =>
            nav.go(MasScreen.returDetail, part: {'return_code': retur.returnCode}),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ReturBadge(status: retur.status, label: retur.statusLabel),
          const SizedBox(width: 6),
          Text('Lihat →',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: m.brand700)),
        ]),
      );
    } else {
      final tombol = MasButton(
        label: 'Ajukan Return',
        primary: false,
        height: 34,
        onTap: it.bisa
            ? () => nav.go(MasScreen.returAjukan,
                part: {'order_code': order.orderCode, 'pn': it.partNumber})
            : null,
      );
      aksi = it.bisa || rt.alasanTidak.isEmpty
          ? tombol
          : Tooltip(message: rt.alasanTidak, child: tombol);
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: m.ink100))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nama,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: m.ink900)),
            Text(it.partNumber, style: masMono(size: 11, color: m.ink500)),
          ]),
        ),
        const SizedBox(width: 8),
        aksi,
      ]),
    );
  }
}
