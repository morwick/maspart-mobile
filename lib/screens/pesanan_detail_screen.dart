// lib/screens/pesanan_detail_screen.dart
// Detail satu pesanan (sisi pembeli): progres, rincian barang, pengiriman,
// pembayaran Midtrans, aksi pembeli, dan chat dengan gudang.
//
// Alur bayar: pesanan baru datang ke sini dengan `autopay: true` → WebView Snap
// langsung terbuka. Apa pun hasil WebView, kebenaran pembayaran tetap diambil
// dari `paymentStatus()` (yang dikonfirmasi webhook Midtrans), bukan dari
// tebakan URL — makanya setelah WebView ditutup kita polling.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../invoice_pdf.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/beli_lagi.dart';
import '../widgets/mas_ui.dart';
import '../widgets/order_chat.dart';
import '../widgets/penilaian.dart';
import '../widgets/retur_ui.dart';
import 'pembayaran_webview.dart';

/// Gudang FISIK pengirim, tanpa prefiks nomor. Kolom `gudang` berisi CABANG
/// pemroses — untuk sub-gudang seperti '06.B80 H1' keduanya berbeda.
String _gudangKirim(OrderDetail o) =>
    (o.fulfillGudang ?? '').replaceFirst(RegExp(r'^\s*\d+\s*\.\s*'), '').trim();

class PesananDetailScreen extends StatefulWidget {
  final Map<String, dynamic> args;
  const PesananDetailScreen({super.key, required this.args});

  @override
  State<PesananDetailScreen> createState() => _PesananDetailScreenState();
}

class _PesananDetailScreenState extends State<PesananDetailScreen> {
  OrderDetail? _order;
  bool _loaded = false;
  String? _error;

  String? _senderPlace;
  bool _checking = false;

  /// Perjalanan paket dari kurir — hanya ada setelah admin mengisi resi.
  TrackingResult? _track;
  bool _melacak = false;

  /// Aksi yang sedang berjalan: 'confirm' | 'cancel' | 'proof'.
  String? _busy;

  Timer? _poll;
  bool _autopayDone = false;
  bool _invoiceBusy = false;
  bool _beliLagiBusy = false;

  /// Buka sheet Nilai otomatis: setelah "Pesanan Diterima" atau datang dari
  /// tombol "⭐ Nilai" di daftar pesanan (args['nilai'] == true).
  late bool _bukaNilai = widget.args['nilai'] == true;

  String get _code => '${widget.args['order_code'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _load().then((_) => _maybeAutopay());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Backend men-cache 10 menit, jadi memanggilnya tiap layar dibuka tidak
  /// menguras kuota API kurir. ⛔ Kegagalan TIDAK boleh menjatuhkan layar —
  /// pesanan tetap harus tampil walau layanan lacak sedang mati.
  Future<void> _lacak() async {
    final o = _order;
    if (o == null || (o.trackingNo ?? '').isEmpty || _melacak) return;
    setState(() => _melacak = true);
    try {
      final t = await ApiService.orderTracking(_code);
      if (mounted) setState(() => _track = t);
    } catch (_) {
      if (mounted) {
        setState(() => _track = const TrackingResult(
            adaResi: true, error: 'Gagal menghubungi layanan lacak.'));
      }
    } finally {
      if (mounted) setState(() => _melacak = false);
    }
  }

  Future<void> _load() async {
    try {
      final o = await ApiService.order(_code);
      if (!mounted) return;
      setState(() {
        _order = o;
        _loaded = true;
      });
      _syncPolling();
      _resolveSender();
      _lacak();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loaded = true;
      });
    }
  }

  /// Auto-poll selama pembayaran gateway masih menunggu — status berubah
  /// sendiri begitu webhook Midtrans masuk, tanpa pembeli menekan apa pun.
  void _syncPolling() {
    final o = _order;
    final perlu = o != null &&
        o.paymentMethod == 'gateway' &&
        o.status == 'menunggu_pembayaran';
    if (perlu && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 8), (_) => _checkPayment());
    } else if (!perlu) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Koordinat gudang → nama lokasi, supaya pembeli tahu barangnya dari mana.
  Future<void> _resolveSender() async {
    final o = _order;
    if (o?.gudangLat == null || o?.gudangLon == null || _senderPlace != null) {
      return;
    }
    try {
      final p = await ApiService.geoReverse(o!.gudangLat!, o.gudangLon!);
      final name = p.address.isNotEmpty ? p.address : p.displayName;
      if (mounted && name.isNotEmpty) setState(() => _senderPlace = name);
    } on ApiException {
      /* nama lokasi cuma pelengkap — koordinat & PIC tetap tampil */
    }
  }

  Future<void> _maybeAutopay() async {
    if (_autopayDone) return;
    _autopayDone = true;
    final url = '${widget.args['payment_url'] ?? ''}';
    if (widget.args['autopay'] != true || url.isEmpty) return;
    await _openSnap(url);
  }

  Future<void> _openSnap(String url) async {
    final outcome = await Navigator.of(context).push<SnapOutcome>(
      MaterialPageRoute(
        builder: (_) => PembayaranWebView(url: url, orderCode: _code),
      ),
    );
    if (!mounted) return;
    if (outcome == SnapOutcome.gagal) {
      setState(() => _error = 'Pembayaran dibatalkan atau gagal. Coba lagi.');
    }
    // Apa pun hasilnya, tanyakan ke server — itulah kebenarannya.
    await _checkPayment();
    await _load();
  }

  Future<void> _checkPayment() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final r = await ApiService.paymentStatus(_code);
      if (r.paid && mounted) await _load();
    } on ApiException {
      /* diamkan — polling berikutnya mencoba lagi */
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _doConfirm() async {
    final pickup = _order?.pickup ?? false;
    final ok = await _confirm(
      pickup ? 'Barang sudah diambil?' : 'Pesanan diterima?',
      pickup
          ? 'Konfirmasi bahwa barang sudah Anda ambil & periksa? Pesanan akan ditandai selesai.'
          : 'Konfirmasi bahwa barang sudah Anda terima & periksa? Pesanan akan ditandai selesai.',
    );
    if (ok != true) return;
    // Seperti Shopee: begitu pesanan diterima, langsung tawarkan penilaian.
    if (mounted) setState(() => _bukaNilai = true);
    await _run('confirm', () => ApiService.confirmOrder(_code),
        gagal: 'Gagal mengonfirmasi penerimaan.');
  }

  Future<void> _doCancel() async {
    final ok = await _confirm(
      'Batalkan pesanan',
      'Batalkan pesanan ini? Pastikan Anda BELUM melakukan pembayaran — '
          'membatalkan setelah transfer dapat membuat dana tertahan.',
    );
    if (ok != true) return;
    await _run('cancel', () => ApiService.cancelOrder(_code),
        gagal: 'Gagal membatalkan pesanan.');
  }

  Future<void> _doUploadProof() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _run(
      'proof',
      () => ApiService.uploadProof(_code, bytes: bytes, filename: file.name),
      gagal: 'Gagal mengunggah bukti.',
    );
  }

  Future<void> _run(String tag, Future<void> Function() action,
      {required String gagal}) async {
    setState(() {
      _busy = tag;
      _error = null;
    });
    try {
      await action();
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : gagal);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 16)),
          content: Text(body, style: const TextStyle(fontSize: 13.5)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ya')),
          ],
        ),
      );

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) AppNav.of(context).toast('Tidak bisa membuka $url');
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppNav.of(context).toast('$label disalin');
  }

  /// Buat & buka Invoice PDF (pesanan lunas). Setara "Cetak Invoice" web.
  Future<void> _cetakInvoice(OrderDetail o) async {
    if (_invoiceBusy) return;
    setState(() => _invoiceBusy = true);
    try {
      await downloadInvoicePdf(o);
    } catch (e) {
      if (mounted) AppNav.of(context).toast('Gagal membuat invoice: $e');
    } finally {
      if (mounted) setState(() => _invoiceBusy = false);
    }
  }

  /// "Beli Lagi": isi pesanan ini dimasukkan lagi ke keranjang (harga/stok
  /// terkini dari server), lalu ringkasan + buka Keranjang.
  Future<void> _beliLagi() async {
    if (_beliLagiBusy) return;
    setState(() => _beliLagiBusy = true);
    try {
      await beliLagiDariPesanan(context, _code);
    } finally {
      if (mounted) setState(() => _beliLagiBusy = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final o = _order;

    if (o == null) {
      return Center(
        child: _loaded
            ? const MasEmpty(
                icon: Icons.receipt_long_outlined,
                title: 'Pesanan tidak ditemukan',
                subtitle: 'Kode pesanan tidak dikenal atau bukan milik Anda.',
              )
            : CircularProgressIndicator(color: m.brand600),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          if (_error != null) ...[
            _alert(m, _error!, tone: MasPillTone.danger),
            const SizedBox(height: 14),
          ],

          MasCard(child: OrderStepper(status: o.status, pickup: o.pickup)),
          const SizedBox(height: 14),

          _items(m, o),
          const SizedBox(height: 14),

          // Invoice hanya untuk pesanan LUNAS (setara halaman invoice web).
          if (invoiceTersedia(o)) ...[
            MasButton(
              label: _invoiceBusy ? 'Menyiapkan…' : '🧾 Cetak Invoice (PDF)',
              primary: false,
              expand: true,
              loading: _invoiceBusy,
              onTap: _invoiceBusy ? null : () => _cetakInvoice(o),
            ),
            const SizedBox(height: 14),
          ],

          // Beli Lagi (pola Shopee) — pesanan selesai / batal / dikirim.
          if (nav.isBuyer && kStatusBeliLagi.contains(o.status)) ...[
            MasButton(
              label: _beliLagiBusy ? 'Memasukkan ke keranjang…' : 'Beli Lagi',
              icon: Icons.replay_rounded,
              primary: o.status != 'dikirim',
              expand: true,
              loading: _beliLagiBusy,
              onTap: _beliLagiBusy ? null : _beliLagi,
            ),
            const SizedBox(height: 14),
          ],

          if (o.trackingNo != null && o.trackingNo!.isNotEmpty) ...[
            _pengiriman(m, o),
            const SizedBox(height: 14),
          ],

          // Pesanan ambil sendiri: yang penting bagi pembeli bukan "dikirim dari
          // mana", tapi KE MANA ia harus datang.
          if (o.pickup) ...[
            _ambilDiToko(m, o),
            const SizedBox(height: 14),
          ] else ...[
            _pengirim(m, o),
            const SizedBox(height: 14),
          ],

          if (o.recipientName != null || o.recipientAddress != null) ...[
            _penerima(m, o),
            const SizedBox(height: 14),
          ],

          _pembayaran(m, o),
          const SizedBox(height: 14),

          // Penilaian ala Shopee — muncul begitu pesanan selesai.
          if (o.status == 'selesai' && o.penilaian != null) ...[
            PenilaianPesananCard(
              order: o,
              peran: PeranPenilaian.pembeli,
              bukaOtomatis: _bukaNilai,
              onChange: () {
                setState(() => _bukaNilai = false);
                _load();
              },
            ),
            const SizedBox(height: 14),
          ],

          // Return per barang — tombol Ajukan Return / status return berjalan.
          if (o.retur?.aktif == true) ...[
            ReturPesananCard(order: o, peran: PeranRetur.pembeli),
            const SizedBox(height: 14),
          ],

          OrderChat(
            title: 'Chat dengan Gudang ${o.gudang}',
            me: nav.username,
            fetch: () async => (await ApiService.orderChat(_code)).messages,
            send: (body) => ApiService.sendOrderChat(_code, body),
          ),
        ],
      ),
    );
  }

  Widget _alert(MasColors m, String msg, {MasPillTone tone = MasPillTone.info}) {
    late Color bg, fg, bd;
    switch (tone) {
      case MasPillTone.danger:
        bg = m.danger50; fg = m.danger600; bd = m.dangerBorder;
      case MasPillTone.brand:
        bg = m.brand50; fg = m.brand700; bd = m.brand100;
      case MasPillTone.warn:
        bg = m.warn50; fg = m.warn600; bd = m.warnBorder;
      default:
        bg = m.info50; fg = m.info600; bd = m.infoBorder;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: bd),
      ),
      child: Text(msg, style: TextStyle(fontSize: 12.5, color: fg, height: 1.45)),
    );
  }

  Widget _items(MasColors m, OrderDetail o) {
    // PPN inklusif: pakai `tax` dari server bila ada, kalau tidak hitung sendiri
    // dengan rumus yang sama persis (floor(subtotal × 12 / 112)).
    final ppn = o.tax?.round() ?? ppnOf(o.subtotal);

    return MasSectionCard(
      title: o.orderCode,
      trailing: MasPill(
        label: orderStatusLabel(o.status, pickup: o.pickup),
        tone: orderStatusTone(o.status),
        height: 20,
      ),
      children: [
        for (final it in o.items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: m.ink100)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(it.partNumber,
                        style: masMono(
                            size: 12, weight: FontWeight.w600, color: m.ink900)),
                    const SizedBox(height: 2),
                    Text(it.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: m.ink700)),
                    const SizedBox(height: 2),
                    Text('${formatRupiah(it.price)} × ${it.qty}',
                        style: TextStyle(fontSize: 11.5, color: m.ink500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(formatRupiah(it.lineTotal),
                  style: masMono(
                      size: 13, weight: FontWeight.w600, color: m.ink900)),
            ]),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(children: [
            _sumRow(m, 'Subtotal', formatRupiah(o.subtotal)),
            const SizedBox(height: 5),
            _sumRow(m, 'Termasuk PPN 12%', formatRupiah(ppn), muted: true),
            const SizedBox(height: 5),
            _sumRow(
              m,
              o.pickup
                  ? 'Ongkir (ambil sendiri)'
                  : 'Ongkir${o.courier != null && o.courier!.isNotEmpty ? ' (${o.courier!.toUpperCase()}${o.courierService != null && o.courierService!.isNotEmpty ? ' ${o.courierService}' : ''})' : ''}',
              o.pickup
                  ? 'Gratis'
                  : o.shippingCost > 0
                      ? formatRupiah(o.shippingCost)
                      : '—',
            ),
            // Potongan voucher/poin + kode voucher — paritas web OrderPotongan.
            OrderPotongan(order: o),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Divider(height: 1, color: m.ink150),
            ),
            Row(children: [
              Expanded(
                child: Text('Total',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: m.ink900)),
              ),
              Text(formatRupiah(o.total),
                  style: masMono(
                      size: 16, weight: FontWeight.w700, color: m.brand700)),
            ]),
          ]),
        ),

        if (o.note != null && o.note!.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: m.ink100)),
            ),
            child: Text('Catatan: ${o.note}',
                style: TextStyle(fontSize: 12.5, color: m.ink600)),
          ),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text('Dibuat ${fmtDate(o.createdAt)} · oleh ${o.username}',
              style: TextStyle(fontSize: 11, color: m.ink400)),
        ),
      ],
    );
  }

  Widget _sumRow(MasColors m, String label, String value, {bool muted = false}) =>
      Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: muted ? 12.5 : 13,
                  color: muted ? m.ink400 : m.ink500)),
        ),
        Text(value,
            style: masMono(
                size: muted ? 12.5 : 13, color: muted ? m.ink400 : m.ink800)),
      ]);

  Widget _pengiriman(MasColors m, OrderDetail o) {
    final resi = o.trackingNo!;
    return MasSectionCard(
      title: '🚚 Pengiriman',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('No. Resi',
                    style: TextStyle(fontSize: 12.5, color: m.ink500)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(resi,
                      style: masMono(
                          size: 13,
                          weight: FontWeight.w700,
                          color: m.ink900)),
                ),
                IconButton(
                  icon: Icon(Icons.copy_rounded, size: 16, color: m.ink500),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copy(resi, 'No. resi'),
                ),
              ]),
              if (o.courier != null && o.courier!.isNotEmpty)
                Text(
                  '${o.courier!.toUpperCase()}'
                  '${o.courierService != null && o.courierService!.isNotEmpty ? ' ${o.courierService}' : ''}',
                  style: TextStyle(fontSize: 12, color: m.ink500),
                ),
              const SizedBox(height: 8),
              // Perjalanan paket langsung dari kurir — pembeli tak perlu
              // menyalin nomor resi ke situs lain.
              if (_melacak && _track == null)
                Text('Melacak paket…',
                    style: TextStyle(fontSize: 12.5, color: m.ink500))
              else if ((_track?.riwayat.isNotEmpty ?? false)) ...[
                Row(children: [
                  MasPill(
                    label: _track!.delivered
                        ? 'TERKIRIM'
                        : (_track!.status.isEmpty
                            ? 'DALAM PERJALANAN'
                            : _track!.status),
                    tone: _track!.delivered
                        ? MasPillTone.brand
                        : MasPillTone.info,
                    height: 18,
                  ),
                  const SizedBox(width: 8),
                  if (_track!.delivered && _track!.penerima.isNotEmpty)
                    Expanded(
                      child: Text(
                        'diterima ${_track!.penerima}'
                        '${_track!.waktuTerima.isEmpty ? '' : ' · ${_track!.waktuTerima}'}',
                        style: TextStyle(fontSize: 12, color: m.ink500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, size: 16, color: m.ink500),
                    visualDensity: VisualDensity.compact,
                    onPressed: _melacak ? null : _lacak,
                  ),
                ]),
                const SizedBox(height: 4),
                for (var i = 0; i < _track!.riwayat.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 5, right: 8),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == 0 ? m.brand700 : m.ink300,
                          ),
                        ),
                        Expanded(
                          child: Text.rich(TextSpan(children: [
                            TextSpan(
                                text: '${_track!.riwayat[i].waktu} ',
                                style: TextStyle(color: m.ink500)),
                            TextSpan(text: _track!.riwayat[i].keterangan),
                            if (_track!.riwayat[i].lokasi.isNotEmpty)
                              TextSpan(
                                  text: ' · ${_track!.riwayat[i].lokasi}',
                                  style: TextStyle(color: m.ink500)),
                          ]), style: const TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ),
              ] else
                GestureDetector(
                  onTap: () => _launch(
                      'https://cekresi.com/?noresi=${Uri.encodeComponent(resi)}'),
                  child: Text(
                      _track?.error == null
                          ? 'Lacak paket →'
                          : 'Perjalanan paket belum bisa ditampilkan — cek di situs kurir →',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: m.brand700)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Kartu "Ambil di Toko" — pengganti Lokasi Pengirim untuk pesanan yang
  /// dijemput sendiri: alamat gudang, kontak, dan kode yang harus dibawa.
  Widget _ambilDiToko(MasColors m, OrderDetail o) {
    final gd = (o.pickupGudang?.isNotEmpty ?? false)
        ? o.pickupGudang!
        : (_gudangKirim(o).isNotEmpty ? _gudangKirim(o) : o.gudang);
    return MasSectionCard(
      title: '🏬 Ambil di Toko',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ambil sendiri di Gudang $gd — tanpa ongkir.',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: m.ink900)),
              const SizedBox(height: 4),
              Text(
                'Bawa kode pesanan ${o.orderCode}'
                '${o.status == 'diproses' ? ' setelah gudang mengabari barang siap.' : '.'}',
                style: TextStyle(fontSize: 12, color: m.ink500),
              ),
              if (o.status == 'dikirim' && (o.batasAmbilAt?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 4),
                Text(
                  'Ambil sebelum ${fmtDate(o.batasAmbilAt)} — lewat tanggal itu admin akan menghubungi Anda.',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: m.warn600),
                ),
              ],
              if (o.pickupPic != null && o.pickupPic!.isNotEmpty) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _launch(
                      'tel:${o.pickupPic!.replaceAll(RegExp(r'[^\d+]'), '')}'),
                  child: Row(children: [
                    Icon(Icons.phone_outlined, size: 14, color: m.brand700),
                    const SizedBox(width: 5),
                    Text('Kontak gudang: ',
                        style: TextStyle(fontSize: 12.5, color: m.ink500)),
                    Text(o.pickupPic!,
                        style: masMono(
                            size: 12.5,
                            weight: FontWeight.w600,
                            color: m.brand700)),
                  ]),
                ),
              ],
              if (o.pickupLat != null && o.pickupLon != null) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _launch(
                      'https://www.google.com/maps/search/?api=1&query=${o.pickupLat},${o.pickupLon}'),
                  child: Text('Lihat lokasi gudang di peta →',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: m.brand700)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _pengirim(MasColors m, OrderDetail o) {
    final kirim = _gudangKirim(o);
    return MasSectionCard(
      title: '📦 Lokasi Pengirim',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gudang ${kirim.isNotEmpty ? kirim : o.gudang}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: m.ink900)),
              // Sub-gudang: yang mengirim beda dari cabang yang memproses.
              if (kirim.isNotEmpty && kirim != o.gudang)
                Text('Diproses cabang ${o.gudang}',
                    style: TextStyle(fontSize: 12, color: m.ink500)),
              if (o.gudangLat != null && o.gudangLon != null) ...[
                const SizedBox(height: 4),
                Text('Lokasi: ${_senderPlace ?? 'memuat lokasi…'}',
                    style: TextStyle(fontSize: 12, color: m.ink500)),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _launch(
                      'https://www.google.com/maps/search/?api=1&query=${o.gudangLat},${o.gudangLon}'),
                  child: Text('Lihat di peta →',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: m.brand700)),
                ),
              ],
              if (o.gudangPic != null && o.gudangPic!.isNotEmpty) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _launch(
                      'tel:${o.gudangPic!.replaceAll(RegExp(r'[^\d+]'), '')}'),
                  child: Row(children: [
                    Icon(Icons.phone_outlined, size: 14, color: m.brand700),
                    const SizedBox(width: 5),
                    Text('PIC Gudang: ${o.gudangPic}',
                        style: masMono(size: 12, color: m.brand700)),
                  ]),
                ),
              ],
              const SizedBox(height: 6),
              Text('Dipilih otomatis sesuai ketersediaan stok.',
                  style: TextStyle(fontSize: 11.5, color: m.ink400)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _penerima(MasColors m, OrderDetail o) => MasSectionCard(
        title: '📍 Penerima',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${o.recipientName ?? ''}'
                  '${o.recipientPhone != null && o.recipientPhone!.isNotEmpty ? ' · ${o.recipientPhone}' : ''}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: m.ink900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${o.recipientAddress ?? ''}'
                  '${o.recipientPostal != null && o.recipientPostal!.isNotEmpty ? ' (${o.recipientPostal})' : ''}',
                  style: TextStyle(fontSize: 12.5, color: m.ink600, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _pembayaran(MasColors m, OrderDetail o) {
    final gateway = o.paymentMethod == 'gateway';
    final menungguBayar = o.status == 'menunggu_pembayaran';
    final lunas = ['diproses', 'dikirim', 'selesai'].contains(o.status);

    return MasSectionCard(
      title: 'Pembayaran',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (gateway && menungguBayar) ...[
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Bayar '),
                    TextSpan(
                      text: formatRupiah(o.total),
                      style: masMono(
                          size: 13, weight: FontWeight.w700, color: m.ink900),
                    ),
                    TextSpan(
                      text: o.paymentChannel == 'snap'
                          ? ' — pilih metode (VA / QRIS / e-wallet / kartu) di halaman pembayaran Midtrans.'
                          : o.paymentChannel != null &&
                                  o.paymentChannel!.isNotEmpty
                              ? ' via ${o.paymentChannel!.toUpperCase()}.'
                              : '.',
                    ),
                  ]),
                  style: TextStyle(fontSize: 13, color: m.ink700, height: 1.55),
                ),
                const SizedBox(height: 12),

                if (o.paymentVa != null && o.paymentVa!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: m.ink50,
                      borderRadius: BorderRadius.circular(MasRadii.input),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nomor Virtual Account',
                            style:
                                TextStyle(fontSize: 11.5, color: m.ink500)),
                        const SizedBox(height: 3),
                        Row(children: [
                          Expanded(
                            child: Text(o.paymentVa!,
                                style: masMono(
                                    size: 17,
                                    weight: FontWeight.w700,
                                    color: m.ink900)),
                          ),
                          IconButton(
                            icon: Icon(Icons.copy_rounded,
                                size: 16, color: m.ink500),
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                _copy(o.paymentVa!, 'Nomor VA'),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                if (o.paymentQr != null && o.paymentQr!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: m.ink50,
                      borderRadius: BorderRadius.circular(MasRadii.input),
                    ),
                    child: Column(children: [
                      Text('Scan QRIS',
                          style: TextStyle(fontSize: 11.5, color: m.ink500)),
                      const SizedBox(height: 8),
                      if (o.paymentQr!.startsWith('http'))
                        Image.network(o.paymentQr!,
                            width: 200, height: 200, fit: BoxFit.contain)
                      else
                        SelectableText(o.paymentQr!,
                            style: masMono(size: 10, color: m.ink600)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],

                if (o.paymentUrl != null && o.paymentUrl!.isNotEmpty) ...[
                  MasButton(
                    label: 'Buka Halaman Pembayaran',
                    icon: Icons.lock_outline_rounded,
                    expand: true,
                    onTap: () => _openSnap(o.paymentUrl!),
                  ),
                  const SizedBox(height: 10),
                ],

                if (o.paymentExpiry != null && o.paymentExpiry!.isNotEmpty) ...[
                  Text('Batas bayar: ${fmtDate(o.paymentExpiry)}',
                      style: TextStyle(fontSize: 11.5, color: m.ink500)),
                  const SizedBox(height: 10),
                ],

                MasButton(
                  label: _checking ? 'Mengecek…' : 'Cek Status Pembayaran',
                  primary: false,
                  height: 38,
                  expand: true,
                  loading: _checking,
                  onTap: _checkPayment,
                ),
                const SizedBox(height: 10),
                _alert(m, 'Status diperbarui otomatis setelah pembayaran masuk.'),
              ],

              if (o.status == 'menunggu_verifikasi')
                _alert(m, 'Menunggu verifikasi pembayaran.'),

              if (lunas)
                _alert(
                  m,
                  'Pembayaran terverifikasi. Status: ${orderStatusLabel(o.status, pickup: o.pickup)}.',
                  tone: MasPillTone.brand,
                ),

              if (o.status == 'batal')
                _alert(m, 'Pesanan dibatalkan.', tone: MasPillTone.danger),

              // Peringatan penting: dibayar setelah order batal → perlu refund.
              if (o.paymentNote != null && o.paymentNote!.isNotEmpty) ...[
                const SizedBox(height: 10),
                _alert(m, o.paymentNote!, tone: MasPillTone.warn),
              ],

              if (o.status == 'dikirim') ...[
                const SizedBox(height: 10),
                MasButton(
                  label: _busy == 'confirm'
                      ? 'Memproses…'
                      : (o.pickup ? '✓ Barang Sudah Diambil' : '✓ Pesanan Diterima'),
                  expand: true,
                  loading: _busy == 'confirm',
                  onTap: _busy != null ? null : _doConfirm,
                ),
              ],

              if (['menunggu_pembayaran', 'menunggu_verifikasi']
                  .contains(o.status)) ...[
                // Bukti transfer manual HANYA untuk order non-gateway —
                // pembayaran Midtrans terverifikasi otomatis lewat webhook.
                if (!gateway) ...[
                  const SizedBox(height: 10),
                  MasButton(
                    label: _busy == 'proof'
                        ? 'Mengunggah…'
                        : '📎 Upload Bukti Transfer',
                    primary: false,
                    height: 38,
                    expand: true,
                    loading: _busy == 'proof',
                    onTap: _busy != null ? null : _doUploadProof,
                  ),
                  if (o.paymentProofUrl != null &&
                      o.paymentProofUrl!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _launch(o.paymentProofUrl!),
                      child: Text('Lihat bukti yang sudah dikirim →',
                          style: TextStyle(
                              fontSize: 12, color: m.brand700)),
                    ),
                  ],
                ],
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: _busy != null ? null : _doCancel,
                    child: Text(
                      _busy == 'cancel' ? 'Membatalkan…' : 'Batalkan Pesanan',
                      style: TextStyle(fontSize: 13, color: m.danger600),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
