// lib/push.dart — push notifikasi SISTEM (baki notifikasi Android) via Firebase
// Cloud Messaging: perubahan status pesanan & notifikasi lonceng lainnya.
//
// Mode TIDUR: selama android/app/google-services.json belum ada, plugin Google
// Services tidak diterapkan (lihat android/app/build.gradle.kts), sehingga
// Firebase.initializeApp() gagal → [Push.aktif] = false dan SEMUA fungsi di sini
// jadi no-op diam-diam. Aplikasi berjalan normal; lonceng dalam aplikasi tetap
// bekerja lewat polling. Taruh file itu + build ulang → push langsung aktif.
//
// Alur:
//   • main()        → Push.init()     : Firebase, kanal "pesanan", pendengar.
//   • shell siap    → Push.daftarkan(): minta izin, kirim token ke server.
//   • logout        → Push.lepas()    : hapus token di server, lalu di perangkat.
//   • ketuk push    → [Push.tautanTertunda] ← tautan web; shell yang membukanya
//                     (via tujuanTautan di app/nav.dart, sama dengan lonceng).
// ⛔ Tak ada fungsi di sini yang boleh melempar galat ke pemanggil.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

/// Penangan pesan saat aplikasi di latar belakang / tertutup. Pesan bertipe
/// `notification` sudah ditampilkan sistem sendiri, jadi cukup kosong — tapi
/// WAJIB terdaftar & top-level (dijalankan di isolate terpisah).
@pragma('vm:entry-point')
Future<void> _pushLatarBelakang(RemoteMessage message) async {}

class Push {
  Push._();

  /// true = Firebase berhasil diinisialisasi (google-services.json terpasang).
  static bool aktif = false;

  /// Tautan web dari push yang diketuk tapi BELUM dibuka shell. Diisi walau
  /// shell belum ada (cold start / masih di layar login); shell mendengarkan
  /// notifier ini dan mengosongkannya lewat [ambilTautan] begitu sesi siap.
  static final ValueNotifier<String?> tautanTertunda = ValueNotifier(null);

  /// Ambil & kosongkan tautan tertunda (null = tak ada).
  static String? ambilTautan() {
    final t = tautanTertunda.value;
    if (t != null) tautanTertunda.value = null;
    return t;
  }

  static final _lokal = FlutterLocalNotificationsPlugin();

  /// Ikon notifikasi = logo putih transparan (Android hanya memakai kanal alfa).
  static const _ikon = 'ic_launcher_foreground';

  /// Kanal yang sama dengan `android.notification.channel_id` dari server dan
  /// meta-data default di AndroidManifest.xml.
  static const _kanal = AndroidNotificationChannel(
    'pesanan',
    'Status Pesanan',
    description: 'Kabar perubahan status pesanan & return',
    importance: Importance.high,
  );

  static StreamSubscription<String>? _subRefresh;

  /// Token FCM terakhir yang berhasil dikirim ke server (untuk dilepas saat logout).
  static String? _tokenTerdaftar;

  static Future<void> init() async {
    // Hanya Android yang dikonfigurasi (iOS belum punya GoogleService-Info.plist).
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Push: Firebase belum dikonfigurasi — push tidur ($e)');
      return;
    }
    aktif = true;
    try {
      FirebaseMessaging.onBackgroundMessage(_pushLatarBelakang);

      await _lokal.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_ikon),
        ),
        onDidReceiveNotificationResponse: (r) => _buka(r.payload),
      );
      await _lokal
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_kanal);

      // Latar depan: FCM TIDAK menampilkan notifikasi sendiri → tampilkan lokal.
      FirebaseMessaging.onMessage.listen(_tampilkanDepan);
      // Diketuk saat aplikasi di latar belakang.
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _buka(_tautanDari(m)));
      // Diketuk saat aplikasi tertutup (cold start) — push sistem…
      final awal = await FirebaseMessaging.instance.getInitialMessage();
      if (awal != null) _buka(_tautanDari(awal));
      // …atau notifikasi lokal yang ditampilkan sebelum aplikasi ditutup.
      final luncur = await _lokal.getNotificationAppLaunchDetails();
      if (luncur?.didNotificationLaunchApp ?? false) {
        _buka(luncur!.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('Push: inisialisasi pendengar gagal ($e)');
    }
  }

  /// Minta izin notifikasi (Android 13+) lalu daftarkan token ke server.
  /// Dipanggil tiap sesi dibuka (login baru maupun login otomatis).
  static Future<void> daftarkan() async {
    if (!aktif) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _kirim(token);
      _subRefresh ??= FirebaseMessaging.instance.onTokenRefresh.listen(_kirim);
    } catch (e) {
      debugPrint('Push: daftar token gagal ($e)');
    }
  }

  static Future<void> _kirim(String token) async {
    try {
      final siap = await ApiService.daftarPerangkat(token, 'android');
      _tokenTerdaftar = token;
      // aktif=false = server belum punya Firebase/migrasi — bukan galat.
      if (!siap) debugPrint('Push: token diterima, push server belum aktif');
    } catch (e) {
      debugPrint('Push: kirim token gagal ($e)');
    }
  }

  /// Logout: lepas token di server (SEBELUM token sesi dibuang), lalu hapus
  /// token perangkat supaya akun berikutnya di HP ini dapat token baru.
  static Future<void> lepas() async {
    if (!aktif) return;
    await _subRefresh?.cancel();
    _subRefresh = null;
    try {
      final token = _tokenTerdaftar ??
          await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 3));
      if (token != null && token.isNotEmpty) await ApiService.lepasPerangkat(token);
    } catch (e) {
      debugPrint('Push: lepas token di server gagal ($e)');
    }
    _tokenTerdaftar = null;
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('Push: hapus token perangkat gagal ($e)');
    }
  }

  static String? _tautanDari(RemoteMessage m) {
    final t = m.data['tautan']?.toString().trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static void _buka(String? tautan) {
    final t = tautan?.trim();
    if (t == null || t.isEmpty) return;
    tautanTertunda.value = t;
  }

  static Future<void> _tampilkanDepan(RemoteMessage m) async {
    try {
      final judul = m.notification?.title ?? m.data['judul']?.toString() ?? '';
      final isi = m.notification?.body ?? m.data['isi']?.toString() ?? '';
      if (judul.isEmpty && isi.isEmpty) return;
      await _lokal.show(
        id: (m.messageId ?? '${DateTime.now().microsecondsSinceEpoch}').hashCode & 0x7fffffff,
        title: judul,
        body: isi,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _kanal.id,
            _kanal.name,
            channelDescription: _kanal.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: _ikon,
            styleInformation: BigTextStyleInformation(isi),
          ),
        ),
        payload: _tautanDari(m),
      );
    } catch (e) {
      debugPrint('Push: tampilkan notifikasi gagal ($e)');
    }
  }
}
