// Penanda AKUN GUDANG di Manajemen User — parsing respons /api/admin/users.
import 'package:flutter_test/flutter_test.dart';
import 'package:maspart_mobile/models.dart';

void main() {
  test('AdminUser membaca gudang_cabang; tanpa field (server lama) = bukan akun gudang', () {
    final a = AdminUser.fromJson({'username': 'andi', 'role': 'user', 'gudang_cabang': ['Jakarta', 'Pekanbaru']});
    expect(a.gudangCabang, ['Jakarta', 'Pekanbaru']);
    expect(a.akunGudang, isTrue);
    final b = AdminUser.fromJson({'username': 'budi', 'role': 'user'});
    expect(b.gudangCabang, isEmpty);
    expect(b.akunGudang, isFalse);
  });

  test('tanda akun_gudang dari server menang; bisa bertanda tanpa memegang gudang', () {
    final c = AdminUser.fromJson({'username': 'citra', 'role': 'user', 'akun_gudang': true, 'gudang_cabang': []});
    expect(c.akunGudang, isTrue);
    expect(c.pegangGudang, isFalse);
    expect(c.akunGudangFlag, isTrue);
    final d = AdminUser.fromJson({'username': 'dodi', 'role': 'user', 'akun_gudang': false});
    expect(d.akunGudang, isFalse);
  });

  test('GudangUtama: display, cadangan ke label', () {
    final g = GudangUtama.fromJson({'key': 'pekanbaru', 'label': '02.Pekanbaru', 'display': 'Pekanbaru', 'akun': 'andi'});
    expect([g.key, g.display, g.akun], ['pekanbaru', 'Pekanbaru', 'andi']);
    expect(GudangUtama.fromJson({'key': 'x', 'label': '23.Medan', 'akun': 'medan'}).display, '23.Medan');
  });
}
