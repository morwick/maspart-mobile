// lib/screens/pilih_lokasi_screen.dart
// Dua layar terkait lokasi:
//
// • PilihLokasiScreen — pembeli memilih GUDANG tempat dia berbelanja. Stok &
//   harga di etalase di-scope backend ke gudang ini.
// • PilihLokasiPeta   — pemetik ALAMAT KIRIM di peta (padanan MapPicker web,
//   Leaflet + OpenStreetMap → flutter_map, sama-sama tanpa API key).
//   Dibuka sebagai halaman penuh dan mengembalikan [GeoPlace].

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api_service.dart';
import '../app/nav.dart';
import '../theme/mas_theme.dart';
import '../widgets/mas_ui.dart';

// ══════════════════════════════════════════════════════════════════════
// Pilih gudang belanja
// ══════════════════════════════════════════════════════════════════════

class PilihLokasiScreen extends StatefulWidget {
  const PilihLokasiScreen({super.key});

  @override
  State<PilihLokasiScreen> createState() => _PilihLokasiScreenState();
}

class _PilihLokasiScreenState extends State<PilihLokasiScreen> {
  List<BuyerLocation> _locations = [];
  String? _current;
  bool _loading = true;
  String? _saving;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.buyerLocations(),
        ApiService.buyerLocation(),
      ]);
      if (!mounted) return;
      setState(() {
        _locations = results[0] as List<BuyerLocation>;
        _current = (results[1] as ({String? key, String? label})).key;
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

  Future<void> _pick(BuyerLocation loc) async {
    setState(() => _saving = loc.key);
    try {
      await ApiService.setBuyerLocation(loc.key);
      if (!mounted) return;
      setState(() => _current = loc.key);
      final nav = AppNav.of(context);
      nav.toast('Lokasi belanja: ${loc.label}');
      nav.go(MasScreen.toko);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text(
          'Pilih gudang tempat Anda berbelanja. Stok dan ongkir dihitung dari '
          'gudang ini, jadi pilih yang paling dekat dengan alamat kirim Anda.',
          style: TextStyle(fontSize: 12.5, color: m.ink600, height: 1.5),
        ),
        const SizedBox(height: 14),

        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: m.danger50,
              borderRadius: BorderRadius.circular(MasRadii.card),
              border: Border.all(color: m.dangerBorder),
            ),
            child: Text(_error!,
                style: TextStyle(fontSize: 12.5, color: m.danger600)),
          ),
          const SizedBox(height: 14),
        ],

        if (_loading)
          Column(children: [
            for (int i = 0; i < 5; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: MasSkeleton(height: 56),
              ),
          ])
        else if (_locations.isEmpty)
          const MasEmpty(
            icon: Icons.place_outlined,
            title: 'Belum ada gudang',
            subtitle: 'Admin belum menandai gudang mana yang bisa dipilih pembeli.',
          )
        else
          MasSectionCard(
            title: 'Gudang Tersedia',
            children: [
              for (final loc in _locations) _row(m, loc),
            ],
          ),
      ],
    );
  }

  Widget _row(MasColors m, BuyerLocation loc) {
    final active = _current == loc.key;
    final busy = _saving == loc.key;

    return InkWell(
      onTap: busy ? null : () => _pick(loc),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: active ? m.brand50 : null,
          border: Border(bottom: BorderSide(color: m.ink100)),
        ),
        child: Row(children: [
          Icon(
            active
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 19,
            color: active ? m.brand600 : m.ink300,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              loc.label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? m.brand700 : m.ink900,
              ),
            ),
          ),
          if (busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: m.brand600),
            )
          else if (active)
            const MasPill(label: 'Dipakai', tone: MasPillTone.brand, height: 20),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Pemetik alamat di peta
// ══════════════════════════════════════════════════════════════════════

/// Titik awal peta bila pembeli belum punya lokasi: Jakarta.
const _defaultCenter = LatLng(-6.2088, 106.8456);

class PilihLokasiPeta extends StatefulWidget {
  final LatLng? initial;
  const PilihLokasiPeta({super.key, this.initial});

  @override
  State<PilihLokasiPeta> createState() => _PilihLokasiPetaState();
}

class _PilihLokasiPetaState extends State<PilihLokasiPeta> {
  final _mapCtl = MapController();
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  LatLng? _picked;
  GeoPlace? _place;
  bool _resolving = false;
  bool _searching = false;
  List<GeoPlace> _results = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _picked = widget.initial;
      _resolve(widget.initial!);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  /// Koordinat → alamat + kode pos (kode pos inilah yang dipakai hitung ongkir).
  Future<void> _resolve(LatLng p) async {
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final place = await ApiService.geoReverse(p.latitude, p.longitude);
      if (mounted) setState(() => _place = place);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.length < 3) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final r = await ApiService.geoSearch(q);
      if (mounted) setState(() => _results = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectResult(GeoPlace g) {
    final p = LatLng(g.lat, g.lon);
    setState(() {
      _picked = p;
      _place = g;
      _results = [];
      _searchCtl.clear();
    });
    _mapCtl.move(p, 16);
    FocusScope.of(context).unfocus();
  }

  void _tap(LatLng p) {
    setState(() => _picked = p);
    _resolve(p);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.mas;

    return Scaffold(
      backgroundColor: m.canvas,
      appBar: AppBar(
        backgroundColor: m.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Pilih Alamat di Peta',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: m.ink900)),
        iconTheme: IconThemeData(color: m.ink800),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: m.ink150),
        ),
      ),
      body: Column(children: [
        // Cari alamat
        Padding(
          padding: const EdgeInsets.all(12),
          child: MasInput(
            controller: _searchCtl,
            hint: 'Cari alamat, jalan, atau kota…',
            onChanged: _onSearchChanged,
            prefix: _searching
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: m.brand600),
                  )
                : Icon(Icons.search_rounded, size: 18, color: m.ink400),
          ),
        ),

        if (_results.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: m.paper,
              borderRadius: BorderRadius.circular(MasRadii.card),
              border: Border.all(color: m.ink150),
              boxShadow: m.shadow1,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final g = _results[i];
                return ListTile(
                  dense: true,
                  leading:
                      Icon(Icons.place_outlined, size: 18, color: m.ink400),
                  title: Text(
                    g.label.isNotEmpty ? g.label : g.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: m.ink800),
                  ),
                  onTap: () => _selectResult(g),
                );
              },
            ),
          ),

        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _mapCtl,
              options: MapOptions(
                initialCenter: _picked ?? _defaultCenter,
                initialZoom: _picked != null ? 16 : 11,
                onTap: (_, p) => _tap(p),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  // OSM mensyaratkan User-Agent yang mengidentifikasi aplikasi.
                  userAgentPackageName: 'com.example.maspart_mobile',
                ),
                if (_picked != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: _picked!,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.location_on_rounded,
                          size: 40, color: m.brand600),
                    ),
                  ]),
              ],
            ),
            if (_picked == null)
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: m.paper,
                    borderRadius: BorderRadius.circular(MasRadii.card),
                    border: Border.all(color: m.ink150),
                    boxShadow: m.shadow1,
                  ),
                  child: Text(
                    'Ketuk peta untuk menaruh pin di alamat kirim Anda.',
                    style: TextStyle(fontSize: 12.5, color: m.ink600),
                  ),
                ),
              ),
          ]),
        ),

        // Panel hasil + tombol pakai
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          decoration: BoxDecoration(
            color: m.paper,
            border: Border(top: BorderSide(color: m.ink150)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(fontSize: 12.5, color: m.danger600))
                else if (_resolving)
                  Text('Mencari alamat…',
                      style: TextStyle(fontSize: 12.5, color: m.ink500))
                else if (_place != null) ...[
                  Text(
                    _place!.displayName.isNotEmpty
                        ? _place!.displayName
                        : _place!.address,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: m.ink900, height: 1.4),
                  ),
                  if (_place!.postal.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Kode pos ${_place!.postal}',
                        style: masMono(size: 12, color: m.ink500)),
                  ] else ...[
                    const SizedBox(height: 4),
                    // Tanpa kode pos ongkir tak bisa dihitung — katakan terus
                    // terang daripada membiarkan pembeli buntu di checkout.
                    Text(
                      'Kode pos tidak terdeteksi di titik ini — isi manual di keranjang.',
                      style: TextStyle(fontSize: 11.5, color: m.warn600),
                    ),
                  ],
                ] else
                  Text('Belum ada titik dipilih.',
                      style: TextStyle(fontSize: 12.5, color: m.ink500)),
                const SizedBox(height: 12),
                MasButton(
                  label: 'Pakai Alamat Ini',
                  expand: true,
                  onTap: _place == null
                      ? null
                      : () => Navigator.pop(context, _place),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
