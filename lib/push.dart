// lib/push.dart — push notifikasi SISTEM (Android & iPhone) via Firebase Cloud
// Messaging: perubahan status pesanan, notifikasi lonceng & siaran promo.
//
// Mode TIDUR: selama file konfigurasi Firebase belum ada —
// android/app/google-services.json (Android) / ios/Runner/GoogleService-Info.plist
// (iOS) — Firebase.initializeApp() gagal → [Push.aktif] = false dan SEMUA fungsi
// di sini jadi no-op diam-diam. Aplikasi berjalan normal; lonceng dalam aplikasi
// tetap bekerja lewat polling. Taruh file itu + build ulang → push langsung aktif.
//
// iOS: FCM mengirim lewat APNs → butuh kunci APNs (.p8, akun Apple Developer
// berbayar) di Firebase. Tanpa itu getAPNSToken() null → token tak didaftarkan.
// Notifikasi saat aplikasi TERBUKA ditampilkan iOS sendiri
// (setForegroundNotificationPresentationOptions), bukan notifikasi lokal seperti
// Android — supaya gambar promo dari Notification Service Extension
// (ios/NotificationService) ikut tampil & tak dobel.
//
// Alur:
//   • main()        → Push.init()     : Firebase, kanal "pesanan", pendengar.
//   • shell siap    → Push.daftarkan(): minta izin, kirim token ke server.
//   • logout        → Push.lepas()    : hapus token di server, lalu di perangkat.
//   • ketuk push    → [Push.tautanTertunda] ← tautan web; shell yang membukanya
//                     (via tujuanTautan di app/nav.dart, sama dengan lonceng).
//   • tiap push     → data['badge'] = jumlah belum dibaca → angka di ikon
//                     aplikasi (lib/ikon_badge.dart), juga saat aplikasi tertutup.
//                     Pesan data-saja {badge} = sinkron angka (dibaca di web).
//   • promo         → data['jenis']=='promo' (siaran admin, /admin/promo-push):
//                     kanal "promo" sendiri (bisa dimatikan pembeli tanpa
//                     kehilangan kabar pesanan), gambar kecil di kanan & besar
//                     saat dibentangkan, TANPA badge (bukan notifikasi lonceng).
// ⛔ Tak ada fungsi di sini yang boleh melempar galat ke pemanggil.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'ikon_badge.dart';

/// Penangan pesan saat aplikasi di latar belakang / tertutup. Pesan bertipe
/// `notification` sudah ditampilkan sistem sendiri; di sini hanya angka badge
/// ikon yang diperbarui. WAJIB terdaftar & top-level (isolate terpisah).
@pragma('vm:entry-point')
Future<void> _pushLatarBelakang(RemoteMessage message) async {
  final n = IkonBadge.dariData(message.data);
  if (n != null) await IkonBadge.pasang(n);
}

class Push {
  Push._();

  /// true = Firebase berhasil diinisialisasi (file konfigurasi Firebase terpasang).
  static bool aktif = false;

  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

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

  /// Kanal siaran promo — samakan dengan `CHANNEL_PROMO` di backend
  /// (services/push.py). Saat aplikasi di latar belakang/tertutup, FCM sendiri
  /// yang menampilkan notifikasinya (lengkap dengan gambar) di kanal ini.
  static const _kanalPromo = AndroidNotificationChannel(
    'promo',
    'Promo & Penawaran',
    description: 'Promo, voucher & penawaran spesial MasPart',
    importance: Importance.high,
  );

  static StreamSubscription<String>? _subRefresh;

  /// Token FCM terakhir yang berhasil dikirim ke server (untuk dilepas saat logout).
  static String? _tokenTerdaftar;

  static Future<void> init() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android && !_ios)) {
      return;
    }
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
          // Izin diminta FirebaseMessaging.requestPermission() di daftarkan();
          // plugin lokal di iOS hanya dipakai membersihkan baki (semuaDibaca).
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => _buka(r.payload),
      );
      final android = _lokal
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_kanal);
      await android?.createNotificationChannel(_kanalPromo);

      // Latar depan: Android — FCM TIDAK menampilkan notifikasi sendiri →
      // tampilkan lokal. iOS — biarkan sistem yang menampilkan (lihat atas).
      if (_ios) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
            alert: true, badge: true, sound: true);
      }
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

  /// Minta izin notifikasi (Android 13+ / iOS) lalu daftarkan token ke server.
  /// Dipanggil tiap sesi dibuka (login baru maupun login otomatis).
  static Future<void> daftarkan() async {
    if (!aktif) return;
    try {
      final izin = await FirebaseMessaging.instance.requestPermission();
      if (_ios) {
        if (izin.authorizationStatus == AuthorizationStatus.denied) return;
        // Token FCM di iOS baru ada setelah token APNs tiba (asinkron, bisa
        // beberapa detik). null terus = kunci APNs/akun Apple belum siap.
        String? apns;
        for (var i = 0; i < 5 && apns == null; i++) {
          apns = await FirebaseMessaging.instance.getAPNSToken();
          if (apns == null) await Future.delayed(const Duration(seconds: 2));
        }
        if (apns == null) {
          debugPrint('Push: token APNs belum tersedia — push iOS belum bisa');
          return;
        }
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _kirim(token);
      _subRefresh ??= FirebaseMessaging.instance.onTokenRefresh.listen(_kirim);
    } catch (e) {
      debugPrint('Push: daftar token gagal ($e)');
    }
  }

  static Future<void> _kirim(String token) async {
    try {
      final siap = await ApiService.daftarPerangkat(token, _ios ? 'ios' : 'android');
      _tokenTerdaftar = token;
      // aktif=false = server belum punya Firebase/migrasi — bukan galat.
      if (!siap) debugPrint('Push: token diterima, push server belum aktif');
    } catch (e) {
      debugPrint('Push: kirim token gagal ($e)');
    }
  }

  /// Semua notifikasi sudah dibaca → angka di ikon hilang & baki notifikasi
  /// sistem aplikasi ini dibersihkan.
  static Future<void> semuaDibaca() async {
    await IkonBadge.pasang(0);
    if (!aktif) return;
    try {
      await _lokal.cancelAll();
    } catch (e) {
      debugPrint('Push: bersihkan baki gagal ($e)');
    }
  }

  /// Logout: lepas token di server (SEBELUM token sesi dibuang), lalu hapus
  /// token perangkat supaya akun berikutnya di HP ini dapat token baru.
  static Future<void> lepas() async {
    await semuaDibaca(); // angka akun lama tak boleh tertinggal di ikon
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

  /// Unduh gambar notifikasi promo (null = tak ada / gagal → tampil tanpa gambar).
  static Future<Uint8List?> _unduhGambar(String? url) async {
    if (url == null || !url.startsWith('https://')) return null;
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      return r.statusCode == 200 && r.bodyBytes.isNotEmpty ? r.bodyBytes : null;
    } catch (e) {
      debugPrint('Push: unduh gambar promo gagal ($e)');
      return null;
    }
  }

  static Future<void> _tampilkanDepan(RemoteMessage m) async {
    final promo = m.data['jenis']?.toString() == 'promo';
    final badge = promo ? null : IkonBadge.dariData(m.data);
    if (badge != null) IkonBadge.pasang(badge);
    if (_ios) return; // sudah ditampilkan sistem (presentation options)
    try {
      final judul = m.notification?.title ?? m.data['judul']?.toString() ?? '';
      final isi = m.notification?.body ?? m.data['isi']?.toString() ?? '';
      if (judul.isEmpty && isi.isEmpty) return;
      final kanal = promo ? _kanalPromo : _kanal;
      // Promo bergambar: kecil di kanan saat ringkas (largeIcon), besar saat
      // dibentangkan (BigPicture) — sama dengan tampilan FCM di latar belakang.
      final gambar = promo
          ? await _unduhGambar(
              m.notification?.android?.imageUrl ?? m.data['gambar']?.toString())
          : null;
      final bmp = gambar == null ? null : ByteArrayAndroidBitmap(gambar);
      await _lokal.show(
        id: (m.messageId ?? '${DateTime.now().microsecondsSinceEpoch}').hashCode & 0x7fffffff,
        title: judul,
        body: isi,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            kanal.id,
            kanal.name,
            channelDescription: kanal.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: _ikon,
            largeIcon: bmp,
            styleInformation: bmp != null
                ? BigPictureStyleInformation(bmp,
                    contentTitle: judul, summaryText: isi, hideExpandedLargeIcon: true)
                : BigTextStyleInformation(isi),
            number: badge,
          ),
        ),
        payload: _tautanDari(m),
      );
    } catch (e) {
      debugPrint('Push: tampilkan notifikasi gagal ($e)');
    }
  }
}
