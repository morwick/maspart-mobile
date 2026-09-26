// lib/screens/login_screen.dart — panel merek grafit di atas (medan baut/mur 3D,
// widgets/login_backdrop.dart), form di bawahnya, footer menempel ke dasar
// layar. Paritas dengan web frontend/src/app/login/page.tsx.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';
import '../widgets/login_backdrop.dart';
import '../api_service.dart';
import '../auth_storage.dart';
import '../app/shell.dart';
import 'lengkapi_profil_screen.dart';

/// Hijau merek pada huruf "M" logo, dipaku (bukan token): di mode gelap brand700
/// dibalik jadi hijau terang.
const _brandGreen = Color(0xFF026A0E);

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

  /// OAuth Client ID Web dari /api/app/meta. Kosong = login Google belum
  /// diaktifkan di server → tombolnya tak ditampilkan (sama dengan web).
  String _googleClientId = '';
  bool _googleBusy = false;

  @override
  void initState() {
    super.initState();
    _restoreLast();
    ApiService.appMeta().then((meta) {
      if (mounted) setState(() => _googleClientId = meta.googleClientId);
    }).catchError((_) {});
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
      final res = await ApiService.loginFull(u, p);
      await AuthStorage.rememberUsername(u, _remember);
      if (!mounted) return;
      TextInput.finishAutofillContext(); // tawarkan simpan sandi ke pengelola HP
      _masukKe(res.user);
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

  /// Tujuan setelah login — padanan `landingPath` web: pembeli yang belum
  /// punya alamat utama → Lengkapi Profil; selain itu ke aplikasi.
  void _masukKe(UserOut user) {
    final lengkapi = user.role == 'pembeli' && user.profileComplete == false;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) =>
            lengkapi ? const LengkapiProfilScreen() : const AppShell()));
  }

  /// Masuk/daftar dengan akun Google. Akun baru otomatis jadi pembeli lalu
  /// diarahkan ke Lengkapi Profil (alur yang sama dengan web).
  Future<void> _masukGoogle() async {
    if (_loading || _googleBusy || _googleClientId.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _googleBusy = true;
      _error = null;
    });
    AuthStorage.persist = _remember;
    try {
      final g = GoogleSignIn(
          scopes: const ['email'], serverClientId: _googleClientId);
      // Keluar dulu supaya pemilih akun SELALU tampil — tanpa ini akun Google
      // terakhir dipakai diam-diam dan pembeli tak bisa ganti akun.
      try {
        await g.signOut();
      } catch (_) {}
      final akun = await g.signIn();
      if (akun == null) {
        // Dibatalkan pembeli.
        if (mounted) setState(() => _googleBusy = false);
        return;
      }
      final idToken = (await akun.authentication).idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const _GoogleGagal(
            'Google tidak memberi token. Pastikan aplikasi terdaftar di Google Cloud.');
      }
      final res = await ApiService.loginGoogle(idToken);
      if (!mounted) return;
      _masukKe(res.token.user);
    } on ApiException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _googleBusy = false;
        _error = e.message;
      });
    } on _GoogleGagal catch (e) {
      if (!mounted) return;
      setState(() {
        _googleBusy = false;
        _error = e.pesan;
      });
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _googleBusy = false;
        _error = 'Gagal masuk dengan Google: $e';
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
    // Panel gelap → ikon status bar terang.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ClipRect(
        child: Stack(children: [
          const Positioned.fill(child: LoginBackdrop()),
          Padding(
            padding: EdgeInsets.fromLTRB(24, top + 28, 24, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
                  child: Text('M', style: masMono(size: 16, weight: FontWeight.w700, color: _brandGreen)),
                ),
                const SizedBox(width: 10),
                const Text('MasPart',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: Colors.white)),
              ]),
              const SizedBox(height: 24),
              const Text('Satu tempat untuk\nsemua part.',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      height: 1.12,
                      letterSpacing: -0.65,
                      color: Colors.white)),
              const SizedBox(height: 8),
              Text('Sinotruk HOWO · mesin Weichai · alat berat Shantui',
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: Colors.white.withValues(alpha: 0.8))),
            ]),
          ),
        ]),
      ),
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
              Text(
                  _googleClientId.isEmpty
                      ? 'Gunakan akun MasPart yang diberikan admin.'
                      : 'Staf: gunakan akun MasPart dari admin. Pembeli: masuk atau daftar dengan akun Google.',
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

              if (_googleClientId.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Divider(color: m.ink200)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('atau', style: TextStyle(fontSize: 12, color: m.ink400)),
                  ),
                  Expanded(child: Divider(color: m.ink200)),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: (_loading || _googleBusy) ? null : _masukGoogle,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: m.paper,
                      side: BorderSide(color: m.ink300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _googleBusy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: m.brand600),
                          )
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('G',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800, color: m.info600)),
                            const SizedBox(width: 10),
                            Text('Masuk dengan Google',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600, color: m.ink800)),
                          ]),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Pembeli baru? Masuk dengan Google — akun dibuat otomatis, lalu isi alamat kirim.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: m.ink500)),
              ],

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

class _GoogleGagal implements Exception {
  final String pesan;
  const _GoogleGagal(this.pesan);
}
