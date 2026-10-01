import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/pitch.dart';
import '../providers/session_provider.dart';
import '../services/pitch_detection.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/pitch_view.dart';

/// Platz am Luftbild korrigieren oder von Hand festlegen.
///
/// Bedienidee: Das Spielfeld liegt fest in der Bildschirmmitte und zeigt
/// immer waagrecht. Darunter verschiebt und dreht man das Luftbild, bis die
/// Linien übereinanderliegen. Länge und Breite stellt man mit +/− ein.
/// Das ist am Handy einfacher als kleine Anfasser an den Ecken.
class PitchEditScreen extends StatefulWidget {
  final int sessionId;
  const PitchEditScreen({super.key, required this.sessionId});

  @override
  State<PitchEditScreen> createState() => _PitchEditScreenState();
}

class _PitchEditScreenState extends State<PitchEditScreen> {
  // Luftbild von basemap.at (Österreich, CC BY 4.0, ca. 30 cm pro Pixel)
  static const _orthoUrl =
      'https://mapsneu.wien.gv.at/basemap/bmaporthofoto30cm/normal/google3857/{z}/{y}/{x}.jpeg';

  late final Pitch? _original;
  late final List<LatLng> _track;
  late double _length;
  late double _width;
  late LatLng _initialCenter;
  late double _initialRotation;
  final _mapController = MapController();
  MapCamera? _camera;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionProvider>().sessionById(widget.sessionId);
    _original = session.pitch;
    // Laufweg als Orientierungshilfe, 1 Punkt pro Sekunde reicht
    _track = [
      for (var i = 0; i < session.points.length; i += 5)
        LatLng(session.points[i].latitude, session.points[i].longitude),
    ];

    final p = _original;
    _length = p?.length ?? 100;
    _width = p?.width ?? 64;
    _initialCenter = p == null ? centroid(session.points) : LatLng(p.centerLat, p.centerLon);
    // flutter_map dreht bei positiver rotation im Uhrzeigersinn. Dann zeigt
    // die waagrechte Bildschirmachse genau in Richtung „rotation“ (gegen den
    // Uhrzeigersinn von Osten aus), also wie Pitch.rotationDeg.
    _initialRotation = p?.rotationDeg ?? 0;
  }

  /// Zoom so wählen, dass der Platz ca. 80 % der Bildschirmbreite füllt.
  void _zoomToPitch() {
    final camera = _mapController.camera;
    final screenWidth = camera.nonRotatedSize.x;
    const earthCircumference = 2 * pi * 6378137;
    final metersPerPixel = _length / (0.8 * screenWidth);
    final zoom = log(earthCircumference * cos(_initialCenter.latitude * pi / 180) /
            (256 * metersPerPixel)) /
        ln2;
    _mapController.move(_initialCenter, zoom.clamp(15.0, 20.0));
    setState(() => _camera = _mapController.camera);
  }

  void _save() {
    final camera = _camera;
    if (camera == null) return;
    final corrected = Pitch(
      centerLat: camera.center.latitude,
      centerLon: camera.center.longitude,
      rotationDeg: normalizePitchAngle(camera.rotation),
      length: _length,
      width: _width,
      fromOsm: _original?.fromOsm ?? false,
    );
    context.read<SessionProvider>().setPitch(widget.sessionId, corrected);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_original == null ? 'Platz festlegen' : 'Platz anpassen'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Speichern')),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _initialCenter,
                    initialZoom: 17.5,
                    initialRotation: _initialRotation,
                    maxZoom: 20,
                    minZoom: 15,
                    onMapReady: _zoomToPitch,
                    onPositionChanged: (camera, _) => setState(() => _camera = camera),
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
                          color: Colors.white.withValues(alpha: 0.5),
                          strokeWidth: 1.2,
                        ),
                      ],
                    ),
                    RichAttributionWidget(
                      attributions: [
                        const TextSourceAttribution('Luftbild: basemap.at'),
                        if (_original?.fromOsm ?? false)
                          const TextSourceAttribution('Platz: © OpenStreetMap-Mitwirkende'),
                      ],
                    ),
                  ],
                ),
                // Das Spielfeld darüber. IgnorePointer, damit Wischen und
                // Drehen bei der Karte darunter ankommen.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _PitchOverlayPainter(
                        camera: _camera,
                        length: _length,
                        width: _width,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SizeControls(
            length: _length,
            width: _width,
            onLength: (v) => setState(() => _length = v),
            onWidth: (v) => setState(() => _width = v),
          ),
        ],
      ),
    );
  }
}

/// Zeichnet das Spielfeld in der Bildschirmmitte, im Maßstab der Karte.
class _PitchOverlayPainter extends CustomPainter {
  final MapCamera? camera;
  final double length;
  final double width;

  _PitchOverlayPainter({required this.camera, required this.length, required this.width});

  @override
  void paint(Canvas canvas, Size size) {
    final cam = camera;
    if (cam == null) return;

    // Meter pro Pixel bei der aktuellen Zoomstufe (Web-Mercator, 256-px-Kacheln)
    const earthCircumference = 2 * pi * 6378137;
    final metersPerPixel = earthCircumference *
        cos(cam.center.latitude * pi / 180) /
        (256 * pow(2, cam.zoom));
    final scale = 1 / metersPerPixel; // Pixel pro Meter

    final origin = Offset(
      size.width / 2 - length * scale / 2,
      size.height / 2 - width * scale / 2,
    );
    Offset toPx(Offset m) => origin + m * scale;

    // Leicht abgedunkelte Fläche, damit die Linien auf hellem Rasen sichtbar sind
    canvas.drawRect(
      Rect.fromPoints(toPx(Offset.zero), toPx(Offset(length, width))),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );
    paintPitchMarkings(
      canvas,
      toPx,
      scale,
      length,
      width,
      color: AppColors.heat,
      strokeWidth: 2,
    );
  }

  @override
  bool shouldRepaint(_PitchOverlayPainter old) =>
      old.camera != camera || old.length != length || old.width != width;
}

/// Länge und Breite mit +/− einstellen (1 m Schritte)
class _SizeControls extends StatelessWidget {
  final double length;
  final double width;
  final ValueChanged<double> onLength;
  final ValueChanged<double> onWidth;

  const _SizeControls({
    required this.length,
    required this.width,
    required this.onLength,
    required this.onWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Luftbild verschieben und mit zwei Fingern drehen, bis die '
              'gelben Linien auf den Platzlinien liegen.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Stepper(
                    label: 'Länge',
                    value: length,
                    min: 45,
                    max: 120,
                    onChanged: onLength,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Stepper(
                    label: 'Breite',
                    value: width,
                    min: 25,
                    max: 90,
                    onChanged: onWidth,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        Row(
          children: [
            IconButton(
              tooltip: '$label −1 m',
              onPressed: value > min ? () => onChanged(value.roundToDouble() - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Text(
                '${value.round()} m',
                textAlign: TextAlign.center,
                style: displayStyle(size: 24),
              ),
            ),
            IconButton(
              tooltip: '$label +1 m',
              onPressed: value < max ? () => onChanged(value.roundToDouble() + 1) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
