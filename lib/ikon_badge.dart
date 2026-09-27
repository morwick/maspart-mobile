// lib/ikon_badge.dart — ANGKA BADGE di ikon aplikasi (bulatan merah seperti
// ikon iPhone) = jumlah notifikasi belum dibaca.
//
// Sumber angka:
//   • push FCM (lib/push.dart) — data['badge'] dari server, juga saat aplikasi
//     tertutup (onBackgroundMessage) + android.notification.notification_count.
//   • lonceng (widgets/notif_bell.dart) — hasil polling /api/notifikasi, dan 0
//     begitu panel dibuka (semua dibaca).
//   • akun non-pembeli (tanpa lonceng) — 0 saat aplikasi dibuka (app/shell.dart).
// Android: angka tampil di launcher yang mendukung (Samsung, Xiaomi, Huawei,
// Oppo/Vivo, dll.); launcher Pixel/AOSP hanya menampilkan titik.
// ⛔ Tak ada fungsi di sini yang boleh melempar galat ke pemanggil.

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';

class IkonBadge {
  IkonBadge._();

  static bool? _didukung;

  /// Pasang angka [n] di ikon aplikasi (0 = hapus).
  /// Sengaja tanpa cache nilai terakhir: isolate latar belakang push punya
  /// memori sendiri, jadi cache di sini bisa basi.
  static Future<void> pasang(int n) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      _didukung ??= await AppBadgePlus.isSupported();
      if (_didukung != true) return;
      await AppBadgePlus.updateBadge(n < 0 ? 0 : n);
    } catch (e) {
      debugPrint('IkonBadge: gagal memasang badge ($e)');
    }
  }

  /// Angka badge dari data push (`data['badge']`, string); null = tak ada.
  static int? dariData(Map<String, dynamic> data) =>
      int.tryParse(data['badge']?.toString() ?? '');
}
