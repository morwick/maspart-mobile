// lib/cart.dart
// Keranjang belanja pembeli — cerminan `frontend/src/lib/cart.ts`.
//
// Disimpan lokal per-username supaya keranjang dua akun di satu HP tidak
// tercampur. PENTING: `harga` di sini adalah harga SAAT PART DIMASUKKAN dan
// bisa basi. Sebelum checkout, layar keranjang wajib menyegarkan dirinya dari
// `ApiService.cartGudang()` — keadaan server yang menang, supaya yang dilihat
// pembeli = yang ditagih.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartItem {
  final String partNumber;
  final String name;

  /// Harga tampilan saat dimasukkan (mis. "Rp 600.000" atau "—").
  final String harga;

  /// Berat per item (gram). 0 = belum ditetapkan.
  final int berat;
  final int qty;

  const CartItem({
    required this.partNumber,
    this.name = '',
    this.harga = '',
    this.berat = 0,
    this.qty = 1,
  });

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
        partNumber: '${j['part_number'] ?? ''}',
        name: '${j['name'] ?? ''}',
        harga: '${j['harga'] ?? ''}',
        berat: (j['berat'] as num?)?.toInt() ?? 0,
        qty: (j['qty'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'part_number': partNumber,
        'name': name,
        'harga': harga,
        'berat': berat,
        'qty': qty,
      };

  CartItem copyWith({int? qty}) => CartItem(
        partNumber: partNumber,
        name: name,
        harga: harga,
        berat: berat,
        qty: qty ?? this.qty,
      );
}

/// Alamat penerima yang diingat antar-pesanan, supaya pembeli tak perlu
/// mengetik ulang nama/HP/alamat tiap belanja.
class SavedAddress {
  final String name;
  final String phone;
  final String address;
  final String postal;

  const SavedAddress({
    this.name = '',
    this.phone = '',
    this.address = '',
    this.postal = '',
  });

  factory SavedAddress.fromJson(Map<String, dynamic> j) => SavedAddress(
        name: '${j['name'] ?? ''}',
        phone: '${j['phone'] ?? ''}',
        address: '${j['address'] ?? ''}',
        postal: '${j['postal'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'address': address,
        'postal': postal,
      };
}

/// True bila string harga punya nilai > 0. "—" / "Rp 0" / "" → false.
bool hasPrice(String? harga) {
  if (harga == null || harga.isEmpty) return false;
  final digits = harga.replaceAll(RegExp(r'[^\d]'), '');
  return digits.isNotEmpty && (int.tryParse(digits) ?? 0) > 0;
}

/// True bila berat (gram) sudah ditetapkan (> 0).
bool hasWeight(int? berat) => berat != null && berat > 0;

/// Angka dari string harga tampilan: "Rp 600.000" → 600000.
int priceToNum(String? harga) {
  if (harga == null) return 0;
  final digits = harga.replaceAll(RegExp(r'[^\d]'), '');
  return int.tryParse(digits) ?? 0;
}

/// Keranjang global. Dengarkan lewat [ChangeNotifier] untuk lencana jumlah.
class CartStore extends ChangeNotifier {
  CartStore._();
  static final CartStore instance = CartStore._();

  /// Sisa versi global (sebelum dipisah per-akun) — dibuang saat load.
  static const _alamatKeyLama = 'maspart_alamat_v1';

  String _username = 'anon';
  List<CartItem> _items = [];
  bool _loaded = false;

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get count => _items.fold(0, (n, i) => n + i.qty);

  String get _key => 'maspart_cart_$_username';

  /// ⛔ WAJIB per-username, sama seperti [_key]. Kunci global membuat akun BARU
  /// di HP yang sama mewarisi nama, nomor HP, dan alamat lengkap milik akun
  /// sebelumnya — data pelanggan lain terpampang, dan barang berisiko dikirim
  /// ke penerima yang salah bila pembeli tak memeriksanya.
  String get _alamatKey => 'maspart_alamat_v1_$_username';

  /// Muat keranjang milik [username]. Panggil sekali setelah login / saat
  /// shell dibangun — mengganti user akan memuat ulang keranjangnya sendiri.
  Future<void> load(String username) async {
    final u = username.isEmpty ? 'anon' : username;
    if (_loaded && u == _username) return;
    _username = u;
    final prefs = await SharedPreferences.getInstance();
    _items = _decode(prefs.getString(_key));
    _loaded = true;
    notifyListeners();
  }

  List<CartItem> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => CartItem.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.partNumber.isNotEmpty)
          .toList();
    } catch (_) {
      // Keranjang rusak → mulai bersih daripada meledak di layar pembeli.
      return [];
    }
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      /* penyimpanan penuh/diblokir → keranjang tetap hidup di memori */
    }
  }

  /// Tambah part. Bila PN sudah ada, qty-nya ditambah.
  Future<void> add(CartItem item, {int qty = 1}) async {
    final i = _items.indexWhere((e) => e.partNumber == item.partNumber);
    if (i >= 0) {
      _items[i] = _items[i].copyWith(qty: _items[i].qty + qty);
    } else {
      _items.add(item.copyWith(qty: qty));
    }
    await _save();
  }

  /// Tambah BANYAK part sekaligus (Beli Lagi) — qty tiap item = `item.qty`.
  /// Aturannya sama dengan [add]: PN yang sudah ada di keranjang qty-nya
  /// DITAMBAH, bukan ditimpa. Disimpan sekali saja di akhir.
  Future<void> addMany(Iterable<CartItem> items) async {
    for (final item in items) {
      if (item.partNumber.isEmpty) continue;
      final qty = item.qty < 1 ? 1 : item.qty;
      final i = _items.indexWhere((e) => e.partNumber == item.partNumber);
      if (i >= 0) {
        _items[i] = _items[i].copyWith(qty: _items[i].qty + qty);
      } else {
        _items.add(item.copyWith(qty: qty));
      }
    }
    await _save();
  }

  Future<void> setQty(String pn, int qty) async {
    final i = _items.indexWhere((e) => e.partNumber == pn);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(qty: qty < 1 ? 1 : qty);
    await _save();
  }

  Future<void> remove(String pn) async {
    _items.removeWhere((e) => e.partNumber == pn);
    await _save();
  }

  /// Buang hanya PN tertentu — dipakai setelah checkout keranjang lintas
  /// gudang, di mana part gudang lain HARUS tetap tersimpan.
  Future<void> removeAll(Iterable<String> pns) async {
    final set = pns.toSet();
    _items.removeWhere((e) => set.contains(e.partNumber));
    await _save();
  }

  Future<void> clear() async {
    _items = [];
    await _save();
  }

  bool contains(String pn) => _items.any((e) => e.partNumber == pn);

  // ── Alamat penerima tersimpan ───────────────────────────────────────

  Future<SavedAddress> loadAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Buang sisa kunci global lama: isinya alamat milik akun yang kebetulan
      // checkout terakhir di HP ini. ⛔ JANGAN dimigrasikan ke kunci baru — itu
      // justru menyalinkan alamat orang lain ke akun yang login duluan.
      await prefs.remove(_alamatKeyLama);
      final raw = prefs.getString(_alamatKey);
      if (raw == null || raw.isEmpty) return const SavedAddress();
      return SavedAddress.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return const SavedAddress();
    }
  }

  Future<void> saveAddress(SavedAddress a) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_alamatKey, jsonEncode(a.toJson()));
    } catch (_) {
      /* abaikan — alamat cuma kenyamanan, bukan syarat checkout */
    }
  }
}
