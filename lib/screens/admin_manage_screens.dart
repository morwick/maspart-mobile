// lib/screens/admin_manage_screens.dart
// Layar ADMIN — semuanya mengambil data ASLI dari API (tidak ada contoh statis):
//   1. UsersScreen       — kelola akun & peran
//   2. MenuControlScreen — izin menu/kolom/harga + pembatasan sesi
//   3. MonitoringScreen  — online/offline, sinyal akun dipakai ramai, riwayat login
//   4. UploadScreen      — unggah dataset (stok/harga/populasi) & katalog
//   5. GudangScreen      — koordinat, kode pos asal, PIC, boleh-kirim
//   6. FotoPartScreen    — foto part manual per PN
//   7. ImageIndexScreen  — galeri cari-by-foto & Catalog BOM
//
// Menggantikan layar contoh berdata hardcoded di `admin_screens.dart`.
// Perilaku mengikuti halaman web padanannya di `frontend/src/app/admin/*`.

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../order_ui.dart';
import '../theme/mas_theme.dart';
import '../utils.dart';
import '../widgets/mas_ui.dart';

// ══════════════════════════════════════════════════════════════════════
// Helper bersama
// ══════════════════════════════════════════════════════════════════════

/// Kotak error merah — muara semua `ApiException.message`. Error TIDAK PERNAH
/// ditelan diam-diam: admin harus tahu kenapa perubahannya tidak tersimpan.
class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: m.danger50,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.dangerBorder),
      ),
      child: Text(message,
          style: TextStyle(fontSize: 12.5, color: m.danger600, height: 1.45)),
    );
  }
}

/// Kotak peringatan kuning — hal yang perlu dipahami, bukan kegagalan.
class _NoticeBox extends StatelessWidget {
  final String message;
  final Widget? child;
  const _NoticeBox(this.message, {this.child});

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: m.warn50,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.warnBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 16, color: m.warn600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style:
                    TextStyle(fontSize: 12.5, color: m.warn600, height: 1.45)),
          ),
        ]),
        if (child != null) ...[const SizedBox(height: 10), child!],
      ]),
    );
  }
}

/// Kotak info hijau — konfirmasi aksi berhasil.
class _InfoBox extends StatelessWidget {
  final String message;
  const _InfoBox(this.message);

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: m.brand50,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.brand100),
      ),
      child: Text(message,
          style: TextStyle(fontSize: 12.5, color: m.brand700, height: 1.45)),
    );
  }
}

/// TextField ringkas — MasInput tidak menerima `keyboardType`, padahal kode pos
/// & koordinat perlu papan tik angka.
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;
  final bool mono;
  const _Field({
    required this.controller,
    required this.hint,
    this.keyboard,
    this.onChanged,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.input),
        border: Border.all(color: m.ink200),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        onChanged: onChanged,
        style: mono
            ? masMono(size: 13, color: m.ink900)
            : TextStyle(fontSize: 13, color: m.ink900),
        cursorColor: m.brand600,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: m.ink400, fontSize: 12.5),
        ),
      ),
    );
  }
}

/// Dropdown bergaya MasPart.
class _Dropdown extends StatelessWidget {
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  const _Dropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius: BorderRadius.circular(MasRadii.input),
        border: Border.all(color: m.ink200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              size: 16, color: m.ink500),
          style: TextStyle(fontSize: 12.5, color: m.ink800),
          dropdownColor: m.paper,
          items: [
            for (final (key, label) in options)
              DropdownMenuItem(
                value: key,
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v == null || v == value) return;
            onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Baris centang dengan penjelasan. [locked] = tidak bisa dimatikan (izin
/// `always` / aturan yang dipaksakan backend) — tetap tampil menyala supaya
/// admin paham izin itu memang berlaku, bukan lupa dicentang.
class _CheckRow extends StatelessWidget {
  final bool value;
  final String label;
  final String? subtitle;
  final bool locked;
  final ValueChanged<bool>? onChanged;
  const _CheckRow({
    required this.value,
    required this.label,
    this.subtitle,
    this.locked = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final on = value || locked;
    return InkWell(
      onTap: (locked || onChanged == null) ? null : () => onChanged!(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: m.ink100)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: on,
              onChanged: locked || onChanged == null
                  ? null
                  : (v) => onChanged!(v ?? false),
              activeColor: m.brand600,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: locked ? m.ink600 : m.ink900,
                    )),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: TextStyle(
                          fontSize: 11.5, color: m.ink500, height: 1.35)),
                ],
              ],
            ),
          ),
          if (locked) ...[
            const SizedBox(width: 8),
            const MasPill(label: 'wajib', tone: MasPillTone.neutral),
          ],
        ]),
      ),
    );
  }
}

/// Dialog konfirmasi. Dipakai untuk aksi yang MENGUBAH/MENGHAPUS data server.
Future<bool> _confirm(
  BuildContext context, {
  required String judul,
  required String pesan,
  String tombol = 'Lanjut',
  bool bahaya = false,
}) async {
  final m = context.mas;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: m.paper,
      title: Text(judul,
          style: TextStyle(
              fontSize: 15.5, fontWeight: FontWeight.w700, color: m.ink900)),
      content: Text(pesan,
          style: TextStyle(fontSize: 13, color: m.ink600, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Batal', style: TextStyle(color: m.ink600)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tombol,
              style: TextStyle(
                color: bahaya ? m.danger600 : m.brand700,
                fontWeight: FontWeight.w700,
              )),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Judul bagian di dalam sheet/dialog.
Widget _sheetHeader(BuildContext ctx, String judul) {
  final m = ctx.mas;
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
    child: Row(children: [
      Expanded(
        child: Text(judul,
            style: TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w700, color: m.ink900)),
      ),
      GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Icon(Icons.close_rounded, size: 20, color: m.ink500),
      ),
    ]),
  );
}

/// Peran akun. Nada warna mengikuti web (admin = perhatian, pembeli = brand).
MasPillTone _roleTone(String role) => switch (role) {
      'admin' => MasPillTone.warn,
      'pembeli' => MasPillTone.brand,
      _ => MasPillTone.neutral,
    };

/// Peran baku yang bisa dipilih admin. Peran lain yang sudah terlanjur ada di
/// database (mis. akun cabang) tetap ditampilkan supaya dropdown tidak pecah.
const _rolesBaku = ['user', 'admin', 'pembeli'];

List<(String, String)> _roleOptions(String current) {
  final keys = [..._rolesBaku, if (!_rolesBaku.contains(current)) current];
  return [for (final r in keys) (r, r)];
}

// ══════════════════════════════════════════════════════════════════════
// 1. Manajemen User
// ══════════════════════════════════════════════════════════════════════

/// Hasil dialog ubah user. Field null = tidak diubah (API memakai spread
/// null-aware, jadi field null tidak ikut terkirim ke server).
class _UserEdit {
  final String? role;
  final String? password;
  final bool? isActive;
  final bool hapus;
  const _UserEdit({this.role, this.password, this.isActive, this.hapus = false});

  bool get adaPerubahan => role != null || password != null || isActive != null;
}

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AdminUser> _users = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final u = await ApiService.listUsers();
      if (!mounted) return;
      setState(() {
        _users = u;
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

  /// Dialog tambah user. Dialog hanya MENGUMPULKAN input; panggilan API
  /// dilakukan di sini supaya error tampil di kotak error layar (satu tempat).
  Future<void> _tambah() async {
    final data = await showDialog<({String username, String password, String role})>(
      context: context,
      builder: (ctx) => const _TambahUserDialog(),
    );
    if (data == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ApiService.createUser(
        username: data.username,
        password: data.password,
        role: data.role,
      );
      if (!mounted) return;
      setState(() => _info = "User '${data.username}' ditambahkan.");
      await _muat();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ubah(AdminUser u) async {
    final aku = AppNav.of(context).username;
    final edit = await showDialog<_UserEdit>(
      context: context,
      builder: (ctx) => _UbahUserDialog(user: u, bolehHapus: u.username != aku),
    );
    if (edit == null || !mounted) return;

    if (edit.hapus) {
      final ok = await _confirm(
        context,
        judul: 'Hapus user?',
        pesan: "Akun '${u.username}' akan dihapus permanen beserta izin "
            'khususnya. Pesanan yang pernah dibuat akun ini tidak ikut terhapus.',
        tombol: 'Hapus',
        bahaya: true,
      );
      if (!ok || !mounted) return;
      await _jalankan(
        () => ApiService.deleteUser(u.username),
        "User '${u.username}' dihapus.",
      );
      return;
    }

    if (!edit.adaPerubahan) return;
    await _jalankan(
      () => ApiService.updateUser(
        u.username,
        role: edit.role,
        password: edit.password,
        isActive: edit.isActive,
      ),
      "Perubahan untuk '${u.username}' tersimpan.",
    );
  }

  /// Jalankan satu aksi tulis lalu muat ulang daftar — dipakai ubah & hapus.
  Future<void> _jalankan(Future<void> Function() aksi, String pesanSukses) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await aksi();
      if (!mounted) return;
      setState(() => _info = pesanSukses);
      await _muat();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final aku = AppNav.of(context).username;

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(children: [
            Expanded(
              child: Text(
                'Kelola akun, peran, dan status aktif. Akun nonaktif tidak bisa login.',
                style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
              ),
            ),
            const SizedBox(width: 10),
            MasButton(
              label: 'Tambah',
              icon: Icons.person_add_alt_1_rounded,
              height: 38,
              onTap: _busy ? null : _tambah,
            ),
          ]),

          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBox(_error!),
          ],
          if (_info != null) ...[
            const SizedBox(height: 12),
            _InfoBox(_info!),
          ],

          const SizedBox(height: 14),
          if (_loading)
            const MasSkeleton(height: 240)
          else if (_users.isEmpty)
            const MasEmpty(
              icon: Icons.person_outline_rounded,
              title: 'Belum ada user',
              subtitle: 'Tambahkan akun pertama lewat tombol Tambah.',
            )
          else ...[
            Text('${_users.length} akun',
                style: TextStyle(fontSize: 12.5, color: m.ink500)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: m.paper,
                borderRadius: BorderRadius.circular(MasRadii.card),
                border: Border.all(color: m.ink150),
                boxShadow: m.shadow1,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [for (final u in _users) _baris(m, u, aku)],
              ),
            ),
            const SizedBox(height: 8),
            Text('Ketuk baris untuk ubah peran, reset password, aktif/nonaktif, atau hapus.',
                style: TextStyle(fontSize: 11.5, color: m.ink400)),
          ],
        ],
      ),
    );
  }

  Widget _baris(MasColors m, AdminUser u, String aku) => InkWell(
        onTap: _busy ? null : () => _ubah(u),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: m.ink100)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(u.username,
                          overflow: TextOverflow.ellipsis,
                          style: masMono(
                              size: 13,
                              weight: FontWeight.w600,
                              color: m.ink900)),
                    ),
                    if (u.username == aku) ...[
                      const SizedBox(width: 6),
                      Text('(anda)',
                          style: TextStyle(fontSize: 11, color: m.ink400)),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    MasPill(label: u.role, tone: _roleTone(u.role)),
                    MasPill(
                      label: u.isActive ? 'aktif' : 'nonaktif',
                      tone: u.isActive
                          ? MasPillTone.brand
                          : MasPillTone.neutral,
                      dot: true,
                    ),
                  ]),
                  if (u.createdAt != null) ...[
                    const SizedBox(height: 4),
                    Text('Dibuat ${fmtDate(u.createdAt)}',
                        style: TextStyle(fontSize: 11, color: m.ink400)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 18, color: m.ink400),
          ]),
        ),
      );
}

class _TambahUserDialog extends StatefulWidget {
  const _TambahUserDialog();

  @override
  State<_TambahUserDialog> createState() => _TambahUserDialogState();
}

class _TambahUserDialogState extends State<_TambahUserDialog> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  String _role = 'user';

  @override
  void dispose() {
    _u.dispose();
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    // Backend menyimpan username huruf kecil — normalkan di sini supaya admin
    // tidak bingung melihat "Budi" berubah jadi "budi" setelah tersimpan.
    final username = _u.text.trim().toLowerCase();
    final valid = username.isNotEmpty && _p.text.trim().isNotEmpty;

    return AlertDialog(
      backgroundColor: m.paper,
      scrollable: true,
      title: Text('Tambah User',
          style: TextStyle(
              fontSize: 15.5, fontWeight: FontWeight.w700, color: m.ink900)),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Align(
              alignment: Alignment.centerLeft, child: MasEyebrow('Username')),
          const SizedBox(height: 6),
          _Field(
            controller: _u,
            hint: 'mis. budi',
            mono: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          const Align(
              alignment: Alignment.centerLeft, child: MasEyebrow('Password')),
          const SizedBox(height: 6),
          _Field(
            controller: _p,
            hint: 'password awal',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          const Align(
              alignment: Alignment.centerLeft, child: MasEyebrow('Peran')),
          const SizedBox(height: 6),
          _Dropdown(
            value: _role,
            options: _roleOptions(_role),
            onChanged: (v) => setState(() => _role = v),
          ),
          const SizedBox(height: 10),
          Text(
            'Peran menentukan menu yang terlihat. Izin per menu masih bisa '
            'diatur terpisah di Menu Control.',
            style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.4),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Batal', style: TextStyle(color: m.ink600)),
        ),
        TextButton(
          onPressed: valid
              ? () => Navigator.pop(
                    context,
                    (
                      username: username,
                      password: _p.text.trim(),
                      role: _role,
                    ),
                  )
              : null,
          child: Text('Tambah',
              style: TextStyle(
                color: valid ? m.brand700 : m.ink400,
                fontWeight: FontWeight.w700,
              )),
        ),
      ],
    );
  }
}

class _UbahUserDialog extends StatefulWidget {
  final AdminUser user;
  final bool bolehHapus;
  const _UbahUserDialog({required this.user, required this.bolehHapus});

  @override
  State<_UbahUserDialog> createState() => _UbahUserDialogState();
}

class _UbahUserDialogState extends State<_UbahUserDialog> {
  final _pw = TextEditingController();
  late String _role = widget.user.role;
  late bool _aktif = widget.user.isActive;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final u = widget.user;
    final pw = _pw.text.trim();

    return AlertDialog(
      backgroundColor: m.paper,
      scrollable: true,
      title: Text(u.username,
          style: masMono(size: 15, weight: FontWeight.w700, color: m.ink900)),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Align(
              alignment: Alignment.centerLeft, child: MasEyebrow('Peran')),
          const SizedBox(height: 6),
          _Dropdown(
            value: _role,
            options: _roleOptions(u.role),
            onChanged: (v) => setState(() => _role = v),
          ),
          const SizedBox(height: 14),
          const Align(
              alignment: Alignment.centerLeft,
              child: MasEyebrow('Reset password')),
          const SizedBox(height: 6),
          _Field(
            controller: _pw,
            hint: 'kosongkan bila tidak diganti',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MasRadii.card),
              border: Border.all(color: m.ink150),
            ),
            clipBehavior: Clip.antiAlias,
            child: _CheckRow(
              value: _aktif,
              label: 'Akun aktif',
              subtitle: 'Dimatikan → user langsung tidak bisa login lagi.',
              onChanged: (v) => setState(() => _aktif = v),
            ),
          ),
          if (widget.bolehHapus) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: MasButton(
                label: 'Hapus user',
                icon: Icons.delete_outline_rounded,
                primary: false,
                height: 38,
                expand: true,
                onTap: () =>
                    Navigator.pop(context, const _UserEdit(hapus: true)),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text('Akun sendiri tidak bisa dihapus dari sini.',
                style: TextStyle(fontSize: 11.5, color: m.ink400)),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Batal', style: TextStyle(color: m.ink600)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _UserEdit(
              // Kirim HANYA yang berubah — field null tidak ikut ke server.
              role: _role == u.role ? null : _role,
              password: pw.isEmpty ? null : pw,
              isActive: _aktif == u.isActive ? null : _aktif,
            ),
          ),
          child: Text('Simpan',
              style: TextStyle(color: m.brand700, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 2. Menu Control (izin & pembatasan sesi)
// ══════════════════════════════════════════════════════════════════════

const _permKinds = <(PermKind, String)>[
  (PermKind.menu, 'Menu'),
  (PermKind.column, 'Kolom'),
  (PermKind.harga, 'Harga'),
  (PermKind.sesi, 'Sesi'),
  (PermKind.asisten, 'Asisten AI'),
];

/// Username semu untuk baris "Default (user baru)" — nilai yang sama dipakai
/// backend/web untuk menyimpan izin bawaan.
const _kDefaultUser = '__default__';

class MenuControlScreen extends StatefulWidget {
  const MenuControlScreen({super.key});

  @override
  State<MenuControlScreen> createState() => _MenuControlScreenState();
}

class _MenuControlScreenState extends State<MenuControlScreen> {
  PermKind _kind = PermKind.menu;
  PermOverview? _data;

  /// Tab "Asisten AI" menampilkan DUA blok izin dari sumber berbeda (persis web
  /// yang merender dua `KindSection`): blok kolom memakai kind `column` — yang
  /// SAMA dengan tab Kolom, jadi centang di sini = centang di sana. Null pada
  /// tab lain.
  PermOverview? _dataKolom;

  /// User yang sedang dibuka. null = daftar user.
  String? _user;

  /// Centang yang sedang diedit (belum disimpan) untuk kind aktif.
  Set<String> _edit = {};

  /// Centang blok kolom pada tab Asisten AI (kind `column`).
  Set<String> _editKolom = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.permOverview(_kind);
      // Tab Asisten AI butuh izin kolom juga — Stok Tertahan & Alternatif
      // bergantung pada `col_stok`, hasil berharga pada `col_harga`.
      final dk = _kind == PermKind.asisten
          ? await ApiService.permOverview(PermKind.column)
          : null;
      if (!mounted) return;
      setState(() {
        _data = d;
        _dataKolom = dk;
        _loading = false;
        // User yang sedang dibuka tetap dibuka setelah reload (mis. sesudah
        // Simpan) supaya admin bisa langsung melihat hasilnya.
        if (_user != null) {
          _edit = _awal(d, _user!);
          if (dk != null) _editKolom = _awal(dk, _user!);
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Centang awal user: override bila ada, kalau tidak pakai default.
  Set<String> _awal(PermOverview d, String username) =>
      username == _kDefaultUser
          ? {...d.defaults}
          : {...(d.permissions[username] ?? d.defaults)};

  void _pilihJenis(int i) {
    final k = _permKinds[i].$1;
    if (k == _kind) return;
    setState(() {
      _kind = k;
      _user = null; // key izin beda per jenis — pilihan lama tak relevan lagi
      _edit = {};
      _editKolom = {};
      _dataKolom = null;
      _info = null;
    });
    _muat();
  }

  void _bukaUser(String username) {
    final d = _data;
    if (d == null) return;
    final dk = _dataKolom;
    setState(() {
      _user = username;
      _edit = _awal(d, username);
      _editKolom = dk == null ? {} : _awal(dk, username);
      _info = null;
      _error = null;
    });
  }

  Future<void> _simpan() async {
    final d = _data;
    final u = _user;
    if (d == null || u == null) return;

    setState(() {
      _saving = true;
      _error = null;
      _info = null;
    });
    try {
      // Kirim menurut urutan kanonik allKeys. Key `always` tidak perlu ikut —
      // backend selalu menambahkannya sendiri.
      final keys = [
        for (final k in d.allKeys.keys)
          if (_edit.contains(k)) k,
      ];
      // Tab Asisten AI: blok kolom disimpan lebih dulu supaya kalau salah satu
      // gagal, yang tersimpan adalah prasyaratnya — bukan kemampuan tanpa kolom.
      final dk = _dataKolom;
      if (dk != null) {
        await ApiService.setPerm(
          PermKind.column,
          u,
          [
            for (final k in dk.allKeys.keys)
              if (_editKolom.contains(k)) k,
          ],
        );
      }
      await ApiService.setPerm(_kind, u, keys);
      if (!mounted) return;
      setState(() => _info = 'Izin $u tersimpan.');
      await _muat();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    final u = _user;
    if (u == null || u == _kDefaultUser) return;
    final ok = await _confirm(
      context,
      judul: 'Kembalikan ke default?',
      pesan: "Pengaturan khusus '$u' dihapus; ia akan mengikuti izin default "
          'lagi. Kalau default berubah nanti, akun ini ikut berubah.',
      tombol: 'Kembalikan',
    );
    if (!ok || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
      _info = null;
    });
    try {
      if (_dataKolom != null) await ApiService.resetPerm(PermKind.column, u);
      await ApiService.resetPerm(_kind, u);
      if (!mounted) return;
      setState(() => _info = "Izin '$u' dikembalikan ke default.");
      await _muat();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final d = _data;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        MasSegmentTabs(
          tabs: [for (final k in _permKinds) k.$2],
          index: _permKinds.indexWhere((k) => k.$1 == _kind),
          onChanged: _pilihJenis,
        ),
        const SizedBox(height: 12),

        // 'sesi' BUKAN izin — mencentang justru MEMBATASI akun. Tanpa
        // keterangan ini admin gampang membaliknya (mengira centang = boleh).
        if (_kind == PermKind.sesi)
          const _NoticeBox(
            'Tab Sesi bukan pemberian izin, melainkan PEMBATASAN. Mencentang '
            '"Hanya 1 perangkat" membuat akun tidak bisa dipakai bersamaan di '
            'dua tempat: begitu orang lain login dengan akun itu, perangkat '
            'lama otomatis keluar. Akun admin tidak pernah dibatasi.',
          )
        // Kebalikan dari tab lain: di sini tanpa baris izin = KOSONG, jadi
        // mencentang benar-benar MEMBERI kemampuan yang biasanya admin-only.
        else if (_kind == PermKind.asisten)
          const _NoticeBox(
            'Centang = MEMBERI kemampuan Asisten AI yang biasanya khusus admin. '
            'Admin & akun "mas" selalu punya Harga SIMS & Populasi — centang '
            'tidak pernah mencabut dari mereka. Akun pembeli tidak bisa diberi '
            'kemampuan ini. Stok Tertahan & Alternatif juga butuh centang '
            '"Kolom Stok"; hasil berharga butuh "Kolom Harga" (blok pertama).',
          )
        else
          Text(
            'Atur akses per user. Akun berperan admin selalu punya akses penuh '
            'dan tidak muncul di daftar ini.',
            style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
          ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorBox(_error!),
        ],
        if (_info != null) ...[
          const SizedBox(height: 12),
          _InfoBox(_info!),
        ],

        const SizedBox(height: 14),
        if (_loading)
          const MasSkeleton(height: 260)
        else if (d == null)
          const SizedBox.shrink()
        else if (_user == null)
          _daftarUser(m, d)
        else
          _editor(m, d, _user!),
      ],
    );
  }

  Widget _daftarUser(MasColors m, PermOverview d) {
    // Admin tidak bisa dibatasi → tidak ditampilkan (sama seperti web).
    final users = d.users.where((u) => u.role != 'admin').toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        decoration: BoxDecoration(
          color: m.paper,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border.all(color: m.ink150),
          boxShadow: m.shadow1,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          _barisUser(
            m,
            username: _kDefaultUser,
            judul: 'Default (user baru)',
            jumlah: d.defaults.length,
            pakaiDefault: false,
            catatan: 'Berlaku untuk user yang belum diatur khusus.',
          ),
          for (final u in users)
            _barisUser(
              m,
              username: u.username,
              judul: u.username,
              jumlah: d.effectiveFor(u.username).length,
              pakaiDefault: !d.permissions.containsKey(u.username),
              catatan: u.role,
            ),
        ]),
      ),
      if (users.isEmpty) ...[
        const SizedBox(height: 10),
        Text('Tidak ada user non-admin.',
            style: TextStyle(fontSize: 12.5, color: m.ink500)),
      ],
      const SizedBox(height: 8),
      Text(
        '${d.allKeys.length} ${_kind == PermKind.sesi ? "pembatasan" : "izin"} '
        'tersedia untuk jenis ini. Ketuk user untuk mengaturnya.',
        style: TextStyle(fontSize: 11.5, color: m.ink400),
      ),
    ]);
  }

  Widget _barisUser(
    MasColors m, {
    required String username,
    required String judul,
    required int jumlah,
    required bool pakaiDefault,
    required String catatan,
  }) =>
      InkWell(
        onTap: () => _bukaUser(username),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: m.ink100)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(judul,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: m.ink900)),
                    ),
                    if (pakaiDefault) ...[
                      const SizedBox(width: 6),
                      const MasPill(
                          label: 'default', tone: MasPillTone.neutral),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text('$catatan · $jumlah aktif',
                      style: TextStyle(fontSize: 11.5, color: m.ink500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: m.ink400),
          ]),
        ),
      );

  /// Satu blok centang untuk sebuah `PermOverview`. Dipisah karena tab Asisten
  /// AI merender dua blok dari dua kind sekaligus.
  Widget _blokIzin(
    MasColors m,
    PermOverview d,
    Set<String> dipilih,
    void Function(Set<String>) simpanKe, {
    String? judul,
  }) {
    final always = d.always.toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (judul != null) ...[
        Text(judul,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: m.ink700)),
        const SizedBox(height: 8),
      ],
      if (d.allKeys.isEmpty)
        const MasEmpty(
          icon: Icons.shield_outlined,
          title: 'Tidak ada yang bisa diatur',
          subtitle: 'Jenis izin ini belum punya key apa pun di server.',
        )
      else
        Container(
          decoration: BoxDecoration(
            color: m.paper,
            borderRadius: BorderRadius.circular(MasRadii.card),
            border: Border.all(color: m.ink150),
            boxShadow: m.shadow1,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final e in d.allKeys.entries)
              _CheckRow(
                value: dipilih.contains(e.key),
                label: e.value.isEmpty ? e.key : e.value,
                subtitle: e.key,
                // Key `always` tidak bisa dimatikan siapa pun — backend
                // memaksanya menyala, jadi jangan beri harapan palsu di UI.
                locked: always.contains(e.key),
                onChanged: _saving
                    ? null
                    : (v) {
                        final next = {...dipilih};
                        v ? next.add(e.key) : next.remove(e.key);
                        setState(() => simpanKe(next));
                      },
              ),
          ]),
        ),
    ]);
  }

  Widget _editor(MasColors m, PermOverview d, String username) {
    final judul =
        username == _kDefaultUser ? 'Default (user baru)' : username;
    final dKolom = _dataKolom;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        GestureDetector(
          onTap: () => setState(() => _user = null),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.chevron_left_rounded, size: 18, color: m.ink500),
            Text('Semua user',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: m.ink600)),
          ]),
        ),
        const Spacer(),
        Flexible(
          child: Text(judul,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700, color: m.ink900)),
        ),
      ]),
      const SizedBox(height: 10),
      if (dKolom != null) ...[
        _blokIzin(m, dKolom, _editKolom, (v) => _editKolom = v,
            judul: 'Kolom Harga & Stok (sumber sama dengan tab Kolom)'),
        const SizedBox(height: 14),
        _blokIzin(m, d, _edit, (v) => _edit = v,
            judul: 'Kemampuan Asisten AI'),
      ] else
        _blokIzin(m, d, _edit, (v) => _edit = v),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: MasButton(
            label: 'Simpan',
            icon: Icons.check_rounded,
            expand: true,
            loading: _saving,
            onTap: d.allKeys.isEmpty ? null : _simpan,
          ),
        ),
        if (username != _kDefaultUser) ...[
          const SizedBox(width: 8),
          MasButton(
            label: 'Kembalikan ke default',
            primary: false,
            onTap: _saving ? null : _reset,
          ),
        ],
      ]),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════
// 3. Monitoring User
// ══════════════════════════════════════════════════════════════════════

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

/// Selang auto-refresh — sama dengan `REFRESH_MS` di web. Status online/offline
/// hanya berguna kalau bergerak sendiri; admin tak seharusnya menarik-narik
/// layar untuk tahu siapa yang baru masuk.
const Duration _monitoringRefresh = Duration(seconds: 15);

class _MonitoringScreenState extends State<MonitoringScreen> {
  MonitoringData? _data;

  /// DDL tabel `login_history` — hanya diambil bila tabelnya memang belum ada.
  String? _sql;
  bool _onlineSaja = false;
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _muat();
    _poll = Timer.periodic(_monitoringRefresh, (_) => _muat(diam: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// [diam] = refresh latar: jangan tampilkan skeleton dan jangan menghapus
  /// data yang sudah tampil, supaya layar tidak berkedip tiap 15 detik.
  Future<void> _muat({bool diam = false}) async {
    if (!diam) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final d = await ApiService.monitoring();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
        if (diam) _error = null; // pulih sendiri setelah gangguan sesaat
      });
      // Tabel riwayat belum dibuat → sediakan DDL-nya, jangan diam saja.
      if (!d.riwayatTersedia && _sql == null) await _muatSql();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Refresh latar yang gagal tidak boleh menimpa data yang masih tampil —
      // jaringan sekejap putus bukan alasan mengosongkan layar.
      if (diam) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _muatSql() async {
    try {
      final s = await ApiService.monitoringSql();
      if (!mounted) return;
      setState(() => _sql = s);
    } on ApiException catch (e) {
      // Kegagalan mengambil DDL tidak boleh menutupi data monitoring yang
      // sudah berhasil dimuat — cukup tampilkan alasannya di kotak error.
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _riwayat(MonitoringUser u) async {
    final nav = AppNav.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RiwayatLoginSheet(username: u.username),
    );
    // Sheet memuat datanya sendiri; toast dipakai hanya bila tabel riwayat
    // memang belum ada (kolom IP/perangkat pasti kosong).
    final d = _data;
    if (d != null && !d.riwayatTersedia) {
      nav.toast('Tabel login_history belum dibuat — riwayat akan kosong.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final d = _data;
    final semua = d?.users ?? const <MonitoringUser>[];
    final users = _onlineSaja ? semua.where((u) => u.online).toList() : semua;
    final ditandai = semua.where((u) => u.kemungkinanDipakaiRamai).length;
    final offline = (d?.totalUsers ?? 0) - (d?.onlineCount ?? 0);

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (_error != null) ...[
            _ErrorBox(_error!),
            const SizedBox(height: 12),
          ],

          if (_loading && d == null)
            const MasSkeleton(height: 300)
          else if (d == null)
            const SizedBox.shrink()
          else ...[
            Row(children: [
              Expanded(
                child: _kartuAngka(
                  m,
                  label: 'Online (${d.onlineWindowMinutes} mnt)',
                  nilai: thousands(d.onlineCount),
                  warna: m.brand600,
                  aktif: _onlineSaja,
                  onTap: () => setState(() => _onlineSaja = true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _kartuAngka(
                  m,
                  label: 'Offline',
                  nilai: thousands(offline < 0 ? 0 : offline),
                  warna: m.ink500,
                  aktif: !_onlineSaja,
                  onTap: () => setState(() => _onlineSaja = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _kartuAngka(
                  m,
                  label: 'Total user',
                  nilai: thousands(d.totalUsers),
                  warna: m.ink900,
                  aktif: false,
                  onTap: null,
                ),
              ),
            ]),

            if (!d.riwayatTersedia) ...[
              const SizedBox(height: 12),
              _NoticeBox(
                'Riwayat login belum aktif — kolom IP & perangkat akan kosong '
                'setelah server restart. Buat tabelnya sekali di Supabase → SQL '
                'Editor, lalu tarik layar ini untuk menyegarkan. Login yang '
                'terjadi setelah itu akan tercatat.',
                child: _sql == null
                    ? null
                    : _kotakSql(m, _sql!),
              ),
            ],

            if (ditandai > 0) ...[
              const SizedBox(height: 12),
              _NoticeBox(
                '$ditandai akun ditandai "mungkin dipakai ramai": dalam '
                '${d.shareDays} hari terakhir login dari ≥${d.shareIpMin} '
                'jaringan atau ≥${d.shareDeviceMin} perangkat berbeda. Ini '
                'SINYAL, bukan vonis — satu orang bisa berpindah WiFi/kuota, '
                'dan satu kantor berbagi satu jaringan. Ketuk user untuk '
                'menelusuri riwayat loginnya sebelum mengambil kesimpulan.',
              ),
            ],

            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: MasEyebrow(_onlineSaja ? 'User online' : 'Semua user'),
              ),
              if (_onlineSaja)
                GestureDetector(
                  onTap: () => setState(() => _onlineSaja = false),
                  child: Text('tampilkan semua',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: m.brand700)),
                ),
            ]),
            const SizedBox(height: 8),

            if (users.isEmpty)
              MasEmpty(
                icon: Icons.people_outline_rounded,
                title: _onlineSaja
                    ? 'Tidak ada user online'
                    : 'Belum ada user',
                subtitle: _onlineSaja
                    ? 'Tidak ada aktivitas dalam ${d.onlineWindowMinutes} menit terakhir.'
                    : 'Daftar user masih kosong.',
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: m.paper,
                  borderRadius: BorderRadius.circular(MasRadii.card),
                  border: Border.all(color: m.ink150),
                  boxShadow: m.shadow1,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [for (final u in users) _barisUser(m, u, d)],
                ),
              ),

            const SizedBox(height: 8),
            Text(
              'Catatan sebaran: "jaringan" menghitung /64 untuk IPv6, sedangkan '
              '"alamat" menghitung alamat mentah. IPv6 memutar alamatnya sendiri '
              'secara berkala, jadi jumlah alamat bisa jauh lebih besar dari '
              'jumlah jaringan TANPA berarti akun dibagi-bagi.',
              style: TextStyle(fontSize: 11.5, color: m.ink400, height: 1.45),
            ),

            const SizedBox(height: 20),
            const MasEyebrow('Aktivitas terbaru'),
            const SizedBox(height: 8),
            if (d.recentActivity.isEmpty)
              Text('Belum ada aktivitas tercatat.',
                  style: TextStyle(fontSize: 12.5, color: m.ink500))
            else
              Container(
                decoration: BoxDecoration(
                  color: m.paper,
                  borderRadius: BorderRadius.circular(MasRadii.card),
                  border: Border.all(color: m.ink150),
                  boxShadow: m.shadow1,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final a in d.recentActivity) _barisAktivitas(m, a),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _kartuAngka(
    MasColors m, {
    required String label,
    required String nilai,
    required Color warna,
    required bool aktif,
    required VoidCallback? onTap,
  }) =>
      MasCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: aktif ? FontWeight.w700 : FontWeight.w500,
                  color: aktif ? m.brand700 : m.ink500,
                )),
            const SizedBox(height: 6),
            Text(nilai,
                style: masMono(
                    size: 20, weight: FontWeight.w700, color: warna)),
          ],
        ),
      );

  /// DDL yang bisa disalin — admin tinggal tempel ke SQL Editor Supabase.
  Widget _kotakSql(MasColors m, String sql) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: m.paper,
              borderRadius: BorderRadius.circular(MasRadii.input),
              border: Border.all(color: m.warnBorder),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                sql,
                style: masMono(size: 10.5, color: m.ink700, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 8),
          MasButton(
            label: 'Salin SQL',
            icon: Icons.copy_all_rounded,
            primary: false,
            height: 34,
            onTap: () async {
              final nav = AppNav.of(context);
              await Clipboard.setData(ClipboardData(text: sql));
              nav.toast('SQL disalin — tempel di Supabase → SQL Editor.');
            },
          ),
        ],
      );

  Widget _barisUser(MasColors m, MonitoringUser u, MonitoringData d) {
    final warnaDot = u.online
        ? m.brand600
        : u.isActive
            ? m.ink300
            : m.danger600;
    final status = u.online ? 'online' : (u.isActive ? 'offline' : 'nonaktif');

    return InkWell(
      onTap: () => _riwayat(u),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: m.ink100)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: warnaDot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(u.username,
                        overflow: TextOverflow.ellipsis,
                        style: masMono(
                            size: 12.5,
                            weight: FontWeight.w600,
                            color: m.ink900)),
                  ),
                  const SizedBox(width: 6),
                  Text('· $status · ${u.role}',
                      style: TextStyle(fontSize: 11.5, color: m.ink500)),
                ]),
                const SizedBox(height: 4),
                if (u.kemungkinanDipakaiRamai) ...[
                  const MasPill(
                      label: 'sinyal: mungkin dipakai ramai',
                      tone: MasPillTone.warn),
                  const SizedBox(height: 4),
                ],
                Text(
                  'IP terakhir: ${u.lastIp ?? "—"} · ${u.lastDevice ?? "perangkat tidak dikenal"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: m.ink600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sebaran ${d.shareDays}h: ${u.ipCount} jaringan '
                  '(${u.alamatCount} alamat) · ${u.deviceCount} perangkat · '
                  '${u.loginCount} login',
                  style: TextStyle(fontSize: 11.5, color: m.ink500),
                ),
                const SizedBox(height: 2),
                Text('Aktif terakhir ${fmtDate(u.lastActiveAt)}',
                    style: TextStyle(fontSize: 11, color: m.ink400)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: m.ink400),
        ]),
      ),
    );
  }

  Widget _barisAktivitas(MasColors m, MonitoringActivity a) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: m.ink100)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: Text('${a.username} · ${a.action}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: m.ink900)),
              ),
              Text(fmtDate(a.createdAt),
                  style: TextStyle(fontSize: 11, color: m.ink400)),
            ]),
            const SizedBox(height: 2),
            Text(
              a.ip != null
                  ? '${a.ip}${a.device != null ? " · ${a.device}" : ""}'
                  : (a.target ?? '—'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: m.ink500),
            ),
          ],
        ),
      );
}

/// Riwayat login satu user — dipakai untuk MENELUSURI akun yang ditandai,
/// bukan untuk menghukumnya.
class _RiwayatLoginSheet extends StatefulWidget {
  final String username;
  const _RiwayatLoginSheet({required this.username});

  @override
  State<_RiwayatLoginSheet> createState() => _RiwayatLoginSheetState();
}

class _RiwayatLoginSheetState extends State<_RiwayatLoginSheet> {
  List<LoginHistoryRow> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final r =
          await ApiService.loginHistory(username: widget.username, limit: 100);
      if (!mounted) return;
      setState(() {
        _rows = r.riwayat;
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

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: m.paper,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(MasRadii.sheet)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _sheetHeader(context, 'Riwayat login · ${widget.username}'),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              if (_loading)
                const MasSkeleton(height: 160)
              else if (_error != null)
                _ErrorBox(_error!)
              else if (_rows.isEmpty)
                const MasEmpty(
                  icon: Icons.history_rounded,
                  title: 'Belum ada riwayat',
                  subtitle:
                      'Belum ada login tercatat untuk user ini (atau tabel login_history baru dibuat).',
                )
              else
                for (final r in _rows)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: m.ink100)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(fmtDate(r.createdAt),
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: m.ink900)),
                        const SizedBox(height: 2),
                        Text(r.ip ?? '—',
                            style: masMono(size: 11.5, color: m.ink600)),
                        if (r.device != null && r.device!.isNotEmpty)
                          Text(r.device!,
                              style: TextStyle(fontSize: 11.5, color: m.ink500)),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 4. Upload Data
// ══════════════════════════════════════════════════════════════════════

const _datasets = <({String kind, String label, String file, String catatan})>[
  (
    kind: 'stok',
    label: 'Stok',
    file: 'stok.xlsx',
    catatan: 'Memicu rebuild indeks stok.',
  ),
  (
    kind: 'harga',
    label: 'Harga',
    file: 'harga.xlsx',
    catatan: 'Memicu rebuild indeks harga.',
  ),
  (
    kind: 'populasi',
    label: 'Populasi Unit',
    file: 'populasi.xlsx',
    catatan: 'Langsung dimuat ulang.',
  ),
];

/// Ambil satu/banyak Excel beserta byte-nya. `withData` wajib: kita mengirim
/// multipart dari memori, dan file dari Drive/Cloud sering tidak punya path.
Future<List<({Uint8List bytes, String filename})>> _pilihExcel({
  bool multi = false,
}) async {
  final res = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls', 'xlsm'],
    withData: true,
    allowMultiple: multi,
  );
  final files = res?.files ?? const [];
  return [
    for (final f in files)
      if (f.bytes != null) (bytes: f.bytes!, filename: f.name),
  ];
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          'Unggah Excel terbaru untuk Stok, Harga, atau Populasi. File menimpa '
          'dataset lama di Storage dan indeksnya langsung diperbarui.',
          style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
        ),
        const SizedBox(height: 12),

        // Jebakan nyata: pernah terjadi upload stok menghapus reservasi aktif.
        // Karena itu setiap unggahan dataset dikonfirmasi dulu.
        const _NoticeBox(
          'Unggahan dataset MENIMPA data lama dan membangun ulang indeks. '
          'Khusus Stok, ini pernah berdampak ke reservasi/pesanan yang sedang '
          'berjalan — pastikan file sudah benar dan waktunya tepat.',
        ),

        const SizedBox(height: 14),
        for (final d in _datasets) ...[
          _DatasetCard(
            kind: d.kind,
            label: d.label,
            file: d.file,
            catatan: d.catatan,
          ),
          const SizedBox(height: 10),
        ],

        const SizedBox(height: 12),
        const MasEyebrow('Upload katalog part'),
        const SizedBox(height: 8),
        const _CatalogUploadCard(),
      ],
    );
  }
}

class _DatasetCard extends StatefulWidget {
  final String kind;
  final String label;
  final String file;
  final String catatan;
  const _DatasetCard({
    required this.kind,
    required this.label,
    required this.file,
    required this.catatan,
  });

  @override
  State<_DatasetCard> createState() => _DatasetCardState();
}

class _DatasetCardState extends State<_DatasetCard> {
  ({Uint8List bytes, String filename})? _file;
  bool _busy = false;
  String? _error;
  String? _info;

  Future<void> _pilih() async {
    final f = await _pilihExcel();
    if (f.isEmpty || !mounted) return;
    setState(() {
      _file = f.first;
      _error = null;
      _info = null;
    });
  }

  Future<void> _unggah() async {
    final f = _file;
    if (f == null) return;

    final ok = await _confirm(
      context,
      judul: 'Unggah dataset ${widget.label}?',
      pesan: '"${f.filename}" akan menimpa ${widget.file} di Storage dan '
          'indeksnya dibangun ulang.'
          '${widget.kind == "stok" ? "\n\nStok yang baru langsung dipakai untuk "
              "menghitung ketersediaan — pesanan/reservasi yang sedang berjalan "
              "bisa ikut terpengaruh." : ""}',
      tombol: 'Unggah',
      bahaya: widget.kind == 'stok',
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final r = await ApiService.uploadDataset(
        kind: widget.kind,
        bytes: f.bytes,
        filename: f.filename,
      );
      if (!mounted) return;
      setState(() {
        _info =
            '${widget.label} terunggah (${(r.size / 1024).round()} KB) & indeks diperbarui.';
        _file = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    return MasCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.label,
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700, color: m.ink900)),
        const SizedBox(height: 3),
        Text('Menimpa ${widget.file} · ${widget.catatan}',
            style: TextStyle(fontSize: 11.5, color: m.ink500)),
        const SizedBox(height: 10),
        Row(children: [
          MasButton(
            label: 'Pilih File',
            icon: Icons.attach_file_rounded,
            primary: false,
            height: 36,
            onTap: _busy ? null : _pilih,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _file?.filename ?? 'Belum ada file dipilih.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: m.ink600),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        MasButton(
          label: _busy ? 'Mengunggah…' : 'Unggah & Perbarui Indeks',
          icon: Icons.upload_rounded,
          expand: true,
          height: 40,
          loading: _busy,
          onTap: _file == null ? null : _unggah,
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _ErrorBox(_error!),
        ],
        if (_info != null) ...[
          const SizedBox(height: 10),
          _InfoBox(_info!),
        ],
      ]),
    );
  }
}

class _CatalogUploadCard extends StatefulWidget {
  const _CatalogUploadCard();

  @override
  State<_CatalogUploadCard> createState() => _CatalogUploadCardState();
}

class _CatalogUploadCardState extends State<_CatalogUploadCard> {
  final _subdir = TextEditingController();

  List<String> _folders = [];
  List<({Uint8List bytes, String filename})> _files = [];
  CatalogUploadResult? _hasil;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _muatFolder();
  }

  @override
  void dispose() {
    _subdir.dispose();
    super.dispose();
  }

  Future<void> _muatFolder() async {
    try {
      final f = await ApiService.catalogFolders();
      if (!mounted) return;
      setState(() => _folders = f);
    } on ApiException catch (e) {
      // Daftar folder hanya bantuan; admin tetap boleh mengetik folder baru.
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pilih() async {
    final f = await _pilihExcel(multi: true);
    if (f.isEmpty || !mounted) return;
    setState(() {
      _files = f;
      _error = null;
      _hasil = null;
    });
  }

  Future<void> _unggah() async {
    final dir = _subdir.text.trim();
    if (dir.isEmpty) {
      setState(() => _error = 'Tentukan folder tujuan dulu (mis. Sinotruk/NX380HP).');
      return;
    }
    if (_files.isEmpty) return;

    final ok = await _confirm(
      context,
      judul: 'Unggah ${_files.length} file katalog?',
      pesan: 'File disimpan ke /data/$dir di server dan langsung terindeks. '
          'File dengan nama sama akan tertimpa.',
      tombol: 'Unggah',
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _hasil = null;
    });
    try {
      final r = await ApiService.uploadCatalog(subdir: dir, files: _files);
      if (!mounted) return;
      setState(() {
        _hasil = r;
        _files = [];
      });
      await _muatFolder(); // folder baru ikut muncul di saran
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final h = _hasil;

    return MasCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Katalog Part (per unit/model)',
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700, color: m.ink900)),
        const SizedBox(height: 3),
        Text(
          'Unggah satu atau beberapa Excel katalog ke folder tujuan di server '
          '(mis. Sinotruk/NX380HP). Langsung tersimpan & terindeks — tanpa deploy ulang.',
          style: TextStyle(fontSize: 11.5, color: m.ink500, height: 1.45),
        ),

        const SizedBox(height: 12),
        const MasEyebrow('Folder tujuan'),
        const SizedBox(height: 6),
        _Field(
          controller: _subdir,
          hint: 'mis. Sinotruk/NX380HP (boleh folder baru)',
          mono: true,
          onChanged: (_) => setState(() {}),
        ),
        if (_folders.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Folder yang sudah ada — ketuk untuk memakai:',
              style: TextStyle(fontSize: 11.5, color: m.ink400)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in _folders)
              GestureDetector(
                onTap: () => setState(() => _subdir.text = f),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _subdir.text == f ? m.brand50 : m.ink50,
                    borderRadius: BorderRadius.circular(MasRadii.chip),
                    border: Border.all(
                        color: _subdir.text == f ? m.brand100 : m.ink200),
                  ),
                  child: Text(f,
                      style: masMono(
                        size: 11.5,
                        weight: FontWeight.w600,
                        color: _subdir.text == f ? m.brand700 : m.ink600,
                      )),
                ),
              ),
          ]),
        ],

        const SizedBox(height: 12),
        const MasEyebrow('File Excel (boleh beberapa)'),
        const SizedBox(height: 6),
        Row(children: [
          MasButton(
            label: 'Pilih File',
            icon: Icons.attach_file_rounded,
            primary: false,
            height: 36,
            onTap: _busy ? null : _pilih,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _files.isEmpty
                  ? 'Belum ada file dipilih.'
                  : '${_files.length} file: ${_files.map((f) => f.filename).join(", ")}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: m.ink600),
            ),
          ),
        ]),

        const SizedBox(height: 12),
        MasButton(
          label: _busy ? 'Mengunggah…' : 'Unggah Katalog & Perbarui Indeks',
          icon: Icons.upload_rounded,
          expand: true,
          height: 40,
          loading: _busy,
          onTap: _files.isEmpty ? null : _unggah,
        ),

        if (_error != null) ...[
          const SizedBox(height: 10),
          _ErrorBox(_error!),
        ],

        if (h != null) ...[
          const SizedBox(height: 10),
          _InfoBox('${h.count} file tersimpan ke /data/${_subdir.text.trim()}.'),
          if (h.saved.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final s in h.saved)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('✓ ${s.path} (${(s.size / 1024).round()} KB)',
                    style: masMono(size: 11, color: m.ink600)),
              ),
          ],
          if (h.errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ErrorBox(
              '${h.errors.length} file gagal:\n'
              '${h.errors.map((e) => "• ${e.file} — ${e.error}").join("\n")}',
            ),
          ],
          if (h.refreshWarning != null && h.refreshWarning!.isNotEmpty) ...[
            const SizedBox(height: 8),
            // File tersimpan tapi indeks belum tentu ikut segar — kalau ini
            // disembunyikan, admin akan mengira katalog baru sudah bisa dicari.
            _NoticeBox('File tersimpan, tapi indeks belum tersegarkan: '
                '${h.refreshWarning}'),
          ],
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 5. Lokasi Gudang
// ══════════════════════════════════════════════════════════════════════

/// Baris gudang yang sedang diedit. Dipakai sebagai model kerja karena
/// `AdminGudang.copyWith` tidak bisa MENGOSONGKAN lat/lon (null = "tidak
/// diubah"), padahal admin boleh menghapus koordinat yang salah.
class _GudangRow {
  final String label;
  final String display;
  final List<String> nearest;
  double? lat;
  double? lon;
  String originPostal;
  String pic;
  String key;
  bool selectable;
  bool canShip;

  _GudangRow.from(AdminGudang g)
      : label = g.label,
        display = g.display,
        nearest = g.nearest,
        lat = g.lat,
        lon = g.lon,
        originPostal = g.originPostal,
        pic = g.pic,
        key = g.key ?? '',
        selectable = g.selectable,
        canShip = g.canShip;

  AdminGudang toModel() => AdminGudang(
        label: label,
        display: display,
        lat: lat,
        lon: lon,
        selectable: selectable,
        key: key.isEmpty ? null : key,
        originPostal: originPostal,
        pic: pic,
        canShip: canShip,
        nearest: nearest,
      );
}

class GudangScreen extends StatefulWidget {
  const GudangScreen({super.key});

  @override
  State<GudangScreen> createState() => _GudangScreenState();
}

class _GudangScreenState extends State<GudangScreen> {
  List<_GudangRow> _rows = [];

  // Controller per gudang (kunci = label) supaya teks tidak melompat saat
  // setState. Dibuang & dibuat ulang setiap kali data server dimuat.
  final Map<String, TextEditingController> _koord = {};
  final Map<String, TextEditingController> _pos = {};
  final Map<String, TextEditingController> _pic = {};
  final Map<String, TextEditingController> _key = {};

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _buangController();
    super.dispose();
  }

  void _buangController() {
    for (final c in [..._koord.values, ..._pos.values, ..._pic.values, ..._key.values]) {
      c.dispose();
    }
    _koord.clear();
    _pos.clear();
    _pic.clear();
    _key.clear();
  }

  Future<void> _muat() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final g = await ApiService.adminGudang();
      if (!mounted) return;
      setState(() {
        _buangController();
        _rows = g.map(_GudangRow.from).toList();
        for (final r in _rows) {
          _koord[r.label] = TextEditingController(
            text: (r.lat != null && r.lon != null) ? '${r.lat}, ${r.lon}' : '',
          );
          _pos[r.label] = TextEditingController(text: r.originPostal);
          _pic[r.label] = TextEditingController(text: r.pic);
          _key[r.label] = TextEditingController(text: r.key);
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

  /// "-6.21, 106.85" (atau dipisah spasi) → lat/lon. Teks kosong = koordinat
  /// dihapus (null), bukan 0 — 0,0 adalah titik nyata di laut lepas.
  void _setKoordinat(_GudangRow r, String text) {
    final parts = text
        .split(RegExp(r'[,\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    setState(() {
      r.lat = parts.isEmpty ? null : double.tryParse(parts[0]);
      r.lon = parts.length < 2 ? null : double.tryParse(parts[1]);
    });
  }

  /// Isi kode pos dari koordinat (reverse-geocoding lewat backend). Manual,
  /// bukan otomatis, supaya tidak menghajar batas laju Nominatim.
  Future<void> _isiKodePos(_GudangRow r) async {
    if (r.lat == null || r.lon == null) {
      setState(() => _error = 'Isi koordinat ${r.display} dulu.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final p = await ApiService.geoReverse(r.lat!, r.lon!);
      if (!mounted) return;
      if (p.postal.isEmpty) {
        setState(() => _error =
            'Kode pos tidak ditemukan untuk koordinat ${r.display} — isi manual.');
        return;
      }
      setState(() {
        r.originPostal = p.postal;
        _pos[r.label]?.text = p.postal;
        _info = 'Kode pos ${r.display} diisi dari koordinat. Jangan lupa Simpan.';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _simpan() async {
    final ok = await _confirm(
      context,
      judul: 'Simpan konfigurasi gudang?',
      pesan: 'Perubahan koordinat mengubah perhitungan gudang terdekat, dan '
          'perubahan kode pos mengubah asal hitung ongkir untuk pesanan baru.',
      tombol: 'Simpan',
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ApiService.saveAdminGudang([for (final r in _rows) r.toModel()]);
      if (!mounted) return;
      setState(() => _info = 'Konfigurasi lokasi gudang tersimpan.');
      await _muat(); // kolom "terdekat" dihitung ulang server setelah simpan
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;

    // Kombinasi paling berbahaya: gudang boleh mengirim tapi tidak punya kode
    // pos asal → server menolak menghitung ongkir dan pesanan gagal di checkout.
    final tanpaPos = _rows
        .where((r) => r.canShip && r.originPostal.trim().isEmpty)
        .map((r) => r.display.isEmpty ? r.label : r.display)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          'Koordinat (lat/lon) dipakai server untuk memilih gudang TERDEKAT saat '
          'stok di gudang pilihan pembeli kosong.',
          style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
        ),
        const SizedBox(height: 10),
        const _NoticeBox(
          'Dua centang yang sering salah dipahami:\n'
          '• "Bisa kirim" mati → gudang itu TIDAK AKAN PERNAH memenuhi pesanan '
          'online (gudang internal). Stoknya tak pernah ditawarkan ke pembeli.\n'
          '• "Kode pos asal" adalah titik awal hitung ongkir dan wajib untuk '
          'SEMUA gudang yang bisa kirim — bukan hanya yang dipilih pembeli. '
          'Kosong = ongkir dari gudang itu gagal dihitung.',
        ),

        if (tanpaPos.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ErrorBox(
            'Gudang berikut boleh kirim tapi kode pos asalnya kosong — ongkir '
            'dari sini akan gagal: ${tanpaPos.join(", ")}.',
          ),
        ],

        if (_error != null) ...[
          const SizedBox(height: 10),
          _ErrorBox(_error!),
        ],
        if (_info != null) ...[
          const SizedBox(height: 10),
          _InfoBox(_info!),
        ],

        const SizedBox(height: 14),
        if (_loading)
          const MasSkeleton(height: 300)
        else if (_rows.isEmpty)
          const MasEmpty(
            icon: Icons.warehouse_outlined,
            title: 'Belum ada data gudang',
            subtitle: 'Server belum mengirim daftar gudang mana pun.',
          )
        else ...[
          for (final r in _rows) ...[
            _kartu(m, r),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          MasButton(
            label: _busy ? 'Menyimpan…' : 'Simpan Semua',
            icon: Icons.save_outlined,
            expand: true,
            height: 46,
            loading: _busy,
            onTap: _simpan,
          ),
          const SizedBox(height: 8),
          Text('Kolom "Terdekat" dihitung ulang server setelah disimpan.',
              style: TextStyle(fontSize: 11.5, color: m.ink400)),
        ],
      ],
    );
  }

  Widget _kartu(MasColors m, _GudangRow r) => MasCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.display.isEmpty ? r.label : r.display,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: m.ink900)),
                  const SizedBox(height: 2),
                  Text(r.label, style: masMono(size: 11, color: m.ink400)),
                ],
              ),
            ),
            if (!r.canShip)
              const MasPill(label: 'internal', tone: MasPillTone.neutral),
          ]),

          const SizedBox(height: 12),
          const MasEyebrow('Koordinat (lat, lon)'),
          const SizedBox(height: 6),
          _Field(
            controller: _koord[r.label]!,
            hint: '-6.21, 106.85',
            mono: true,
            keyboard: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            onChanged: (v) => _setKoordinat(r, v),
          ),

          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MasEyebrow('Kode pos asal'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _pos[r.label]!,
                    hint: 'mis. 14350',
                    mono: true,
                    keyboard: TextInputType.number,
                    // setState supaya peringatan "boleh kirim tapi kode pos
                    // kosong" di atas ikut hidup/mati saat diketik.
                    onChanged: (v) => setState(
                      () => r.originPostal = v.replaceAll(RegExp(r'\D'), ''),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MasButton(
              label: 'Dari koordinat',
              primary: false,
              height: 38,
              onTap: _busy ? null : () => _isiKodePos(r),
            ),
          ]),

          const SizedBox(height: 12),
          const MasEyebrow('No. PIC'),
          const SizedBox(height: 6),
          _Field(
            controller: _pic[r.label]!,
            hint: '08xxxxxxxxxx',
            mono: true,
            keyboard: TextInputType.phone,
            onChanged: (v) => r.pic = v.trim(),
          ),

          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MasRadii.card),
              border: Border.all(color: m.ink150),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              _CheckRow(
                value: r.canShip,
                label: 'Bisa jadi gudang pengirim',
                subtitle:
                    'Dimatikan → stok gudang ini tak pernah dipakai untuk pesanan online.',
                onChanged: (v) => setState(() => r.canShip = v),
              ),
              _CheckRow(
                value: r.selectable,
                label: 'Bisa dipilih pembeli',
                subtitle:
                    'Muncul di daftar lokasi belanja. Perlu Key/Akun cabang untuk routing pesanan.',
                onChanged: (v) => setState(() => r.selectable = v),
              ),
            ]),
          ),

          if (r.selectable) ...[
            const SizedBox(height: 12),
            const MasEyebrow('Key / akun cabang'),
            const SizedBox(height: 6),
            _Field(
              controller: _key[r.label]!,
              hint: 'mis. jakarta',
              mono: true,
              onChanged: (v) => r.key = v.trim().toLowerCase(),
            ),
          ],

          const SizedBox(height: 10),
          Text(
            'Terdekat: ${r.nearest.isEmpty ? "—" : r.nearest.join(" · ")}',
            style: TextStyle(fontSize: 11.5, color: m.ink500),
          ),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════
// 6. Foto Part
// ══════════════════════════════════════════════════════════════════════

class FotoPartScreen extends StatefulWidget {
  const FotoPartScreen({super.key});

  @override
  State<FotoPartScreen> createState() => _FotoPartScreenState();
}

class _FotoPartScreenState extends State<FotoPartScreen> {
  final _ctrl = TextEditingController();

  /// PN yang fotonya sedang ditampilkan (sudah dinormalkan huruf besar).
  String _pn = '';
  List<AdminPhoto> _photos = [];
  bool _loading = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _muat(String pn) async {
    final target = pn.trim().toUpperCase();
    if (target.isEmpty) {
      setState(() => _error = 'Isi Part Number dulu.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final p = await ApiService.adminPhotos(target);
      if (!mounted) return;
      setState(() {
        _pn = target;
        _photos = p;
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

  Future<void> _unggah() async {
    if (_pn.isEmpty) return;
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null || !mounted) return;

    final bytes = await x.readAsBytes();
    if (!mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ApiService.uploadPhoto(pn: _pn, bytes: bytes, filename: x.name);
      if (!mounted) return;
      setState(() => _info = 'Foto diunggah untuk $_pn.');
      await _muat(_pn);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hapus(AdminPhoto p) async {
    final ok = await _confirm(
      context,
      judul: 'Hapus foto?',
      pesan: '"${p.fileName}" akan dihapus permanen dari $_pn.',
      tombol: 'Hapus',
      bahaya: true,
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ApiService.deletePhoto(p.id);
      if (!mounted) return;
      setState(() => _info = 'Foto dihapus.');
      await _muat(_pn);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          'Foto manual melengkapi foto SIMS: dipakai di detail part & jadi bahan '
          'galeri Cari-by-Foto.',
          style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: MasInput(
              controller: _ctrl,
              hint: 'Part Number (mis. WG9925550180)',
              mono: true,
              height: 42,
              action: TextInputAction.search,
              onSubmitted: _muat,
            ),
          ),
          const SizedBox(width: 8),
          MasButton(
            label: 'Muat Foto',
            height: 42,
            onTap: _loading ? null : () => _muat(_ctrl.text),
          ),
        ]),

        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorBox(_error!),
        ],
        if (_info != null) ...[
          const SizedBox(height: 12),
          _InfoBox(_info!),
        ],

        if (_pn.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Text(_pn,
                  style: masMono(
                      size: 14, weight: FontWeight.w700, color: m.ink900)),
            ),
            MasButton(
              label: 'Unggah Foto',
              icon: Icons.add_photo_alternate_outlined,
              height: 38,
              loading: _busy,
              onTap: _busy ? null : _unggah,
            ),
          ]),
          const SizedBox(height: 12),
        ],

        if (_loading)
          const MasSkeleton(height: 220)
        else if (_pn.isEmpty)
          const MasEmpty(
            icon: Icons.photo_library_outlined,
            title: 'Masukkan Part Number',
            subtitle: 'Foto yang sudah diunggah untuk PN itu akan muncul di sini.',
          )
        else if (_photos.isEmpty)
          MasEmpty(
            icon: Icons.image_not_supported_outlined,
            title: 'Belum ada foto',
            subtitle: 'Belum ada foto manual untuk $_pn. Unggah lewat tombol di atas.',
          )
        else
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.82,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [for (final p in _photos) _kartuFoto(m, p)],
          ),
      ],
    );
  }

  Widget _kartuFoto(MasColors m, AdminPhoto p) => Container(
        decoration: BoxDecoration(
          color: m.paper,
          borderRadius: BorderRadius.circular(MasRadii.card),
          border: Border.all(color: m.ink200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.white,
              child: Image.network(
                // Lewat helper: foto http:// / learned:// harus diproksi backend.
                ApiService.partImageUrl(p.storageUrl),
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : Container(color: m.ink50),
                errorBuilder: (_, _, _) => const HatchBox(label: 'gagal dimuat'),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Row(children: [
              Expanded(
                child: Text(p.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: m.ink500)),
              ),
              GestureDetector(
                onTap: _busy ? null : () => _hapus(p),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline_rounded,
                      size: 18, color: m.danger600),
                ),
              ),
            ]),
          ),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════
// 7. Image Index & Catalog BOM
// ══════════════════════════════════════════════════════════════════════

class ImageIndexScreen extends StatefulWidget {
  const ImageIndexScreen({super.key});

  @override
  State<ImageIndexScreen> createState() => _ImageIndexScreenState();
}

class _ImageIndexScreenState extends State<ImageIndexScreen> {
  final _pn = TextEditingController();
  final _bulk = TextEditingController();

  IndexStatusInfo? _status;
  CatalogBomStatus? _bom;
  List<IndexResult> _hasil = [];

  /// Timpa embedding yang sudah ada. Default mati — indexing ulang itu mahal.
  bool _reindex = false;

  bool _loading = true;
  bool _busy = false; // index 1 PN / bulk
  bool _reload = false; // muat ulang galeri
  bool _bomBusy = false; // rebuild BOM
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _muatStatus();
  }

  @override
  void dispose() {
    _pn.dispose();
    _bulk.dispose();
    super.dispose();
  }

  Future<void> _muatStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await ApiService.indexStatus();
      final b = await ApiService.catalogBomStatus();
      if (!mounted) return;
      setState(() {
        _status = s;
        _bom = b;
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

  Future<void> _indexSatu() async {
    final pn = _pn.text.trim().toUpperCase();
    if (pn.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _hasil = [];
    });
    try {
      final r = await ApiService.indexPart(pn, reindex: _reindex);
      if (!mounted) return;
      setState(() => _hasil = [r]);
      await _muatStatus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _indexBulk() async {
    final text = _bulk.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _hasil = [];
    });
    try {
      final r = await ApiService.indexBulk(text, reindex: _reindex);
      if (!mounted) return;
      setState(() => _hasil = r.results);
      await _muatStatus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _muatUlangGaleri() async {
    setState(() {
      _reload = true;
      _error = null;
      _info = null;
    });
    try {
      final r = await ApiService.reloadGallery();
      if (!mounted) return;
      // `ok == false` bukan exception: server membalas 200 dengan alasannya.
      if (!r.ok) {
        setState(() => _error = r.error ?? 'Gagal memuat galeri dari CSV.');
        return;
      }
      setState(() => _info = 'Galeri dimuat ulang: ${thousands(r.total)} foto.');
      await _muatStatus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _reload = false);
    }
  }

  Future<void> _rebuildBom() async {
    final ok = await _confirm(
      context,
      judul: 'Bangun ulang Catalog BOM?',
      pesan: 'Server memindai sheet kategori SEMUA file katalog. Operasi berat '
          '— bisa memakan waktu. Jangan tutup layar ini sampai selesai.',
      tombol: 'Bangun ulang',
    );
    if (!ok || !mounted) return;

    setState(() {
      _bomBusy = true;
      _error = null;
      _info = null;
    });
    try {
      final r = await ApiService.rebuildCatalogBom();
      if (!mounted) return;
      setState(() => _info = 'BOM dibangun ulang: ${r.unitBerkategori} unit · '
          '${r.kategori} kategori · ${r.assyTerindeks} assy · '
          '${thousands(r.totalBarisPart)} baris part (${r.ukuranKb} KB).');
      await _muatStatus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _bomBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final s = _status;
    final b = _bom;

    return RefreshIndicator(
      onRefresh: _muatStatus,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Bangun embedding (DINOv2) dari foto SIMS supaya part bisa ditemukan '
            'lewat Cari by Foto.',
            style: TextStyle(fontSize: 12.5, color: m.ink500, height: 1.5),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBox(_error!),
          ],
          if (_info != null) ...[
            const SizedBox(height: 12),
            _InfoBox(_info!),
          ],

          const SizedBox(height: 14),
          if (_loading && s == null)
            const MasSkeleton(height: 140)
          else if (s != null) ...[
            MasSectionCard(
              title: 'Status indeks',
              children: [
                MasKeyValue(
                  label: 'Total terindeks',
                  value: thousands(s.totalIndexed),
                  mono: true,
                ),
                MasKeyValue(
                  label: 'Pustaka AI (torch)',
                  value: s.torch ? 'tersedia' : 'tidak tersedia',
                  valueColor: s.torch ? m.brand700 : m.danger600,
                ),
                MasKeyValue(
                  label: 'Model',
                  value: s.modelReady ? 'siap' : 'belum dimuat',
                  valueColor: s.modelReady ? m.brand700 : m.warn600,
                ),
                MasKeyValue(
                  label: 'Sumber galeri',
                  value: s.galleryLocal ? 'file CSV (lokal)' : 'database',
                  divider: false,
                ),
              ],
            ),
            if (!s.torch) ...[
              const SizedBox(height: 10),
              // Tanpa torch, semua tombol indeks di bawah pasti gagal.
              const _NoticeBox(
                'Pustaka AI tidak tersedia di server — pengindeksan foto tidak '
                'akan berjalan sampai torch terpasang.',
              ),
            ],
            const SizedBox(height: 10),
            MasButton(
              label: 'Muat Ulang Galeri',
              icon: Icons.refresh_rounded,
              primary: false,
              expand: true,
              height: 40,
              loading: _reload,
              onTap: _reload ? null : _muatUlangGaleri,
            ),
            const SizedBox(height: 6),
            Text('Memuat ulang galeri Cari-by-Foto dari CSV terbaru, tanpa restart server.',
                style: TextStyle(fontSize: 11.5, color: m.ink400)),
          ],

          const SizedBox(height: 18),
          MasCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Catalog BOM',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: m.ink900)),
                const SizedBox(height: 3),
                Text(
                  b == null
                      ? 'Status belum termuat.'
                      : b.available
                          ? 'Terindeks: ${thousands(b.unit)} unit · ${thousands(b.kategori)} kategori.'
                          : 'Belum ada data BOM.',
                  style: TextStyle(fontSize: 12, color: m.ink600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bangun ulang setelah menambah/mengubah katalog, supaya fitur '
                  'banding part per kategori di Asisten AI ikut ter-update.',
                  style:
                      TextStyle(fontSize: 11.5, color: m.ink500, height: 1.45),
                ),
                const SizedBox(height: 10),
                MasButton(
                  label: _bomBusy ? 'Membangun ulang…' : 'Rebuild BOM',
                  icon: Icons.autorenew_rounded,
                  primary: false,
                  expand: true,
                  height: 40,
                  loading: _bomBusy,
                  onTap: _bomBusy ? null : _rebuildBom,
                ),
                if (_bomBusy) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Memindai sheet kategori seluruh file katalog — biarkan layar '
                    'ini terbuka sampai selesai.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: m.ink400),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MasRadii.card),
              border: Border.all(color: m.ink150),
              color: m.paper,
            ),
            clipBehavior: Clip.antiAlias,
            child: _CheckRow(
              value: _reindex,
              label: 'Re-index',
              subtitle:
                  'Timpa embedding yang sudah ada. Mati = foto yang sudah terindeks dilewati (jauh lebih cepat).',
              onChanged: _busy ? null : (v) => setState(() => _reindex = v),
            ),
          ),

          const SizedBox(height: 14),
          const MasEyebrow('Indeks 1 part'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: MasInput(
                controller: _pn,
                hint: 'Part Number',
                mono: true,
                height: 42,
                action: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _indexSatu(),
              ),
            ),
            const SizedBox(width: 8),
            MasButton(
              label: 'Indeks',
              height: 42,
              onTap: (_busy || _pn.text.trim().isEmpty) ? null : _indexSatu,
            ),
          ]),

          const SizedBox(height: 18),
          const MasEyebrow('Indeks massal (maks 50 PN)'),
          const SizedBox(height: 8),
          MasInput(
            controller: _bulk,
            hint: 'WG9925550180\nWG1642230041',
            mono: true,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          MasButton(
            label: _busy ? 'Mengindeks…' : 'Indeks Massal',
            icon: Icons.playlist_add_check_rounded,
            expand: true,
            height: 44,
            loading: _busy,
            onTap: _bulk.text.trim().isEmpty ? null : _indexBulk,
          ),
          if (_busy) ...[
            const SizedBox(height: 8),
            Text(
              'Mengunduh foto SIMS + menghitung embedding di CPU — bisa lambat '
              'untuk banyak foto.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: m.ink400),
            ),
          ],

          if (_hasil.isNotEmpty) ...[
            const SizedBox(height: 18),
            const MasEyebrow('Hasil'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: m.paper,
                borderRadius: BorderRadius.circular(MasRadii.card),
                border: Border.all(color: m.ink150),
                boxShadow: m.shadow1,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [for (final r in _hasil) _barisHasil(m, r)],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _barisHasil(MasColors m, IndexResult r) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: m.ink100)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: Text(r.pn,
                    style: masMono(
                        size: 12.5,
                        weight: FontWeight.w600,
                        color: m.ink900)),
              ),
              MasPill(
                label: r.error != null
                    ? 'gagal'
                    : r.indexed > 0
                        ? '+${r.indexed} terindeks'
                        : 'tidak ada yang baru',
                tone: r.error != null
                    ? MasPillTone.danger
                    : r.indexed > 0
                        ? MasPillTone.brand
                        : MasPillTone.neutral,
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Foto ditemukan ${r.found} · sudah ada ${r.already} · '
              'terindeks ${r.indexed} · gagal ${r.failed}',
              style: TextStyle(fontSize: 11.5, color: m.ink500),
            ),
            if (r.error != null && r.error!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(r.error!,
                  style: TextStyle(fontSize: 11.5, color: m.danger600)),
            ],
          ],
        ),
      );
}
