# GeoRide — AR-Based Real-Time Ride Sharing App
## Agentic Implementation Guide: 3D Map Visuals, GPS Direction Arrows & Glowing Path System

> **Document Purpose:** This guide is structured for autonomous agentic execution. Each section is self-contained with clear prerequisites, implementation steps, file paths, and validation checks. Execute sections in order unless marked `[PARALLEL]`.

---

## Table of Contents

1. [Project Structure & Prerequisites](#1-project-structure--prerequisites)
2. [Module A — Enhanced 3D Map Interface](#2-module-a--enhanced-3d-map-interface)
3. [Module B — 3D Direction Arrow System (GPS-Based)](#3-module-b--3d-direction-arrow-system-gps-based)
4. [Module C — 3D Landmark & Environment Artifacts](#4-module-c--3d-landmark--environment-artifacts)
5. [Module D — Glowing Source-to-Destination Path](#5-module-d--glowing-source-to-destination-path)
6. [Module E — Performance Optimization Layer](#6-module-e--performance-optimization-layer)
7. [Firebase Backend Changes](#7-firebase-backend-changes)
8. [Integration Checklist](#8-integration-checklist)
9. [Validation & Testing Plan](#9-validation--testing-plan)

---

## 1. Project Structure & Prerequisites

### 1.1 Assumed Existing Stack

```
georide/
├── lib/
│   ├── main.dart
│   ├── screens/
│   │   ├── map_screen.dart          ← PRIMARY FILE TO MODIFY
│   │   ├── host_ride_screen.dart
│   │   ├── join_ride_screen.dart
│   │   └── chat_screen.dart
│   ├── services/
│   │   ├── firebase_service.dart
│   │   ├── location_service.dart
│   │   └── ride_service.dart
│   ├── models/
│   │   ├── ride_model.dart
│   │   └── user_model.dart
│   └── widgets/
│       └── scanner_widget.dart
├── android/
├── pubspec.yaml
└── firebase.json
```

### 1.2 Required pubspec.yaml Dependencies

Agent must add/update these in `pubspec.yaml` under `dependencies:`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Maps & Location
  google_maps_flutter: ^2.6.1
  geolocator: ^11.0.0
  geocoding: ^3.0.0

  # 3D Rendering & AR Overlay
  flutter_map: ^6.1.0          # Fallback lightweight map for custom layer
  latlong2: ^0.9.0

  # Direction & Routing
  flutter_polyline_points: ^2.0.0
  google_directions_api: ^0.9.0

  # Animation & Visual Effects
  flutter_animate: ^4.5.0
  animated_text_kit: ^4.2.2
  lottie: ^3.1.0

  # 3D / AR Overlay (Custom Painter based — no native AR required)
  vector_math: ^2.1.4

  # Firebase (existing — verify versions)
  firebase_core: ^2.27.0
  firebase_auth: ^4.17.0
  cloud_firestore: ^4.15.0
  firebase_database: ^10.4.0
  firebase_messaging: ^14.7.0

  # Utilities
  rxdart: ^0.27.7
  provider: ^6.1.2
  http: ^1.2.1
  flutter_dotenv: ^5.1.0
```

Run after updating:
```bash
flutter pub get
```

### 1.3 Google Maps API Keys Required

Agent must verify the following APIs are enabled in Google Cloud Console:
- Maps SDK for Android
- Directions API
- Places API (Nearby Search)
- Roads API (for snapping paths to roads)

Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<meta-data
  android:name="com.google.android.geo.API_KEY"
  android:value="${MAPS_API_KEY}"/>
```

Add to `android/local.properties`:
```
MAPS_API_KEY=YOUR_ACTUAL_KEY_HERE
```

---

## 2. Module A — Enhanced 3D Map Interface

### 2.1 Overview

Upgrade the existing flat Google Maps view to a **tilt-enabled, compass-reactive 3D map** with real-time building extrusion rendering. Performance-optimized using camera throttling and custom marker caching.

### 2.2 File: `lib/services/map_controller_service.dart` (NEW FILE)

Create this file entirely:

```dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapControllerService {
  GoogleMapController? _controller;
  StreamSubscription<Position>? _positionStream;

  // Camera constants for Pokemon GO-style 3D view
  static const double DEFAULT_TILT = 60.0;       // degrees from vertical
  static const double DEFAULT_ZOOM = 18.5;        // street-level
  static const double NAVIGATION_ZOOM = 19.2;     // close-in while navigating
  static const double OVERVIEW_ZOOM = 15.0;       // zoomed out overview
  static const double MAX_TILT = 67.5;
  static const double MIN_TILT = 0.0;

  // Throttle camera updates to max 10fps to prevent jank
  DateTime _lastCameraUpdate = DateTime.now();
  static const int CAMERA_THROTTLE_MS = 100;

  void attach(GoogleMapController controller) {
    _controller = controller;
  }

  void dispose() {
    _positionStream?.cancel();
    _controller?.dispose();
  }

  /// Animate to 3D street-level view centered on user
  Future<void> animateTo3DView(LatLng position, {double? bearing}) async {
    final controller = _controller;
    if (controller == null) return;

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: position,
          zoom: DEFAULT_ZOOM,
          tilt: DEFAULT_TILT,
          bearing: bearing ?? 0.0,
        ),
      ),
    );
  }

  /// Smooth heading-reactive camera — called on compass/gyro updates
  Future<void> updateCameraBearing(LatLng position, double heading) async {
    final now = DateTime.now();
    if (now.difference(_lastCameraUpdate).inMilliseconds < CAMERA_THROTTLE_MS) return;
    _lastCameraUpdate = now;

    final controller = _controller;
    if (controller == null) return;

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: position,
          zoom: NAVIGATION_ZOOM,
          tilt: DEFAULT_TILT,
          bearing: heading,
        ),
      ),
    );
  }

  /// Toggle between 3D street view and top-down overview
  Future<void> toggleOverview(LatLng position, bool isOverview) async {
    final controller = _controller;
    if (controller == null) return;

    if (isOverview) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: position,
            zoom: OVERVIEW_ZOOM,
            tilt: 0,
            bearing: 0,
          ),
        ),
      );
    } else {
      await animateTo3DView(position);
    }
  }

  /// Fit camera to show full path from source to destination
  Future<void> fitPathBounds(List<LatLng> points) async {
    if (points.isEmpty || _controller == null) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    await _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        120.0, // padding in pixels
      ),
    );
  }
}
```

### 2.3 File: `lib/config/map_styles.dart` (NEW FILE)

Custom Google Maps JSON style for high-contrast 3D urban look (dark teal, inspired by tech mobility apps):

```dart
const String kGeoRideMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#0d1b2a"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#8ec5fc"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#0d1b2a"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill",
    "stylers": [{"color": "#d4a574"}]},
  {"featureType": "building", "elementType": "geometry.fill",
    "stylers": [{"color": "#1a2a3a"}]},
  {"featureType": "building", "elementType": "geometry.stroke",
    "stylers": [{"color": "#2a4a6a"}, {"weight": 1.5}]},
  {"featureType": "poi", "elementType": "labels.text.fill",
    "stylers": [{"color": "#f9a826"}]},
  {"featureType": "poi.park", "elementType": "geometry",
    "stylers": [{"color": "#0f2d1a"}]},
  {"featureType": "road", "elementType": "geometry",
    "stylers": [{"color": "#1e3a5f"}]},
  {"featureType": "road", "elementType": "geometry.stroke",
    "stylers": [{"color": "#0a1628"}]},
  {"featureType": "road.arterial", "elementType": "geometry",
    "stylers": [{"color": "#2a5a8a"}]},
  {"featureType": "road.highway", "elementType": "geometry",
    "stylers": [{"color": "#3a7ab5"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke",
    "stylers": [{"color": "#1a4a7a"}]},
  {"featureType": "road.local", "elementType": "labels.text.fill",
    "stylers": [{"color": "#616161"}]},
  {"featureType": "transit", "elementType": "labels.text.fill",
    "stylers": [{"color": "#f9a826"}]},
  {"featureType": "transit.station", "elementType": "geometry",
    "stylers": [{"color": "#1a3a5a"}]},
  {"featureType": "water", "elementType": "geometry",
    "stylers": [{"color": "#0a1a2a"}]},
  {"featureType": "water", "elementType": "labels.text.fill",
    "stylers": [{"color": "#515c6d"}]}
]
''';
```

### 2.4 Modify: `lib/screens/map_screen.dart`

Replace or wrap the existing `GoogleMap` widget with this enhanced configuration:

```dart
// Add these imports at top of map_screen.dart
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/map_styles.dart';
import '../services/map_controller_service.dart';
import '../widgets/direction_arrow_overlay.dart';
import '../widgets/glowing_path_overlay.dart';
import '../widgets/ar_landmark_overlay.dart';

// Inside MapScreenState class — add these fields
final MapControllerService _mapService = MapControllerService();
bool _isOverviewMode = false;
Set<Polyline> _glowingPolylines = {};
Set<Marker> _arMarkers = {};

// Replace GoogleMap widget configuration:
GoogleMap(
  onMapCreated: (controller) async {
    _mapService.attach(controller);
    await controller.setMapStyle(kGeoRideMapStyle);
    await _mapService.animateTo3DView(_currentPosition);
  },
  initialCameraPosition: CameraPosition(
    target: _currentPosition,
    zoom: 18.5,
    tilt: 60.0,
    bearing: 0,
  ),
  mapType: MapType.normal,       // Normal gives best 3D building rendering
  myLocationEnabled: true,
  myLocationButtonEnabled: false, // Custom button used instead
  compassEnabled: true,
  buildingsEnabled: true,         // CRITICAL: enables 3D building extrusion
  indoorViewEnabled: false,
  trafficEnabled: false,          // Disable traffic layer for performance
  zoomControlsEnabled: false,
  rotateGesturesEnabled: true,
  tiltGesturesEnabled: true,
  markers: _arMarkers,
  polylines: _glowingPolylines,
  onCameraMove: (position) {
    // Sync direction arrows with camera bearing
    setState(() => _currentBearing = position.bearing);
  },
),
```

---

## 3. Module B — 3D Direction Arrow System (GPS-Based)

### 3.1 Overview

Custom Flutter `CustomPainter` overlay that renders floating 3D-perspective navigation arrows on top of the map. Arrows point toward the next waypoint in the path, react to GPS heading, and pulse when user is near a turn. Inspired by Google Maps Live View AR arrows.

### 3.2 File: `lib/widgets/direction_arrow_overlay.dart` (NEW FILE)

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vector_math/vector_math.dart' as vm;

class DirectionArrowOverlay extends StatefulWidget {
  final LatLng currentPosition;
  final LatLng nextWaypoint;
  final double currentBearing;     // device compass heading in degrees
  final double distanceToNext;     // meters to next waypoint
  final bool isNavigating;

  const DirectionArrowOverlay({
    Key? key,
    required this.currentPosition,
    required this.nextWaypoint,
    required this.currentBearing,
    required this.distanceToNext,
    required this.isNavigating,
  }) : super(key: key);

  @override
  State<DirectionArrowOverlay> createState() => _DirectionArrowOverlayState();
}

class _DirectionArrowOverlayState extends State<DirectionArrowOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _floatController;
  late Animation<double> _pulseAnim;
  late Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _floatController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _floatAnim = Tween<double>(begin: -8.0, end: 8.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  /// Calculate bearing from current position to next waypoint
  double _calculateBearingToWaypoint() {
    final lat1 = widget.currentPosition.latitude * math.pi / 180;
    final lng1 = widget.currentPosition.longitude * math.pi / 180;
    final lat2 = widget.nextWaypoint.latitude * math.pi / 180;
    final lng2 = widget.nextWaypoint.longitude * math.pi / 180;

    final dLng = lng2 - lng1;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  /// Relative angle from device heading to waypoint
  double _getRelativeAngle() {
    final waypointBearing = _calculateBearingToWaypoint();
    double relative = waypointBearing - widget.currentBearing;
    if (relative > 180) relative -= 360;
    if (relative < -180) relative += 360;
    return relative;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isNavigating) return const SizedBox.shrink();

    final relativeAngle = _getRelativeAngle();
    final isNearTurn = widget.distanceToNext < 30; // within 30 meters

    return Positioned(
      bottom: 160,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseAnim, _floatAnim]),
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _floatAnim.value),
              child: Transform.scale(
                scale: isNearTurn ? _pulseAnim.value : 1.0,
                child: _buildArrow(relativeAngle, isNearTurn),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildArrow(double relativeAngle, bool isNearTurn) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Distance chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isNearTurn ? Colors.orange : const Color(0xFF00E5FF),
              width: 1.5,
            ),
          ),
          child: Text(
            widget.distanceToNext < 1000
                ? '${widget.distanceToNext.toInt()} m'
                : '${(widget.distanceToNext / 1000).toStringAsFixed(1)} km',
            style: TextStyle(
              color: isNearTurn ? Colors.orange : const Color(0xFF00E5FF),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 3D Arrow with rotation
        Transform.rotate(
          angle: relativeAngle * math.pi / 180,
          child: CustomPaint(
            size: const Size(80, 100),
            painter: _Arrow3DPainter(
              isNearTurn: isNearTurn,
              glowIntensity: isNearTurn ? _pulseAnim.value : 1.0,
            ),
          ),
        ),
      ],
    );
  }
}

class _Arrow3DPainter extends CustomPainter {
  final bool isNearTurn;
  final double glowIntensity;

  _Arrow3DPainter({required this.isNearTurn, required this.glowIntensity});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final baseColor = isNearTurn ? Colors.orange : const Color(0xFF00E5FF);

    // Glow shadow layers (outer → inner)
    for (int i = 4; i >= 0; i--) {
      final glowPaint = Paint()
        ..color = baseColor.withOpacity((0.08 + i * 0.05) * glowIntensity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, (i + 1) * 6.0);

      final glowPath = _buildArrowPath(cx, size.height, scale: 1.0 + i * 0.08);
      canvas.drawPath(glowPath, glowPaint);
    }

    // 3D perspective — dark underside
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..style = PaintingStyle.fill;
    canvas.drawPath(_buildArrowPath(cx, size.height, offsetY: 6), shadowPaint);

    // Main arrow gradient fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          baseColor,
          baseColor.withOpacity(0.6),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(_buildArrowPath(cx, size.height), fillPaint);

    // Arrow outline
    final strokePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(_buildArrowPath(cx, size.height), strokePaint);

    // Specular highlight (top-left gleam for 3D look)
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final highlightPath = Path()
      ..moveTo(cx - 10, size.height * 0.55)
      ..lineTo(cx, size.height * 0.1)
      ..lineTo(cx + 8, size.height * 0.45);
    canvas.drawPath(highlightPath, highlightPaint);
  }

  Path _buildArrowPath(double cx, double height, {double scale = 1.0, double offsetY = 0}) {
    final w = 28.0 * scale;
    final h = height * scale;
    return Path()
      ..moveTo(cx, offsetY + h * 0.05)              // tip
      ..lineTo(cx + w, offsetY + h * 0.52)          // right shoulder
      ..lineTo(cx + w * 0.45, offsetY + h * 0.52)   // right notch
      ..lineTo(cx + w * 0.45, offsetY + h * 0.95)   // right tail bottom
      ..lineTo(cx - w * 0.45, offsetY + h * 0.95)   // left tail bottom
      ..lineTo(cx - w * 0.45, offsetY + h * 0.52)   // left notch
      ..lineTo(cx - w, offsetY + h * 0.52)           // left shoulder
      ..close();
  }

  @override
  bool shouldRepaint(_Arrow3DPainter old) =>
      old.isNearTurn != isNearTurn || old.glowIntensity != glowIntensity;
}
```

### 3.3 File: `lib/services/navigation_service.dart` (NEW FILE)

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';

class WaypointStep {
  final LatLng startLocation;
  final LatLng endLocation;
  final String instruction;          // HTML turn instruction
  final double distanceMeters;
  final int durationSeconds;
  final String maneuver;             // "turn-left", "turn-right", "straight", etc.
  final List<LatLng> polylinePoints; // sub-segment decoded points

  WaypointStep({
    required this.startLocation,
    required this.endLocation,
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.maneuver,
    required this.polylinePoints,
  });
}

class NavigationService {
  final String _apiKey = dotenv.env['MAPS_API_KEY'] ?? '';

  List<WaypointStep> _steps = [];
  int _currentStepIndex = 0;

  List<WaypointStep> get steps => _steps;
  WaypointStep? get currentStep =>
      _steps.isNotEmpty && _currentStepIndex < _steps.length
          ? _steps[_currentStepIndex]
          : null;

  LatLng? get nextWaypoint => currentStep?.endLocation;

  /// Fetch route from Google Directions API and parse into steps
  Future<List<LatLng>> fetchRoute({
    required LatLng origin,
    required LatLng destination,
    String mode = 'walking', // walking gives pedestrian paths
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&mode=$mode'
      '&alternatives=false'
      '&key=$_apiKey',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) throw Exception('Directions API error');

    final data = json.decode(response.body);
    if (data['status'] != 'OK') throw Exception('No route: ${data['status']}');

    final route = data['routes'][0];
    final leg = route['legs'][0];
    final List<dynamic> rawSteps = leg['steps'];

    _steps = rawSteps.map((step) {
      return WaypointStep(
        startLocation: LatLng(
          step['start_location']['lat'],
          step['start_location']['lng'],
        ),
        endLocation: LatLng(
          step['end_location']['lat'],
          step['end_location']['lng'],
        ),
        instruction: step['html_instructions'] ?? '',
        distanceMeters: (step['distance']['value'] as num).toDouble(),
        durationSeconds: step['duration']['value'] as int,
        maneuver: step['maneuver'] ?? 'straight',
        polylinePoints: _decodePolyline(step['polyline']['points']),
      );
    }).toList();

    _currentStepIndex = 0;

    // Return full decoded overview polyline
    return _decodePolyline(route['overview_polyline']['points']);
  }

  /// Advance to next step if user is close enough to current waypoint
  void updateProgress(LatLng userPosition) {
    if (currentStep == null) return;
    final dist = Geolocator.distanceBetween(
      userPosition.latitude,
      userPosition.longitude,
      currentStep!.endLocation.latitude,
      currentStep!.endLocation.longitude,
    );
    if (dist < 15.0 && _currentStepIndex < _steps.length - 1) {
      _currentStepIndex++;
    }
  }

  double distanceToNextWaypoint(LatLng userPosition) {
    if (nextWaypoint == null) return 0;
    return Geolocator.distanceBetween(
      userPosition.latitude,
      userPosition.longitude,
      nextWaypoint!.latitude,
      nextWaypoint!.longitude,
    );
  }

  void reset() {
    _steps = [];
    _currentStepIndex = 0;
  }

  /// Decode Google Maps encoded polyline to LatLng list
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
```

---

## 4. Module C — 3D Landmark & Environment Artifacts

### 4.1 Overview

Custom `CustomPainter`-based AR artifact renderer (no native AR SDK required) that places floating 3D icons above key locations: building entrances, transport hubs, ride pickup pins, and rider avatars. Renders perspective-projected icons that shrink with distance.

### 4.2 File: `lib/widgets/ar_landmark_overlay.dart` (NEW FILE)

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum LandmarkType { ridePickup, metroStation, busStop, autoStand, railStation, riderNearby, destination }

class ARLandmark {
  final String id;
  final LatLng position;
  final LandmarkType type;
  final String label;
  final double? distanceMeters;

  const ARLandmark({
    required this.id,
    required this.position,
    required this.type,
    required this.label,
    this.distanceMeters,
  });
}

/// Builds Google Maps custom BitmapDescriptor markers that look like 3D floating cards
/// Agent: Call this in map_screen.dart to replace flat markers with AR-styled markers
class ARMarkerFactory {
  static Color _colorForType(LandmarkType type) {
    switch (type) {
      case LandmarkType.ridePickup: return const Color(0xFF00E5FF);
      case LandmarkType.metroStation: return const Color(0xFF7C4DFF);
      case LandmarkType.busStop: return const Color(0xFFFFD600);
      case LandmarkType.autoStand: return const Color(0xFFFF6D00);
      case LandmarkType.railStation: return const Color(0xFF00E676);
      case LandmarkType.riderNearby: return const Color(0xFFFF4081);
      case LandmarkType.destination: return const Color(0xFFFF1744);
    }
  }

  static IconData _iconForType(LandmarkType type) {
    switch (type) {
      case LandmarkType.ridePickup: return Icons.directions_car;
      case LandmarkType.metroStation: return Icons.subway;
      case LandmarkType.busStop: return Icons.directions_bus;
      case LandmarkType.autoStand: return Icons.electric_rickshaw;
      case LandmarkType.railStation: return Icons.train;
      case LandmarkType.riderNearby: return Icons.person_pin_circle;
      case LandmarkType.destination: return Icons.flag;
    }
  }

  /// Creates a Widget that renders as a floating 3D card — wrap in RepaintBoundary
  /// and convert to BitmapDescriptor using toImage() for use as Google Maps marker
  static Widget buildMarkerWidget(ARLandmark landmark) {
    final color = _colorForType(landmark.type);
    final icon = _iconForType(landmark.type);

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Floating card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1B2A).withOpacity(0.92),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color, width: 2),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.6), blurRadius: 16, spreadRadius: 2),
                  BoxShadow(color: color.withOpacity(0.3), blurRadius: 32, spreadRadius: 4),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        landmark.label,
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      if (landmark.distanceMeters != null)
                        Text(
                          landmark.distanceMeters! < 1000
                              ? '${landmark.distanceMeters!.toInt()} m away'
                              : '${(landmark.distanceMeters! / 1000).toStringAsFixed(1)} km',
                          style: const TextStyle(color: Colors.white60, fontSize: 10),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Connecting stem + base dot
            Container(width: 2, height: 12, color: color.withOpacity(0.7)),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withOpacity(0.8), blurRadius: 8)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 4.3 File: `lib/services/landmark_service.dart` (NEW FILE)

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/ar_landmark_overlay.dart';

class LandmarkService {
  final String _apiKey = dotenv.env['MAPS_API_KEY'] ?? '';

  /// Fetch nearby transport hubs using Google Places Nearby Search
  Future<List<ARLandmark>> fetchNearbyTransportHubs(
    LatLng userPosition, {
    int radiusMeters = 800,
  }) async {
    final landmarks = <ARLandmark>[];

    // Query types mapped to LandmarkType
    final queries = {
      'subway_station': LandmarkType.metroStation,
      'bus_station': LandmarkType.busStop,
      'train_station': LandmarkType.railStation,
    };

    for (final entry in queries.entries) {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=${userPosition.latitude},${userPosition.longitude}'
        '&radius=$radiusMeters'
        '&type=${entry.key}'
        '&key=$_apiKey',
      );

      try {
        final response = await http.get(url);
        if (response.statusCode != 200) continue;

        final data = json.decode(response.body);
        if (data['status'] != 'OK') continue;

        for (final place in data['results'].take(5)) {
          final lat = place['geometry']['location']['lat'];
          final lng = place['geometry']['location']['lng'];
          final pos = LatLng(lat, lng);
          final dist = Geolocator.distanceBetween(
            userPosition.latitude, userPosition.longitude, lat, lng,
          );

          landmarks.add(ARLandmark(
            id: place['place_id'],
            position: pos,
            type: entry.value,
            label: place['name'],
            distanceMeters: dist,
          ));
        }
      } catch (_) {
        // Silently skip failed place queries
      }
    }

    // Sort by distance
    landmarks.sort((a, b) =>
        (a.distanceMeters ?? 9999).compareTo(b.distanceMeters ?? 9999));

    return landmarks;
  }

  /// Auto-rickshaw stands — not in Google Places, use OSM Overpass API
  Future<List<ARLandmark>> fetchAutoStands(LatLng userPosition) async {
    final lat = userPosition.latitude;
    final lng = userPosition.longitude;
    const delta = 0.008; // ~900m bounding box

    final query = '''
[out:json];
node["amenity"="taxi"]["name"~"auto",i]
(${lat - delta},${lng - delta},${lat + delta},${lng + delta});
out body 5;
''';

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: {'data': query},
      );
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      final List<ARLandmark> stands = [];

      for (final element in (data['elements'] as List).take(5)) {
        final pos = LatLng(element['lat'], element['lon']);
        final dist = Geolocator.distanceBetween(
            lat, lng, element['lat'], element['lon']);

        stands.add(ARLandmark(
          id: element['id'].toString(),
          position: pos,
          type: LandmarkType.autoStand,
          label: element['tags']?['name'] ?? 'Auto Stand',
          distanceMeters: dist,
        ));
      }
      return stands;
    } catch (_) {
      return [];
    }
  }
}
```

---

## 5. Module D — Glowing Source-to-Destination Path

### 5.1 Overview

Multi-layer glowing polyline rendered on Google Maps that pulses with animated opacity. Uses the road-snapped decoded polyline from Module B's `NavigationService`. Three layered polylines simulate a neon glow: outer glow (wide, low opacity), mid glow (medium, medium opacity), core line (thin, full opacity, white).

### 5.2 File: `lib/widgets/glowing_path_overlay.dart` (NEW FILE)

```dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GlowingPathBuilder {
  /// Build a set of layered polylines that create a neon glow effect
  /// Returns a Set<Polyline> to pass directly to GoogleMap's polylines param
  static Set<Polyline> buildGlowingPath({
    required List<LatLng> points,
    required Color baseColor,
    String idPrefix = 'georide_path',
    double animationValue = 1.0, // 0.0 to 1.0, drive with AnimationController
  }) {
    if (points.isEmpty) return {};

    return {
      // Layer 1: Outer glow (widest, most transparent)
      Polyline(
        polylineId: PolylineId('${idPrefix}_outer'),
        points: points,
        color: baseColor.withOpacity(0.15 * animationValue),
        width: 24,
        jointType: JointType.round,
        endCap: Cap.roundCap,
        startCap: Cap.roundCap,
      ),
      // Layer 2: Mid glow
      Polyline(
        polylineId: PolylineId('${idPrefix}_mid'),
        points: points,
        color: baseColor.withOpacity(0.35 * animationValue),
        width: 14,
        jointType: JointType.round,
        endCap: Cap.roundCap,
        startCap: Cap.roundCap,
      ),
      // Layer 3: Inner glow
      Polyline(
        polylineId: PolylineId('${idPrefix}_inner'),
        points: points,
        color: baseColor.withOpacity(0.65 * animationValue),
        width: 7,
        jointType: JointType.round,
        endCap: Cap.roundCap,
        startCap: Cap.roundCap,
      ),
      // Layer 4: Core bright line
      Polyline(
        polylineId: PolylineId('${idPrefix}_core'),
        points: points,
        color: Colors.white.withOpacity(0.9 * animationValue),
        width: 3,
        jointType: JointType.round,
        endCap: Cap.roundCap,
        startCap: Cap.roundCap,
      ),
    };
  }

  /// Build a "traveled" segment overlay (already-passed route segment, dimmed)
  static Set<Polyline> buildTraveledPath({
    required List<LatLng> points,
    String idPrefix = 'georide_traveled',
  }) {
    if (points.isEmpty) return {};
    return {
      Polyline(
        polylineId: PolylineId('${idPrefix}_traveled'),
        points: points,
        color: Colors.white.withOpacity(0.2),
        width: 4,
        patterns: [PatternItem.dash(12), PatternItem.gap(8)],
      ),
    };
  }
}
```

### 5.3 Integrate Path Animation into `map_screen.dart`

Add these fields and methods to `MapScreenState`:

```dart
// Add to MapScreenState fields
late AnimationController _pathGlowController;
late Animation<double> _pathGlowAnim;
List<LatLng> _routePoints = [];
final NavigationService _navService = NavigationService();
Color _pathColor = const Color(0xFF00E5FF); // cyan default

@override
void initState() {
  super.initState();
  _pathGlowController = AnimationController(
    duration: const Duration(milliseconds: 1500),
    vsync: this,
  )..repeat(reverse: true);

  _pathGlowAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
    CurvedAnimation(parent: _pathGlowController, curve: Curves.easeInOut),
  );

  _pathGlowAnim.addListener(() {
    if (_routePoints.isNotEmpty) {
      setState(() {
        _glowingPolylines = GlowingPathBuilder.buildGlowingPath(
          points: _routePoints,
          baseColor: _pathColor,
          animationValue: _pathGlowAnim.value,
        );
      });
    }
  });
}

/// Call this when user selects a ride to join — fetches and renders the route
Future<void> _loadRouteToDestination(LatLng destination) async {
  try {
    final currentPos = LatLng(_currentLat, _currentLng); // use actual position fields
    final points = await _navService.fetchRoute(
      origin: currentPos,
      destination: destination,
    );
    setState(() {
      _routePoints = points;
      // Color changes if route goes through a dense area
      _pathColor = const Color(0xFF00E5FF);
    });
  } catch (e) {
    debugPrint('Route fetch failed: $e');
  }
}

@override
void dispose() {
  _pathGlowController.dispose();
  _navService.reset();
  _mapService.dispose();
  super.dispose();
}
```

---

## 6. Module E — Performance Optimization Layer

### 6.1 Overview

The 3D map with multiple overlays can be heavy. This module implements: marker clustering, GPS update throttling, polyline point simplification, and frame-budget-aware rebuilds.

### 6.2 File: `lib/services/performance_service.dart` (NEW FILE)

```dart
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PerformanceService {
  /// Ramer-Douglas-Peucker polyline simplification
  /// epsilon: tolerance in degrees (~0.00001 ≈ 1 meter)
  static List<LatLng> simplifyPolyline(List<LatLng> points, {double epsilon = 0.00005}) {
    if (points.length < 3) return points;

    double maxDist = 0;
    int maxIndex = 0;

    for (int i = 1; i < points.length - 1; i++) {
      final dist = _perpendicularDistance(points[i], points.first, points.last);
      if (dist > maxDist) {
        maxDist = dist;
        maxIndex = i;
      }
    }

    if (maxDist > epsilon) {
      final left = simplifyPolyline(points.sublist(0, maxIndex + 1), epsilon: epsilon);
      final right = simplifyPolyline(points.sublist(maxIndex), epsilon: epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [points.first, points.last];
    }
  }

  static double _perpendicularDistance(LatLng point, LatLng lineStart, LatLng lineEnd) {
    final dx = lineEnd.longitude - lineStart.longitude;
    final dy = lineEnd.latitude - lineStart.latitude;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return 0;
    return ((dy * point.longitude - dx * point.latitude +
            lineEnd.longitude * lineStart.latitude -
            lineEnd.latitude * lineStart.longitude) /
        len).abs();
  }

  /// Only show AR markers within visible map bounds + 20% padding
  static List<T> filterByBounds<T>(
    List<T> items,
    LatLngBounds bounds,
    LatLng Function(T) getPosition,
  ) {
    final latPad = (bounds.northeast.latitude - bounds.southwest.latitude) * 0.2;
    final lngPad = (bounds.northeast.longitude - bounds.southwest.longitude) * 0.2;

    return items.where((item) {
      final pos = getPosition(item);
      return pos.latitude >= bounds.southwest.latitude - latPad &&
          pos.latitude <= bounds.northeast.latitude + latPad &&
          pos.longitude >= bounds.southwest.longitude - lngPad &&
          pos.longitude <= bounds.northeast.longitude + lngPad;
    }).toList();
  }

  /// GPS throttle — only emit position if moved more than threshold meters
  static LatLng? throttlePosition(
    LatLng newPos,
    LatLng? lastPos, {
    double thresholdMeters = 3.0,
  }) {
    if (lastPos == null) return newPos;
    final dx = (newPos.latitude - lastPos.latitude) * 111320;
    final dy = (newPos.longitude - lastPos.longitude) * 111320 * math.cos(lastPos.latitude * math.pi / 180);
    final dist = math.sqrt(dx * dx + dy * dy);
    return dist >= thresholdMeters ? newPos : null;
  }
}
```

---

## 7. Firebase Backend Changes

### 7.1 Firestore Schema Updates

Agent: Add the following collection structure to Firebase Firestore. Do NOT delete existing collections.

**Collection: `routes`** (NEW)
```
routes/{routeId}
  ├── hostUserId: string
  ├── rideId: string (FK to rides collection)
  ├── encodedPolyline: string  (full Google-encoded polyline)
  ├── waypoints: array<{lat: number, lng: number}>
  ├── totalDistanceMeters: number
  ├── totalDurationSeconds: number
  ├── createdAt: timestamp
  └── expiresAt: timestamp
```

**Update collection: `rides`** (EXISTING — add fields)
```
rides/{rideId}
  ├── ... existing fields ...
  ├── destinationLat: number        ← ADD
  ├── destinationLng: number        ← ADD
  ├── originLat: number             ← ADD
  ├── originLng: number             ← ADD
  └── routeId: string (optional)   ← ADD (populated after route fetch)
```

### 7.2 Firebase Realtime Database — Location Update Rate

In `firebase.json` or Realtime Database rules, ensure location nodes use server-side timestamps:

```json
{
  "rules": {
    "user_locations": {
      "$uid": {
        ".write": "$uid === auth.uid",
        ".read": "auth != null",
        ".validate": "newData.hasChildren(['lat', 'lng', 'timestamp', 'bearing'])"
      }
    }
  }
}
```

### 7.3 File: `lib/services/location_service.dart` (UPDATE EXISTING)

Add bearing tracking to existing location service:

```dart
// Add to existing LocationService class

double _lastBearing = 0.0;
LatLng? _lastThrottledPosition;

Stream<Map<String, dynamic>> get locationWithBearingStream {
  return Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,       // only emit if moved 3+ meters
      timeLimit: Duration(seconds: 2),
    ),
  ).map((position) {
    // Compute bearing from velocity if available
    final bearing = position.heading >= 0 ? position.heading : _lastBearing;
    _lastBearing = bearing;

    return {
      'lat': position.latitude,
      'lng': position.longitude,
      'bearing': bearing,
      'speed': position.speed,
      'accuracy': position.accuracy,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  });
}

/// Push location to Firebase Realtime DB for other riders to see
Future<void> pushLocationToFirebase(String userId, Map<String, dynamic> locationData) async {
  // Use existing firebase_database reference pattern in your project
  // Example: FirebaseDatabase.instance.ref('user_locations/$userId').set(locationData);
}
```

---

## 8. Integration Checklist

Agent: Execute each item in order. Check off as complete.

### Step 1 — Dependencies
- [ ] Update `pubspec.yaml` with all packages from Section 1.2
- [ ] Run `flutter pub get`
- [ ] Verify no version conflicts with existing firebase packages

### Step 2 — API Keys & Config
- [ ] Enable Google Directions API in Cloud Console
- [ ] Enable Google Places API in Cloud Console
- [ ] Add `MAPS_API_KEY` to `android/local.properties`
- [ ] Create `.env` file in project root with `MAPS_API_KEY=YOUR_KEY`
- [ ] Add `flutter_dotenv` load in `main.dart`: `await dotenv.load(fileName: '.env');`
- [ ] Add `.env` to `pubspec.yaml` assets section

### Step 3 — New Files (Create in order)
- [ ] `lib/config/map_styles.dart`
- [ ] `lib/services/map_controller_service.dart`
- [ ] `lib/services/navigation_service.dart`
- [ ] `lib/services/landmark_service.dart`
- [ ] `lib/services/performance_service.dart`
- [ ] `lib/widgets/direction_arrow_overlay.dart`
- [ ] `lib/widgets/ar_landmark_overlay.dart`
- [ ] `lib/widgets/glowing_path_overlay.dart`

### Step 4 — Modify Existing Files
- [ ] `lib/screens/map_screen.dart` — apply all modifications from Sections 2.4, 5.3
- [ ] `lib/services/location_service.dart` — add bearing stream from Section 7.3
- [ ] `AndroidManifest.xml` — add API key meta-data

### Step 5 — Firebase
- [ ] Add `routes` collection schema to Firestore
- [ ] Add `destinationLat`, `destinationLng`, `originLat`, `originLng`, `routeId` fields to `rides` documents
- [ ] Update Realtime Database rules from Section 7.2

### Step 6 — Wire Up in MapScreen
- [ ] `MapControllerService` attached in `onMapCreated`
- [ ] `buildingsEnabled: true` set on GoogleMap
- [ ] Map style set via `controller.setMapStyle(kGeoRideMapStyle)`
- [ ] `DirectionArrowOverlay` added to widget stack (use `Stack` wrapping GoogleMap)
- [ ] `GlowingPathBuilder` called in `_pathGlowAnim` listener
- [ ] `LandmarkService` called on location update (throttled to every 2 minutes)
- [ ] `PerformanceService.simplifyPolyline()` applied to route before rendering

### Step 7 — Test Build
- [ ] `flutter build apk --debug`
- [ ] Fix any compilation errors
- [ ] Run on physical Android device (3D buildings only render on device, not emulator)

---

## 9. Validation & Testing Plan

### 9.1 3D Map Visual Tests

| Test | Expected Result | Pass Criteria |
|------|----------------|---------------|
| Launch app on physical device | Map renders in 60° tilt 3D mode | Buildings visible and extruded |
| Rotate device | Map bearing follows device heading | Smooth rotation, <2° lag |
| Pinch zoom in | Buildings get taller in 3D perspective | No visual glitching |
| Toggle overview mode | Flat top-down view | Smooth transition animation |

### 9.2 Direction Arrow Tests

| Test | Expected Result |
|------|----------------|
| Start navigation to a waypoint | Arrow appears floating above map bottom |
| Walk toward waypoint | Arrow stays pointed toward destination |
| Approach within 30m of waypoint | Arrow pulses orange |
| Pass waypoint | Steps advance, arrow repoints |

### 9.3 Glowing Path Tests

| Test | Expected Result |
|------|----------------|
| Select a ride with destination | Cyan glowing path appears from user to destination |
| Path pulsing | Glow opacity breathes 0.6→1.0 every 1.5s |
| Path on dense-building route | Path visible above building footprints |

### 9.4 Performance Targets

| Metric | Target |
|--------|--------|
| Map frame rate | ≥45 fps on Snapdragon 660 |
| GPS update lag | <500ms to UI reflection |
| Route fetch time | <2s on 4G connection |
| AR marker load time | <3s after location obtained |

### 9.5 Edge Cases to Handle

- No internet connection → show cached last route, disable live features, show toast
- GPS unavailable → disable scanner, show location permission prompt
- Directions API quota exceeded → show toast, fall back to straight-line path
- Empty route result (no walkable path) → show alert, suggest transport hub
- Overpass API timeout (auto stands) → silently skip, no crash

---

## Appendix A — Full Widget Stack Layout for MapScreen

Agent: Use this `Stack` layout structure inside `MapScreenState.build()`:

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Stack(
      children: [
        // Layer 1: Base 3D map (always present)
        GoogleMap(/* ... full config from Section 2.4 ... */),

        // Layer 2: Glowing path is rendered as polylines inside GoogleMap widget
        // (already part of GoogleMap via polylines: _glowingPolylines)

        // Layer 3: Direction arrows — only visible during navigation
        if (_isNavigating)
          DirectionArrowOverlay(
            currentPosition: _currentLatLng,
            nextWaypoint: _navService.nextWaypoint ?? _currentLatLng,
            currentBearing: _currentBearing,
            distanceToNext: _navService.distanceToNextWaypoint(_currentLatLng),
            isNavigating: _isNavigating,
          ),

        // Layer 4: Top HUD — compass, mode toggle, scanner status
        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          right: 16,
          child: Column(
            children: [
              _buildCompassButton(),
              const SizedBox(height: 8),
              _buildOverviewToggle(),
            ],
          ),
        ),

        // Layer 5: Bottom action bar — Host Ride, Join Ride
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomActionBar(),
        ),
      ],
    ),
  );
}
```

---

## Appendix B — Key Constants Reference

```dart
// lib/config/app_constants.dart (NEW FILE)

class GeoRideConstants {
  // Map
  static const double mapDefaultTilt = 60.0;
  static const double mapDefaultZoom = 18.5;
  static const double mapNavigationZoom = 19.2;

  // Scanner radius
  static const double scannerRadiusMeters = 500.0;

  // Navigation
  static const double waypointAdvanceThresholdMeters = 15.0;
  static const double nearTurnThresholdMeters = 30.0;

  // Performance
  static const int gpsThrottleMs = 100;
  static const double gpsMinMovementMeters = 3.0;
  static const double polylineSimplificationEpsilon = 0.00005;
  static const int landmarkRefreshIntervalSeconds = 120;

  // Glow
  static const int pathGlowAnimationMs = 1500;

  // Colors
  static const Color primaryCyan = Color(0xFF00E5FF);
  static const Color waypointOrange = Color(0xFFFF6D00);
  static const Color destinationRed = Color(0xFFFF1744);
  static const Color pathGlowColor = Color(0xFF00E5FF);
  static const Color mapDarkBase = Color(0xFF0D1B2A);
}
```

---

*End of GeoRide AR Implementation Guide v1.0 — Prepared for Agentic Execution*
*Generated for: Amity University Mumbai, Department of Computer Science, AY 2025–26*
*Project Guide: Prof. / Dr. Prashant Kumar Shukla*
