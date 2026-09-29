// Uji aturan bilah bawah (bottom navigation): isinya WAJIB tunduk pada peran &
// izin Menu Control — kalau tidak, bilah ini jadi pintu belakang ke layar yang
// sengaja dimatikan admin untuk akun tersebut.
import 'package:flutter_test/flutter_test.dart';
import 'package:maspart_mobile/app/nav.dart';

void main() {
  Set<MasScreen> access({
    String role = 'user',
    Set<String>? allowed,
    String? branch,
    List<String> gudangKelola = const [],
  }) =>
      accessibleScreens(buildNavSections(
        role: role,
        allowed: allowed,
        branch: branch,
        gudangKelola: gudangKelola,
      ));

  group('buildBottomTabs', () {
    test('staf penuh → Beranda, Cari, Asisten, Foto (maks 4)', () {
      final tabs = buildBottomTabs(role: 'user', accessible: access());
      expect(tabs.length, kMaxBottomTabs);
      expect(tabs.map((t) => t.screen).toList(), [
        MasScreen.dashboard,
        MasScreen.search,
        MasScreen.asisten,
        MasScreen.foto,
      ]);
    });

    test('pembeli → alur belanja, bukan menu staf', () {
      final tabs = buildBottomTabs(role: 'pembeli', accessible: access(role: 'pembeli'));
      // 'Cari' dicabut dari menu pembeli 2026-09-23 (kotak cari etalase Belanja
      // sudah jadi pencarian pembeli) — slot keempat kini Chat.
      expect(tabs.map((t) => t.screen).toList(), [
        MasScreen.toko,
        MasScreen.asisten,
        MasScreen.pesanan,
        MasScreen.chat,
      ]);
    });

    test('menu yang dimatikan Menu Control TIDAK muncul di bilah bawah', () {
      // Akun staf tanpa izin 'ai' & 'search_image' → Asisten dan Foto hilang,
      // digantikan kandidat berikutnya yang memang boleh (Harga).
      final tabs = buildBottomTabs(
        role: 'user',
        accessible: access(allowed: {'search', 'harga', 'stok'}),
      );
      final screens = tabs.map((t) => t.screen).toList();
      expect(screens.contains(MasScreen.asisten), isFalse);
      expect(screens.contains(MasScreen.foto), isFalse);
      expect(screens, [
        MasScreen.dashboard,
        MasScreen.search,
        MasScreen.harga,
        MasScreen.stok,
      ]);
    });

    test('pembeli dengan menu terpangkas habis → bilah bawah TIDAK ditampilkan', () {
      // Hanya "Belanja" yang tersisa (item tanpa permKey) + layar anak.
      final tabs = buildBottomTabs(
        role: 'pembeli',
        accessible: {MasScreen.toko, ...const {MasScreen.keranjang}},
      );
      expect(tabs, isEmpty, reason: 'bilah berisi satu tombol tak berguna');
    });

    test('layar detail tidak memakai bilah bawah', () {
      expect(kNoBottomBar.contains(MasScreen.part), isTrue);
      expect(kNoBottomBar.contains(MasScreen.keranjang), isTrue);
      expect(kNoBottomBar.contains(MasScreen.dashboard), isFalse);
    });
  });

  // Masukan penguji 2026-09-29: seksi "Admin" datar dipecah per pekerjaan
  // (paritas AppShell.tsx web).
  group('seksi menu admin', () {
    List<MasScreen> isi(List<NavSection> secs, String label) =>
        secs.firstWhere((s) => s.label == label).items.map((it) => it.screen).toList();

    test('admin → Data (+User & Gudang), Penjualan, Tools AI, Sistem', () {
      final secs = buildNavSections(role: 'admin', allowed: null);
      expect(secs.map((s) => s.label).toList(), [
        'Ringkasan', 'Pencarian', 'Data', 'Penjualan', 'Tools Pembelajaran AI', 'Sistem',
      ]);
      expect(isi(secs, 'Data'), containsAll([MasScreen.users, MasScreen.gudang]));
      expect(isi(secs, 'Penjualan'),
          [MasScreen.orders, MasScreen.bermasalah, MasScreen.penjualan]);
      expect(isi(secs, 'Tools Pembelajaran AI'),
          containsAll([MasScreen.feedback, MasScreen.fotopart, MasScreen.imageindex]));
      expect(isi(secs, 'Sistem'),
          [MasScreen.menu, MasScreen.monitoring, MasScreen.upload]);
    });

    test('staf non-admin tak mendapat menu admin di seksi Data', () {
      final secs = buildNavSections(role: 'user', allowed: null);
      expect(isi(secs, 'Data').contains(MasScreen.users), isFalse);
      expect(secs.any((s) => s.label == 'Penjualan'), isFalse);
    });
  });
}
