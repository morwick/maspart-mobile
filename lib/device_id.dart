// lib/device_id.dart
// Identitas perangkat untuk kebijakan "Kunci ke perangkat pertama" (Menu
// Control → Sesi) — cerminan `frontend/src/lib/device.ts`.
//
// Kode acak dibuat SEKALI lalu disimpan di secure storage, dan dikirim di tiap
// login sebagai `device_id`. Tanpa ini akun yang dikunci ditolak backend
// ("aplikasi Anda tidak mengirim identitas perangkat").
//
// Konsekuensi yang harus dipahami admin: hapus data aplikasi / uninstall =
// kode baru = dianggap perangkat lain → login ditolak sampai admin melepas
// ikatan. TIDAK ikut dihapus saat logout — logout bukan ganti perangkat.

import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceId {
  static const _storage = FlutterSecureStorage();
  static const _key = 'maspart_device_id';
  static String? _cache;

  /// Kode perangkat ini; "" bila penyimpanan tak bisa dipakai (backend lalu
  /// menolak akun yang dikunci — sama dengan web saat localStorage diblokir).
  static Future<String> get() async {
    if (_cache != null && _cache!.isNotEmpty) return _cache!;
    try {
      var id = await _storage.read(key: _key);
      if (id == null || id.isEmpty) {
        final r = Random.secure();
        final hex = List.generate(16, (_) => r.nextInt(256))
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        id = 'app-$hex';
        await _storage.write(key: _key, value: id);
      }
      _cache = id;
      return id;
    } catch (_) {
      return '';
    }
  }

  /// User-Agent login → label "Aplikasi MasPart di Android" di Menu Control
  /// (backend `login_history.device_label`). Default `Dart/x (dart:io)` terbaca
  /// "Tidak dikenal", jadi admin tak bisa membedakan HP dari curl.
  static String userAgent() {
    String os;
    try {
      os = Platform.isAndroid
          ? 'Android'
          : Platform.isIOS
              ? 'iPhone'
              : Platform.operatingSystem;
    } catch (_) {
      os = 'unknown';
    }
    return 'MasPartApp ($os)';
  }
}
