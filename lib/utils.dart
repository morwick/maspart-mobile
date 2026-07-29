// lib/utils.dart — helper murni bersama (format, parsing, turunan model).

/// Bandingkan dua nomor versi "x.y.z" secara NUMERIK per segmen.
/// >0 bila [a] lebih baru dari [b], <0 bila lebih lama, 0 bila sama.
/// Segmen non-angka / panjang beda diperlakukan sebagai 0. Dipakai notifikasi
/// update (banding nama versi, bukan versionCode).
int compareVersion(String a, String b) {
  List<int> parse(String v) => v
      .trim()
      .split('.')
      .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
  final pa = parse(a);
  final pb = parse(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}

/// Model truk dari `file`: ambil teks setelah " - ". "Katalog - NX280" → "NX280".
String modelFromFile(String? file) {
  if (file == null || file.isEmpty) return '';
  final i = file.lastIndexOf(' - ');
  return i >= 0 ? file.substring(i + 3).trim() : file.trim();
}

/// Kategori model dari folder induk `path`.
String modelFromPath(String? path) {
  if (path == null || path.trim().isEmpty || path.trim() == '-') return '';
  final parts = path
      .replaceAll('\\', '/')
      .split('/')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length >= 2) return parts[parts.length - 2];
  return '';
}

/// Nilai model untuk filter: utamakan folder (`path`), fallback ke `file`.
String modelFilterValue(Map<String, dynamic> item) {
  final m = modelFromPath(item['path'] as String?);
  return m.isNotEmpty ? m : modelFromFile(item['file'] as String?);
}

/// Format Rupiah: 185000 → "Rp 185.000".
String formatRupiah(num? value) {
  final v = (value ?? 0).round();
  final s = v.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return 'Rp ${v < 0 ? '-' : ''}$buf';
}

/// Angka ribuan tanpa prefix: 2418 → "2.418".
String thousands(num? value) {
  final v = (value ?? 0).round();
  final s = v.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}$buf';
}

int asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

num? asNum(dynamic v) {
  if (v is num) return v;
  if (v is String) {
    final cleaned = v.replaceAll(RegExp(r'[^\d.\-]'), '');
    if (cleaned.isEmpty) return null;
    return num.tryParse(cleaned);
  }
  return null;
}

String stockLabel(int stok) {
  if (stok <= 0) return 'Habis';
  if (stok <= 5) return 'Menipis';
  return 'Tersedia';
}
