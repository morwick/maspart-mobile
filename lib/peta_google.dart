// lib/peta_google.dart
// Apakah Google Maps bisa dipakai di perangkat ini.
//
// Kunci Google Maps SDK dipasang di sisi native (android/local.properties →
// AndroidManifest, ios/Flutter/Secrets.xcconfig → Info.plist). Tanpa kunci,
// peta Google tampil kosong (Android) atau crash (iOS) — jadi layar peta
// bertanya dulu ke native lewat kanal `maspart/peta` dan memakai OpenStreetMap
// (flutter_map) bila jawabannya tidak.

import 'package:flutter/services.dart';

class PetaGoogle {
  PetaGoogle._();

  static const _kanal = MethodChannel('maspart/peta');
  static Future<bool>? _siap;

  /// true = API key Google Maps terpasang. Dicek sekali per sesi aplikasi.
  static Future<bool> siap() => _siap ??= _cek();

  static Future<bool> _cek() async {
    try {
      return await _kanal.invokeMethod<bool>('googleSiap') ?? false;
    } catch (_) {
      return false; // platform tanpa kanal (tes, desktop) → OpenStreetMap
    }
  }
}
