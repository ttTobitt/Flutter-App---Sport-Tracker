import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/pitch.dart';
import '../providers/session_provider.dart';
import '../services/pitch_detection.dart';
import '../services/pitch_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common_widgets.dart';

/// Platz aus einer Liste auswählen, wenn die automatische Erkennung keinen
/// oder den falschen gefunden hat.
///
/// Zuerst werden die nächsten Plätze um die Einheit gezeigt (auf dem
/// Luftbild nummeriert). Ist der richtige nicht dabei, kann man nach Verein,
/// Sportanlage oder Ort suchen und bekommt die Plätze dort.
///
/// Gibt `true` zurück, wenn ein Platz gewählt wurde.
class PitchPickerScreen extends StatefulWidget {
  final int sessionId;
  const PitchPickerScreen({super.key, required this.sessionId});

  @override
  State<PitchPickerScreen> createState() => _PitchPickerScreenState();
}

/// Ein Platz in der Liste, mit dem, was der Nutzer zum Entscheiden braucht
class _Choice {
  final PitchCandidate candidate;
  final Pitch pitch;
  final double distanceM; // von der Einheit
  final double share; // Anteil der Laufpunkte auf diesem Platz

  _Choice(this.candidate, this.pitch, this.distanceM, this.share);
}

class _PitchPickerScreenState extends State<PitchPickerScreen> {
  static const _orthoUrl =
      'https://mapsneu.wien.gv.at/basemap/bmaporthofoto30cm/normal/google3857/{z}/{y}/{x}.jpeg';
  static const _maxChoices = 5;

  final _pitchService = PitchService();
  final _mapController = MapController();
  final _searchController = TextEditingController();

  late final List<LatLng> _track;
  late final LatLng _sessionCenter;

  List<_Choice> _choices = [];
  List<PlaceResult>? _places; // Suchergebnisse, null = keine Suche offen
  String? _placeName; // gewählter Suchtreffer, für die Überschrift
  int? _selected;
  bool _loading = false;
  String? _error;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionProvider>().sessionById(
      widget.sessionId,
    );
    _track = [
      for (var i = 0; i < session.points.length; i += 5)
        LatLng(session.points[i].latitude, session.points[i].longitude),
    ];
    _sessionCenter = centroid(session.points);
    _loadPitches(_sessionCenter, radius: 3000);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  LatLng? _lastCenter;
  int _lastRadius = 3000;
  bool _online = false; // wurde schon online nachgesehen?

  /// Plätze um [center] laden, die nächsten [_maxChoices] behalten. Zuerst
  /// aus der Platz-Liste der App, mit [online] über OpenStreetMap-Server.
  Future<void> _loadPitches(
    LatLng center, {
    required int radius,
    bool online = false,
  }) async {
    _lastCenter = center;
    _lastRadius = radius;
    _online = online;
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
    });
    try {
      final candidates = await _pitchService.candidatesAround(
        center,
        radiusInMeters: radius,
        online: online,
      );
      final session = mounted
          ? context.read<SessionProvider>().findSession(widget.sessionId)
          : null;
      if (session == null) return;
      const distance = Distance();
      final sample = [
        for (var i = 0; i < session.points.length; i += 5) session.points[i],
      ];

      final choices = <_Choice>[];
      for (final c in candidates) {
        final pitch = pitchFromPolygon(c.outline);
        if (pitch == null) continue;
        final onPitch = sample
            .where((p) => pitchContains(pitch, p.latitude, p.longitude))
            .length;
        choices.add(
          _Choice(
            c,
            pitch,
            distance(center, LatLng(pitch.centerLat, pitch.centerLon)),
            sample.isEmpty ? 0 : onPitch / sample.length,
          ),
        );
      }
      choices.sort((a, b) => a.distanceM.compareTo(b.distanceM));
      setState(() => _choices = choices.take(_maxChoices).toList());
      _fitMap();
    } on PitchServiceUnavailable catch (e) {
      setState(() => _error = '$e Bitte später nochmal versuchen.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search(String text) async {
    if (text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final places = await _pitchService.searchPlaces(
        text.trim(),
        _sessionCenter,
      );
      setState(() => _places = places);
    } on PitchServiceUnavailable catch (e) {
      setState(() => _error = '$e Bitte später nochmal versuchen.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openPlace(PlaceResult place) {
    setState(() {
      _places = null;
      _placeName = place.title;
    });
    // Sportanlagen sind selten größer als 1 km
    _loadPitches(place.position, radius: 1000);
  }

  /// Karte so zoomen, dass alle Plätze (und der Laufweg) zu sehen sind
  void _fitMap() {
    if (!_mapReady) return;
    final points = [
      for (final c in _choices) ...c.candidate.outline,
      if (_placeName == null) ..._track,
    ];
    if (points.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(32),
        maxZoom: 18,
      ),
    );
  }

  void _select(int i) {
    setState(() => _selected = i);
    final c = _choices[i];
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: c.candidate.outline,
        padding: const EdgeInsets.all(48),
        maxZoom: 19,
      ),
    );
  }

  Future<void> _confirm() async {
    final i = _selected;
    if (i == null) return;
    await context.read<SessionProvider>().assignPitch(
      widget.sessionId,
      _choices[i].pitch,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Platz auswählen')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Verein, Sportanlage oder Ort suchen',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Suchen',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _search(_searchController.text),
                ),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          SizedBox(height: 240, child: _buildMap()),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildList()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected == null ? null : _confirm,
                  child: const Text('Diesen Platz nehmen'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _sessionCenter,
        initialZoom: 15,
        maxZoom: 20,
        onMapReady: () {
          _mapReady = true;
          _fitMap();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _orthoUrl,
          maxNativeZoom: 19,
          userAgentPackageName: 'com.example.sporttrackerflutterapp',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: _track,
              color: Colors.white.withValues(alpha: 0.6),
              strokeWidth: 1.2,
            ),
          ],
        ),
        PolygonLayer(
          polygons: [
            for (var i = 0; i < _choices.length; i++)
              Polygon(
                points: _choices[i].candidate.outline,
                color: (i == _selected ? AppColors.heat : Colors.white)
                    .withValues(alpha: i == _selected ? 0.35 : 0.15),
                borderColor: i == _selected ? AppColors.heat : Colors.white,
                borderStrokeWidth: i == _selected ? 3 : 1.5,
                label: '${i + 1}',
                labelStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  shadows: [Shadow(blurRadius: 3)],
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('Luftbild: basemap.at'),
            TextSourceAttribution('Plätze: © OpenStreetMap-Mitwirkende'),
          ],
        ),
      ],
    );
  }

  Widget _buildList() {
    const muted = TextStyle(fontSize: 13, color: AppColors.textMuted);

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center, style: muted),
        ),
      );
    }

    // Suchergebnisse: erst einen Ort wählen, dann kommen die Plätze dort
    final places = _places;
    if (places != null) {
      if (places.isEmpty && !_loading) {
        return const Center(child: Text('Nichts gefunden.', style: muted));
      }
      return ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SectionLabel('Suchergebnisse'),
          ),
          for (final place in places)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(place.title),
              subtitle: Text(
                place.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _openPlace(place),
            ),
        ],
      );
    }

    if (_loading && _choices.isEmpty) return const SizedBox.shrink();

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SectionLabel(
            _placeName == null
                ? 'Plätze in der Nähe'
                : 'Plätze bei $_placeName',
          ),
        ),
        if (_choices.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Hier ist in OpenStreetMap kein Fußballplatz eingetragen. '
              'Such oben nach dem Verein oder lege den Platz von Hand fest.',
              style: muted,
            ),
          ),
        for (var i = 0; i < _choices.length; i++)
          _ChoiceTile(
            number: i + 1,
            choice: _choices[i],
            selected: i == _selected,
            onTap: () => _select(i),
          ),
        // Die Liste in der App ist ein Stand von einem bestimmten Tag. Ein
        // neu eingetragener Platz fehlt dort, online ist er schon.
        if (!_online && _lastCenter != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: TextButton.icon(
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Nicht dabei? Online nachsehen'),
              onPressed: () =>
                  _loadPitches(_lastCenter!, radius: _lastRadius, online: true),
            ),
          ),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final int number;
  final _Choice choice;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.number,
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = choice.pitch;
    final km = choice.distanceM / 1000;
    final distance = choice.distanceM < 1000
        ? '${choice.distanceM.round()} m entfernt'
        : '${formatNumber(km)} km entfernt';
    final share = (choice.share * 100).round();

    return ListTile(
      selected: selected,
      selectedTileColor: AppColors.heat.withValues(alpha: 0.15),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: selected ? AppColors.heat : AppColors.track,
        foregroundColor: AppColors.ink,
        child: Text(
          '$number',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(choice.candidate.name ?? 'Fußballplatz ohne Namen'),
      subtitle: Text(
        '$distance · ${p.length.round()} × ${p.width.round()} m'
        '${share > 0 ? ' · $share % deiner Punkte' : ''}',
      ),
      onTap: onTap,
    );
  }
}
