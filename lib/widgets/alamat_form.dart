// lib/widgets/alamat_form.dart
// Form satu alamat pengiriman (tambah/ubah) + pemilih kecamatan — cerminan
// `components/AlamatForm.tsx` & `components/WilayahPicker.tsx` di web.
// Dipakai layar Lengkapi Profil dan Profil Saya. Validasi klien menyamai
// `buyer_profile.sanitize_address` di backend supaya pesan muncul sebelum request.

import 'dart:async';

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../screens/pilih_lokasi_screen.dart' show PilihLokasiPeta;
import '../theme/mas_theme.dart';
import 'mas_ui.dart';

const _kLabels = ['Rumah', 'Kantor', 'Gudang'];
const _kLain = '__lain__';

/// Sama persis dengan `validasiAlamat` web. null = valid.
String? validasiAlamat(Alamat b) {
  if (b.namaPenerima.trim().isEmpty) return 'Nama penerima wajib diisi.';
  final tel = b.telepon.replaceAll(RegExp(r'[\s().-]'), '');
  final digits = tel.startsWith('+') ? tel.substring(1) : tel;
  if (!RegExp(r'^\d{8,20}$').hasMatch(digits)) {
    return 'Nomor telepon tidak valid (8–20 digit).';
  }
  if (!RegExp(r'^\d{5}$').hasMatch(b.kodePos.replaceAll(RegExp(r'\D'), ''))) {
    return 'Pilih kecamatan agar kode pos terisi (5 digit).';
  }
  if (b.alamat.trim().length < 8) {
    return 'Alamat lengkap terlalu pendek (nama jalan, nomor, RT/RW).';
  }
  return null;
}

class AlamatForm extends StatefulWidget {
  final Alamat? initial;

  /// Prefill nama/HP dari profil saat alamat pertama.
  final String prefillNama;
  final String prefillTelepon;
  final bool submitting;
  final String submitLabel;

  /// Sembunyikan centang utama (alamat pertama dipaksa utama).
  final bool forceDefault;
  final Future<void> Function(Alamat body) onSubmit;
  final VoidCallback? onCancel;

  const AlamatForm({
    super.key,
    this.initial,
    this.prefillNama = '',
    this.prefillTelepon = '',
    this.submitting = false,
    this.submitLabel = 'Simpan alamat',
    this.forceDefault = false,
    required this.onSubmit,
    this.onCancel,
  });

  @override
  State<AlamatForm> createState() => _AlamatFormState();
}

class _AlamatFormState extends State<AlamatForm> {
  late String _label;
  final _labelLain = TextEditingController();
  final _nama = TextEditingController();
  final _telepon = TextEditingController();
  final _alamat = TextEditingController();
  late _WilayahValue _wilayah;
  late bool _isDefault;
  double? _lat;
  double? _lng;
  bool _cariWilayah = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    final lbl = a?.label ?? 'Rumah';
    if (a != null && lbl.isNotEmpty && !_kLabels.contains(lbl)) {
      _label = _kLain;
      _labelLain.text = lbl;
    } else {
      _label = lbl.isEmpty ? 'Rumah' : lbl;
    }
    _nama.text = (a?.namaPenerima.isNotEmpty ?? false)
        ? a!.namaPenerima
        : widget.prefillNama;
    _telepon.text =
        (a?.telepon.isNotEmpty ?? false) ? a!.telepon : widget.prefillTelepon;
    _alamat.text = a?.alamat ?? '';
    _wilayah = _WilayahValue(
      provinsi: a?.provinsi ?? '',
      kota: a?.kota ?? '',
      kecamatan: a?.kecamatan ?? '',
      kodePos: a?.kodePos ?? '',
    );
    _isDefault = (a?.isDefault ?? false) || widget.forceDefault;
    _lat = a?.lat;
    _lng = a?.lng;
    // Alamat lama dari peta yang tersimpan hanya dengan kode pos → lengkapi.
    if (a != null &&
        a.kodePos.isNotEmpty &&
        a.kecamatan.isEmpty &&
        a.alamat.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _isiWilayahDariPeta(a.alamat, a.kodePos));
    }
  }

  @override
  void dispose() {
    _labelLain.dispose();
    _nama.dispose();
    _telepon.dispose();
    _alamat.dispose();
    super.dispose();
  }

  String get _labelPakai => _label == _kLain
      ? (_labelLain.text.trim().isEmpty ? 'Lainnya' : _labelLain.text.trim())
      : _label;

  Future<void> _submit() async {
    final body = Alamat(
      id: widget.initial?.id ?? 0,
      label: _labelPakai,
      namaPenerima: _nama.text.trim(),
      telepon: _telepon.text.trim(),
      provinsi: _wilayah.provinsi,
      kota: _wilayah.kota,
      kecamatan: _wilayah.kecamatan,
      kodePos: _wilayah.kodePos,
      alamat: _alamat.text.trim(),
      lat: _lat,
      lng: _lng,
      isDefault: widget.forceDefault ? true : _isDefault,
    );
    final salah = validasiAlamat(body);
    if (salah != null) {
      setState(() => _err = salah);
      return;
    }
    setState(() => _err = null);
    await widget.onSubmit(body);
  }

  Future<void> _bukaPeta() async {
    final place = await Navigator.of(context).push<GeoPlace>(
      MaterialPageRoute(builder: (_) => const PilihLokasiPeta()),
    );
    if (place == null || !mounted) return;
    final postal = RegExp(r'^\d{5}$').hasMatch(place.postal) ? place.postal : '';
    final perluWilayah = _wilayah.kecamatan.isEmpty;
    setState(() {
      _lat = place.lat;
      _lng = place.lon;
      final teks =
          place.displayName.isNotEmpty ? place.displayName : place.address;
      if (_alamat.text.trim().isEmpty && teks.isNotEmpty) _alamat.text = teks;
      if (_wilayah.kodePos.isEmpty && postal.isNotEmpty) {
        _wilayah = _wilayah.copyWith(kodePos: postal);
      }
    });
    if (perluWilayah) {
      await _isiWilayahDariPeta(
          place.address.isNotEmpty ? place.address : place.displayName,
          postal);
    }
  }

  /// Titik peta hanya memberi kode pos + teks alamat; kecamatan/kota/provinsi
  /// dicocokkan ke data RajaOngkir (sumber ongkir) di backend. Tak menimpa
  /// kecamatan yang sudah dipilih pembeli sementara permintaan berjalan.
  Future<void> _isiWilayahDariPeta(String teks, String postal) async {
    if (teks.trim().isEmpty) return;
    setState(() => _cariWilayah = true);
    try {
      final w = await ApiService.wilayahDariPeta(teks, postal);
      if (!mounted || w == null || w.kodePos.isEmpty) return;
      if (_wilayah.kecamatan.isNotEmpty) return;
      setState(() => _wilayah = _WilayahValue(
            provinsi: w.provinsi,
            kota: w.kota,
            kecamatan: w.kecamatan,
            kodePos: w.kodePos,
          ));
    } catch (_) {
      // biarkan pembeli memilih kecamatan sendiri
    } finally {
      if (mounted) setState(() => _cariWilayah = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final busy = widget.submitting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _judul(m, 'Label alamat'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final l in [..._kLabels, _kLain])
            _chip(m, l == _kLain ? 'Lainnya' : l, _label == l,
                () => setState(() => _label = l)),
        ]),
        if (_label == _kLain) ...[
          const SizedBox(height: 8),
          MasInput(controller: _labelLain, hint: 'mis. Proyek Cikarang'),
        ],
        const SizedBox(height: 14),
        _judul(m, 'Nama penerima'),
        MasInput(
          controller: _nama,
          hint: 'Nama lengkap',
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          enabled: !busy,
        ),
        const SizedBox(height: 12),
        _judul(m, 'No. HP penerima'),
        MasInput(
          controller: _telepon,
          hint: '0812xxxxxxx',
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          enabled: !busy,
        ),
        const SizedBox(height: 12),
        _WilayahPicker(
          value: _wilayah,
          disabled: busy,
          onChanged: (v) => setState(() => _wilayah = v),
        ),
        if (_cariWilayah)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Mencocokkan kecamatan dari titik peta…',
                style: TextStyle(fontSize: 11.5, color: m.ink400)),
          ),
        const SizedBox(height: 12),
        _judul(m, 'Alamat lengkap'),
        MasInput(
          controller: _alamat,
          hint: 'Nama jalan, nomor, RT/RW, patokan',
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          enabled: !busy,
        ),
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 6,
          children: [
            MasButton(
              label: _lat != null ? 'Ubah titik peta' : 'Tandai di peta (opsional)',
              icon: Icons.place_outlined,
              primary: false,
              height: 36,
              onTap: busy ? null : _bukaPeta,
            ),
            if (_lat != null && _lng != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                    style: TextStyle(fontSize: 11.5, color: m.ink500)),
                TextButton(
                  onPressed: () => setState(() {
                    _lat = null;
                    _lng = null;
                  }),
                  child: const Text('hapus'),
                ),
              ]),
          ],
        ),
        if (!widget.forceDefault)
          CheckboxListTile(
            value: _isDefault,
            onChanged: busy ? null : (v) => setState(() => _isDefault = v ?? false),
            title: Text('Jadikan alamat utama',
                style: TextStyle(fontSize: 13.5, color: m.ink800)),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: m.brand600,
          ),
        if (_err != null) ...[
          const SizedBox(height: 8),
          _galat(m, _err!),
        ],
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (widget.onCancel != null) ...[
            MasButton(
              label: 'Batal',
              primary: false,
              height: 40,
              onTap: busy ? null : widget.onCancel,
            ),
            const SizedBox(width: 8),
          ],
          MasButton(
            label: busy ? 'Menyimpan…' : widget.submitLabel,
            height: 40,
            loading: busy,
            onTap: busy ? null : _submit,
          ),
        ]),
      ],
    );
  }

  Widget _chip(MasColors m, String label, bool aktif, VoidCallback onTap) =>
      Material(
        color: aktif ? m.brand600 : m.paper,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: aktif ? m.brand600 : m.ink300),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: aktif ? Colors.white : m.ink700)),
          ),
        ),
      );
}

Widget _judul(MasColors m, String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(t,
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: m.ink700)),
    );

Widget _galat(MasColors m, String t) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: m.danger50,
        borderRadius: BorderRadius.circular(MasRadii.card),
        border: Border.all(color: m.dangerBorder),
      ),
      child: Text(t, style: TextStyle(fontSize: 12.5, color: m.danger600)),
    );

class _WilayahValue {
  final String provinsi;
  final String kota;
  final String kecamatan;
  final String kodePos;
  const _WilayahValue(
      {this.provinsi = '', this.kota = '', this.kecamatan = '', this.kodePos = ''});

  _WilayahValue copyWith(
          {String? provinsi, String? kota, String? kecamatan, String? kodePos}) =>
      _WilayahValue(
        provinsi: provinsi ?? this.provinsi,
        kota: kota ?? this.kota,
        kecamatan: kecamatan ?? this.kecamatan,
        kodePos: kodePos ?? this.kodePos,
      );
}

/// Pemilih kecamatan/kota/provinsi + kode pos. Sumber = RajaOngkir lewat
/// /api/geo/wilayah — sumber yang SAMA dengan ongkir, jadi kode pos yang dipilih
/// pasti dikenal saat hitung tarif. Bila RajaOngkir belum aktif (manual),
/// beralih ke empat isian bebas.
class _WilayahPicker extends StatefulWidget {
  final _WilayahValue value;
  final ValueChanged<_WilayahValue> onChanged;
  final bool disabled;
  const _WilayahPicker(
      {super.key,
      required this.value,
      required this.onChanged,
      this.disabled = false});

  @override
  State<_WilayahPicker> createState() => _WilayahPickerState();
}

class _WilayahPickerState extends State<_WilayahPicker> {
  final _q = TextEditingController();
  final _prov = TextEditingController();
  final _kota = TextEditingController();
  final _kec = TextEditingController();
  final _pos = TextEditingController();
  Timer? _debounce;
  int _seq = 0;
  List<Wilayah> _rows = [];
  bool _manual = false;
  bool _busy = false;
  String? _err;
  String _lastQ = '';

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_q, _prov, _kota, _kec, _pos]) {
      c.dispose();
    }
    super.dispose();
  }

  void _cari(String teks) {
    _debounce?.cancel();
    final t = teks.trim();
    setState(() => _lastQ = t);
    if (t.length < 3) {
      _seq++; // batalkan hasil pencarian yang masih di jalan
      setState(() {
        _rows = [];
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final my = ++_seq;
      setState(() {
        _busy = true;
        _err = null;
      });
      try {
        final r = await ApiService.searchWilayah(t);
        if (!mounted || my != _seq) return;
        if (r.manual) {
          _masukManual();
          return;
        }
        setState(() {
          _rows = r.results;
          _err = r.error;
        });
      } on ApiException catch (e) {
        if (mounted && my == _seq) setState(() => _err = e.message);
      } finally {
        if (mounted && my == _seq) setState(() => _busy = false);
      }
    });
  }

  void _masukManual() {
    final v = widget.value;
    _prov.text = v.provinsi;
    _kota.text = v.kota;
    _kec.text = v.kecamatan;
    _pos.text = v.kodePos;
    setState(() {
      _manual = true;
      _busy = false;
    });
  }

  void _kirimManual() => widget.onChanged(_WilayahValue(
        provinsi: _prov.text,
        kota: _kota.text,
        kecamatan: _kec.text,
        kodePos: _pos.text.trim(),
      ));

  @override
  Widget build(BuildContext context) {
    final m = context.mas;
    final v = widget.value;

    if (_manual) {
      Widget isian(String label, TextEditingController c,
              {TextInputType? kb}) =>
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _judul(m, label),
                  MasInput(
                    controller: c,
                    hint: label,
                    keyboardType: kb,
                    enabled: !widget.disabled,
                    onChanged: (_) => _kirimManual(),
                  ),
                ]),
          );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        isian('Provinsi', _prov),
        isian('Kota/Kabupaten', _kota),
        isian('Kecamatan', _kec),
        isian('Kode pos', _pos, kb: TextInputType.number),
      ]);
    }

    final terisi =
        v.kecamatan.isNotEmpty || v.kota.isNotEmpty || v.kodePos.isNotEmpty;
    final ringkas = [v.kecamatan, v.kota, v.provinsi]
        .where((e) => e.isNotEmpty)
        .join(', ');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _judul(m, 'Kecamatan / Kota'),
      if (terisi)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: m.ink50,
            borderRadius: BorderRadius.circular(MasRadii.input),
            border: Border.all(color: m.ink300),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      ringkas.isEmpty
                          ? 'Kecamatan belum dipilih — ketuk Ganti'
                          : ringkas,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: ringkas.isEmpty ? m.warn600 : m.ink900)),
                  const SizedBox(height: 2),
                  Text('Kode pos ${v.kodePos.isEmpty ? '—' : v.kodePos}',
                      style: TextStyle(fontSize: 11.5, color: m.ink500)),
                ],
              ),
            ),
            if (!widget.disabled)
              MasButton(
                label: 'Ganti',
                primary: false,
                height: 32,
                onTap: () {
                  _q.clear();
                  setState(() {
                    _rows = [];
                    _lastQ = '';
                  });
                  widget.onChanged(const _WilayahValue());
                },
              ),
          ]),
        )
      else ...[
        MasInput(
          controller: _q,
          hint: 'Ketik nama kecamatan atau kota, mis. Kelapa Gading',
          enabled: !widget.disabled,
          autocorrect: false,
          onChanged: _cari,
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Mencari…',
                style: TextStyle(fontSize: 11.5, color: m.ink400)),
          ),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_err!,
                style: TextStyle(fontSize: 11.5, color: m.danger600)),
          ),
        if (_rows.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: m.paper,
              borderRadius: BorderRadius.circular(MasRadii.card),
              border: Border.all(color: m.ink200),
              boxShadow: m.shadow2,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _rows.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: m.ink150),
              itemBuilder: (_, i) {
                final r = _rows[i];
                final atas = [r.kelurahan, r.kecamatan]
                    .where((e) => e.isNotEmpty)
                    .join(', ');
                final bawah =
                    [r.kota, r.provinsi].where((e) => e.isNotEmpty).join(', ');
                return InkWell(
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    _q.clear();
                    setState(() {
                      _rows = [];
                      _lastQ = '';
                    });
                    widget.onChanged(_WilayahValue(
                      provinsi: r.provinsi,
                      kota: r.kota,
                      kecamatan: r.kecamatan,
                      kodePos: r.kodePos,
                    ));
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(atas.isEmpty ? r.label : atas,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: m.ink900)),
                        Text('$bawah · ${r.kodePos}',
                            style: TextStyle(fontSize: 11.5, color: m.ink500)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (!_busy && _err == null && _rows.isEmpty && _lastQ.length >= 3)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Tidak ditemukan — coba nama kecamatan atau kode pos.',
                style: TextStyle(fontSize: 11.5, color: m.ink400)),
          ),
      ],
    ]);
  }
}
