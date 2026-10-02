// lib/perusahaan.dart — penerbit dokumen resmi (kop surat).
//
// Kop surat resmi PT. Mas Automobil Sejahtera (KOP_SURAT_MAS_AUTO.docx).
// Salinan `PERUSAHAAN` di web: frontend/src/lib/invoice-format.ts — ubah
// keduanya bersamaan supaya invoice web & aplikasi tetap kembar.

class Perusahaan {
  Perusahaan._();

  static const nama = 'PT. MAS AUTOMOBIL SEJAHTERA';
  static const alamat =
      'Jl. SM Amin No. 226, RT 006 / RW 003, Kel. Binawidya, Kec. Binawidya';
  static const kota = 'Kota Pekanbaru, Riau 28292';
  static const telepon = '(0761) 565226';
  static const email = 'masautomobilsejahtera@gmail.com';
  static const web = 'maspart.tech';

  /// Logo + tulisan "MAS AUTOMOBIL SEJAHTERA" (434×186 px).
  static const logo = 'assets/kop/mas-logo.png';

  /// Logo tanpa tulisan — tanda air samar di tengah halaman (433×146 px).
  static const tandaAir = 'assets/kop/mas-tanda-air.png';
}
