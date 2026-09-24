// lib/screens/toko_screen.dart
// ETALASE BELANJA PEMBELI — beranda toko gaya e-commerce.
// Data dari /api/buyer/home (kategori, terlaris, unggulan) + /api/buyer/catalog
// (grid produk: cari, kategori, sort, ready-only, muat-lebih). Stok sudah
// di-scope backend ke lokasi gudang pembeli.

import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../cart.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/flash_sale.dart';
import '../widgets/mas_ui.dart';
import '../widgets/penilaian.dart';
import '../widgets/promo_banner.dart';

const _pageSize = 24;

const _sortOptions = <(String, String)>[
  ('relevan', 'Paling relevan'),
  ('harga_asc', 'Harga terendah'),
  ('harga_desc', 'Harga tertinggi'),
  ('nama', 'Nama A–Z'),
  ('stok', 'Stok terbanyak'),
];

class TokoScreen extends StatefulWidget {
  const TokoScreen({super.key});

  @override
  State<TokoScreen> createState() => _TokoScreenState();
}

class _TokoScreenState extends State<TokoScreen> {
  final _cart = CartStore.instance;
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  TokoHome? _home;
  TokoCatalog? _cat;
  List<TokoProduct> _items = [];

  /// Isi strip flash sale — ditarik SENDIRI, sekali (lihat [_loadFlash]).
  List<TokoProduct> _flashItems = [];

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  String _q = '';
  String _kategori = '';
  String _sort = 'relevan';
  bool _readyOnly = false;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCartChanged);
    _loadHome();
    _loadCatalog();
    if (FlashSaleKampanye.tampil) _loadFlash();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cart.removeListener(_onCartChanged);
    _searchCtl.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadHome() async {
    try {
      final h = await ApiService.tokoHome();
      if (mounted) setState(() => _home = h);
    } on ApiException catch (e) {
      // Beranda cuma pemanis (strip & kategori) — katalog di bawah tetap jalan,
      // jadi jangan menutup seluruh layar hanya karena ini gagal.
      if (mounted && e.isAuth) setState(() => _error = e.message);
    }
  }

  /// Kolam strip flash sale — permintaan TERPISAH dari grid (sama seperti web):
  /// `/api/buyer/home` terlalu sedikit setelah disaring, dan memakai `_items`
  /// membuat isi promo ikut bergeser saat pembeli mengetik di kolom cari.
  /// sort "relevan" + 100 (backend mendahulukan yang berfoto), lalu yang tak
  /// berfoto dibuang dan diurutkan stok terbanyak di sini.
  Future<void> _loadFlash() async {
    try {
      final r = await ApiService.tokoCatalog(
          ready: true, sort: 'relevan', page: 1, pageSize: 100);
      if (!mounted) return;
      final berfoto = r.items
          .where((p) => (p.foto ?? '').isNotEmpty)
          .toList()
        ..sort((a, b) => b.stok.compareTo(a.stok));
      setState(() => _flashItems = berfoto);
    } catch (_) {
      /* strip promo tak sepenting katalog — diam saja bila gagal */
    }
  }

  /// Muat halaman 1 sesuai filter aktif.
  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ApiService.tokoCatalog(
        q: _q,
        kategori: _kategori,
        sort: _sort,
        ready: _readyOnly,
        page: 1,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _cat = r;
        _items = r.items;
        _page = 1;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final cat = _cat;
    if (cat == null || _page >= cat.totalPages || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final r = await ApiService.tokoCatalog(
        q: _q,
        kategori: _kategori,
        sort: _sort,
        ready: _readyOnly,
        page: _page + 1,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...r.items];
        _page = r.page;
        _cat = r;
      });
    } on ApiException {
      /* biarkan — tombol bisa dicoba lagi */
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final q = v.trim();
      if (q == _q) return;
      _q = q;
      _loadCatalog();
    });
  }

  void _setKategori(String k) {
    setState(() => _kategori = _kategori == k ? '' : k);
    _loadCatalog();
  }

  int _qtyOf(String pn) {
    for (final i in _cart.items) {
      if (i.partNumber == pn) return i.qty;
    }
    return 0;
  }

  void _add(TokoProduct p) {
    _cart.add(CartItem(
      partNumber: p.partNumber,
      name: p.name,
      harga: p.hargaDisplay,
      berat: p.berat,
    ));
    AppNav.of(context).toast('${p.partNumber} masuk keranjang');
  }

  /// Mode jelajah = tanpa pencarian & tanpa kategori → tampilkan strip.
  bool get _browsing => _q.isEmpty && _kategori.isEmpty;

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);
    final cat = _cat;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadHome(), _loadCatalog()]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _judul(m),

          // Banner promo + strip flash sale — urutan sama dengan web /toko
          // (di atas chip kategori). Keduanya mengatur jarak atasnya sendiri.
          const PromoBanner(),
          FlashSale(
            items: _flashItems,
            onOpen: (p) => nav.go(MasScreen.part,
                part: {'part_number': p.partNumber, 'part_name': p.name}),
          ),

          if (_home != null && _home!.kategori.isNotEmpty) ...[
            const SizedBox(height: 14),
            _kategoriChips(m),
          ],

          if (_error != null) ...[
            const SizedBox(height: 14),
            _errorBox(m, _error!),
          ],

          if (_browsing && _home != null) ...[
            _strip(m, 'Terlaris', Icons.local_fire_department_rounded,
                _home!.terlaris),
            _strip(m, 'Pilihan bergambar', Icons.auto_awesome_rounded,
                _home!.unggulan),
          ],

          const SizedBox(height: 20),
          _toolbar(m, cat),
          const SizedBox(height: 12),

          if (_loading)
            _grid([for (int i = 0; i < 6; i++) const MasSkeleton(height: 268)])
          else if (_items.isEmpty)
            MasEmpty(
              icon: Icons.storefront_outlined,
              // Teks sama dengan web /toko.
              title: _q.isNotEmpty
                  ? 'Tidak ada produk yang cocok dengan "$_q".'
                  : 'Tidak ada produk yang cocok.',
              subtitle: _q.isNotEmpty || _kategori.isNotEmpty
                  ? 'Coba kata kunci atau kategori lain.'
                  : 'Coba ubah filter.',
              action: _q.isNotEmpty || _kategori.isNotEmpty
                  ? MasButton(
                      label: 'Tampilkan semua produk',
                      primary: false,
                      height: 38,
                      onTap: _resetFilter,
                    )
                  : null,
            )
          else ...[
            _grid([
              for (final p in _items)
                _ProductCard(
                  product: p,
                  qty: _qtyOf(p.partNumber),
                  onOpen: () => nav.go(MasScreen.part,
                      part: {'part_number': p.partNumber, 'part_name': p.name}),
                  onAdd: () => _add(p),
                  onQty: (q) => _cart.setQty(p.partNumber, q),
                  onRemove: () => _cart.remove(p.partNumber),
                ),
            ]),
            if (cat != null && _page < cat.totalPages) ...[
              const SizedBox(height: 18),
              Center(
                child: MasButton(
                  label: _loadingMore
                      ? 'Memuat…'
                      : 'Muat lebih banyak (${thousands(cat.count - _items.length)} lagi)',
                  primary: false,
                  loading: _loadingMore,
                  onTap: _loadMore,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── Bagian ──────────────────────────────────────────────────────────

  /// Baris judul + kolom cari — pengganti hero hijau lama.
  ///
  /// ⛔ JANGAN hidupkan lagi hero besar (gradien + chip lokasi + chip
  /// keranjang), sama seperti web /toko: keranjang sudah ada di header, dan di
  /// HP hero mendorong banner & flash sale keluar layar pertama. Yang memang
  /// cuma ada di sini: jumlah produk etalase + kolom cari.
  Widget _judul(MasColors m) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('Belanja Part',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: m.ink900,
                letterSpacing: -0.3,
              )),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _home != null
                  ? '${thousands(_home!.totalProduk)} produk siap dibeli'
                  : 'Memuat etalase…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: m.ink500),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: m.paper,
          borderRadius: BorderRadius.circular(MasRadii.input),
          border: Border.all(color: m.ink200),
        ),
        child: Row(children: [
          Icon(Icons.search_rounded, size: 18, color: m.ink400),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtl,
              onChanged: (v) {
                setState(() {}); // tampil/sembunyikan tombol ✕
                _onSearchChanged(v);
              },
              style: TextStyle(fontSize: 14, color: m.ink900),
              cursorColor: m.brand600,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Cari part number atau nama part…',
                hintStyle: TextStyle(color: m.ink400, fontSize: 13.5),
              ),
            ),
          ),
          if (_searchCtl.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchCtl.clear();
                _debounce?.cancel();
                _q = '';
                _loadCatalog();
              },
              child: Icon(Icons.close_rounded, size: 18, color: m.ink400),
            ),
        ]),
      ),
    ]);
  }

  /// "Tampilkan semua produk" di hasil kosong — kosongkan cari + kategori.
  void _resetFilter() {
    _debounce?.cancel();
    _searchCtl.clear();
    setState(() {
      _q = '';
      _kategori = '';
    });
    _loadCatalog();
  }

  Widget _kategoriChips(MasColors m) {
    Widget chip(String label, String key, {int? count}) {
      final active = _kategori == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => key.isEmpty
              ? (_kategori.isEmpty ? null : _setKategori(_kategori))
              : _setKategori(key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: active ? m.brand700 : m.paper,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active ? m.brand700 : m.ink200),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: active ? Colors.white : m.ink700,
                  )),
              if (count != null) ...[
                const SizedBox(width: 4),
                Text('(${thousands(count)})',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: active
                          ? Colors.white.withValues(alpha: 0.7)
                          : m.ink500,
                    )),
              ],
            ]),
          ),
        ),
      );
    }

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip('Semua', ''),
          for (final k in _home!.kategori) chip(k.label, k.key, count: k.count),
        ],
      ),
    );
  }

  Widget _strip(
      MasColors m, String title, IconData icon, List<TokoProduct> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    final nav = AppNav.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 20),
      Row(children: [
        Icon(icon, size: 17, color: m.brand700),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w700, color: m.ink900)),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 280,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final p = items[i];
            return SizedBox(
              width: 172,
              child: _ProductCard(
                product: p,
                qty: _qtyOf(p.partNumber),
                onOpen: () => nav.go(MasScreen.part, part: {
                  'part_number': p.partNumber,
                  'part_name': p.name,
                }),
                onAdd: () => _add(p),
                onQty: (q) => _cart.setQty(p.partNumber, q),
                onRemove: () => _cart.remove(p.partNumber),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _toolbar(MasColors m, TokoCatalog? cat) {
    final judul = _q.isNotEmpty
        ? 'Hasil "$_q"'
        : _kategori.isNotEmpty
            ? (_home?.kategori
                    .where((k) => k.key == _kategori)
                    .firstOrNull
                    ?.label ??
                'Kategori')
            : 'Semua Part';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(judul,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: m.ink900)),
        ),
        if (cat != null)
          Text('${thousands(cat.count)} produk',
              style: TextStyle(fontSize: 12, color: m.ink500)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        GestureDetector(
          onTap: () {
            setState(() => _readyOnly = !_readyOnly);
            _loadCatalog();
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _readyOnly,
                onChanged: (v) {
                  setState(() => _readyOnly = v ?? false);
                  _loadCatalog();
                },
                activeColor: m.brand600,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 7),
            Text('Hanya READY',
                style: TextStyle(fontSize: 12.5, color: m.ink600)),
          ]),
        ),
        const Spacer(),
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: m.paper,
            borderRadius: BorderRadius.circular(MasRadii.input),
            border: Border.all(color: m.ink200),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _sort,
              isDense: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  size: 16, color: m.ink500),
              style: TextStyle(fontSize: 12.5, color: m.ink800),
              dropdownColor: m.paper,
              items: [
                for (final (key, label) in _sortOptions)
                  DropdownMenuItem(value: key, child: Text(label)),
              ],
              onChanged: (v) {
                if (v == null || v == _sort) return;
                setState(() => _sort = v);
                _loadCatalog();
              },
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _grid(List<Widget> children) => GridView.count(
        crossAxisCount: 2,
        childAspectRatio: 0.60,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: children,
      );

  Widget _errorBox(MasColors m, String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: m.danger50,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border.all(color: m.dangerBorder),
        ),
        child: Text(msg, style: TextStyle(fontSize: 12.5, color: m.danger600)),
      );
}

// ══════════════════════════════════════════════════════════════════════
// Kartu produk
// ══════════════════════════════════════════════════════════════════════

class _ProductCard extends StatelessWidget {
  final TokoProduct product;
  final int qty;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  final ValueChanged<int> onQty;
  final VoidCallback onRemove;

  const _ProductCard({
    required this.product,
    required this.qty,
    required this.onOpen,
    required this.onAdd,
    required this.onQty,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final p = product;

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: m.paper,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border.all(color: m.ink150),
          boxShadow: m.shadow1,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto FLEKSIBEL (mengisi ruang atas yang tersisa) dengan `contain`
            // supaya part memanjang tak melebarkan kartu. Sengaja BUKAN tinggi
            // tetap: konten di bawah selalu digambar penuh dulu, foto yang
            // menyusut bila sel pendek — jadi tombol tak pernah terpotong.
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: p.foto != null && p.foto!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: ApiService.partImageUrl(p.foto!),
                          fit: BoxFit.contain,
                          placeholder: (_, _) => Container(color: m.ink50),
                          errorWidget: (_, _, _) => _noPhoto(m),
                        )
                      : _noPhoto(m),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: MasPill(
                    label: p.ready
                        ? 'READY${p.gudang.isNotEmpty ? ' · ${p.gudang}' : ''}'
                        : 'Habis',
                    tone: p.ready ? MasPillTone.brand : MasPillTone.danger,
                    height: 19,
                  ),
                ),
              ]),
            ),

            // Konten mengambil tinggi intrinsiknya (tidak di-`Expanded`), jadi
            // tombol aksi di bawah SELALU tampil penuh.
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: m.ink900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(p.partNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: masMono(size: 10.5, color: m.ink500)),
                  const SizedBox(height: 4),
                  Text(formatRupiah(p.harga),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: m.brand700,
                      )),
                  // Baris ala Shopee: ★ rata-rata · terjual · stok.
                  Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (p.ulasan > 0) ...[
                        const Icon(Icons.star_rounded, size: 12, color: kBintang),
                        Text(fmtRating(p.rating),
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: m.ink700)),
                      ],
                      if (p.terjual > 0)
                        Text('${p.ulasan > 0 ? '· ' : ''}${terjualLabel(p.terjual)} terjual',
                            style: TextStyle(fontSize: 10.5, color: m.ink500)),
                      if (p.ready)
                        Text('${p.ulasan > 0 || p.terjual > 0 ? '· ' : ''}Stok ${thousands(p.stok)}',
                            style: TextStyle(fontSize: 10.5, color: m.ink500)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _action(m),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noPhoto(MasColors m) => Container(
        color: m.ink50,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.settings_outlined, size: 26, color: m.ink300),
            const SizedBox(height: 5),
            Text('Belum ada foto',
                style: TextStyle(fontSize: 10.5, color: m.ink400)),
          ],
        ),
      );

  Widget _action(MasColors m) {
    // Stepper qty muncul begitu part ada di keranjang — pembeli bisa menambah
    // tanpa membuka halaman keranjang.
    if (qty > 0) {
      return Row(children: [
        _stepBtn(m, Icons.remove_rounded,
            () => qty <= 1 ? onRemove() : onQty(qty - 1)),
        Expanded(
          child: Center(
            child: Text('$qty',
                style: masMono(
                    size: 13, weight: FontWeight.w700, color: m.ink900)),
          ),
        ),
        _stepBtn(m, Icons.add_rounded, () => onQty(qty + 1)),
      ]);
    }

    final ready = product.ready;
    return SizedBox(
      height: 32,
      width: double.infinity,
      child: Material(
        color: ready ? m.brand600 : m.ink100,
        borderRadius: BorderRadius.circular(MasRadii.input),
        child: InkWell(
          onTap: ready ? onAdd : null,
          borderRadius: BorderRadius.circular(MasRadii.input),
          child: Center(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.shopping_cart_outlined,
                  size: 14, color: ready ? Colors.white : m.ink400),
              const SizedBox(width: 6),
              Text(
                ready ? 'Keranjang' : 'Stok habis',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ready ? Colors.white : m.ink400,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stepBtn(MasColors m, IconData icon, VoidCallback onTap) => SizedBox(
        width: 32,
        height: 32,
        child: Material(
          color: m.paper,
          borderRadius: BorderRadius.circular(MasRadii.input),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(MasRadii.input),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(MasRadii.input),
                border: Border.all(color: m.ink200),
              ),
              child: Icon(icon, size: 15, color: m.ink700),
            ),
          ),
        ),
      );
}
