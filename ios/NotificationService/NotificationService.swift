import UserNotifications

/// Notification Service Extension — menempelkan GAMBAR notifikasi promo
/// (siaran admin /admin/promo-push) sebelum iOS menampilkannya: kecil di kanan
/// notifikasi, besar saat ditekan lama. Setara gambar di Android.
///
/// Server (backend services/push.py `_pesan_promo`) mengirim `mutable-content: 1`
/// + URL gambar di `fcm_options.image` (format FCM) dan `gambar` (data MasPart).
/// Gagal unduh / waktu habis → notifikasi tetap tampil, hanya tanpa gambar.
class NotificationService: UNNotificationServiceExtension {
  private var handler: ((UNNotificationContent) -> Void)?
  private var konten: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    handler = contentHandler
    konten = request.content.mutableCopy() as? UNMutableNotificationContent
    guard let konten = konten, let url = Self.urlGambar(request.content.userInfo) else {
      selesai()
      return
    }
    URLSession.shared.downloadTask(with: url) { [weak self] lokasi, resp, _ in
      // Hanya respons 200 bergambar: halaman galat (404 HTML) jangan ditempel.
      let http = resp as? HTTPURLResponse
      if let lokasi = lokasi, http?.statusCode == 200,
         http?.mimeType?.hasPrefix("image/") ?? false,
         let lampiran = Self.lampiran(lokasi, url: url, mime: http?.mimeType) {
        konten.attachments = [lampiran]
      }
      self?.selesai()
    }.resume()
  }

  /// iOS memberi ±30 dtk; bila habis, tampilkan apa adanya (tanpa gambar).
  override func serviceExtensionTimeWillExpire() {
    selesai()
  }

  /// Panggil handler TEPAT sekali (unduhan & batas waktu bisa berbarengan).
  private func selesai() {
    guard let h = handler else { return }
    handler = nil
    h(konten ?? UNNotificationContent())
  }

  private static func urlGambar(_ info: [AnyHashable: Any]) -> URL? {
    let fcm = (info["fcm_options"] as? [String: Any])?["image"] as? String
    let teks = fcm ?? (info["gambar"] as? String) ?? ""
    guard teks.hasPrefix("https://"), let url = URL(string: teks) else { return nil }
    return url
  }

  /// Berkas unduhan → lampiran. iOS menebak jenis gambar dari ekstensi berkas,
  /// jadi file sementara diberi ekstensi dari MIME / URL.
  private static func lampiran(_ lokasi: URL, url: URL, mime: String?) -> UNNotificationAttachment? {
    let ext: String
    switch mime {
    case "image/png": ext = "png"
    case "image/gif": ext = "gif"
    case "image/webp": ext = "webp"
    case "image/jpeg", "image/jpg": ext = "jpg"
    default: ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
    }
    let tujuan = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    do {
      try FileManager.default.moveItem(at: lokasi, to: tujuan)
      return try UNNotificationAttachment(identifier: "gambar", url: tujuan)
    } catch {
      return nil
    }
  }
}
