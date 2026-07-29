// lib/screens/login_screen.dart — mengikuti desain: hero hijau + kartu login mengambang.
import 'package:flutter/material.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';
import '../api_service.dart';
import '../auth_storage.dart';
import '../app/shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final bool _obscure = true;
  bool _loading = false;
  bool _remember = true;
  String? _error;

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
    try {
      final token = await ApiService.login(u, p);
      await AuthStorage.saveToken(token);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AppShell()));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.statusCode == 401 ? 'Username atau password salah. Coba lagi.' : e.message;
      });
    } catch (_) {
      if (!mounted) return;
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
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hero(context),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _card(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 24, 20, 52),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.7, -1), end: Alignment(0.7, 1),
          colors: [Color(0xFF1EA83A), Color(0xFF028912), Color(0xFF026A0E)],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34, height: 34, alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
            child: Text('M', style: masMono(size: 16, weight: FontWeight.w700, color: const Color(0xFF026A0E))),
          ),
          const SizedBox(width: 10),
          const Text('MasPart', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: Colors.white)),
        ]),
        const SizedBox(height: 22),
        const Text('Cari part dengan\ncepat & akurat.',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, height: 1.15, letterSpacing: -0.4, color: Colors.white)),
        const SizedBox(height: 12),
        Text(
          'Database part Shantui & Sinotruk — pencarian fuzzy, by foto, perbandingan harga, dan populasi unit dalam satu tempat.',
          style: TextStyle(fontSize: 13, height: 1.6, color: Colors.white.withValues(alpha: 0.85)),
        ),
        const SizedBox(height: 20),
        Row(children: [
          _stat('2.418', 'part terindeks'),
          const SizedBox(width: 28),
          _stat('42', 'unit aktif'),
          const SizedBox(width: 28),
          _stat('17', 'cabang'),
        ]),
      ]),
    );
  }

  Widget _stat(String value, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: masMono(size: 20, weight: FontWeight.w700, color: Colors.white)),
          Text(label, style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.8))),
        ],
      );

  Widget _card(BuildContext context) {
    final m = context.mas;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.sheet),
        border: Border.all(color: m.ink150),
        boxShadow: m.shadow3,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('LOGIN',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: m.ink400, letterSpacing: 1.2)),
        const SizedBox(height: 4),
        Text('Selamat datang kembali',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: m.ink900, letterSpacing: -0.2)),
        const SizedBox(height: 4),
        Text('Masuk dengan akun MasPart-mu.', style: TextStyle(fontSize: 13, color: m.ink500)),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _errorBanner(context, _error!),
        ],
        const SizedBox(height: 20),
        _label(context, 'Username'),
        const SizedBox(height: 6),
        MasInput(controller: _userCtrl, hint: 'andi.gudang', action: TextInputAction.next),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _label(context, 'Password'),
          Text('Lupa password?', style: TextStyle(fontSize: 12, color: m.brand700)),
        ]),
        const SizedBox(height: 6),
        MasInput(
          controller: _passCtrl,
          hint: '••••••••',
          obscure: _obscure,
          action: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          prefix: null,
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: () => setState(() => _remember = !_remember),
          child: Row(children: [
            _check(context, _remember),
            const SizedBox(width: 8),
            Text('Ingat saya di device ini', style: TextStyle(fontSize: 13, color: m.ink700)),
          ]),
        ),
        const SizedBox(height: 16),
        MasButton(label: 'Masuk', onTap: _submit, expand: true, height: 48, loading: _loading),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Divider(color: m.ink150, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('ATAU', style: TextStyle(fontSize: 10.5, color: m.ink400, letterSpacing: 1.2)),
          ),
          Expanded(child: Divider(color: m.ink150, height: 1)),
        ]),
        const SizedBox(height: 16),
        MasButton(
          label: 'SSO via Supabase',
          primary: false,
          height: 48,
          expand: true,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SSO belum tersedia di aplikasi mobile.')),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text('v4.0 · MasPart · session timeout 12 jam',
              style: TextStyle(fontSize: 11, color: m.ink400)),
        ),
      ]),
    );
  }

  Widget _label(BuildContext context, String t) => Text(t,
      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: context.mas.ink700));

  Widget _check(BuildContext context, bool value) {
    final m = context.mas;
    return Container(
      width: 18, height: 18,
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
        borderRadius: BorderRadius.circular(MasRadii.input),
        border: Border.all(color: m.dangerBorder),
      ),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, size: 18, color: m.danger600),
        const SizedBox(width: 9),
        Expanded(child: Text(msg, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: m.danger600))),
      ]),
    );
  }
}
