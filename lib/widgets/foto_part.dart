// lib/widgets/foto_part.dart
// Gambar kecil part di baris Keranjang / Checkout (ala Shopee) — cerminan
// `frontend/src/app/keranjang/FotoPart.tsx`. Tanpa foto atau gagal dimuat →
// kotak berikon gir, tinggi baris tetap sama.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api_service.dart';
import '../theme/mas_theme.dart';

class FotoPart extends StatelessWidget {
  /// Path/URL foto mentah dari server (`foto` /cart/gudang). null/'' = ikon gir.
  final String? foto;
  final double ukuran;

  const FotoPart({super.key, this.foto, this.ukuran = 64});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final f = foto;
    Widget kosong() => Container(
          color: m.ink50,
          alignment: Alignment.center,
          child: Icon(Icons.settings_outlined,
              size: ukuran * 0.36, color: m.ink300),
        );
    return Container(
      width: ukuran,
      height: ukuran,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: m.ink150),
      ),
      clipBehavior: Clip.antiAlias,
      child: f != null && f.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.all(4),
              child: CachedNetworkImage(
                imageUrl: ApiService.partImageUrl(f),
                fit: BoxFit.contain,
                placeholder: (_, _) => Container(color: m.ink50),
                errorWidget: (_, _, _) => kosong(),
              ),
            )
          : kosong(),
    );
  }
}
