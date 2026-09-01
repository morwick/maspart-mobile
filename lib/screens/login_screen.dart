// lib/screens/login_screen.dart — mengikuti desain "Login Redesign.dc" (frame 1b,
// Phone 390×844): pita merek hijau di atas, form di bawahnya, footer menempel
// ke dasar layar. Paritas dengan web frontend/src/app/login/page.tsx.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';
import '../api_service.dart';
import '../auth_storage.dart';
import '../app/shell.dart';

/// Hijau panel merek dipaku (bukan token): di mode gelap brand700 dibalik jadi
/// hijau terang dan teks putih di atasnya hilang.
const _panelGreen = Color(0xFF026A0E);
const _panelBlob = Color(0xFF028912);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _remember = true;
  String? _error;

  /// Versi terpasang untuk footer. Dulu tertulis mati "v4.0" — angka yang tak
  /// pernah cocok dengan versi APK mana pun, jadi laporan user tak bisa
  /// dipakai untuk menentukan versi mereka.
  String _version = '';

  @override
  void initState() {
    super.initState();
    _restoreLast();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = 'v${i.version}');
    }).catchError((_) {});
  }

  /// Isi awal form dari login terakhir (username saja — password tak pernah
  /// disimpan).
  Future<void> _restoreLast() async {
    final (remember, username) = await AuthStorage.lastLogin();
    if (!mounted) return;
    setState(() {
      _remember = remember;
      if (username.isNotEmpty && _userCtrl.text.isEmpty) _userCtrl.text = username;
    });
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    final u = _userCtrl.text.trim();
    final p = _passCtrl.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Username dan password wajib diisi.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    // Centang "Ingat saya" menentukan apakah token ditulis ke disk atau hanya
    // hidup selama proses aplikasi — DIPASANG SEBELUM login karena
    // ApiService.login() yang menyimpan tokennya.
    AuthStorage.persist = _remember;
    try {
      final token = await ApiService.login(u, p);
      await AuthStorage.saveToken(token);
      await AuthStorage.rememberUsername(u, _remember);
      if (!mounted) return;
      TextInput.finishAutofillContext(); // tawarkan simpan sandi ke pengelola HP
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AppShell()));
    } on ApiException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _loading = false;
        _error = e.statusCode == 401 ? 'Username atau password salah. Coba lagi.' : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _loading = false;
        _error = 'Gagal terhubung. Periksa koneksi Anda.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Scaffold(
      backgroundColor: m.canvas,
      // resizeToAvoidBottomInset default: form ikut naik saat keyboard muncul,
      // dan LayoutBuilder di bawah membuat sisanya bisa digulir.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hero(context),
          Expanded(child: _form(context)),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return ClipRect(
      child: Stack(children: [
        Positioned(
          right: -90,
          top: -120,
          child: Container(
            width: 300,
            height: 300,
            decoration: const BoxDecoration(color: _panelBlob, shape: BoxShape.circle),
          ),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(24, top + 28, 24, 30),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
                child: Text('M', style: masMono(size: 15, weight: FontWeight.w700, color: _panelGreen)),
              ),
              const SizedBox(width: 10),
              const Text('MasPart',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white)),
            ]),
            const SizedBox(height: 24),
            const Text('Satu tempat untuk\nsemua part.',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                    letterSpacing: -0.5,
                    color: Colors.white)),
            const SizedBox(height: 8),
            Text('Cari part, cek stok & harga, pesan dan lacak sampai cabang.',
                style: TextStyle(fontSize: 13.5, height: 1.5, color: Colors.white.withValues(alpha: 0.8))),
          ]),
        ),
      ]),
    );
  }

  Widget _form(BuildContext context) {
    final m = context.mas;
    final bottom = MediaQuery.of(context).padding.bottom;
    return LayoutBuilder(builder: (context, c) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 28, 24, 22 + bottom),
        child: ConstrainedBox(
          // Tinggi minimum = sisa layar dikurangi padding, supaya footer bisa
          // didorong ke dasar (Spacer) tapi tetap bisa digulir saat keyboard
          // menutupi form. clamp: saat keyboard terbuka di layar pendek, sisa
          // ruang bisa lebih kecil dari padding → minHeight negatif = assert.
          constraints: BoxConstraints(
            minHeight: (c.maxHeight - 50 - bottom).clamp(0.0, double.infinity),
          ),
          child: IntrinsicHeight(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Masuk',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: m.ink900)),
              const SizedBox(height: 6),
              Text('Gunakan akun MasPart yang diberikan admin.',
                  style: TextStyle(fontSize: 13.5, color: m.ink500)),
              const SizedBox(height: 24),

              AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _label(context, 'Username'),
                  const SizedBox(height: 7),
                  MasInput(
                    controller: _userCtrl,
                    hint: 'andi.gudang',
                    action: TextInputAction.next,
                    height: 50,
                    radius: 10,
                    fontSize: 16,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.username],
                    keyboardType: TextInputType.name,
                  ),
                  const SizedBox(height: 16),

                  _label(context, 'Password'),
                  const SizedBox(height: 7),
                  MasInput(
                    controller: _passCtrl,
                    hint: '••••••••',
                    obscure: _obscure,
                    action: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    height: 50,
                    radius: 10,
                    fontSize: 16,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.password],
                    suffix: _pwToggle(context),
                  ),
                ]),
              ),
              const SizedBox(height: 4),

              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _remember = !_remember);
                },
                child: SizedBox(
                  height: 44, // target sentuh nyaman
                  child: Row(children: [
                    _check(context, _remember),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _remember
                            ? 'Ingat saya di device ini'
                            : 'Jangan ingat — keluar saat aplikasi ditutup',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: m.ink700),
                      ),
                    ),
                  ]),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 4),
                _errorBanner(context, _error!),
              ],
              const SizedBox(height: 16),

              MasButton(label: 'Masuk', onTap: _submit, expand: true, height: 52, loading: _loading),

              const Spacer(),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Lupa password? Hubungi admin.', style: TextStyle(fontSize: 12, color: m.ink400)),
                Text(_version, style: masMono(size: 12, color: m.ink400)),
              ]),
            ]),
          ),
        ),
      );
    });
  }

  Widget _pwToggle(BuildContext context) {
    final m = context.mas;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _obscure = !_obscure),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Text(_obscure ? 'Lihat' : 'Sembunyikan',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: m.ink600)),
      ),
    );
  }

  Widget _label(BuildContext context, String t) => Text(t,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.mas.ink700));

  Widget _check(BuildContext context, bool value) {
    final m = context.mas;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: value ? m.brand600 : m.paper,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: value ? m.brand600 : m.ink300, width: 1.5),
      ),
      child: value ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
    );
  }

  Widget _errorBanner(BuildContext context, String msg) {
    final m = context.mas;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: m.danger50,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.dangerBorder),
      ),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, size: 18, color: m.danger600),
        const SizedBox(width: 9),
        Expanded(
            child: Text(msg,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: m.danger600))),
      ]),
    );
  }
}
