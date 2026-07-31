# MasPart Mobile — PROJECT.md

Aplikasi Android untuk MASPART (katalog & penjualan suku cadang truk Sinotruk).
Klien Flutter di atas backend FastAPI yang sama dengan web (`maspart.tech`).

- **Versi:** 2.2.0 (`pubspec.yaml` → `version: 2.2.0+13`) — rilis 2026-07-31
- **Package id:** `com.example.maspart_mobile`
- **Backend default:** `https://maspart.tech`
- **Disajikan di:** <https://maspart.tech/download> (APK = `frontend/public/maspart.apk`
  di repo utama — terpanggang di image frontend, deploy = `push.sh frontend` + recreate)
- **Kode:** ~27.000 baris Dart di `lib/`

> ⚠️ Repo ini punya riwayat commit sejak 2026-07-29 (`66fbc2b`) tapi **masih TANPA
> REMOTE** — commit hanya ada di laptop ini. Prioritaskan menambah remote + push.
> ⚠️ Jebakan build rilis (2026-07-31): `flutter build` yang di-background-kan harness
> AI bisa TERBUNUH — jalankan sebagai proses Windows terlepas (path penuh Git Bash;
> `cmd /c bash` jatuh ke WSL kosong) + pantau file log.

> **Perubahan sejak 2.1.4 (sesi 21–23 Juli 2026):**
> - **2.1.5** — fix stok tampil `—` di Detail Part HP.
> - **2.1.6** — alamat penerima tersimpan **per-akun** (bukan per-perangkat).
> - **2.1.7** — **lacak resi di dalam aplikasi** (manifest kurir via `/track/waybill`,
>   cache 10 menit; hanya pesanan sukses).
> - **2.1.8** — **popup Mode Perbaikan Asisten AI**: admin menyalakan saklar global di
>   Menu Control (web) → klien menampilkan popup pemberitahuan; server-driven, paritas
>   web. File terkait: `asisten_screen.dart`, `api_service.dart`, `shell.dart`,
>   `admin_ai_screens.dart`.
> - Auto-logout idle 5 menit sempat masuk lalu **dibatalkan pemilik** (di-revert web+mobile).
>
> **Perubahan 2.1.9 → 2.2.0 (sesi 29–31 Juli 2026):**
> - **2.1.9** — commit awal repo; Stop giliran asisten + konfirmasi hapus chat +
>   autoscroll cerdas (paritas UI/UX web Fase 1).
> - **2.2.0** (`a68dc84`) — rilis besar:
>   - **Rak & Kartu Stok**: stok per gudang di Detail Part bisa dibuka → rak/catatan/
>     foto kartu + tombol Ubah (gate `AppNav.bolehUbahRak` per label gudang PENUH);
>     layar "Rak & Kartu Stok" (daftar/cari live/edit; impor Excel = web-only); foto
>     via `image_picker` KAMERA dulu (use-case utama: memotret kartu di depan rak;
>     kompresi di sumber 1600px/q85 — backend mengompres lagi sbg penegak). Form ubah
>     bersama `widgets/rak_editor.dart` mengunci urutan kritis simpan-rak-DULU-baru-
>     foto. Semua endpoint pakai alias `{pn:path}` + encode (PN bisa ber-'/').
>   - **Kartu pertanyaan asisten** (`tanya_user`) — pilihan bergaya kartu; juga
>     dipakai alur konfirmasi fitur backend "Ajarkan Lewat Chat" (jalan TANPA
>     perubahan klien — kartu & chat generik).
>   - **Panel "Sebab guard menyala"** di Observabilitas AI (`guardSebab`).
>   - Saring live + bilah "N baris · M berfoto" (rak & pengetahuan).
> - **Ter-commit, menunggu APK berikutnya** (`5472690`): label "💬 dari chat" + chip
>   filter di layar Pengetahuan AI (`PengetahuanDok.asal`); (`b5e64a1`) chip
>   TAWARAN AJAR di layar pembuka asisten — "💡 N topik berulang gagal saya
>   jawab — Ajari saya?" (aiStatusFull += gapAjar/gapTopik dari gap_ajar;
>   hanya terisi utk akun yang boleh mengajar).

> **Perubahan besar sejak 2.0.0 (sesi 16 Juli 2026):**
> - **Notifikasi update in-app + config server-driven** (§9) — aplikasi cek versi
>   terbaru & feature-flag dari server saat dibuka; admin mengaturnya lewat halaman
>   web **Config Aplikasi** (`/admin/app-config`) TANPA rebuild.
> - **Fitur Invoice** pembeli (`lib/invoice_pdf.dart`, dep `pdf`) — unduh PDF pesanan lunas.
> - **Gating izin kolom stok/harga** di Cari Part & Detail Part (persis Menu Control web).
> - Perbaikan/parity: Asisten AI (streaming langkah live), Cari Part (saran/sort/paginasi),
>   Cari by Foto (crop + galeri belajar), Observabilitas AI (token), Populasi sort,
>   Pesanan/Cabang (tab/cari/aksi cepat), tombol Keranjang toko tak lagi terpotong.
> - Dep baru: `pdf`, `package_info_plus`.

Dokumen ini menjelaskan **apa isi aplikasinya**, **aturan yang tak boleh dilanggar**,
dan **cara mendorong rilis ke halaman download**. Untuk sejarah & keputusan sisi
web, lihat `PROJECT.md` di repo `maspart-v5`.

---

## 1. Prinsip yang menentukan benar/salahnya aplikasi ini

Empat hal berikut menyangkut **uang** dan **kejujuran data**. Melanggarnya tidak
membuat aplikasi crash — ia hanya menagih pembeli dengan angka yang salah, atau
menampilkan sesuatu yang tidak benar. Itu jauh lebih berbahaya.

### 1.1 PPN 12% itu INKLUSIF, bukan tambahan
Harga jual dari Accurate **sudah mengandung PPN**. Jadi:

```
ppn   = floor(subtotal × 12 / 112)      // komponen, hanya untuk ditampilkan
total = subtotal + ongkir               // PPN TIDAK ditambahkan di sini
```

Contoh dari Accurate: Sub Total 80.000 → PPN 12% 8.571 → **Total tetap 80.000**.
Implementasi: `lib/order_ui.dart` (`ppnOf`, `totalOf`). Harus sama persis dengan
`orders.ppn_included` di backend dan `order-ui.ts` di web. Kalau berbeda, tagihan
ke pembeli tidak akan cocok dengan dokumen Accurate.

### 1.2 Satu pesanan = satu gudang
Kurir tidak bisa mengirim satu paket dari dua kota. Keranjang **boleh** berisi
part dari banyak gudang, tapi checkout hanya untuk **gudang terpilih**; part dari
gudang lain **tetap tersimpan di keranjang** untuk pesanan berikutnya — tidak
dihapus. Implementasi: `lib/screens/keranjang_screen.dart` (`_gudangAktif`,
`_itemsBeli`, `CartStore.removeAll`).

### 1.3 Keadaan server selalu menang atas keranjang lokal
Keranjang di perangkat menyimpan harga **saat part dimasukkan** — bisa basi.
Sebelum checkout, layar keranjang wajib menyegarkan diri lewat
`ApiService.cartGudang()`, yang mengembalikan harga yang **akan ditagih**, gudang
pengirim, dan boleh-tidaknya part dibeli (`bisaDibeli` + `alasan`). Yang dilihat
pembeli harus = yang ditagih.

### 1.4 "Gagal mengambil data" ≠ "data bernilai nol"
Kalau stok Accurate gagal diambil (sesi kedaluwarsa / belum dikonfigurasi),
**jangan tampilkan 0**. Nol berarti *habis*; gagal berarti *tidak tahu*. Layar
Stok dan Detail Part membedakan keduanya secara eksplisit. Hal yang sama berlaku
di fitur cek-unit: `error` = gagal mengecek ke EPC, `cocok == false` = berhasil
mengecek dan memang tidak cocok. Dua hal berbeda, jangan disamakan.

> **Catatan sejarah.** Sebelum v2.0.0, 15 layar (Stok, Pesanan, Penjualan,
> Monitoring, Users, Menu Control, dll.) me-render **konstanta hardcoded** dan
> tampak seperti data asli. Semua sudah diganti dengan data dari API. Jangan
> pernah mengulangi pola itu: layar tanpa data lebih jujur daripada layar
> berdata palsu.

---

## 2. Arsitektur

```
lib/
  main.dart               entry point + tema
  config.dart             AppConfig.apiBaseUrl (dart-define)
  auth_storage.dart       JWT di flutter_secure_storage (Android Keystore)
  api_service.dart        ~120 method — cerminan frontend/src/lib/api.ts
  models.dart             seluruh model; di-export ulang oleh api_service.dart
  cart.dart               CartStore (ChangeNotifier) + alamat tersimpan
  order_ui.dart           ppnOf/totalOf, status pesanan, OrderStepper, fmtDate
  utils.dart              formatRupiah, thousands, compareVersion (semver), dsb.
  invoice_pdf.dart        buildInvoicePdf/downloadInvoicePdf (dep `pdf` + open_filex)

  app/
    shell.dart            satu Scaffold; header + drawer + body per-layar;
                          fetch app-meta (update-notifier + config) di _loadSession
    nav.dart              enum MasScreen, judul, seksi drawer, AppNav
                          (+ getter izin kolom & getter config server-driven)
    mas_drawer.dart       drawer Command Center

  theme/mas_theme.dart    MasColors (context.mas), MasRadii, masMono()
  widgets/
    mas_ui.dart           MasCard, MasSectionCard, MasPill, MasInput, MasButton…
    order_chat.dart       widget percakapan (dipakai pembeli & cabang)

  screens/
    login, dashboard, search, part_detail, foto, harga, asisten
    toko, keranjang, pilih_lokasi, pesanan, pesanan_detail, pembayaran_webview,
    chat                                    ← alur pembeli
    cabang_screens.dart                     ← peran cabang
    data_screens.dart                       ← stok, populasi, compare, batch, opname
    orders_screens.dart                     ← pesanan admin + laporan penjualan
    admin_ai_screens.dart                   ← feedback, chat-log, misses, sinonim
    admin_manage_screens.dart               ← users, menu control, monitoring,
                                              upload, gudang, foto part, image index
```

### Navigasi
Bukan `Navigator` bertingkat. `AppShell` memegang satu `MasScreen` aktif dan
sebuah bag argumen (`_args`), lalu memilih body lewat `switch`. Layar berpindah
dengan `AppNav.of(context).go(MasScreen.x, part: {...})`.

Konsekuensi yang harus diingat: **layar dibangun ulang tiap navigasi**. State
apa pun yang harus bertahan (mis. riwayat chat asisten) wajib disimpan sendiri —
lihat `_simpanChat()` di `asisten_screen.dart`.

### Lapisan API
Semua panggilan lewat helper privat `_Api` di `api_service.dart`, sehingga
penanganan 401 (buang token + pesan "Sesi habis") ditulis **sekali saja**. Nama
path dan field JSON dijaga **persis** sama dengan backend — jangan "merapikan"
nama field di sisi Dart.

### Izin (Menu Control)
`ApiService.getMyPermissions()` → `menus`, `columns`, `harga_subtabs`, `role`,
`branch`. Kunci menu di backend (`MENU_TABS`): `ai`, `search`, `search_image`,
`compare`, `batch`, `populasi`, `harga`, `stok`.

Izin berlaku untuk **semua peran, termasuk pembeli** — admin mematikan "Asisten
AI" berarti menunya hilang untuk pembeli juga. `buildNavSections()` di `nav.dart`
yang menegakkan ini.

---

## 3. Layar per peran

**Pembeli** — Belanja (etalase), Cari Part, Asisten AI, Chat, Pesanan Saya,
Ganti Lokasi. Ditambah keranjang (ikon di header, berlencana) dan detail pesanan.

**User internal** — Dashboard, Pencarian (Asisten AI, Cari Part, Cari by Foto,
Bandingkan 2 Part, Batch Download), Data (Populasi, Harga, Stok, Stok Opname).

**Cabang** — semua milik user internal + seksi "Cabang <label>": Pesanan Masuk,
Chat, Laporan Penjualan.

**Admin** — semua di atas + Pesanan, Laporan Penjualan, Umpan Balik AI,
Observabilitas AI, Pencarian Nihil, Kamus Sinonim, Menu Control, Monitoring User,
Upload Data, Manajemen User, Lokasi Gudang, Foto Part, Image Index.

### Alur belanja (yang paling rawan)
```
toko → keranjang → alamat + kode pos → ongkir otomatis → checkout
     → Midtrans Snap (WebView in-app) → polling status → pesanan lunas
```
- Ongkir dihitung otomatis 900 ms setelah kode pos ≥ 5 digit (tombol manual tetap ada).
- Berat tertagih = `max(berat asli, volumetrik)`, dihitung **server** (`cartWeight`).
- Pembayaran: `paymentChannel: 'snap'` — metode (VA/QRIS/e-wallet/kartu) dipilih
  pembeli di halaman Midtrans.
- **Kebenaran pembayaran hanya dari `ApiService.paymentStatus()`** (dikonfirmasi
  webhook Midtrans di backend), **bukan** dari tebakan URL di WebView. WebView
  hanya memberi *sinyal*; setelah ditutup, layar tetap polling. Tombol "Sudah
  Bayar" ada karena sebagian metode (mis. VA) tidak pernah mengarahkan balik.

---

## 4. Konfigurasi

`lib/config.dart`:

```dart
static const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://maspart.tech',   // default = PRODUKSI
);
```

Build biasa langsung menembak produksi. Override untuk pengembangan:

```bash
# HP fisik via USB (jalankan `adb reverse tcp:8001 tcp:8001` dulu)
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8001

# Emulator Android
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001
```

---

## 5. Cara PUSH ke maspart.tech/download

Halaman `/download` menyajikan **file statis** `frontend/public/maspart.apk` dari
repo web (`maspart-v5`). Jadi merilis aplikasi = mengganti file itu lalu
men-deploy frontend.

> **Prasyarat:** akses SSH ke `root@maspart.tech` dan akses dashboard Coolify.
> Repo web diasumsikan ada di
> `D:\Project Python\maspart-main (PROJECT V5)\maspart-main`.

### Langkah 1 — naikkan versi

`pubspec.yaml`:
```yaml
version: 2.1.8+11    # versionName + build; contoh RILIS TERAKHIR
```

`versionCode` **wajib naik**, kalau tidak Android menolak update. Dengan
`--split-per-abi`, Flutter menambahkan offset ABI: arm64-v8a → `2000 + build`.
Jadi `+11` menjadi `versionCode 2011`. Riwayat: 2.1.0+3 (2003) → 2.1.1+4 (2004)
→ 2.1.2+5 (2005) → 2.1.3+6 (2006) → 2.1.4+7 (2007) → 2.1.5+8 (2008)
→ 2.1.6+9 (2009) → 2.1.7+10 (2010) → **2.1.8+11 (2011)**.

> **Setelah rilis, umumkan versi baru** supaya notifikasi update in-app menyala:
> di web **Config Aplikasi** (`/admin/app-config`) isi **"Versi terbaru"** =
> `2.1.9` (nama, bukan angka). Sejak 2.1.4 aplikasi membandingkan **nama versi**
> (semver), jadi `latest_code`/`min_code` (angka) **tak perlu disentuh admin** —
> lihat §9.

### Langkah 2 — build split arm64

APK yang live adalah **arm64-v8a saja** (bukan fat APK). Bersihkan dulu supaya
tidak ada file lama yang tanpa sengaja ikut terkirim:

```bash
cd /d/src/maspart_mobile
rm -f build/app/outputs/flutter-apk/app-*-release.apk
flutter build apk --release --split-per-abi
```

Hasil yang dipakai: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

> ⚠️ **Jebakan nyata.** Folder `build/` menyimpan APK dari build-build sebelumnya.
> Kalau tidak dihapus, sangat mudah menyalin APK **lama** sambil mengira sudah
> merilis yang baru. Selalu cek stempel waktunya:
> `ls -l --time-style=+%H:%M build/app/outputs/flutter-apk/`

### Langkah 3 — verifikasi APK sebelum dikirim

```bash
export JAVA_HOME="C:/Program Files/Android/Android Studio/jbr"
SDK=D:/src/android-sdk
APK=build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# versi & package
"$SDK/build-tools/37.0.0/aapt2.exe" dump badging "$APK" | grep ^package

# tanda tangan — HARUS sama dengan APK yang sedang live
"$SDK/build-tools/37.0.0/apksigner.bat" verify --print-certs "$APK" | grep "SHA-256 digest"
```

Yang harus benar:
- `versionCode` **lebih besar** dari yang live sekarang.
- Sertifikat SHA-256 **identik** dengan APK live.
  Saat ini: `9d30e94eeae58ab08cd93dca2b3cde87b6fe4b45d814732815ac942198f80740`
  (`CN=Android Debug`).

> ⚠️ **Rilis masih ditandatangani kunci DEBUG.** `android/app/build.gradle.kts`
> masih memakai `signingConfigs.getByName("debug")`. Ini bukan praktik yang benar
> untuk produksi, tapi **jangan diganti sembarangan**: begitu keystore berubah,
> tanda tangannya tidak cocok lagi dan **semua user harus uninstall dulu** sebelum
> bisa memasang update. Migrasi ke keystore sendiri butuh rencana tersendiri.

### Langkah 4 — pasang APK + naikkan versi di halaman download

```bash
WEB="/d/Project Python/maspart-main (PROJECT V5)/maspart-main"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$WEB/frontend/public/maspart.apk"
```

Lalu sunting `$WEB/frontend/src/app/download/page.tsx`:

```ts
const APK_SIZE   = "21 MB";    // sesuaikan: du -m frontend/public/maspart.apk
const APP_VERSION = "2.1.8";   // sesuaikan dengan pubspec
```

### Langkah 5 — kirim ke server & rebuild image

```bash
cd "$WEB"
bash deploy/coolify/push.sh frontend
```

Script ini `scp` `frontend/src` + `frontend/public` ke
`root@maspart.tech:/opt/maspart/frontend/`, lalu membangun ulang image di server.

> Script mengirim **isi disk apa adanya**, bukan isi commit. Pastikan
> `git status frontend/` bersih supaya tidak ada perubahan setengah jadi yang
> ikut terbawa.

### Langkah 6 — REDEPLOY (manual, wajib)

**Push saja belum membuatnya live.** Image sudah dibangun, tapi container yang
berjalan masih memakai image lama.

> Coolify → Projects → *My first project* → *production* → service **`maspart`**
> → tombol **REDEPLOY**

### Langkah 7 — pastikan benar-benar live

```bash
curl -sI https://maspart.tech/maspart.apk | grep -i content-length
```

Angkanya harus sama dengan ukuran APK baru. Kalau masih ukuran lama, redeploy
belum jalan.

---

## 6. Jebakan yang sudah pernah menggigit

| Masalah | Sebab | Solusi |
|---|---|---|
| Build Android gagal: `Could not find method jcenter()` | `flutter pub add file_picker` me-resolve ke **3.0.4** (kuno, pakai jcenter yang sudah dihapus Gradle 9) | Pin `file_picker: 11.0.0`. API-nya juga berubah: `FilePicker.pickFiles(...)` **statis**, bukan `FilePicker.platform.pickFiles(...)` |
| `Inconsistent JVM-target compatibility (17 vs 21)` | Sebagian plugin meng-compile Kotlin di JVM 21 sementara Java tetap 17 | Sudah ditangani terpusat di `android/build.gradle.kts` — `subprojects { KotlinCompile → JVM_17 }`. Jangan menambal per-plugin. |
| `ambiguous_import: OrderChat` | Model dan widget bernama sama | Model dinamai `OrderChatThread`; widget tetap `OrderChat` |
| Gradle OOM / build acak gagal | `org.gradle.jvmargs=-Xmx1024m` (RAM mesin terbatas) | Ulangi build; tutup aplikasi berat lain |
| Merilis APK lama tanpa sadar | File lama tertinggal di `build/` | `rm -f build/app/outputs/flutter-apk/app-*-release.apk` sebelum build |

---

## 7. Perbedaan yang disengaja terhadap web

- **Tata letak**, bukan fitur. Sidebar → drawer; tabel → kartu (tabel 6 kolom tak
  terbaca di HP); modal → bottom sheet; grid produk 2 kolom.
- **Midtrans dibuka di WebView dalam aplikasi**, bukan redirect keluar.
- **Riwayat chat asisten** bertahan sampai aplikasi ditutup-buka
  (`SharedPreferences`), sedangkan `sessionStorage` di web hilang saat tab
  ditutup. Foto yang **dikirim user** tidak ikut disimpan (bytes terlalu besar) —
  setelah dipulihkan, teksnya tetap ada, gambarnya tidak.
- Aturan bisnis, angka, dan endpoint: **sama persis**.

---

## 8. Yang belum diverifikasi

v2.0.0 di-push ke produksi **tanpa pernah dijalankan melawan server sungguhan**
(keputusan sadar pemilik, 13 Juli 2026). `flutter analyze` bersih dan APK
ter-build, tapi tidak ada satu pun alur yang pernah dijalankan end-to-end.

Yang paling perlu diuji lebih dulu, karena menyentuh uang:

1. **Checkout → Midtrans → status lunas.** Terutama deteksi selesai-bayar di
   WebView (`_outcomeOf` di `pembayaran_webview.dart`): Midtrans mengarahkan balik
   dengan cara berbeda tiap metode. Jaring pengamannya adalah polling
   `paymentStatus()` + tombol "Sudah Bayar".
2. **Ongkir muncul** setelah kode pos diisi (gudang pemenuh + berat volumetrik).
3. **Keranjang lintas gudang** — pastikan part gudang lain benar-benar tetap
   tersimpan setelah checkout gudang pertama.
4. **Asisten AI** — lampiran Excel (`sheetId` harus ikut terkirim di giliran
   berikutnya) dan unduh Excel.

---

## 9. Notifikasi update in-app + config server-driven (sejak 2.1.1)

Aplikasi ini disebar sebagai **APK sideload** (bukan Play Store) → tak ada
auto-update. Dua mekanisme membuatnya tetap terkelola tanpa sering rebuild:

### 9.1 Sumber data — `GET /api/app/meta` (publik, backend v5)
Aplikasi memanggilnya saat dibuka (`shell._loadAppMeta`, non-blocking, di-cache
`SharedPreferences`). Bentuk:
```json
{ "version": { "latest_name": "2.1.8", "min_name": "2.1.4", "force": false,
               "download_url": "https://maspart.tech/download",
               "latest_code": 2011, "min_code": 2007 },
  "config":  { "asisten_suggestions": [...], "foto": {...}, "search": {...} } }
```
Backend: `services/app_config.py` (file `<DATA_DIR>/app_config.json`, seed dari
env `Settings`), router `routers/app_meta.py`. Admin mengedit lewat
`/api/admin/app-config` → **halaman web `/admin/app-config` ("Config Aplikasi")**.

### 9.2 Notifikasi update (`_updateScreen` di shell.dart)
- **HALAMAN PENUH** saat app dibuka bila ada versi baru (gradient hijau, tombol
  **X**/"Nanti saja" + **Perbarui Sekarang** → `launchUrl(download_url)`).
- **Force** (`force==true` & versi terpasang < minimum): sama tapi **tanpa X** —
  wajib update.
- **Banding berbasis NAMA VERSI (semver)** sejak 2.1.4: `compareVersion` (utils)
  membandingkan `PackageInfo.version` ("2.1.4") dengan `latest_name`/`min_name`.
  Admin cukup mengisi **nama** versi — tak perlu tahu versionCode.
  > Transisi: app **2.1.1–2.1.3** masih membandingkan `versionCode`
  > (`latest_code`/`min_code`). Selama masih ada user versi itu, set juga angka
  > tsb (dilakukan saat rilis). Setelah semua di 2.1.4+, cukup nama.

### 9.3 Config server-driven (feature-flag)
Di-share ke layar lewat `AppNav` (getter ber-**fallback** ke default hardcoded,
jadi server kosong/offline tak memecahkan app). Yang dikonsumsi: saran Asisten
(`asisten_screen`), default Cari-by-Foto (`foto_screen`), limit Cari Part
(`search_screen`). Ubah di panel admin → berlaku saat app dibuka berikutnya,
**tanpa rebuild**.
