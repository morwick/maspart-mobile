import Flutter
import GoogleMaps
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Push (lib/push.dart): FlutterAppDelegate jadi delegate notifikasi supaya
    // firebase_messaging & flutter_local_notifications SAMA-SAMA menerima
    // event tampil/ketuk (FlutterAppDelegate meneruskannya ke tiap plugin).
    UNUserNotificationCenter.current().delegate = self
    if let kunci = AppDelegate.kunciMaps { GMSServices.provideAPIKey(kunci) }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // lib/peta_google.dart: Google Maps hanya dipakai bila API key terpasang —
    // tanpa provideAPIKey, GMSMapView langsung crash → Dart memakai OpenStreetMap.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MaspartPeta") {
      FlutterMethodChannel(name: "maspart/peta", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          if call.method == "googleSiap" {
            result(AppDelegate.kunciMaps != nil)
          } else {
            result(FlutterMethodNotImplemented)
          }
        }
    }
  }

  /// MAPS_API_KEY dari ios/Flutter/Secrets.xcconfig → Info.plist (GMSApiKey).
  /// nil bila kosong / belum diisi (nilai "$(MAPS_API_KEY)" mentah = tak terdefinisi).
  static let kunciMaps: String? = {
    guard let k = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String else { return nil }
    let t = k.trimmingCharacters(in: .whitespaces)
    return (t.isEmpty || t.hasPrefix("$(")) ? nil : t
  }()
}
