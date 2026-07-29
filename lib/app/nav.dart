// lib/app/nav.dart
// Model navigasi shell: enum layar, judul header, seksi drawer, dan AppNav
// (InheritedWidget yang dipakai layar untuk berpindah / buka drawer / toast).

import 'package:flutter/material.dart';

/// Seluruh layar dalam shell.
enum MasScreen {
  // Umum
  dashboard,
  search,
  part,
  asisten,
  foto,
  harga,
  compare,
  batch,
  populasi,
  stok,
  opname,

  // Pembeli
  toko,
  keranjang,
  pesanan,
  pesananDetail,
  pilihLokasi,
  chat,

  // Cabang
  cabangPesanan,
  cabangPesananDetail,
  cabangPenjualan,
  cabangChat,

  // Admin
  orders,
  orderDetail,
  penjualan,
  feedback,
  chatlog,
  misses,
  sinonim,
  pengetahuan,
  menu,
  monitoring,
  upload,
  users,
  gudang,
  fotopart,
  imageindex,
}

/// Judul & subjudul header per layar.
const Map<MasScreen, (String, String)> kScreenTitles = {
  MasScreen.dashboard: ('Dashboard', ''),
  MasScreen.search: ('Cari Part', 'Cari berdasarkan kode atau nama part'),
  MasScreen.part: ('Detail Part', ''),
  MasScreen.asisten: ('Asisten AI', 'DeepSeek + tool katalog, EPC & stok'),
  MasScreen.foto: ('Cari by Foto', 'Cari part mirip via foto (DINOv2 + SIMS)'),
  MasScreen.harga: ('Harga', 'List, cari & batch harga sparepart'),
  MasScreen.compare: ('Bandingkan 2 Part', 'Analisis interchange via foto SIMS + nama'),
  MasScreen.batch: ('Batch Download', 'Unduh katalog Excel banyak part sekaligus'),
  MasScreen.populasi: ('Populasi Unit', 'Daftar unit & spesifikasi armada'),
  MasScreen.stok: ('Stok', 'Stok seluruh barang dari Accurate'),
  MasScreen.opname: ('Stok Opname', 'Hitung fisik & bandingkan dengan sistem'),

  MasScreen.toko: ('Belanja Part', 'Etalase part siap kirim dari gudang terdekat'),
  MasScreen.keranjang: ('Keranjang', 'Tinjau part, pilih ekspedisi, lalu bayar'),
  MasScreen.pesanan: ('Pesanan Saya', 'Riwayat & status pesanan'),
  MasScreen.pesananDetail: ('Detail Pesanan', ''),
  MasScreen.pilihLokasi: ('Ganti Lokasi', 'Pilih gudang tempat Anda berbelanja'),
  MasScreen.chat: ('Chat', 'Tanya gudang sebelum memesan'),

  MasScreen.cabangPesanan: ('Pesanan Masuk', 'Pesanan yang harus dipenuhi cabang ini'),
  MasScreen.cabangPesananDetail: ('Detail Pesanan', ''),
  MasScreen.cabangPenjualan: ('Laporan Penjualan', 'Rekap omzet cabang'),
  MasScreen.cabangChat: ('Chat Pembeli', 'Percakapan dengan pembeli'),

  MasScreen.orders: ('Pesanan', 'Kelola & verifikasi pesanan'),
  MasScreen.orderDetail: ('Detail Pesanan', ''),
  MasScreen.penjualan: ('Laporan Penjualan', 'Rekap omzet & barang terjual'),
  MasScreen.feedback: ('Umpan Balik AI', 'Jawaban yang dinilai user'),
  MasScreen.chatlog: ('Observabilitas AI', 'Latensi, guard & tool asisten'),
  MasScreen.misses: ('Pencarian Nihil', 'Query 0 hasil — kandidat sinonim'),
  MasScreen.sinonim: ('Kamus Sinonim', 'Istilah lapangan → kata kunci katalog'),
  MasScreen.pengetahuan:
      ('Pengetahuan AI', 'Isi yang diindeks & dipakai Asisten AI saat menjawab'),
  MasScreen.menu: ('Menu Control', 'Atur izin menu, kolom & sub-tab per user'),
  MasScreen.monitoring: ('Monitoring User', 'Status online/offline & aktivitas'),
  MasScreen.upload: ('Upload Data', 'Unggah dataset stok, harga & populasi'),
  MasScreen.users: ('Manajemen User', 'Kelola akun & peran'),
  MasScreen.gudang: ('Lokasi Gudang', 'Koordinat & PIC tiap cabang'),
  MasScreen.fotopart: ('Foto Part', 'Tinjau & unggah foto part manual'),
  MasScreen.imageindex: ('Image Index', 'Kelola galeri cari-by-foto & catalog BOM'),
};

/// Satu item menu di drawer. [permKey] = kunci izin (MENU_TABS di backend);
/// null = tidak diatur izin (selalu tampil bila section-nya tampil).
class NavItem {
  final String label;
  final IconData icon;
  final MasScreen screen;
  final String? permKey;
  const NavItem(this.label, this.icon, this.screen, {this.permKey});
}

/// Satu seksi di drawer.
class NavSection {
  final String label;
  final List<NavItem> items;
  const NavSection(this.label, this.items);
}

// ── Definisi item (selaras AppShell.tsx web) ─────────────────────────

const NavItem _navDashboard =
    NavItem('Dashboard', Icons.dashboard_rounded, MasScreen.dashboard);

/// Menu pembeli — hanya alur belanja. Item ber-permKey tetap tunduk Menu
/// Control: admin mematikan "Asisten AI" → menunya hilang untuk pembeli juga.
const List<NavItem> _navBuyer = [
  NavItem('Belanja', Icons.storefront_outlined, MasScreen.toko),
  NavItem('Cari Part', Icons.search_rounded, MasScreen.search, permKey: 'search'),
  NavItem('Asisten AI', Icons.smart_toy_rounded, MasScreen.asisten, permKey: 'ai'),
  NavItem('Chat', Icons.chat_bubble_outline_rounded, MasScreen.chat),
  NavItem('Pesanan Saya', Icons.receipt_long_outlined, MasScreen.pesanan),
  NavItem('Ganti Lokasi', Icons.place_outlined, MasScreen.pilihLokasi),
];

const List<NavItem> _navPrimary = [
  NavItem('Asisten AI', Icons.smart_toy_rounded, MasScreen.asisten, permKey: 'ai'),
  NavItem('Cari Part', Icons.search_rounded, MasScreen.search, permKey: 'search'),
  NavItem('Cari by Foto', Icons.photo_camera_outlined, MasScreen.foto, permKey: 'search_image'),
  NavItem('Bandingkan 2 Part', Icons.compare_arrows_rounded, MasScreen.compare, permKey: 'compare'),
  NavItem('Batch Download', Icons.download_rounded, MasScreen.batch, permKey: 'batch'),
];

const List<NavItem> _navData = [
  NavItem('Populasi Unit', Icons.local_shipping_outlined, MasScreen.populasi, permKey: 'populasi'),
  NavItem('Harga', Icons.payments_outlined, MasScreen.harga, permKey: 'harga'),
  NavItem('Stok', Icons.grid_view_rounded, MasScreen.stok, permKey: 'stok'),
  NavItem('Stok Opname', Icons.fact_check_outlined, MasScreen.opname),
];

const List<NavItem> _navAdmin = [
  NavItem('Pesanan', Icons.shopping_cart_outlined, MasScreen.orders),
  NavItem('Laporan Penjualan', Icons.bar_chart_rounded, MasScreen.penjualan),
  NavItem('Umpan Balik AI', Icons.forum_outlined, MasScreen.feedback),
  NavItem('Observabilitas AI', Icons.monitor_heart_outlined, MasScreen.chatlog),
  NavItem('Pencarian Nihil', Icons.search_off_rounded, MasScreen.misses),
  NavItem('Kamus Sinonim', Icons.menu_book_outlined, MasScreen.sinonim),
  NavItem('Pengetahuan AI', Icons.auto_stories_outlined, MasScreen.pengetahuan),
  NavItem('Menu Control', Icons.shield_outlined, MasScreen.menu),
  NavItem('Monitoring User', Icons.pie_chart_outline_rounded, MasScreen.monitoring),
  NavItem('Upload Data', Icons.upload_rounded, MasScreen.upload),
  NavItem('Manajemen User', Icons.person_outline_rounded, MasScreen.users),
  NavItem('Lokasi Gudang', Icons.place_outlined, MasScreen.gudang),
  NavItem('Foto Part', Icons.photo_library_outlined, MasScreen.fotopart),
  NavItem('Image Index', Icons.grid_on_rounded, MasScreen.imageindex),
];

const List<NavItem> _navCabang = [
  NavItem('Pesanan Masuk', Icons.shopping_cart_outlined, MasScreen.cabangPesanan),
  NavItem('Chat', Icons.chat_bubble_outline_rounded, MasScreen.cabangChat),
  NavItem('Laporan Penjualan', Icons.bar_chart_rounded, MasScreen.cabangPenjualan),
];

/// Layar anak yang dicapai dari layar lain (bukan lewat drawer), jadi tak
/// boleh dijegal guard izin.
const Set<MasScreen> _kChildScreens = {
  MasScreen.part,
  MasScreen.pesananDetail,
  MasScreen.orderDetail,
  MasScreen.cabangPesananDetail,
  MasScreen.keranjang,
};

/// Bangun struktur drawer sesuai peran & izin — persis logika web (AppShell.tsx):
/// - pembeli → hanya alur belanja (tetap difilter Menu Control).
/// - admin   → Ringkasan + Pencarian + Data + Admin.
/// - cabang  → Ringkasan + Pencarian + Data + "Cabang <label>".
/// - user    → Ringkasan + Pencarian + Data.
///
/// [allowed] null = izin belum dimuat → tampilkan semua item ber-permKey (aman:
/// seksi Admin tetap digembok oleh role, bukan oleh izin).
List<NavSection> buildNavSections({
  required String role,
  required Set<String>? allowed,
  String? branch,
}) {
  final isAdmin = role == 'admin';
  final isBuyer = role == 'pembeli';

  bool show(NavItem it) =>
      it.permKey == null || allowed == null || allowed.contains(it.permKey);

  if (isBuyer) {
    return [
      NavSection('Belanja', _navBuyer.where(show).toList()),
    ].where((s) => s.items.isNotEmpty).toList();
  }

  final out = <NavSection>[
    const NavSection('Ringkasan', [_navDashboard]),
    NavSection('Pencarian', _navPrimary.where(show).toList()),
    NavSection('Data', _navData.where(show).toList()),
  ];

  if (branch != null && branch.isNotEmpty) {
    out.add(NavSection('Cabang $branch', _navCabang));
  }
  if (isAdmin) out.add(const NavSection('Admin', _navAdmin));

  return out.where((s) => s.items.isNotEmpty).toList();
}

/// Kumpulan layar yang boleh diakses untuk peran/izin tertentu (untuk guard).
Set<MasScreen> accessibleScreens(List<NavSection> sections) => {
      for (final s in sections)
        for (final it in s.items) it.screen,
      ..._kChildScreens,
    };

/// Aksi navigasi yang dipublikasikan shell ke seluruh layar anak.
class AppNav extends InheritedWidget {
  final MasScreen screen;

  /// Argumen untuk layar tujuan (part terpilih, kode pesanan, dsb).
  final Map<String, dynamic>? selectedPart;
  final String username;
  final String role;

  /// Izin kolom efektif (MENU_COLUMNS backend: `col_stok`, `col_harga`).
  /// null = izin belum dimuat → default tampilkan (persis web sebelum ensurePerms).
  final Set<String>? columns;

  /// Config server-driven (`/api/app/meta` → `config`). Kosong = pakai default
  /// hardcoded tiap layar. Baca lewat helper di bawah agar fallback konsisten.
  final Map<String, dynamic> config;
  final Set<MasScreen> accessible;
  final void Function(MasScreen target, {Map<String, dynamic>? part}) go;
  final VoidCallback back;
  final bool canBack;
  final VoidCallback openDrawer;
  final VoidCallback closeDrawer;
  final void Function(String message) toast;
  final VoidCallback logout;

  const AppNav({
    super.key,
    required this.screen,
    required this.selectedPart,
    required this.username,
    required this.role,
    this.columns,
    this.config = const {},
    required this.accessible,
    required this.go,
    required this.back,
    required this.canBack,
    required this.openDrawer,
    required this.closeDrawer,
    required this.toast,
    required this.logout,
    required super.child,
  });

  bool get isAdmin => role == 'admin';
  bool get isBuyer => role == 'pembeli';

  /// Izin lihat kolom Stok — persis web (`search`/`part`):
  /// `buyer ? false : (admin || col_stok)`. Default tampil sebelum izin dimuat.
  bool get showStok =>
      isBuyer ? false : (isAdmin || columns == null || columns!.contains('col_stok'));

  /// Izin lihat kolom Harga — persis web: `admin || col_harga`. Default tampil
  /// sebelum izin dimuat. (Di Detail Part, pembeli SELALU lihat harga — ditangani
  /// khusus di layar itu karena pembeli perlu harga untuk belanja.)
  bool get showHarga =>
      isAdmin || columns == null || columns!.contains('col_harga');

  // ── Helper config server-driven (semua dengan fallback aman) ─────────

  Map<String, dynamic> _sub(String key) {
    final v = config[key];
    return v is Map ? v.cast<String, dynamic>() : const {};
  }

  /// Chip saran layar Asisten. Kosong/absen → pakai [fallback] hardcoded.
  List<String> asistenSuggestions(List<String> fallback) {
    final v = config['asisten_suggestions'];
    if (v is List) {
      final list = v.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
      if (list.isNotEmpty) return list;
    }
    return fallback;
  }

  bool fotoTtaDefault(bool fallback) {
    final v = _sub('foto')['tta_default'];
    return v is bool ? v : fallback;
  }

  int fotoTopK(int fallback) {
    final v = _sub('foto')['top_k'];
    return v is num ? v.toInt() : fallback;
  }

  double fotoThreshold(double fallback) {
    final v = _sub('foto')['threshold'];
    return v is num ? v.toDouble() : fallback;
  }

  int searchPageSize(int fallback) {
    final v = _sub('search')['page_size'];
    return v is num ? v.toInt() : fallback;
  }

  int searchFetchSize(int fallback) {
    final v = _sub('search')['fetch_size'];
    return v is num ? v.toInt() : fallback;
  }

  int searchMaxFetch(int fallback) {
    final v = _sub('search')['max_fetch'];
    return v is num ? v.toInt() : fallback;
  }

  static AppNav of(BuildContext context) {
    final nav = context.dependOnInheritedWidgetOfExactType<AppNav>();
    assert(nav != null, 'AppNav tidak ditemukan — layar harus di dalam AppShell');
    return nav!;
  }

  @override
  bool updateShouldNotify(AppNav old) =>
      old.screen != screen ||
      old.selectedPart != selectedPart ||
      old.username != username ||
      old.role != role ||
      old.columns != columns ||
      old.config != config;
}
