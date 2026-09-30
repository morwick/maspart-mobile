/// Konfigurasi terpusat untuk URL API.
///
/// `apiBaseUrl` dibaca dari --dart-define saat build. Default kini menunjuk ke
/// SERVER PRODUKSI (https://maspart.tech), jadi `flutter build apk --release`
/// langsung memakai server live tanpa flag tambahan.
///
/// Override untuk development (kalau perlu uji ke backend lokal):
///   HP fisik via USB + adb reverse : --dart-define=API_BASE_URL=http://127.0.0.1:8001
///   Emulator Android               : --dart-define=API_BASE_URL=http://10.0.2.2:8001
///
/// Build APK rilis (produksi, default):
///   flutter build apk --release
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://maspart.tech',
  );

  // Endpoint paths (backend MASPART V5 — semua di bawah prefix /api).
  static const String loginPath        = '/api/auth/login';
  static const String mePath           = '/api/auth/me';
  static const String permissionsPath  = '/api/auth/permissions';
  static const String searchPnPath     = '/api/parts/search';
  static const String searchNamePath   = '/api/parts/search-name';
  static const String searchImagePath  = '/api/parts/search-image';
  static const String photosPath       = '/api/parts/photos';
  static const String aiStatusPath     = '/api/ai/status';
  static const String aiChatPath       = '/api/ai/chat';

  /// OAuth Client ID Google tipe **iOS** (Google Cloud Console, bundle ID app).
  /// iOS wajib punya ini — tanpa itu GoogleSignIn SDK melempar exception native
  /// (crash). Android tak memakainya. Default = client "Maspart iOS" (project
  /// part-finder, bundle com.example.maspartMobile) — BUKAN rahasia. Ganti
  /// bundle ID → buat client iOS baru, override via
  ///   --dart-define=GOOGLE_IOS_CLIENT_ID=xxxx.apps.googleusercontent.com
  /// dan perbarui reversed client ID di CFBundleURLTypes ios/Runner/Info.plist.
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '793205866762-1inn0gb4tvm94df5aiu0gh6hpfn4e8dd.apps.googleusercontent.com',
  );

  // Storage key untuk JWT
  static const String tokenStorageKey = 'jwt_access_token';
}
