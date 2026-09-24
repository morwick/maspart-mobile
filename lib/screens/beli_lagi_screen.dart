// lib/screens/beli_lagi_screen.dart
// "Beli Lagi" — riwayat barang yang pernah dibeli pembeli (pola Tokopedia
// "Beli Lagi" / Shopee "Beli Lagi"). Sumber: `GET /api/beli-lagi` — satu baris
// per PN dari pesanan LUNAS, sudah dinilai ulang dengan harga/stok terkini.
//
// ⛔ Gagal baca riwayat (503/jaringan) = layar GALAT + Coba lagi, BUKAN
// "belum pernah beli" — pembeli tak boleh dikira belum pernah belanja.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../cart.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/beli_lagi.dart';
import '../widgets/mas_ui.dart';

/// Urutan daftar — (kunci, label).
const _kUrutan = <(String, String)>[
  ('terakhir', 'Terakhir dibeli'),
  ('sering', 'Paling sering dibeli'),
  ('harga', 'Harga terendah'),
];

class BeliLagiScreen extends StatefulWidget {
  const BeliLagiScreen({super.key});

  @override
  State<BeliLagiScreen> createState() => _BeliLagiScreenState();
}

class _BeliLagiScreenState extends State<BeliLagiScreen> {
  final _searchCtrl = TextEditingController();

  List<BeliLagiItem> _items = [];
  bool _loading = true;
  String? _error;

  String _q = '';
  String _urut = 'terakhir';
  bool _tersediaSaja = false;

  /// Jumlah pilihan pembeli per PN (stepper). Absen = usulan server (`qty`).
  final Map<String, int> _qty = {};

  /// Mode pilih banyak: centang beberapa lalu "Masukkan N ke keranjang".
  bool _modePilih = false;
  final Set<String> _dipilih = {};
  bool _memasukkan = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final items = await ApiService.beliLagiRiwayat();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        // Pilihan untuk PN yang kini tak bisa dibeli dibuang.
        final bisa = {
          for (final i in items)
            if (i.bisaDibeli) i.partNumber,
        };
        _dipilih.removeWhere((pn) => !bisa.contains(pn));
        _qty.removeWhere((pn, _) => !bisa.contains(pn));
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.isNotEmpty
            ? e.message
            : 'Riwayat belanja sedang tak bisa dibaca. Coba lagi sebentar.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat riwayat belanja. Periksa koneksi Anda.';
        _loading = false;
      });
    }
  }

  // ── Turunan ─────────────────────────────────────────────────────────

  /// Batas atas stepper: stok tersisa; bila stok tak diketahui (0) pakai
  /// usulan server supaya stepper tetap bisa dipakai.
  int _maks(BeliLagiItem it) => it.stok > 0 ? it.stok : (it.qty < 1 ? 1 : it.qty);

  int _qtyOf(BeliLagiItem it) {
    final q = _qty[it.partNumber] ?? it.qty;
    final maks = _maks(it);
    if (q < 1) return 1;
    return q > maks ? maks : q;
  }

  /// Daftar setelah cari + saring + urut. Urutan asal server = terbaru dulu,
  /// jadi indeks asal dipakai sebagai pemecah seri yang stabil.
  List<BeliLagiItem> get _tampil {
    final term = _q.trim().toLowerCase();
    final idx = <String, int>{
      for (int i = 0; i < _items.length; i++) _items[i].partNumber: i,
    };
    final list = _items
        .where((it) => !_tersediaSaja || it.bisaDibeli)
        .where((it) =>
            term.isEmpty ||
            it.name.toLowerCase().contains(term) ||
            it.partNumber.toLowerCase().contains(term))
        .toList();
    int asal(BeliLagiItem it) => idx[it.partNumber] ?? 0;
    switch (_urut) {
      case 'sering':
        list.sort((a, b) {
          final c = b.kali.compareTo(a.kali);
          if (c != 0) return c;
          final d = b.totalQty.compareTo(a.totalQty);
          return d != 0 ? d : asal(a).compareTo(asal(b));
        });
      case 'harga':
        // Harga belum tersedia (0) ditaruh paling bawah, bukan paling atas.
        list.sort((a, b) {
          final adaA = a.harga > 0, adaB = b.harga > 0;
          if (adaA != adaB) return adaA ? -1 : 1;
          final c = a.harga.compareTo(b.harga);
          return c != 0 ? c : asal(a).compareTo(asal(b));
        });
      default:
        list.sort((a, b) => asal(a).compareTo(asal(b)));
    }
    return list;
  }

  // ── Aksi ────────────────────────────────────────────────────────────

  Future<void> _tambahSatu(BeliLagiItem it) async {
    final nav = AppNav.of(context);
    final q = _qtyOf(it);
    await CartStore.instance.add(cartItemDariBeliLagi(it, qty: q), qty: q);
    nav.toast('${it.judul} ×$q masuk keranjang',
        actionLabel: 'Lihat', onAction: () => nav.go(MasScreen.keranjang));
  }

  Future<void> _masukkanDipilih() async {
    if (_memasukkan || _dipilih.isEmpty) return;
    final nav = AppNav.of(context);
    setState(() => _memasukkan = true);
    try {
      final pilih = _items
          .where((it) => it.bisaDibeli && _dipilih.contains(it.partNumber))
          .toList();
      final n = await masukkanBeliLagi(pilih, qtyPilihan: {
        for (final it in pilih) it.partNumber: _qtyOf(it),
      });
      if (!mounted) return;
      setState(() {
        _dipilih.clear();
        _modePilih = false;
      });
      nav.toast('$n barang dimasukkan ke keranjang',
          actionLabel: 'Lihat', onAction: () => nav.go(MasScreen.keranjang));
    } finally {
      if (mounted) setState(() => _memasukkan = false);
    }
  }

  void _togglePilih(BeliLagiItem it) {
    if (!it.bisaDibeli) return;
    setState(() {
      if (!_dipilih.remove(it.partNumber)) _dipilih.add(it.partNumber);
    });
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final tampil = _tampil;

    final List<Widget> isi;
    if (_loading) {
      isi = [
        for (int i = 0; i < 4; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: MasSkeleton(height: 120),
          ),
      ];
    } else if (_error != null && _items.isEmpty) {
      isi = [
        MasErrorState(
          title: 'Riwayat belanja gagal dimuat',
          message: _error!,
          onRetry: _load,
        ),
      ];
    } else if (_items.isEmpty) {
      isi = [
        MasEmpty(
          icon: Icons.shopping_bag_outlined,
          title: 'Belum ada barang yang pernah dibeli',
          subtitle:
              'Barang dari pesanan yang sudah dibayar akan muncul di sini, siap dipesan ulang.',
          action: MasButton(
            label: 'Ke Toko',
            icon: Icons.storefront_outlined,
            onTap: () => nav.go(MasScreen.toko),
          ),
        ),
      ];
    } else {
      isi = [
        if (_error != null) ...[
          _banner(m, _error!),
          const SizedBox(height: 10),
        ],
        if (tampil.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(children: [
              Text('Tidak ada barang yang cocok',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: m.ink800)),
              const SizedBox(height: 4),
              Text('Ubah kata pencarian atau matikan saringan.',
                  style: TextStyle(fontSize: 12.5, color: m.ink500)),
              const SizedBox(height: 12),
              MasButton(
                label: 'Tampilkan semua',
                primary: false,
                height: 36,
                onTap: () => setState(() {
                  _q = '';
                  _searchCtrl.clear();
                  _tersediaSaja = false;
                }),
              ),
            ]),
          )
        else
          for (final it in tampil)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _baris(m, nav, it),
            ),
      ];
    }

    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              if (!_loading && _items.isNotEmpty) ...[
                _kontrol(m, tampil.length),
                const SizedBox(height: 12),
              ],
              ...isi,
            ],
          ),
        ),
      ),
      if (_modePilih) _bilahPilih(m),
    ]);
  }

  /// Kotak cari + urutan + saringan + tombol mode pilih.
  Widget _kontrol(MasColors m, int jumlah) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MasInput(
          controller: _searchCtrl,
          hint: 'Cari nama barang atau PN…',
          height: 40,
          prefix: Icon(Icons.search_rounded, size: 18, color: m.ink400),
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final u in _kUrutan) ...[
                _chip(m, u.$2, _urut == u.$1,
                    () => setState(() => _urut = u.$1)),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _chip(
            m,
            'Hanya yang tersedia',
            _tersediaSaja,
            () => setState(() => _tersediaSaja = !_tersediaSaja),
            ikon: _tersediaSaja
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
          ),
          const Spacer(),
          Text('$jumlah barang',
              style: TextStyle(fontSize: 12, color: m.ink500)),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => setState(() {
              _modePilih = !_modePilih;
              if (!_modePilih) _dipilih.clear();
            }),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(_modePilih ? 'Batal pilih' : 'Pilih',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: m.brand700)),
          ),
        ]),
      ],
    );
  }

  Widget _chip(MasColors m, String label, bool aktif, VoidCallback onTap,
      {IconData? ikon}) {
    return Material(
      color: aktif ? m.brand600 : m.paper,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: aktif ? m.brand600 : m.ink200),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (ikon != null) ...[
              Icon(ikon, size: 15, color: aktif ? Colors.white : m.ink500),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: aktif ? Colors.white : m.ink700,
                )),
          ]),
        ),
      ),
    );
  }

  /// Satu barang: foto, nama, PN, frekuensi beli, harga + lencana selisih,
  /// gudang/stok, lalu stepper + "+ Keranjang". Tak bisa dibeli → redup
  /// dengan alasannya, tanpa tombol beli.
  Widget _baris(MasColors m, AppNav nav, BeliLagiItem it) {
    final bisa = it.bisaDibeli;
    final dipilih = _dipilih.contains(it.partNumber);
    final tgl = tglPendek(it.terakhir);
    final selisih = labelSelisihHarga(it.selisihHarga);
    final q = _qtyOf(it);
    final maks = _maks(it);

    void buka() => nav.go(MasScreen.part,
        part: {'part_number': it.partNumber, 'part_name': it.name});

    final kartu = Material(
      color: m.paper,
      borderRadius: BorderRadius.circular(MasRadii.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _modePilih ? (bisa ? () => _togglePilih(it) : null) : buka,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MasRadii.card),
            border: Border.all(
                color: dipilih ? m.brand600 : m.ink150,
                width: dipilih ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_modePilih) ...[
                  SizedBox(
                    width: 28,
                    height: 64,
                    child: Checkbox(
                      value: dipilih,
                      onChanged: bisa ? (_) => _togglePilih(it) : null,
                      activeColor: m.brand600,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                _foto(m, it),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.judul,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: m.ink900)),
                      const SizedBox(height: 2),
                      Text(it.partNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: masMono(size: 11, color: m.ink500)),
                      const SizedBox(height: 3),
                      Text(
                        'Dibeli ${it.kali < 1 ? 1 : it.kali}x'
                        '${tgl.isEmpty ? '' : ' · terakhir $tgl'}',
                        style: TextStyle(fontSize: 11.5, color: m.ink500),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            it.harga > 0
                                ? (it.hargaDisplay.isNotEmpty
                                    ? it.hargaDisplay
                                    : formatRupiah(it.harga))
                                : 'Harga belum tersedia',
                            style: it.harga > 0
                                ? TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: m.brand700)
                                : TextStyle(fontSize: 12.5, color: m.ink500),
                          ),
                          if (selisih.isNotEmpty)
                            MasPill(
                              label: selisih,
                              tone: it.selisihHarga < 0
                                  ? MasPillTone.brand
                                  : MasPillTone.warn,
                              height: 19,
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      if (bisa)
                        Text(
                          [
                            if (it.gudang.isNotEmpty) 'Gudang ${it.gudang}',
                            'Stok ${thousands(it.stok)}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: m.ink600),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: MasPill(
                            label: _labelAlasan(it.alasan),
                            tone: MasPillTone.danger,
                            height: 19,
                          ),
                        ),
                    ],
                  ),
                ),
              ]),
              if (bisa && !_modePilih) ...[
                const SizedBox(height: 10),
                Row(children: [
                  _stepper(m, it, q, maks),
                  const Spacer(),
                  SizedBox(
                    height: 34,
                    child: MasButton(
                      label: '+ Keranjang',
                      height: 34,
                      onTap: () => _tambahSatu(it),
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );

    return bisa ? kartu : Opacity(opacity: 0.6, child: kartu);
  }

  /// Alasan server → kalimat pendek untuk pembeli.
  String _labelAlasan(String alasan) {
    final a = alasan.trim();
    if (a.isEmpty) return 'Tidak tersedia';
    return '${a[0].toUpperCase()}${a.substring(1)}';
  }

  Widget _foto(MasColors m, BeliLagiItem it) {
    final foto = it.foto;
    Widget kosong() => Container(
          color: m.ink50,
          alignment: Alignment.center,
          child: Icon(Icons.settings_outlined, size: 24, color: m.ink300),
        );
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: m.ink150),
      ),
      clipBehavior: Clip.antiAlias,
      child: foto != null && foto.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: ApiService.partImageUrl(foto),
              fit: BoxFit.contain,
              placeholder: (_, _) => Container(color: m.ink50),
              errorWidget: (_, _, _) => kosong(),
            )
          : kosong(),
    );
  }

  Widget _stepper(MasColors m, BeliLagiItem it, int q, int maks) {
    Widget tombol(IconData ik, VoidCallback? onTap) => Material(
          color: m.paper,
          borderRadius: BorderRadius.circular(MasRadii.input),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(MasRadii.input),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(MasRadii.input),
                border: Border.all(color: m.ink200),
              ),
              child: Icon(ik,
                  size: 16, color: onTap == null ? m.ink300 : m.ink700),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      tombol(Icons.remove_rounded,
          q > 1 ? () => setState(() => _qty[it.partNumber] = q - 1) : null),
      SizedBox(
        width: 40,
        child: Center(
          child: Text('$q',
              style:
                  masMono(size: 13.5, weight: FontWeight.w700, color: m.ink900)),
        ),
      ),
      tombol(Icons.add_rounded,
          q < maks ? () => setState(() => _qty[it.partNumber] = q + 1) : null),
    ]);
  }

  /// Bilah bawah mode pilih banyak.
  Widget _bilahPilih(MasColors m) {
    final n = _dipilih.length;
    final semuaBisa = _tampil.where((i) => i.bisaDibeli).toList();
    final semuaTerpilih =
        semuaBisa.isNotEmpty && semuaBisa.every((i) => _dipilih.contains(i.partNumber));
    return Container(
      decoration: BoxDecoration(
        color: m.paper,
        border: Border(top: BorderSide(color: m.ink150)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
          child: Row(children: [
            TextButton.icon(
              onPressed: semuaBisa.isEmpty
                  ? null
                  : () => setState(() {
                        if (semuaTerpilih) {
                          _dipilih.removeAll(semuaBisa.map((i) => i.partNumber));
                        } else {
                          _dipilih.addAll(semuaBisa.map((i) => i.partNumber));
                        }
                      }),
              icon: Icon(
                  semuaTerpilih
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 18,
                  color: m.brand600),
              label: Text('Semua',
                  style: TextStyle(fontSize: 13, color: m.ink800)),
            ),
            const Spacer(),
            MasButton(
              label: n > 0 ? 'Masukkan $n ke keranjang' : 'Pilih barang',
              icon: Icons.add_shopping_cart_rounded,
              height: 40,
              loading: _memasukkan,
              onTap: n == 0 || _memasukkan ? null : _masukkanDipilih,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _banner(MasColors m, String t) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: m.danger50,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border.all(color: m.dangerBorder),
        ),
        child: Row(children: [
          Expanded(
            child: Text(t,
                style: TextStyle(fontSize: 12.5, color: m.danger600)),
          ),
          TextButton(onPressed: _load, child: const Text('Coba lagi')),
        ]),
      );
}
