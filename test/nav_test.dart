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
      expect(tabs.map((t) => t.screen).toList(), [
        MasScreen.toko,
        MasScreen.search,
        MasScreen.asisten,
        MasScreen.pesanan,
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
}
