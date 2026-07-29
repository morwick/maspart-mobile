import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'config.dart';

/// Wrapper di atas flutter_secure_storage untuk simpan/load JWT token.
/// Token disimpan ENCRYPTED di Android Keystore (otomatis oleh library).
class AuthStorage {
  static const _storage = FlutterSecureStorage();

  static Future<void> saveToken(String token) async {
    await _storage.write(key: AppConfig.tokenStorageKey, value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: AppConfig.tokenStorageKey);
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: AppConfig.tokenStorageKey);
  }
}
