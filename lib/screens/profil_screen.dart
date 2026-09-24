// lib/screens/profil_screen.dart
// Profil Saya (pembeli) — tata letak ala halaman "Saya" e-commerce: kartu
// profil + ringkasan poin/voucher/pesanan, pintasan status pesanan, data akun,
// buku alamat (tambah / ubah / hapus / jadikan utama) dan menu cepat —
// cerminan `frontend/src/app/profil/page.tsx`.
// Alamat utama mengisi checkout & menentukan gudang terdekat + ongkir.

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../theme/mas_theme.dart';
import '../widgets/alamat_form.dart';
import '../widgets/mas_ui.dart';

class ProfilScreen extends StatefulWidget {
  const ProfilScreen({super.key});

  @override
  State<ProfilScreen> createState() => _ProfilScreenState();
}

/// Form alamat yang terbuka: null = tidak ada, 0 = alamat baru, >0 = id diedit.
class _ProfilScreenState extends State<ProfilScreen> {
  BuyerProfile? _profil;
  List<Alamat> _alamat = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _msg;

  bool _editAkun = false;
  final _nama = TextEditingController();
  final _telepon = TextEditingController();
  int? _form;

  // Ringkasan pelengkap — null = tak tersedia (fitur mati / gagal) → disembunyikan.
  int? _poin;
  int? _voucher;
  List<OrderSummary>? _orders;
  int? _returAktif;
  static const _returAkhir = {'selesai', 'ditolak', 'dibatalkan'};

  @override
  void initState() {
    super.initState();
    _load();
    _loadRingkas();
  }

  /// Poin/voucher/pesanan/retur dimuat terpisah: gagal satu tak menggagalkan
  /// halaman, cukup selnya yang tak tampil.
  Future<void> _loadRingkas() async {
    Future<T?> aman<T>(Future<T> f) async {
      try {
        return await f;
      } catch (_) {
        return null;
      }
    }

    final hasil = await Future.wait<Object?>([
      aman(ApiService.poin()),
      aman(ApiService.vouchers()),
      aman(ApiService.myOrders()),
      aman(ApiService.getMyReturns()),
    ]);
    if (!mounted) return;
    final po = hasil[0] as PoinSaldo?;
    final vo = hasil[1]
        as ({bool aktif, List<Voucher> tersedia, List<Voucher> saya})?;
    final re = hasil[3] as ({bool aktif, List<ReturRingkas> returns})?;
    setState(() {
      _poin = (po != null && po.aktif) ? po.saldo : null;
      _voucher = (vo != null && vo.aktif)
          ? vo.saya.where((v) => v.usedOrderCode.isEmpty && v.berlaku).length
          : null;
      _orders = hasil[2] as List<OrderSummary>?;
      _returAktif = (re != null && re.aktif)
          ? re.returns.where((r) => !_returAkhir.contains(r.status)).length
          : null;
    });
  }

  Future<void> _refresh() => Future.wait([_load(), _loadRingkas()]);

  @override
  void dispose() {
    _nama.dispose();
    _telepon.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final hasil = await Future.wait([
        ApiService.buyerProfile(),
        ApiService.listAlamat(),
      ]);
      if (!mounted) return;
      final p = hasil[0] as BuyerProfile;
      setState(() {
        _profil = p;
        _alamat = hasil[1] as List<Alamat>;
        if (!_editAkun) {
          _nama.text = p.nama;
          _telepon.text = p.telepon;
        }
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Jalankan aksi dengan status sibuk + pesan hasil, lalu muat ulang.
  Future<void> _aksi(Future<void> Function() kerja, String sukses,
      {bool muatUlang = true}) async {
    setState(() {
      _busy = true;
      _error = null;
      _msg = null;
    });
    try {
      await kerja();
      if (!mounted) return;
      setState(() => _msg = sukses);
      if (muatUlang) await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _simpanAkun() => _aksi(() async {
        final p = await ApiService.updateBuyerProfile(
            nama: _nama.text.trim(), telepon: _telepon.text.trim());
        if (mounted) {
          setState(() {
            _profil = p;
            _editAkun = false;
          });
        }
      }, 'Data akun tersimpan.', muatUlang: false);

  Future<void> _simpanAlamat(Alamat body) => _aksi(() async {
        if (_form == 0) {
          await ApiService.createAlamat(body);
        } else if (_form != null) {
          await ApiService.updateAlamat(_form!, body);
        }
        if (mounted) setState(() => _form = null);
      }, 'Alamat tersimpan.');

  Future<void> _hapus(Alamat a) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus alamat?'),
        content: Text('Hapus alamat "${a.label}" (${a.namaPenerima})?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ya != true) return;
    await _aksi(() => ApiService.deleteAlamat(a.id), 'Alamat dihapus.');
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final nav = AppNav.of(context);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_error != null) ...[
            _banner(m, _error!, galat: true),
            const SizedBox(height: 12),
          ],
          if (_msg != null && _error == null) ...[
            _banner(m, _msg!),
            const SizedBox(height: 12),
          ],
          if (_loading) ...[
            const MasSkeleton(height: 190),
            const SizedBox(height: 14),
            const MasSkeleton(height: 110),
          ] else ...[
            _kartuProfil(m, nav),
            const SizedBox(height: 14),
            _kartuPesanan(m, nav),
            const SizedBox(height: 14),
            _kartuAkun(m),
            const SizedBox(height: 14),
            _kartuAlamat(m),
            const SizedBox(height: 14),
            _menuCepat(m, nav),
          ],
        ],
      ),
    );
  }

  Widget _kartuAkun(MasColors m) {
    final p = _profil;
    return MasCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: _judul(m, 'Data Akun',
                'Kelola informasi akun untuk melengkapi pesananmu'),
          ),
          if (!_editAkun)
            _tautan(m, 'Ubah', () => setState(() => _editAkun = true)),
        ]),
        const SizedBox(height: 12),
        if (_editAkun) ...[
          _label(m, 'Nama lengkap / perusahaan'),
          MasInput(
            controller: _nama,
            hint: 'Nama lengkap',
            textCapitalization: TextCapitalization.words,
            enabled: !_busy,
          ),
          const SizedBox(height: 10),
          _label(m, 'No. HP / WhatsApp'),
          MasInput(
            controller: _telepon,
            hint: '0812xxxxxxx',
            keyboardType: TextInputType.phone,
            enabled: !_busy,
          ),
          const SizedBox(height: 12),
          Row(children: [
            MasButton(
              label: _busy ? 'Menyimpan…' : 'Simpan',
              height: 38,
              loading: _busy,
              onTap: _busy ? null : _simpanAkun,
            ),
            const SizedBox(width: 8),
            MasButton(
              label: 'Batal',
              primary: false,
              height: 38,
              onTap: _busy
                  ? null
                  : () => setState(() {
                        _editAkun = false;
                        _nama.text = p?.nama ?? '';
                        _telepon.text = p?.telepon ?? '';
                      }),
            ),
          ]),
        ] else ...[
          _baris(m, 'Nama', p?.nama ?? '', kosong: 'belum diisi'),
          _baris(m, 'Username', p?.username ?? '', mono: true),
          _baris(m, 'Email', p?.email ?? '', kosong: '—'),
          _baris(m, 'No. HP', p?.telepon ?? '', kosong: 'belum diisi'),
          _baris(
              m,
              'Masuk dengan',
              p?.authProvider == 'google'
                  ? 'Akun Google'
                  : 'Username & password'),
          // Bukan pilihan lagi: gudang acuan ditentukan dari alamat utama
          // (gudang terdekat). Ubah alamatnya, gudangnya ikut.
          _baris(m, 'Gudang terdekat', p?.gudangLabel ?? '',
              kosong: 'mengikuti alamat utama',
              catatan:
                  'Dipilih otomatis dari alamat utama — menentukan stok & ongkir'),
        ],
      ]),
    );
  }

  Widget _kartuAlamat(MasColors m) {
    Alamat? editing;
    if (_form != null && _form! > 0) {
      for (final a in _alamat) {
        if (a.id == _form) editing = a;
      }
    }
    return MasCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: _judul(
                m,
                'Alamat Saya',
                _alamat.any((a) => a.isDefault)
                    ? 'Alamat utama dipakai otomatis saat checkout'
                    : 'Tambahkan alamat supaya ongkir langsung terhitung'),
          ),
          if (_form == null)
            MasButton(
              label: 'Tambah',
              icon: Icons.add,
              height: 32,
              onTap: _busy ? null : () => setState(() => _form = 0),
            ),
        ]),
        const SizedBox(height: 12),
        if (_form != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: m.ink50,
              borderRadius: BorderRadius.circular(MasRadii.card),
              border: Border.all(color: m.ink200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_form == 0 ? 'Alamat baru' : 'Ubah alamat',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: m.ink900)),
                const SizedBox(height: 12),
                AlamatForm(
                  key: ValueKey(_form),
                  initial: editing,
                  prefillNama: _profil?.nama ?? '',
                  prefillTelepon: _profil?.telepon ?? '',
                  submitting: _busy,
                  onSubmit: _simpanAlamat,
                  onCancel: () => setState(() => _form = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_alamat.isEmpty && _form == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: m.ink100,
                child: Icon(Icons.location_on_outlined, color: m.ink400),
              ),
              const SizedBox(height: 8),
              Text('Belum ada alamat',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: m.ink800)),
              const SizedBox(height: 2),
              Text(
                'Tambahkan supaya checkout terisi otomatis dan ongkir langsung terhitung.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: m.ink500),
              ),
            ]),
          )
        else
          // Alamat utama selalu paling atas.
          for (final (i, a) in ([..._alamat]
                ..sort((x, y) =>
                    (y.isDefault ? 1 : 0) - (x.isDefault ? 1 : 0)))
              .indexed) ...[
            if (i > 0) Divider(height: 1, color: m.ink150),
            _kartuSatuAlamat(m, a),
          ],
      ]),
    );
  }

  Widget _kartuSatuAlamat(MasColors m, Alamat a) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: a.isDefault ? m.brand50 : m.ink100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.location_on_outlined,
                size: 18, color: a.isDefault ? m.brand600 : m.ink500),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: a.namaPenerima,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: m.ink900)),
                  TextSpan(
                      text: '  |  ${a.telepon}',
                      style: TextStyle(color: m.ink600)),
                ]),
                style: const TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 2),
              Text(a.alamat, style: TextStyle(fontSize: 13, color: m.ink700)),
              Text('${a.wilayah} ${a.kodePos}'.trim(),
                  style: TextStyle(fontSize: 12.5, color: m.ink500)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                MasPill(label: a.label, height: 20),
                if (a.isDefault)
                  const MasPill(
                      label: 'Utama', tone: MasPillTone.brand, height: 20),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                _tautan(m, 'Ubah',
                    _busy ? null : () => setState(() => _form = a.id)),
                const SizedBox(width: 12),
                _tautan(m, 'Hapus', _busy ? null : () => _hapus(a),
                    bahaya: true),
                const Spacer(),
                if (!a.isDefault)
                  MasButton(
                    label: 'Jadikan Utama',
                    primary: false,
                    height: 30,
                    onTap: _busy
                        ? null
                        : () => _aksi(() => ApiService.setAlamatDefault(a.id),
                            'Alamat utama diperbarui.'),
                  ),
              ]),
            ]),
          ),
        ]),
      );

  // ── Kartu profil: pita hijau + avatar inisial + chip + statistik ──
  Widget _kartuProfil(MasColors m, AppNav nav) {
    final p = _profil;
    final nama =
        (p?.nama.isNotEmpty ?? false) ? p!.nama : (p?.username ?? '');
    final stat = <(String, String, MasScreen)>[
      if (_poin != null) (_rb(_poin!), 'Poin MasPart', MasScreen.poin),
      if (_voucher != null) ('$_voucher', 'Voucher Saya', MasScreen.voucher),
      if (_orders != null)
        ('${_aktifCount()}', 'Pesanan aktif', MasScreen.pesanan),
    ];
    return MasCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MasRadii.card),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 100,
            child: Stack(children: [
              Container(
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [m.brand700, m.brand500]),
                ),
              ),
              Positioned(
                left: 16,
                top: 26,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration:
                      BoxDecoration(color: m.paper, shape: BoxShape.circle),
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: m.brand600,
                    child: Text(_inisial(p?.nama ?? '', p?.username ?? ''),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              if (!_editAkun)
                Positioned(
                  right: 10,
                  top: 70,
                  child: _tautan(
                      m, 'Ubah Profil', () => setState(() => _editAkun = true)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nama,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: m.ink900)),
              const SizedBox(height: 2),
              Text('@${p?.username ?? ''}',
                  style: masMono(size: 12, color: m.ink500)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                MasPill(
                  label: p?.authProvider == 'google'
                      ? 'Akun Google'
                      : 'Username & password',
                  tone: p?.authProvider == 'google'
                      ? MasPillTone.info
                      : MasPillTone.neutral,
                ),
                if ((p?.gudangLabel ?? '').isNotEmpty)
                  MasPill(
                      label: 'Gudang ${p!.gudangLabel}',
                      tone: MasPillTone.brand)
                else
                  const MasPill(
                      label: 'Belum ada alamat utama', tone: MasPillTone.warn),
              ]),
            ]),
          ),
          if (stat.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: m.ink150))),
              child: IntrinsicHeight(
                child: Row(children: [
                  for (final (i, s) in stat.indexed) ...[
                    if (i > 0) VerticalDivider(width: 1, color: m.ink150),
                    Expanded(
                      child: InkWell(
                        onTap: () => nav.go(s.$3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(children: [
                            Text(s.$1,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: m.ink900)),
                            const SizedBox(height: 2),
                            Text(s.$2,
                                style: TextStyle(
                                    fontSize: 11.5, color: m.ink500)),
                          ]),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  int _aktifCount() => (_orders ?? const <OrderSummary>[])
      .where((o) => const {
            'menunggu_pembayaran',
            'menunggu_verifikasi',
            'diproses',
            'dikirim',
          }.contains(o.status))
      .length;

  // ── Pesanan Saya: pintasan status ala Shopee ──
  Widget _kartuPesanan(MasColors m, AppNav nav) {
    final o = _orders ?? const <OrderSummary>[];
    int n(bool Function(OrderSummary) f) => o.where(f).length;
    void tab(String t) => nav.go(MasScreen.pesanan, part: {'tab': t});
    final item = <(String, IconData, int?, VoidCallback)>[
      (
        'Belum Bayar',
        Icons.account_balance_wallet_outlined,
        n((x) =>
            x.status == 'menunggu_pembayaran' ||
            x.status == 'menunggu_verifikasi'),
        () => tab('belum'),
      ),
      (
        'Diproses',
        Icons.inventory_2_outlined,
        n((x) => x.status == 'diproses'),
        () => tab('diproses'),
      ),
      (
        'Dikirim',
        Icons.local_shipping_outlined,
        n((x) => x.status == 'dikirim'),
        () => tab('dikirim'),
      ),
      (
        'Beri Nilai',
        Icons.star_border_rounded,
        n((x) => x.status == 'selesai' && x.bisaNilai && !x.sudahDinilai),
        () => tab('selesai'),
      ),
      (
        'Return',
        Icons.assignment_return_outlined,
        _returAktif,
        () => nav.go(MasScreen.returSaya),
      ),
    ];
    return MasCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _judul(m, 'Pesanan Saya', null)),
          _tautan(m, 'Lihat riwayat ›', () => nav.go(MasScreen.pesanan)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (final it in item)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: it.$4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: [
                    Badge(
                      isLabelVisible: (it.$3 ?? 0) > 0,
                      label: Text((it.$3 ?? 0) > 99 ? '99+' : '${it.$3}'),
                      backgroundColor: m.danger600,
                      child: Icon(it.$2, size: 26, color: m.ink700),
                    ),
                    const SizedBox(height: 6),
                    Text(it.$1,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: m.ink700)),
                  ]),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  // ── Menu cepat + Keluar ──
  Widget _menuCepat(MasColors m, AppNav nav) {
    Widget baris(IconData ik, String teks, VoidCallback onTap,
            {String? ket}) =>
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(children: [
              Icon(ik, size: 20, color: m.ink500),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(teks,
                      style: TextStyle(fontSize: 14, color: m.ink800))),
              if (ket != null)
                Text(ket, style: TextStyle(fontSize: 12.5, color: m.ink500)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: m.ink400),
            ]),
          ),
        );
    return MasCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        // Beli Lagi (pola Tokopedia) — riwayat barang yang pernah dibeli.
        if (nav.isBuyer) ...[
          baris(Icons.replay_rounded, 'Beli Lagi',
              () => nav.go(MasScreen.beliLagi),
              ket: 'Pesan ulang'),
          Divider(height: 1, color: m.ink150),
        ],
        baris(Icons.confirmation_number_outlined, 'Voucher Saya',
            () => nav.go(MasScreen.voucher),
            ket: (_voucher ?? 0) > 0 ? '$_voucher siap pakai' : null),
        Divider(height: 1, color: m.ink150),
        baris(Icons.monetization_on_outlined, 'Poin MasPart',
            () => nav.go(MasScreen.poin),
            ket: _poin != null ? '${_rb(_poin!)} poin' : null),
        Divider(height: 1, color: m.ink150),
        baris(Icons.assignment_return_outlined, 'Return Saya',
            () => nav.go(MasScreen.returSaya)),
        Divider(height: 1, color: m.ink150),
        baris(Icons.chat_bubble_outline_rounded, 'Chat',
            () => nav.go(MasScreen.chat)),
        Divider(height: 1, color: m.ink150),
        InkWell(
          onTap: nav.logout,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.logout_rounded, size: 18, color: m.danger600),
              const SizedBox(width: 8),
              Text('Keluar',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: m.danger600)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _judul(MasColors m, String t, String? sub) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: m.ink900)),
        if (sub != null)
          Text(sub, style: TextStyle(fontSize: 12, color: m.ink500)),
      ]);

  Widget _tautan(MasColors m, String t, VoidCallback? onTap,
          {bool bahaya = false}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(t,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: onTap == null
                      ? m.ink400
                      : (bahaya ? m.danger600 : m.brand600))),
        ),
      );

  static String _inisial(String nama, String username) {
    final kata = (nama.isNotEmpty ? nama : username)
        .trim()
        .split(RegExp(r'\s+'))
        .where((k) => k.isNotEmpty)
        .toList();
    if (kata.isEmpty) return '?';
    final s = kata.length >= 2
        ? kata[0][0] + kata[1][0]
        : kata[0].substring(0, kata[0].length < 2 ? kata[0].length : 2);
    return s.toUpperCase();
  }

  /// 1234 → "1.234" (pemisah ribuan ala Indonesia).
  static String _rb(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

  Widget _label(MasColors m, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: m.ink700)),
      );

  Widget _baris(MasColors m, String k, String v,
      {String kosong = '—', bool mono = false, String? catatan}) {
    final isi = v.isEmpty ? kosong : v;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(fontSize: 11.5, color: m.ink500)),
        const SizedBox(height: 1),
        Text(isi,
            style: mono && v.isNotEmpty
                ? masMono(size: 13.5, color: m.ink900)
                : TextStyle(
                    fontSize: 13.5, color: v.isEmpty ? m.ink400 : m.ink900)),
        if (catatan != null)
          Text(catatan, style: TextStyle(fontSize: 11, color: m.ink500)),
      ]),
    );
  }

  Widget _banner(MasColors m, String t, {bool galat = false}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: galat ? m.danger50 : m.brand50,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border.all(color: galat ? m.dangerBorder : m.brand100),
        ),
        child: Text(t,
            style: TextStyle(
                fontSize: 12.5, color: galat ? m.danger600 : m.brand700)),
      );
}
