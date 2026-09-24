// lib/screens/lengkapi_profil_screen.dart
// Langkah setelah daftar via Google: data diri + alamat kirim pertama (jadi
// alamat utama) — cerminan `frontend/src/app/daftar/lengkapi/page.tsx`.
// Berdiri sendiri (di luar AppShell) seperti di web. Boleh dilewati —
// checkout tetap menerima alamat ketikan.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/shell.dart';
import '../auth_storage.dart';
import '../theme/mas_theme.dart';
import '../widgets/alamat_form.dart';
import '../widgets/mas_ui.dart';
import 'login_screen.dart';

class LengkapiProfilScreen extends StatefulWidget {
  const LengkapiProfilScreen({super.key});

  @override
  State<LengkapiProfilScreen> createState() => _LengkapiProfilScreenState();
}

class _LengkapiProfilScreenState extends State<LengkapiProfilScreen> {
  BuyerProfile? _profil;
  final _nama = TextEditingController();
  final _telepon = TextEditingController();
  int _step = 1;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nama.dispose();
    _telepon.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await ApiService.buyerProfile();
      if (!mounted) return;
      // Alamat sudah lengkap → langsung belanja. Gudang acuan diturunkan dari
      // alamat itu, jadi tak ada lagi langkah "pilih lokasi".
      if (p.profileComplete) return _keToko();
      setState(() {
        _profil = p;
        _nama.text = p.nama;
        _telepon.text = p.telepon;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) return _keLogin();
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _keToko() => Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AppShell()));

  Future<void> _keLogin() async {
    await AuthStorage.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _lanjut() {
    if (_nama.text.trim().isEmpty) {
      setState(() => _error = 'Nama wajib diisi.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _step = 2;
    });
  }

  Future<void> _simpan(Alamat body) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final tel = _telepon.text.trim();
      await ApiService.updateBuyerProfile(
          nama: _nama.text.trim(), telepon: tel.isNotEmpty ? tel : body.telepon);
      await ApiService.createAlamat(Alamat(
        label: body.label,
        namaPenerima: body.namaPenerima,
        telepon: body.telepon,
        provinsi: body.provinsi,
        kota: body.kota,
        kecamatan: body.kecamatan,
        kodePos: body.kodePos,
        alamat: body.alamat,
        lat: body.lat,
        lng: body.lng,
        isDefault: true,
      ));
      if (mounted) _keToko();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) return _keLogin();
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Scaffold(
      backgroundColor: m.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: m.paper,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: m.ink150),
                boxShadow: m.shadow2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: m.brand600,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('M',
                          style: masMono(
                              size: 14,
                              weight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    Text('MasPart',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: m.ink900)),
                    const Spacer(),
                    Text('Langkah $_step dari 2',
                        style: TextStyle(fontSize: 12, color: m.ink400)),
                  ]),
                  const SizedBox(height: 16),
                  Text(
                    _step == 1
                        ? 'Selamat datang! Lengkapi data diri'
                        : 'Alamat pengiriman',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: m.ink900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _step == 1
                        ? 'Akun kamu sudah dibuat dari akun Google. Data ini dipakai untuk pengiriman dan konfirmasi pesanan.'
                        : 'Alamat ini jadi alamat utama — otomatis terisi saat checkout dan menentukan ongkir. Bisa ditambah/diubah di menu Profil.',
                    style: TextStyle(fontSize: 13, color: m.ink500),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: m.danger50,
                        borderRadius: BorderRadius.circular(MasRadii.card),
                        border: Border.all(color: m.dangerBorder),
                      ),
                      child: Text(_error!,
                          style:
                              TextStyle(fontSize: 12.5, color: m.danger600)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_step == 1)
                    ..._langkah1(m)
                  else ...[
                    AlamatForm(
                      prefillNama: _nama.text.trim(),
                      prefillTelepon: _telepon.text.trim(),
                      forceDefault: true,
                      submitting: _saving,
                      submitLabel: 'Simpan & lanjut belanja',
                      onSubmit: _simpan,
                      onCancel: () => setState(() => _step = 1),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _saving ? null : _keToko,
                      child: const Text('Lewati untuk sekarang'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _langkah1(MasColors m) => [
        if ((_profil?.email ?? '').isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: m.ink50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: m.ink200),
            ),
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Masuk sebagai '),
                TextSpan(
                    text: _profil!.email,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' · username '),
                TextSpan(
                    text: _profil!.username,
                    style: masMono(size: 12.5, color: m.ink700)),
              ]),
              style: TextStyle(fontSize: 12.5, color: m.ink600),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text('Nama lengkap / nama perusahaan',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: m.ink700)),
        const SizedBox(height: 6),
        MasInput(
          controller: _nama,
          hint: 'Nama lengkap',
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        Text('No. HP / WhatsApp',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: m.ink700)),
        const SizedBox(height: 6),
        MasInput(
          controller: _telepon,
          hint: '0812xxxxxxx',
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 18),
        MasButton(label: 'Lanjut isi alamat', expand: true, onTap: _lanjut),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _keToko,
          child: const Text('Lewati untuk sekarang'),
        ),
      ];
}
