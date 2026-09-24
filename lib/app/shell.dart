// lib/app/shell.dart
// Shell utama: header 56px + drawer Command Center + body per-layar + toggle tema.
// Satu scaffold, banyak layar (arsitektur single-component sesuai desain).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_service.dart';
import '../auth_storage.dart';
import '../cart.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/notif_bell.dart';
import 'mas_drawer.dart';
import 'nav.dart';

import '../screens/admin_ai_screens.dart';
import '../screens/admin_manage_screens.dart';
import '../screens/admin_pengetahuan_screen.dart';
import '../screens/asisten_screen.dart';
import '../screens/beli_lagi_screen.dart';
import '../screens/cabang_screens.dart';
import '../screens/chat_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/data_screens.dart';
import '../screens/foto_screen.dart';
import '../screens/harga_screen.dart';
import '../screens/keranjang_screen.dart';
import '../screens/login_screen.dart';
import '../screens/orders_screens.dart';
import '../screens/part_detail_screen.dart';
import '../screens/pesanan_detail_screen.dart';
import '../screens/pesanan_screen.dart';
import '../screens/poin_screen.dart';
import '../screens/profil_screen.dart';
import '../screens/voucher_screen.dart';
import '../screens/pilih_lokasi_screen.dart';
import '../screens/rak_screen.dart';
import '../screens/retur_screens.dart';
import '../screens/search_screen.dart';
import '../screens/toko_screen.dart';

/// Kunci cache config server-driven (agar tersedia sebelum fetch selesai/offline).
const String _kAppConfigKey = 'maspart_app_config';

class AppShell extends StatefulWidget {
  final MasScreen initial;
  const AppShell({super.key, this.initial = MasScreen.dashboard});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _cart = CartStore.instance;

  late MasScreen _screen = widget.initial;

  /// Argumen layar aktif (part terpilih, kode pesanan, dsb).
  Map<String, dynamic>? _args;
  final List<(MasScreen, Map<String, dynamic>?)> _history = [];

  String _username = '';
  String _role = 'user';
  Set<String>? _allowedMenus; // null = izin belum dimuat
  Set<String>? _columns; // izin kolom (col_stok/col_harga); null = belum dimuat
  // Fitur halaman elevated (Menu Control tab "Fitur"), mis. 'stok_weichai'.
  // Default TERTUTUP → kosong (bukan null): sebelum izin dimuat, fiturnya tak
  // ditampilkan. Admin ditangani di getter nav.
  Set<String> _fitur = const {};
  String? _branch;

  /// Gudang yang boleh DITULIS pada Rak & Kartu Stok (label penuh). Kosong =
  /// user bukan pengelola gudang → menunya disembunyikan (lihat buildNavSections).
  List<String> _gudangKelola = const [];
  bool _navigated = false;

  // Config server-driven + notifikasi update.
  Map<String, dynamic> _appConfig = const {};
  bool _updateAvailable = false; // versi baru tersedia (banner)
  bool _forceUpdate = false; // versi terpasang < minimum & force → wajib update
  bool _updateDismissed = false; // user menutup banner
  String _downloadUrl = 'https://maspart.tech/download';

  /// Versi terpasang, untuk kaki drawer. Kosong = belum terbaca.
  String _appVersion = '';

  /// Waktu tombol Kembali terakhir ditekan di beranda — dipakai pola "tekan
  /// sekali lagi untuk keluar" supaya aplikasi tak tertutup tak sengaja.
  DateTime? _lastBackAt;

  List<NavSection> get _sections => buildNavSections(
        role: _role,
        allowed: _allowedMenus,
        branch: _branch,
        gudangKelola: _gudangKelola,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cart.addListener(_onCartChanged);
    _loadCachedConfig();
    _loadSession();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _appVersion = i.version);
    }).catchError((_) {});
  }

  /// Izin dimuat sekali saat sesi dibuka, padahal admin bisa mengubah centang
  /// Menu Control kapan saja untuk akun LAIN — tak ada event yang bisa dipakai
  /// di sisi klien. Menyegarkannya saat aplikasi kembali aktif adalah padanan
  /// TTL 60 detik di web: perubahan terlihat tanpa harus login ulang.
  /// (Penegakan sesungguhnya tetap di server.)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    try {
      final p = await ApiService.getMyPermissions();
      if (!mounted) return;
      setState(() {
        _role = p.role.isNotEmpty ? p.role : _role;
        _allowedMenus = p.menus.toSet();
        _columns = p.columns.toSet();
        _fitur = p.fitur.toSet();
        _branch = p.branch?.trim();
        _gudangKelola = p.gudangKelola;
      });
      _applyHomeAndGuard();
    } catch (_) {
      /* jaringan mati / server lama → pertahankan izin yang sudah ada */
    }
  }

  /// Muat config server-driven dari cache lebih dulu, supaya layar punya nilai
  /// sebelum fetch selesai (atau saat offline).
  Future<void> _loadCachedConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kAppConfigKey);
      if (raw == null || raw.isEmpty || !mounted) return;
      final m = jsonDecode(raw);
      if (m is Map) setState(() => _appConfig = m.cast<String, dynamic>());
    } catch (_) {
      /* cache rusak → pakai default hardcoded di tiap layar */
    }
  }

  /// Metadata aplikasi: config server-driven + cek versi (notifikasi update).
  /// Non-blocking & tahan-gagal — server lama/offline tak boleh memecahkan app.
  Future<void> _loadAppMeta() async {
    AppMeta meta;
    try {
      meta = await ApiService.appMeta();
    } catch (_) {
      return; // endpoint belum ada / jaringan → diamkan, pakai cache/default
    }
    if (!mounted) return;
    setState(() => _appConfig = meta.config);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAppConfigKey, jsonEncode(meta.config));
    } catch (_) {/* cache gagal → tak fatal */}

    // Bandingkan NAMA VERSI (semver) terpasang dengan versi terbaru server —
    // admin cukup mengisi "2.1.4", tak perlu tahu versionCode.
    String installed = '';
    try {
      final info = await PackageInfo.fromPlatform();
      installed = info.version; // versionName, mis. "2.1.4"
    } catch (_) {}
    final v = meta.version;
    if (!mounted || v.latestName.isEmpty || installed.isEmpty) return;
    setState(() {
      _downloadUrl = v.downloadUrl;
      _updateAvailable = compareVersion(v.latestName, installed) > 0;
      _forceUpdate = v.force &&
          v.minName.isNotEmpty &&
          compareVersion(installed, v.minName) < 0;
    });
  }

  Future<void> _openDownload() async {
    final uri = Uri.tryParse(_downloadUrl);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('Tidak bisa membuka $_downloadUrl');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cart.removeListener(_onCartChanged);
    super.dispose();
  }

  // Lencana keranjang di drawer ikut berubah saat isi keranjang berubah.
  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSession() async {
    // Config server-driven + cek update — jalan sendiri, tak memblokir sesi.
    _loadAppMeta();

    ApiService.me().then((u) {
      if (!mounted) return;
      final username = (u['username'] ?? u['name'] ?? '').toString();
      setState(() {
        _username = username;
        _role = (u['role'] ?? _role).toString();
      });
      // Keranjang disimpan PER-USER: dua akun di satu HP tak boleh tercampur.
      _cart.load(username);
      _applyHomeAndGuard();
    }).catchError((_) {});

    // Izin menu efektif (persis Menu Control web) — berlaku untuk SEMUA peran,
    // termasuk pembeli.
    try {
      final p = await ApiService.getMyPermissions();
      if (!mounted) return;
      setState(() {
        _role = p.role.isNotEmpty ? p.role : _role;
        _allowedMenus = p.menus.toSet();
        _columns = p.columns.toSet();
        _fitur = p.fitur.toSet();
        _branch = p.branch?.trim();
        _gudangKelola = p.gudangKelola;
      });
      _applyHomeAndGuard();
    } on ApiException {
      /* endpoint tak tersedia → biarkan default aman (semua item ber-permKey) */
    }
  }

  MasScreen _homeScreen(List<NavSection> secs) {
    if (secs.isNotEmpty && secs.first.items.isNotEmpty) {
      return secs.first.items.first.screen;
    }
    return MasScreen.search;
  }

  /// Arahkan ke beranda yang benar & cegah membuka layar tanpa izin.
  void _applyHomeAndGuard() {
    final secs = _sections;
    final access = accessibleScreens(secs);
    setState(() {
      if (!_navigated) {
        _screen = _homeScreen(secs);
      } else if (!access.contains(_screen)) {
        _screen = _homeScreen(secs);
        _history.clear();
      }
    });
  }

  void _go(MasScreen target, {Map<String, dynamic>? part}) {
    // Menekan tujuan yang SEDANG dibuka (bilah bawah / drawer) tak boleh
    // menumpuk riwayat — kalau tidak, tombol Kembali harus ditekan sekian kali
    // untuk keluar dari satu layar yang sama.
    if (target == _screen && part == null) {
      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() {
      _navigated = true;
      _history.add((_screen, _args));
      _screen = target;
      if (part != null) _args = part;
    });
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _back() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    setState(() {
      _screen = prev.$1;
      _args = prev.$2;
    });
  }

  /// Tombol Kembali perangkat keras Android. Shell ini menyimpan riwayatnya
  /// SENDIRI (bukan lewat Navigator), jadi tanpa penanganan ini satu tekan
  /// Kembali dari layar sedalam apa pun langsung MENUTUP aplikasi — cacat
  /// paling terasa di HP.
  ///
  /// Urutannya: tutup drawer → mundur di riwayat → kembali ke beranda →
  /// "tekan sekali lagi untuk keluar".
  void _handleSystemBack() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
      return;
    }
    if (_history.isNotEmpty) {
      HapticFeedback.selectionClick();
      _back();
      return;
    }
    final home = _homeScreen(_sections);
    if (_screen != home) {
      setState(() => _screen = home);
      return;
    }
    final now = DateTime.now();
    final last = _lastBackAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    _toast('Tekan Kembali sekali lagi untuk keluar');
  }

  /// Pesan singkat. [actionLabel] + [onAction] memberi JALAN KELUAR langsung
  /// (mis. "masuk keranjang → Lihat"), supaya user tak perlu mencari sendiri
  /// menu tujuannya setelah membaca notifikasinya.
  void _toast(String message, {String? actionLabel, VoidCallback? onAction}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        action: (actionLabel == null || onAction == null)
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ));
  }

  Future<void> _logout() async {
    await ApiService.logout(); // audit log: LOGOUT (sebelum token dibuang)
    await AuthStorage.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }

  (String, String) get _title {
    final a = _args;
    if (_screen == MasScreen.part && a != null) {
      return ('${a['part_number'] ?? 'Detail Part'}', '${a['part_name'] ?? ''}');
    }
    // Layar detail pesanan: kode pesanan lebih berguna di header daripada
    // judul generik.
    const detailPesanan = {
      MasScreen.pesananDetail,
      MasScreen.orderDetail,
      MasScreen.cabangPesananDetail,
    };
    if (detailPesanan.contains(_screen) && a?['order_code'] != null) {
      return ('${a!['order_code']}', 'Detail pesanan');
    }
    if ((_screen == MasScreen.returDetail ||
            _screen == MasScreen.cabangReturDetail) &&
        a?['return_code'] != null) {
      return ('Return ${a!['return_code']}', 'Detail return');
    }
    if (_screen == MasScreen.returAjukan && a?['order_code'] != null) {
      return ('Ajukan Return', 'Pesanan ${a!['order_code']}');
    }
    return kScreenTitles[_screen] ?? ('MasPart', '');
  }

  Widget _buildBody() {
    final args = _args ?? const <String, dynamic>{};
    switch (_screen) {
      // Umum
      case MasScreen.dashboard:
        return const DashboardScreen();
      case MasScreen.search:
        return const SearchPartScreen();
      case MasScreen.part:
        return PartDetailScreen(part: args);
      case MasScreen.asisten:
        return const AsistenScreen();
      case MasScreen.foto:
        return const FotoScreen();
      case MasScreen.harga:
        return const HargaScreen();
      case MasScreen.compare:
        return const CompareScreen();
      case MasScreen.batch:
        return const BatchScreen();
      case MasScreen.populasi:
        return const PopulasiScreen();
      case MasScreen.stok:
        return const StokScreen();
      case MasScreen.opname:
        return const OpnameScreen();
      case MasScreen.rak:
        return const RakScreen();

      // Pembeli
      case MasScreen.toko:
        return const TokoScreen();
      case MasScreen.keranjang:
        return const KeranjangScreen();
      case MasScreen.pesanan:
        return PesananScreen(args: args);
      case MasScreen.poin:
        return const PoinScreen();
      case MasScreen.voucher:
        return const VoucherScreen();
      case MasScreen.pesananDetail:
        return PesananDetailScreen(args: args);
      case MasScreen.beliLagi:
        return const BeliLagiScreen();
      case MasScreen.pilihLokasi:
        return const PilihLokasiScreen();
      case MasScreen.chat:
        return ChatScreen(args: args);
      case MasScreen.profil:
        return const ProfilScreen();
      case MasScreen.returSaya:
        return const ReturSayaScreen();
      case MasScreen.returAjukan:
        return AjukanReturScreen(args: args);
      case MasScreen.returDetail:
        return ReturDetailScreen(args: args);

      // Cabang
      case MasScreen.cabangPesanan:
        return const CabangPesananScreen();
      case MasScreen.cabangPesananDetail:
        return CabangPesananDetailScreen(args: args);
      case MasScreen.cabangRetur:
        return const CabangReturScreen();
      case MasScreen.cabangReturDetail:
        return CabangReturDetailScreen(args: args);
      case MasScreen.cabangPenjualan:
        return const CabangPenjualanScreen();
      case MasScreen.cabangChat:
        return const CabangChatScreen();

      // Admin
      case MasScreen.orders:
        return const OrdersScreen();
      case MasScreen.orderDetail:
        return OrderDetailScreen(args: args);
      case MasScreen.penjualan:
        return const PenjualanScreen();
      case MasScreen.feedback:
        return const FeedbackScreen();
      case MasScreen.chatlog:
        return const ChatLogScreen();
      case MasScreen.misses:
        return const MissesScreen();
      case MasScreen.sinonim:
        return SinonimScreen(args: args);
      case MasScreen.maksud:
        return const MaksudScreen();
      case MasScreen.pengetahuan:
        return const PengetahuanScreen();
      case MasScreen.menu:
        return const MenuControlScreen();
      case MasScreen.monitoring:
        return const MonitoringScreen();
      case MasScreen.upload:
        return const UploadScreen();
      case MasScreen.users:
        return const UsersScreen();
      case MasScreen.gudang:
        return const GudangScreen();
      case MasScreen.fotopart:
        return const FotoPartScreen();
      case MasScreen.imageindex:
        return const ImageIndexScreen();
    }
  }

  /// Kunci KeyedSubtree: layar detail harus dibangun ulang saat argumennya
  /// berubah (mis. buka pesanan lain), kalau tidak state lama ikut terbawa.
  String get _bodyKey {
    final a = _args;
    return switch (_screen) {
      MasScreen.part => 'part:${a?['part_number'] ?? ''}',
      MasScreen.pesananDetail ||
      MasScreen.orderDetail ||
      MasScreen.cabangPesananDetail =>
        '${_screen.name}:${a?['order_code'] ?? ''}',
      MasScreen.returAjukan =>
        'returAjukan:${a?['order_code'] ?? ''}:${a?['pn'] ?? ''}',
      MasScreen.returDetail || MasScreen.cabangReturDetail =>
        '${_screen.name}:${a?['return_code'] ?? ''}',
      // Dua layar ini bisa dibuka dengan isian awal (Chat Gudang dari Detail
      // Part, "+ Sinonim" dari Pencarian Nihil). Tanpa argumen di kunci, state
      // kunjungan sebelumnya terpakai ulang dan prefill-nya hilang.
      MasScreen.chat => 'chat:${a?['gudang'] ?? ''}',
      MasScreen.sinonim => 'sinonim:${a?['trigger'] ?? ''}',
      _ => _screen.name,
    };
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final title = _title;
    final isBuyer = _role == 'pembeli';
    final sections = _sections;
    final access = accessibleScreens(sections);
    final updateWall = _forceUpdate || (_updateAvailable && !_updateDismissed);
    // Papan ketik terbuka (mengetik di Asisten / kolom cari) → bilah bawah
    // disembunyikan: ia akan naik menempel di atas papan ketik dan memakan
    // ruang jawaban tanpa gunanya.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final tabs = updateWall || keyboardUp || kNoBottomBar.contains(_screen)
        ? const <NavTab>[]
        : buildBottomTabs(role: _role, accessible: access);

    return PopScope(
      // Shell memakai riwayat internal, bukan Navigator: tanpa canPop:false
      // tombol Kembali menutup aplikasi dari layar mana pun.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: m.canvas,
        drawerEnableOpenDragGesture: true,
        drawer: Drawer(
          backgroundColor: const Color(0xFF0F1411),
          width: 272,
          shape: const RoundedRectangleBorder(),
          child: MasDrawer(
            current: _screen,
            username: _username,
            role: _role,
            sections: sections,
            version: _appVersion,
            onGo: (s) => _go(s),
            onLogout: _logout,
          ),
        ),
        bottomNavigationBar: tabs.isEmpty
            ? null
            : _BottomBar(
                tabs: tabs,
                current: _screen,
                onTap: (t) => _go(t),
                onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                menuActive: false,
              ),
        body: AppNav(
          screen: _screen,
          selectedPart: _args,
          username: _username,
          role: _role,
          columns: _columns,
          fitur: _fitur,
          gudangKelola: _gudangKelola,
          config: _appConfig,
          accessible: access,
          go: _go,
          back: _back,
          canBack: _history.isNotEmpty,
          openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
          closeDrawer: () {
            if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
              Navigator.of(context).pop();
            }
          },
          toast: _toast,
          logout: _logout,
          child: updateWall
              // Notifikasi update = SATU HALAMAN PENUH saat app dibuka (bisa
              // ditutup kecuali force). Muncul di atas segalanya.
              ? _updateScreen(m, dismissible: !_forceUpdate)
              // Bawah: bila bilah bawah tampil, DIA yang menyerap inset gestur
              // sistem; bila tidak, SafeArea ini yang melakukannya. Persis satu
              // kali — aplikasi menggambar edge-to-edge (wajib di Android 15).
              : SafeArea(
                  bottom: tabs.isEmpty,
                  child: Column(
                    children: [
                      _Header(
                        title: title.$1,
                        subtitle: title.$2,
                        onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                        // Pintasan keranjang hanya berarti untuk pembeli.
                        cartCount: isBuyer ? _cart.count : 0,
                        onCart: isBuyer ? () => _go(MasScreen.keranjang) : null,
                        // Lonceng notifikasi (status return) — pembeli saja,
                        // paritas web NotifBell.
                        showNotif: isBuyer,
                      ),
                      Expanded(
                        child: KeyedSubtree(
                          key: ValueKey(_bodyKey),
                          child: _buildBody(),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// Halaman penuh "Versi baru tersedia" — muncul saat app dibuka bila ada
  /// update. [dismissible] false = update WAJIB (force): tak ada X / "Nanti saja".
  Widget _updateScreen(MasColors m, {required bool dismissible}) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F1411), Color(0xFF026A0E), Color(0xFF028912)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(children: [
            // Baris atas: tombol tutup (X) hanya bila boleh ditutup.
            SizedBox(
              height: 44,
              child: dismissible
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                        tooltip: 'Tutup',
                        onPressed: () => setState(() => _updateDismissed = true),
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
                    ),
                    child: const Icon(Icons.system_update_alt_rounded, size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Versi baru tersedia',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    dismissible
                        ? 'Ada pembaruan MasPart dengan fitur & perbaikan terbaru. '
                            'Perbarui sekarang untuk pengalaman terbaik.'
                        : 'Versi aplikasi Anda sudah tidak didukung lagi. '
                            'Perbarui untuk melanjutkan memakai aplikasi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, height: 1.55, color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ]),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _openDownload,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF026A0E),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Perbarui Sekarang',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            if (dismissible) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => setState(() => _updateDismissed = true),
                child: Text('Nanti saja',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13.5)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onMenu;
  final int cartCount;
  final VoidCallback? onCart;
  final bool showNotif;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.onMenu,
    this.cartCount = 0,
    this.onCart,
    this.showNotif = false,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final theme = ThemeScope.of(context);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: m.paper,
        border: Border(bottom: BorderSide(color: m.ink150)),
      ),
      child: Row(children: [
        _iconButton(context, Icons.menu_rounded, onMenu, tooltip: 'Menu'),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: m.ink900,
                    letterSpacing: -0.1,
                  )),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: m.ink500)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (showNotif) const NotifBell(),
        if (onCart != null) ...[
          _cartButton(context),
          const SizedBox(width: 8),
        ],
        _iconButton(
          context,
          theme.isDarkIn(context) ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          () => theme.toggleFrom(context),
          tooltip: theme.mode == ThemeMode.system
              ? 'Tema ikut HP — tekan untuk mengunci'
              : 'Ganti tema (tekan lama: ikut HP)',
          onLongPress: () {
            theme.followSystem();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Tema mengikuti setelan HP')));
          },
        ),
      ]),
    );
  }

  Widget _cartButton(BuildContext context) {
    final m = context.mas;
    return Stack(clipBehavior: Clip.none, children: [
      _iconButton(context, Icons.shopping_cart_outlined, onCart!, tooltip: 'Keranjang'),
      if (cartCount > 0)
        Positioned(
          right: -3,
          top: -3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 16),
            height: 16,
            decoration: BoxDecoration(
              color: m.brand600,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: m.paper, width: 1.5),
            ),
            child: Center(
              child: Text(
                cartCount > 99 ? '99+' : '$cartCount',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _iconButton(
    BuildContext context,
    IconData icon,
    VoidCallback onTap, {
    String? tooltip,
    VoidCallback? onLongPress,
  }) {
    final m = context.mas;
    Widget btn = Material(
      color: m.paper,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress: onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onLongPress();
              },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: m.ink200),
          ),
          child: Icon(icon, size: 16, color: m.ink700),
        ),
      ),
    );
    if (tooltip != null) btn = Tooltip(message: tooltip, child: btn);
    return btn;
  }
}

/// Bilah navigasi bawah — tujuan yang paling sering dipakai dalam SATU tekan.
///
/// Sebelumnya seluruh perpindahan layar harus lewat drawer (buka drawer →
/// gulir → pilih): tiga gerakan untuk pekerjaan yang di lapangan dilakukan
/// puluhan kali sehari, sambil memegang HP satu tangan. Isinya mengikuti peran
/// & izin (lihat [buildBottomTabs]); slot terakhir membuka drawer untuk sisanya.
class _BottomBar extends StatelessWidget {
  final List<NavTab> tabs;
  final MasScreen current;
  final ValueChanged<MasScreen> onTap;
  final VoidCallback onMenu;
  final bool menuActive;

  const _BottomBar({
    required this.tabs,
    required this.current,
    required this.onTap,
    required this.onMenu,
    required this.menuActive,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      decoration: BoxDecoration(
        color: m.paper,
        border: Border(top: BorderSide(color: m.ink150)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(children: [
            for (final t in tabs)
              Expanded(
                child: _cell(
                  context,
                  label: t.label,
                  icon: t.screen == current ? t.activeIcon : t.icon,
                  active: t.screen == current,
                  onTap: () => onTap(t.screen),
                ),
              ),
            Expanded(
              child: _cell(
                context,
                label: 'Menu',
                icon: Icons.menu_rounded,
                active: menuActive,
                onTap: onMenu,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _cell(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    final m = context.mas;
    final fg = active ? m.brand700 : m.ink500;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkResponse(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        radius: 44,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: active ? m.brand50 : Colors.transparent,
                borderRadius: BorderRadius.circular(MasRadii.pill),
              ),
              child: Icon(icon, size: 19, color: fg),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
