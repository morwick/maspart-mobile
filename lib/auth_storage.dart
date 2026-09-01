import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

/// Wrapper di atas flutter_secure_storage untuk simpan/load JWT token.
/// Token disimpan ENCRYPTED di Android Keystore (otomatis oleh library).
///
/// Mendukung dua mode, sesuai centang **"Ingat saya di device ini"** di layar
/// login — sebelumnya centang itu tak berpengaruh apa pun, token SELALU ditulis
/// ke disk:
///   • [persist] = true  → token ditulis ke secure storage (login otomatis
///     saat aplikasi dibuka lagi);
///   • [persist] = false → token hanya hidup di MEMORI proses, jadi begitu
///     aplikasi ditutup, sesinya ikut hilang (HP pinjaman / bersama).
class AuthStorage {
  static const _storage = FlutterSecureStorage();

  /// Token sesi berjalan. Selalu terisi setelah login, di kedua mode.
  static String? _memory;

  /// Nama pengguna terakhir yang berhasil login & memilih "Ingat saya".
  static const _lastUserKey = 'maspart_last_username';
  static const _persistKey = 'maspart_ingat_saya';

  /// Simpan token ke disk (true) atau cukup ke memori sesi ini (false).
  static bool persist = true;

  static Future<void> saveToken(String token) async {
    _memory = token;
    if (persist) {
      await _storage.write(key: AppConfig.tokenStorageKey, value: token);
    } else {
      // Mode sesi-saja: pastikan token lama di disk tidak tertinggal.
      await _storage.delete(key: AppConfig.tokenStorageKey);
    }
  }

  static Future<String?> getToken() async {
    if (_memory != null && _memory!.isNotEmpty) return _memory;
    final t = await _storage.read(key: AppConfig.tokenStorageKey);
    _memory = t;
    return t;
  }

  static Future<void> clearToken() async {
    _memory = null;
    await _storage.delete(key: AppConfig.tokenStorageKey);
  }

  // ── Kenyamanan login: ingat username (BUKAN password) ────────────────

  /// Pilihan "Ingat saya" terakhir + username-nya, untuk mengisi awal form
  /// login. Password tidak pernah disimpan di mana pun.
  static Future<(bool, String)> lastLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_persistKey) ?? true;
      return (remember, remember ? (prefs.getString(_lastUserKey) ?? '') : '');
    } catch (_) {
      return (true, '');
    }
  }

  static Future<void> rememberUsername(String username, bool remember) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_persistKey, remember);
      if (remember && username.trim().isNotEmpty) {
        await prefs.setString(_lastUserKey, username.trim());
      } else {
        await prefs.remove(_lastUserKey);
      }
    } catch (_) {
      /* gagal simpan preferensi → tidak fatal, form cuma mulai kosong */
    }
  }
}
