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
  rak,

  // Pembeli
  toko,
  keranjang,
  pesanan,
  pesananDetail,
  pilihLokasi,
  poin,
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
  maksud,
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
  MasScreen.rak: ('Rak & Kartu Stok', 'Lokasi rak & foto kartu stok per gudang'),

  MasScreen.toko: ('Belanja Part', 'Etalase part siap kirim dari gudang terdekat'),
  MasScreen.keranjang: ('Keranjang', 'Tinjau part, pilih ekspedisi, lalu bayar'),
  MasScreen.pesanan: ('Pesanan Saya', 'Riwayat & status pesanan'),
  MasScreen.pesananDetail: ('Detail Pesanan', ''),
  MasScreen.pilihLokasi: ('Ganti Lokasi', 'Pilih gudang tempat Anda berbelanja'),
  MasScreen.poin: ('Poin Saya', 'Kumpulkan poin tiap belanja, tukar jadi potongan'),
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
  MasScreen.maksud: ('Rute Maksud', 'Istilah khas bengkel → alat yang dipakai Asisten AI'),
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
  NavItem('Poin Saya', Icons.card_giftcard_rounded, MasScreen.poin, permKey: 'poin'),
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
  NavItem('Rak & Kartu Stok', Icons.shelves, MasScreen.rak, permKey: 'rak'),
];

const List<NavItem> _navAdmin = [
  NavItem('Pesanan', Icons.shopping_cart_outlined, MasScreen.orders),
  NavItem('Laporan Penjualan', Icons.bar_chart_rounded, MasScreen.penjualan),
  NavItem('Umpan Balik AI', Icons.forum_outlined, MasScreen.feedback),
  NavItem('Observabilitas AI', Icons.monitor_heart_outlined, MasScreen.chatlog),
  NavItem('Pencarian Nihil', Icons.search_off_rounded, MasScreen.misses),
  NavItem('Kamus Sinonim', Icons.menu_book_outlined, MasScreen.sinonim),
  NavItem('Rute Maksud', Icons.alt_route_rounded, MasScreen.maksud),
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
///
/// [gudangKelola] = daftar gudang yang boleh DITULIS user (izin Rak & Kartu
/// Stok); kosong berarti user hanya bisa MELIHAT rak dari Detail Part.
List<NavSection> buildNavSections({
  required String role,
  required Set<String>? allowed,
  String? branch,
  List<String> gudangKelola = const [],
}) {
  final isAdmin = role == 'admin';
  final isBuyer = role == 'pembeli';

  bool show(NavItem it) {
    // "Rak & Kartu Stok" adalah menu PENGELOLA. Melihat rak terbuka untuk semua
    // staf lewat Detail Part, tapi halaman ini isinya aksi tulis — tanpa syarat
    // gudang_kelola, staf biasa membuka layar yang semua tombolnya mati.
    if (it.screen == MasScreen.rak && !isAdmin && gudangKelola.isEmpty) {
      return false;
    }
    return it.permKey == null || allowed == null || allowed.contains(it.permKey);
  }

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

/// Satu tujuan di bilah bawah (bottom navigation).
class NavTab {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final MasScreen screen;
  const NavTab(this.label, this.icon, this.activeIcon, this.screen);
}

/// Kandidat bilah bawah menurut peran, berurut prioritas. Yang tak boleh
/// diakses akun ini dilewati, lalu diambil 4 teratas (slot ke-5 = "Menu").
const List<NavTab> _tabsBuyer = [
  NavTab('Belanja', Icons.storefront_outlined, Icons.storefront, MasScreen.toko),
  NavTab('Cari', Icons.search_rounded, Icons.search_rounded, MasScreen.search),
  NavTab('Asisten', Icons.smart_toy_outlined, Icons.smart_toy_rounded, MasScreen.asisten),
  NavTab('Pesanan', Icons.receipt_long_outlined, Icons.receipt_long, MasScreen.pesanan),
  NavTab('Chat', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, MasScreen.chat),
];

const List<NavTab> _tabsStaff = [
  NavTab('Beranda', Icons.dashboard_outlined, Icons.dashboard_rounded, MasScreen.dashboard),
  NavTab('Cari', Icons.search_rounded, Icons.search_rounded, MasScreen.search),
  NavTab('Asisten', Icons.smart_toy_outlined, Icons.smart_toy_rounded, MasScreen.asisten),
  NavTab('Foto', Icons.photo_camera_outlined, Icons.photo_camera_rounded, MasScreen.foto),
  NavTab('Harga', Icons.payments_outlined, Icons.payments_rounded, MasScreen.harga),
  NavTab('Stok', Icons.grid_view_outlined, Icons.grid_view_rounded, MasScreen.stok),
  NavTab('Populasi', Icons.local_shipping_outlined, Icons.local_shipping_rounded, MasScreen.populasi),
];

/// Maksimal 4 tujuan tetap; sisanya lewat tombol "Menu" (drawer).
const int kMaxBottomTabs = 4;

/// Bangun isi bilah bawah. Kosong (≤1 tujuan) → bilahnya tak ditampilkan sama
/// sekali, supaya akun yang menunya dipangkas Menu Control tak dapat bilah
/// berisi satu tombol.
List<NavTab> buildBottomTabs({
  required String role,
  required Set<MasScreen> accessible,
}) {
  final src = role == 'pembeli' ? _tabsBuyer : _tabsStaff;
  final out = <NavTab>[];
  for (final t in src) {
    if (!accessible.contains(t.screen)) continue;
    out.add(t);
    if (out.length == kMaxBottomTabs) break;
  }
  return out.length >= 2 ? out : const [];
}

/// Layar DALAM (detail) — bilah bawah disembunyikan di sini supaya isinya dapat
/// tinggi penuh dan jelas bahwa user sedang "masuk ke dalam", bukan berpindah
/// tujuan utama.
const Set<MasScreen> kNoBottomBar = {
  MasScreen.part,
  MasScreen.pesananDetail,
  MasScreen.orderDetail,
  MasScreen.cabangPesananDetail,
  MasScreen.keranjang,
  MasScreen.pilihLokasi,
};

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

  /// Fitur halaman elevated yang menyala (Menu Control tab "Fitur"), mis.
  /// `stok_weichai`. ⚠️ Beda dari [columns]: default-nya TERTUTUP, jadi
  /// "belum dimuat" = jangan tampilkan dulu (kosong, bukan null).
  final Set<String> fitur;

  /// Gudang yang boleh DITULIS user pada fitur Rak & Kartu Stok — label PENUH
  /// ("01.Jakarta"). Kosong = user hanya boleh MELIHAT rak.
  final List<String> gudangKelola;

  /// Config server-driven (`/api/app/meta` → `config`). Kosong = pakai default
  /// hardcoded tiap layar. Baca lewat helper di bawah agar fallback konsisten.
  final Map<String, dynamic> config;
  final Set<MasScreen> accessible;
  final void Function(MasScreen target, {Map<String, dynamic>? part}) go;
  final VoidCallback back;
  final bool canBack;
  final VoidCallback openDrawer;
  final VoidCallback closeDrawer;
  final void Function(String message, {String? actionLabel, VoidCallback? onAction}) toast;
  final VoidCallback logout;

  const AppNav({
    super.key,
    required this.screen,
    required this.selectedPart,
    required this.username,
    required this.role,
    this.columns,
    this.fitur = const {},
    this.gudangKelola = const [],
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

  /// Kartu "Stok Pemasok Weichai" di Detail Part — fitur elevated, DEFAULT
  /// hanya admin & akun 'mas' (aturan pemilik 2026-08-25). Beda dari showStok:
  /// sebelum izin dimuat kartunya TIDAK ditampilkan (fail-closed), supaya tak
  /// berkedip untuk akun yang tak berhak. Pagar tampilan saja — server tetap
  /// membalas `blocked` untuk yang tak berizin.
  bool get showWeichaiStock =>
      !isBuyer && (isAdmin || fitur.contains('stok_weichai'));

  /// Boleh mengubah rak gudang ini? [gudangPenuh] WAJIB label penuh Accurate
  /// ("01.Jakarta") — nama lokasi versi pembeli tak akan pernah cocok.
  /// Ini pagar TAMPILAN saja; penegakan sesungguhnya tetap 403 dari server.
  bool bolehUbahRak(String gudangPenuh) =>
      isAdmin || gudangKelola.contains(gudangPenuh);

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
      old.fitur != fitur ||
      old.gudangKelola != gudangKelola ||
      old.config != config;
}
