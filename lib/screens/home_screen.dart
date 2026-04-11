import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================================================
// SHARING POINT MODEL (inline per architecture rules)
// ============================================================================

class SharingPoint {
  final String id;
  final String creatorId;
  final double lat;
  final double lng;
  final String destination;
  final int seatsAvailable;
  final int totalSeats;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> passengers;

  SharingPoint({
    required this.id, required this.creatorId, required this.lat,
    required this.lng, required this.destination, required this.seatsAvailable,
    required this.totalSeats, required this.status, required this.createdAt,
    required this.expiresAt, required this.passengers,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isVisible => status == 'active' && !isExpired && seatsAvailable > 0;

  Duration get timeRemaining =>
      isExpired ? Duration.zero : expiresAt.difference(DateTime.now());

  String get timeRemainingText {
    if (isExpired) return 'Expired';
    return '${timeRemaining.inMinutes}m ${timeRemaining.inSeconds % 60}s';
  }

  factory SharingPoint.fromMap(String docId, Map<String, dynamic> map) {
    final now = DateTime.now();
    final createdAt = (map['createdAt'] as Timestamp?)?.toDate() ?? now;
    final expiresAt = (map['expiresAt'] as Timestamp?)?.toDate() ??
        createdAt.add(const Duration(minutes: 30));
    return SharingPoint(
      id: docId, creatorId: map['creatorId'] ?? '',
      lat: (map['lat'] ?? 0.0).toDouble(),
      lng: (map['lng'] ?? 0.0).toDouble(),
      destination: map['destination'] ?? '',
      seatsAvailable: map['seatsAvailable'] ?? 0,
      totalSeats: map['totalSeats'] ?? map['seatsAvailable'] ?? 0,
      status: map['status'] ?? 'active',
      createdAt: createdAt, expiresAt: expiresAt,
      passengers: List<String>.from(map['passengers'] ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
    'creatorId': creatorId, 'lat': lat, 'lng': lng,
    'destination': destination, 'seatsAvailable': seatsAvailable,
    'totalSeats': totalSeats, 'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
    'expiresAt': Timestamp.fromDate(expiresAt),
    'passengers': passengers,
  };
}

// ============================================================================
// HOME SCREEN — Phase 1 + 2 + 3: Map + Avatar + Hosting + Portals
// ============================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // Map state
  // ---------------------------------------------------------------------------
  MapLibreMapController? _mapController;
  bool _isMapReady = false;
  bool _is3DMode = true;
  double _currentZoom = 16.0;
  String? _mapStyleJson;
  bool _imagesRegistered = false;

  // ---------------------------------------------------------------------------
  // GPS state
  // ---------------------------------------------------------------------------
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSub;
  final List<Position> _positionBuffer = [];

  // ---------------------------------------------------------------------------
  // Camera debounce
  // ---------------------------------------------------------------------------
  DateTime? _lastCameraAnimateTime;
  static const _minAnimateInterval = Duration(seconds: 2);

  // ---------------------------------------------------------------------------
  // Avatar Symbol (geo-anchored on the map)
  // ---------------------------------------------------------------------------
  Symbol? _avatarSymbol;
  bool _avatarCreated = false;

  // ---------------------------------------------------------------------------
  // Loading state
  // ---------------------------------------------------------------------------
  bool _isLoading = true;
  String _loadingMessage = 'Getting your location...';

  // ---------------------------------------------------------------------------
  // Phase 2: Ride hosting state
  // ---------------------------------------------------------------------------
  bool _isCreatingRide = false;

  // ---------------------------------------------------------------------------
  // Phase 3: Portal rendering state
  // ---------------------------------------------------------------------------
  List<SharingPoint> _activeRides = [];
  final Map<String, Symbol> _portalSymbols = {};
  StreamSubscription<QuerySnapshot>? _ridesStreamSub;
  bool _pendingPortalUpdate = false;
  Timer? _expiryTimer;

  // ---------------------------------------------------------------------------
  // Phase 5: Navigation & HUD state
  // ---------------------------------------------------------------------------
  SharingPoint? _myCurrentRide;
  Line? _routeLine;
  Position? _lastRouteFetchPosition;
  bool _isFetchingRoute = false;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _initLocation();
    _startRidesStream();
    _startExpiryTimer();
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _ridesStreamSub?.cancel();
    _expiryTimer?.cancel();
    if (_mapController != null) {
      _mapController!.onSymbolTapped.remove(_onSymbolTapped);
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // LOAD MAP STYLE
  // ---------------------------------------------------------------------------
  Future<void> _loadMapStyle() async {
    try {
      final response = await http.get(
        Uri.parse('https://tiles.openfreemap.org/styles/liberty'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final styleMap = jsonDecode(response.body) as Map<String, dynamic>;
        _applyPokemonGoTheme(styleMap);
        setState(() => _mapStyleJson = jsonEncode(styleMap));
        debugPrint('✅ Remote style loaded & themed');
      } else {
        setState(() => _mapStyleJson = 'https://tiles.openfreemap.org/styles/liberty');
      }
    } catch (e) {
      debugPrint('⚠️ Could not fetch remote style: $e');
      setState(() => _mapStyleJson = 'https://tiles.openfreemap.org/styles/liberty');
    }
  }

  void _applyPokemonGoTheme(Map<String, dynamic> style) {
    final layers = style['layers'] as List<dynamic>? ?? [];
    for (final layer in layers) {
      final id = layer['id'] as String? ?? '';
      final paint = layer['paint'] as Map<String, dynamic>?;
      if (paint == null) continue;

      if (id == 'background') {
        paint['background-color'] = '#81c784';
      } else if (id == 'park') {
        paint['fill-color'] = '#4caf50';
        paint['fill-opacity'] = 0.6;
      } else if (id.contains('wood')) {
        paint['fill-color'] = '#388e3c';
        paint['fill-opacity'] = 0.4;
      } else if (id.contains('grass')) {
        paint['fill-color'] = '#66bb6a';
        paint['fill-opacity'] = 0.5;
      } else if (id == 'water') {
        paint['fill-color'] = '#42a5f5';
      } else if (id.contains('waterway')) {
        paint['line-color'] = '#42a5f5';
      } else if (id.contains('sand')) {
        paint['fill-color'] = '#ffe082';
      } else if (id == 'building-3d') {
        paint['fill-extrusion-color'] = '#e0e0e0';
        paint['fill-extrusion-opacity'] = 0.85;
      } else if (id == 'building') {
        paint['fill-color'] = '#e0e0e0';
      }
    }
  }

  // ---------------------------------------------------------------------------
  // LOCATION INIT
  // ---------------------------------------------------------------------------
  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _loadingMessage = 'Please enable location services');
        await Future.delayed(const Duration(seconds: 2));
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          setState(() {
            _loadingMessage = 'Location services are disabled';
            _isLoading = false;
          });
          return;
        }
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _loadingMessage = 'Location permission denied';
            _isLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loadingMessage = 'Location permission permanently denied.\nPlease enable in Settings.';
          _isLoading = false;
        });
        return;
      }

      setState(() => _loadingMessage = 'Acquiring GPS fix...');
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      setState(() {
        _currentPosition = position;
        _isLoading = false;
      });
      _positionBuffer.add(position);
      _startPositionStream();
    } catch (e) {
      debugPrint('❌ Location error: $e');
      setState(() {
        _loadingMessage = 'Failed to get location: $e';
        _isLoading = false;
      });
    }
  }

  void _startPositionStream() {
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      _onPositionUpdate,
      onError: (e) => debugPrint('❌ Position stream error: $e'),
    );
  }

  // ---------------------------------------------------------------------------
  // POSITION UPDATE + SMOOTHING
  // ---------------------------------------------------------------------------
  void _onPositionUpdate(Position pos) {
    _positionBuffer.add(pos);
    if (_positionBuffer.length > 3) _positionBuffer.removeAt(0);

    Position smoothed = pos;
    if (_positionBuffer.length >= 3) {
      final first = _positionBuffer.first;
      final last = _positionBuffer.last;
      final spread = Geolocator.distanceBetween(
        first.latitude, first.longitude,
        last.latitude, last.longitude,
      );
      if (spread < 100) {
        double avgLat = 0, avgLng = 0;
        for (final p in _positionBuffer) {
          avgLat += p.latitude;
          avgLng += p.longitude;
        }
        avgLat /= _positionBuffer.length;
        avgLng /= _positionBuffer.length;
        smoothed = Position(
          latitude: avgLat, longitude: avgLng,
          timestamp: pos.timestamp, accuracy: pos.accuracy,
          altitude: pos.altitude, altitudeAccuracy: pos.altitudeAccuracy,
          heading: pos.heading, headingAccuracy: pos.headingAccuracy,
          speed: pos.speed, speedAccuracy: pos.speedAccuracy,
        );
      }
    }

    setState(() => _currentPosition = smoothed);
    _updateAvatarPosition(smoothed);
    _animateCameraToPosition(smoothed);

    if (_myCurrentRide != null && _myCurrentRide!.creatorId != FirebaseAuth.instance.currentUser?.uid) {
      _checkAndFetchRoute(_myCurrentRide!);
    }
  }

  // ---------------------------------------------------------------------------
  // AVATAR IMAGE GENERATION
  // ---------------------------------------------------------------------------
  Future<Uint8List> _generateAvatarImage() async {
    const double imgSize = 192;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(imgSize / 2, imgSize / 2);
    final coreRadius = imgSize * 0.28;

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00E5FF).withValues(alpha: 0.3),
          const Color(0xFF00BCD4).withValues(alpha: 0.1),
          Colors.transparent,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: imgSize * 0.45));
    canvas.drawCircle(center, imgSize * 0.45, glowPaint);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + coreRadius * 0.5),
        width: coreRadius * 2.2, height: coreRadius * 0.6,
      ),
      shadowPaint,
    );

    final borderPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(center, coreRadius + 4, borderPaint);

    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: const [Color(0xFF4DD0E1), Color(0xFF00ACC1), Color(0xFF00838F)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius, corePaint);

    final highlightPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withValues(alpha: 0.6), Colors.white.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(
        center: Offset(center.dx - coreRadius * 0.25, center.dy - coreRadius * 0.3),
        radius: coreRadius * 0.55,
      ));
    canvas.drawCircle(
      Offset(center.dx - coreRadius * 0.25, center.dy - coreRadius * 0.3),
      coreRadius * 0.55, highlightPaint,
    );

    final personPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx, center.dy - coreRadius * 0.18), coreRadius * 0.22, personPaint);
    final bodyPath = Path();
    final bodyTop = center.dy + coreRadius * 0.05;
    final bodyWidth = coreRadius * 0.55;
    bodyPath.moveTo(center.dx - bodyWidth / 2, bodyTop + coreRadius * 0.35);
    bodyPath.quadraticBezierTo(center.dx - bodyWidth / 2, bodyTop, center.dx, bodyTop);
    bodyPath.quadraticBezierTo(center.dx + bodyWidth / 2, bodyTop, center.dx + bodyWidth / 2, bodyTop + coreRadius * 0.35);
    bodyPath.close();
    canvas.drawPath(bodyPath, personPaint);

    final arrowPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final arrowPath = Path();
    arrowPath.moveTo(center.dx, center.dy - coreRadius - 14);
    arrowPath.lineTo(center.dx - 10, center.dy - coreRadius + 3);
    arrowPath.lineTo(center.dx + 10, center.dy - coreRadius + 3);
    arrowPath.close();
    canvas.drawPath(arrowPath, arrowPaint);
    canvas.drawPath(arrowPath, Paint()..color = const Color(0xFF006064)..style = PaintingStyle.stroke..strokeWidth = 2);

    final picture = recorder.endRecording();
    final image = await picture.toImage(imgSize.toInt(), imgSize.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // ---------------------------------------------------------------------------
  // PORTAL IMAGE GENERATION (Phase 3)
  // ---------------------------------------------------------------------------
  Future<Uint8List> _generatePortalImage() async {
    const double imgSize = 160;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(imgSize / 2, imgSize / 2);
    final coreRadius = imgSize * 0.25;

    // Outer glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF9800).withValues(alpha: 0.4),
          const Color(0xFFFF5722).withValues(alpha: 0.15),
          Colors.transparent,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: imgSize * 0.45));
    canvas.drawCircle(center, imgSize * 0.45, glowPaint);

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + coreRadius * 0.5),
        width: coreRadius * 2.0, height: coreRadius * 0.5,
      ),
      shadowPaint,
    );

    // White border
    canvas.drawCircle(center, coreRadius + 4, Paint()..color = Colors.white..style = PaintingStyle.fill);

    // Orange gradient core
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: const [Color(0xFFFFB74D), Color(0xFFFF9800), Color(0xFFE65100)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius, corePaint);

    // Highlight
    final hlPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withValues(alpha: 0.5), Colors.white.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(
        center: Offset(center.dx - coreRadius * 0.2, center.dy - coreRadius * 0.25),
        radius: coreRadius * 0.5,
      ));
    canvas.drawCircle(
      Offset(center.dx - coreRadius * 0.2, center.dy - coreRadius * 0.25),
      coreRadius * 0.5, hlPaint,
    );

    // Car icon (simple shape)
    final carPaint = Paint()..color = Colors.white.withValues(alpha: 0.95)..style = PaintingStyle.fill;
    // Car body
    final carBody = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(center.dx, center.dy + 2), width: coreRadius * 0.8, height: coreRadius * 0.4),
      Radius.circular(coreRadius * 0.1),
    );
    canvas.drawRRect(carBody, carPaint);
    // Car top (roof)
    final roofPath = Path();
    roofPath.moveTo(center.dx - coreRadius * 0.25, center.dy + 2 - coreRadius * 0.2);
    roofPath.lineTo(center.dx - coreRadius * 0.15, center.dy - coreRadius * 0.15);
    roofPath.lineTo(center.dx + coreRadius * 0.15, center.dy - coreRadius * 0.15);
    roofPath.lineTo(center.dx + coreRadius * 0.25, center.dy + 2 - coreRadius * 0.2);
    roofPath.close();
    canvas.drawPath(roofPath, carPaint);

    // Pulse ring indicator at top
    final topArrowPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final topPath = Path();
    topPath.moveTo(center.dx, center.dy - coreRadius - 12);
    topPath.lineTo(center.dx - 8, center.dy - coreRadius + 2);
    topPath.lineTo(center.dx + 8, center.dy - coreRadius + 2);
    topPath.close();
    canvas.drawPath(topPath, topArrowPaint);
    canvas.drawPath(topPath, Paint()..color = const Color(0xFFE65100)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    final picture = recorder.endRecording();
    final image = await picture.toImage(imgSize.toInt(), imgSize.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // ---------------------------------------------------------------------------
  // REGISTER IMAGES ON MAP
  // ---------------------------------------------------------------------------
  Future<void> _registerMarkerImages() async {
    if (_mapController == null || _imagesRegistered) return;
    try {
      final avatarBytes = await _generateAvatarImage();
      await _mapController!.addImage('avatar-icon', avatarBytes);

      final portalBytes = await _generatePortalImage();
      await _mapController!.addImage('portal-icon', portalBytes);

      _imagesRegistered = true;
      debugPrint('✅ Avatar + Portal images registered');

      // Retry pending portal updates now that images are registered
      if (_pendingPortalUpdate) {
        _pendingPortalUpdate = false;
        await _updatePortalSymbols();
      }
    } catch (e) {
      debugPrint('❌ Failed to register images: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // CREATE / UPDATE AVATAR SYMBOL
  // ---------------------------------------------------------------------------
  Future<void> _createAvatarSymbol() async {
    if (_mapController == null || !_imagesRegistered || _currentPosition == null) return;
    if (_avatarCreated) return;

    try {
      _avatarSymbol = await _mapController!.addSymbol(SymbolOptions(
        geometry: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        iconImage: 'avatar-icon',
        iconSize: 0.55,
        iconAnchor: 'center',
      ));
      _avatarCreated = true;
      debugPrint('✅ Avatar symbol placed');
    } catch (e) {
      debugPrint('❌ Failed to create avatar symbol: $e');
    }
  }

  Future<void> _updateAvatarPosition(Position pos) async {
    if (_mapController == null || _avatarSymbol == null) return;
    try {
      await _mapController!.updateSymbol(
        _avatarSymbol!,
        SymbolOptions(geometry: LatLng(pos.latitude, pos.longitude)),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to update avatar position: $e');
    }
  }

  // ===========================================================================
  // PHASE 3: PORTAL RENDERING
  // ===========================================================================

  /// Start listening to active rides from Firestore
  void _startRidesStream() {
    _ridesStreamSub = FirebaseFirestore.instance
        .collection('sharing_points')
        .where('status', whereIn: ['active', 'full'])
        .snapshots()
        .listen(
      (snapshot) {
        final rides = snapshot.docs
            .map((doc) => SharingPoint.fromMap(doc.id, doc.data()))
            .where((ride) => !ride.isExpired)
            .toList();

        final user = FirebaseAuth.instance.currentUser;
        SharingPoint? myRide;
        if (user != null) {
          try {
            myRide = rides.firstWhere((r) => r.creatorId == user.uid || r.passengers.contains(user.uid));
          } catch (_) {}
        }

        setState(() {
          _activeRides = rides;
          _myCurrentRide = myRide;
        });
        
        _updatePortalSymbols();
        
        if (myRide == null && _routeLine != null) {
          _clearRoute();
        } else if (myRide != null && !myRide.isExpired && myRide.creatorId != user?.uid) {
          _checkAndFetchRoute(myRide);
        }

        debugPrint('📡 Rides stream: ${rides.length} active rides');
      },
      onError: (e) => debugPrint('❌ Rides stream error: $e'),
    );
  }

  /// Start a timer that checks for expired rides every 30s
  void _startExpiryTimer() {
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      // Remove expired rides from the list and update symbols
      final before = _activeRides.length;
      _activeRides.removeWhere((ride) => ride.isExpired);
      if (_activeRides.length != before) {
        debugPrint('⏰ Expiry check: removed ${before - _activeRides.length} expired rides');
        _updatePortalSymbols();
        setState(() {}); // Refresh UI
      }

      // Also mark expired rides as 'expired' in Firestore
      _cleanUpExpiredRides();
    });
  }

  /// Mark expired rides as 'expired' in Firestore (host's rides only)
  Future<void> _cleanUpExpiredRides() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final query = await FirebaseFirestore.instance
          .collection('sharing_points')
          .where('creatorId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'active')
          .get();

      for (final doc in query.docs) {
        final ride = SharingPoint.fromMap(doc.id, doc.data());
        if (ride.isExpired) {
          await doc.reference.update({'status': 'expired'});
          debugPrint('🗑️ Marked ride ${doc.id} as expired');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Expiry cleanup error: $e');
    }
  }

  /// Update portal symbols on the map (deferred pattern)
  Future<void> _updatePortalSymbols() async {
    if (_mapController == null || !_isMapReady || !_imagesRegistered) {
      _pendingPortalUpdate = true; // Will retry when ready
      return;
    }
    _pendingPortalUpdate = false;

    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUid = currentUser?.uid ?? '';

    // Determine which ride IDs should be visible
    final visibleIds = <String>{};
    for (final ride in _activeRides) {
      if (ride.isVisible || ride.status == 'full') {
        // Don't show portal for the creator's own ride (they see it via Host panel later)
        // Actually, show all portals so everyone can see them
        visibleIds.add(ride.id);
      }
    }

    // Remove symbols for rides that are no longer active
    final toRemove = _portalSymbols.keys.where((id) => !visibleIds.contains(id)).toList();
    for (final id in toRemove) {
      try {
        await _mapController!.removeSymbol(_portalSymbols[id]!);
      } catch (_) {
        // May already be removed
      }
      _portalSymbols.remove(id);
    }

    // Add/update symbols for active rides
    for (final ride in _activeRides) {
      if (!visibleIds.contains(ride.id)) continue;

      if (_portalSymbols.containsKey(ride.id)) {
        // Symbol exists → update position (in case data changed)
        try {
          await _mapController!.updateSymbol(
            _portalSymbols[ride.id]!,
            SymbolOptions(
              geometry: LatLng(ride.lat, ride.lng),
            ),
          );
        } catch (e) {
          debugPrint('⚠️ Failed to update portal ${ride.id}: $e');
        }
      } else {
        // New ride → add symbol
        try {
          final symbol = await _mapController!.addSymbol(SymbolOptions(
            geometry: LatLng(ride.lat, ride.lng),
            iconImage: 'portal-icon',
            iconSize: 0.85, // INCREASED FROM 0.5
            iconAnchor: 'center',
          ));
          _portalSymbols[ride.id] = symbol;
          debugPrint('🔮 Portal placed for ride ${ride.id} → ${ride.destination}');
        } catch (e) {
          debugPrint('❌ Failed to add portal ${ride.id}: $e');
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // CAMERA ANIMATION (DEBOUNCED)
  // ---------------------------------------------------------------------------
  void _animateCameraToPosition(Position pos) {
    if (!_isMapReady || _mapController == null) return;

    final now = DateTime.now();
    final canAnimate = _lastCameraAnimateTime == null ||
        now.difference(_lastCameraAnimateTime!) >= _minAnimateInterval;

    if (canAnimate) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: _currentZoom,
          tilt: _is3DMode ? 60.0 : 0.0,
        )),
        duration: const Duration(milliseconds: 500),
      );
      _lastCameraAnimateTime = now;
    }
  }

  void _goToMyLocation() {
    if (_currentPosition == null || _mapController == null) return;
    _lastCameraAnimateTime = null;
    _animateCameraToPosition(_currentPosition!);
  }

  void _toggle3DMode() {
    setState(() {
      _is3DMode = !_is3DMode;
      _currentZoom = _is3DMode ? 16.0 : 18.0;
    });

    if (_currentPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          zoom: _currentZoom,
          tilt: _is3DMode ? 60.0 : 0.0,
        )),
        duration: const Duration(milliseconds: 600),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // MAP CALLBACKS
  // ---------------------------------------------------------------------------
  void _onMapCreated(MapLibreMapController controller) async {
    _mapController = controller;
    _isMapReady = true;
    _mapController!.onSymbolTapped.add(_onSymbolTapped);
    debugPrint('✅ Map created');

    await _registerMarkerImages();
    await _updatePortalSymbols();
    await _createAvatarSymbol();
  }

  void _onStyleLoaded() {
    debugPrint('✅ Map style loaded');
    if (!_imagesRegistered) {
      _registerMarkerImages().then((_) {
        _createAvatarSymbol();
        _updatePortalSymbols();
      });
    }
    if (_pendingPortalUpdate) {
      _updatePortalSymbols();
    }
  }

  // ===========================================================================
  // PHASE 4: JOIN FLOW (Map Tap & Bottom Sheet)
  // ===========================================================================

  void _handleMapTap(LatLng tapLocation) {
    if (_activeRides.isEmpty) return;

    SharingPoint? closestRide;
    double minDistance = double.infinity;

    for (final ride in _activeRides) {
      if (!ride.isVisible && ride.status != 'full') continue;

      final distance = Geolocator.distanceBetween(
        tapLocation.latitude, tapLocation.longitude,
        ride.lat, ride.lng,
      );

      // 50 meters radius for tapping
      if (distance <= 50 && distance < minDistance) {
        minDistance = distance;
        closestRide = ride;
      }
    }

    if (closestRide != null) {
      _showRideBottomSheet(closestRide);
    }
  }

  void _onSymbolTapped(Symbol symbol) {
    if (_activeRides.isEmpty) return;

    // Find if the tapped symbol belongs to a portal
    final entry = _portalSymbols.entries.where((e) => e.value.id == symbol.id).toList();
    if (entry.isNotEmpty) {
      final rideId = entry.first.key;
      try {
        final ride = _activeRides.firstWhere((r) => r.id == rideId);
        _showRideBottomSheet(ride);
      } catch (e) {
        debugPrint('⚠️ Tapped portal ride data not found in _activeRides');
      }
    }
  }

  void _showRideBottomSheet(SharingPoint ride) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _RideBottomSheet(
        rideId: ride.id,
        currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
      ),
    );
  }

  // ===========================================================================
  // PHASE 2: RIDE HOSTING
  // ===========================================================================

  Future<bool> _isAlreadyHosting() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final query = await FirebaseFirestore.instance
        .collection('sharing_points')
        .where('creatorId', isEqualTo: user.uid)
        .where('status', whereIn: ['active', 'full', 'ongoing'])
        .get();
    return query.docs.isNotEmpty;
  }

  Future<bool> _isAlreadyPassenger() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final query = await FirebaseFirestore.instance
        .collection('sharing_points')
        .where('passengers', arrayContains: user.uid)
        .where('status', whereIn: ['active', 'full', 'ongoing'])
        .get();
    return query.docs.isNotEmpty;
  }

  void _showHostRideDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('Not authenticated. Please restart the app.', isError: true);
      return;
    }
    if (_currentPosition == null) {
      _showSnackBar('GPS not available. Cannot host a ride.', isError: true);
      return;
    }
    if (_isCreatingRide) return;

    final alreadyHosting = await _isAlreadyHosting();
    if (alreadyHosting) {
      _showSnackBar('You are already hosting a ride!', isError: true);
      return;
    }
    final alreadyPassenger = await _isAlreadyPassenger();
    if (alreadyPassenger) {
      _showSnackBar('You are already in a ride. Leave it first.', isError: true);
      return;
    }

    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _HostRideDialog(),
    );
    if (result == null) return;

    _isCreatingRide = true;
    try {
      final now = DateTime.now();
      final waitMinutes = result['waitMinutes'] as int;
      final expiresAt = now.add(Duration(minutes: waitMinutes));

      final rideData = SharingPoint(
        id: '', creatorId: user.uid,
        lat: _currentPosition!.latitude, lng: _currentPosition!.longitude,
        destination: result['destination'] as String,
        seatsAvailable: result['seats'] as int,
        totalSeats: result['seats'] as int,
        status: 'active', createdAt: now, expiresAt: expiresAt,
        passengers: [],
      );

      await FirebaseFirestore.instance
          .collection('sharing_points')
          .add(rideData.toMap());

      _showSnackBar('🎉 Ride created! Others can join for ${waitMinutes}min.');
      debugPrint('✅ Ride created: ${result['destination']}');
    } catch (e) {
      debugPrint('❌ Failed to create ride: $e');
      _showSnackBar('Failed to create ride: $e', isError: true);
    } finally {
      _isCreatingRide = false;
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white, size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFE53935) : const Color(0xFF43A047),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  // ===========================================================================
  // PHASE 5: DASHBOARD PANELS & ROUTE LINE
  // ===========================================================================

  Future<void> _clearRoute() async {
    if (_routeLine != null && _mapController != null) {
      try {
        await _mapController!.removeLine(_routeLine!);
      } catch (_) {}
      _routeLine = null;
    }
  }

  Future<void> _checkAndFetchRoute(SharingPoint ride) async {
    if (_currentPosition == null || _mapController == null || _isFetchingRoute) return;

    if (_lastRouteFetchPosition != null) {
      final dist = Geolocator.distanceBetween(
        _currentPosition!.latitude, _currentPosition!.longitude,
        _lastRouteFetchPosition!.latitude, _lastRouteFetchPosition!.longitude,
      );
      if (dist < 50 && _routeLine != null) return;
    }

    _isFetchingRoute = true;
    _lastRouteFetchPosition = _currentPosition;

    try {
      final startLng = _currentPosition!.longitude.toStringAsFixed(6);
      final startLat = _currentPosition!.latitude.toStringAsFixed(6);
      final endLng = ride.lng.toStringAsFixed(6);
      final endLat = ride.lat.toStringAsFixed(6);

      final url = 'https://router.project-osrm.org/route/v1/driving/$startLng,$startLat;$endLng,$endLat?overview=full&geometries=geojson';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final geometry = data['routes'][0]['geometry']['coordinates'] as List;
          final points = geometry.map((coord) => LatLng(coord[1], coord[0])).toList();

          await _clearRoute();
          _routeLine = await _mapController!.addLine(LineOptions(
            geometry: points,
            lineColor: '#00FFFF', // Cyan
            lineWidth: 6.0,
            lineOpacity: 0.8,
            lineJoin: 'round',
          ));
        }
      }
    } catch (e) {
      debugPrint('⚠️ Route fetch error: $e');
    } finally {
      if (mounted) _isFetchingRoute = false;
    }
  }

  Future<void> _leaveOrCancelRide() async {
    if (_myCurrentRide == null) return;
    final ride = _myCurrentRide!;
    final user = FirebaseAuth.instance.currentUser;
    final isHost = ride.creatorId == user?.uid;
    
    final docRef = FirebaseFirestore.instance.collection('sharing_points').doc(ride.id);

    try {
      if (isHost) {
        await docRef.update({'status': 'expired'});
        _showSnackBar('Ride cancelled.');
      } else {
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(docRef);
          if (!snapshot.exists) return;
          final currentRide = SharingPoint.fromMap(snapshot.id, snapshot.data()!);
          
          if (!currentRide.passengers.contains(user?.uid)) return;
          
          final newSeats = currentRide.seatsAvailable + 1;
          transaction.update(docRef, {
            'passengers': FieldValue.arrayRemove([user?.uid]),
            'seatsAvailable': newSeats,
            'status': currentRide.status == 'full' ? 'active' : currentRide.status,
          });
        });
        _showSnackBar('Left the ride.');
      }
      await _clearRoute();
      setState(() => _myCurrentRide = null);
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    }
  }

  Widget _buildActiveRideHUD() {
    final isHost = _myCurrentRide!.creatorId == FirebaseAuth.instance.currentUser?.uid;
    
    // For passenger, calculate distance to host (portal location)
    String distanceText = '';
    if (!isHost && _currentPosition != null) {
      final dist = Geolocator.distanceBetween(
        _currentPosition!.latitude, _currentPosition!.longitude,
        _myCurrentRide!.lat, _myCurrentRide!.lng,
      );
      if (dist > 1000) {
        distanceText = '${(dist / 1000).toStringAsFixed(1)}km away';
      } else {
        distanceText = '${dist.toInt()}m away';
      }
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16, right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isHost ? Colors.blueAccent : Colors.cyanAccent, width: 2),
          boxShadow: [BoxShadow(color: (isHost ? Colors.blueAccent : Colors.cyanAccent).withValues(alpha: 0.3), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(isHost ? Icons.radar : Icons.directions_car, color: isHost ? Colors.blueAccent : Colors.cyanAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  isHost ? 'YOUR HOSTED RIDE' : 'ONGOING RIDE',
                  style: TextStyle(color: isHost ? Colors.blueAccent : Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                const Spacer(),
                if (isHost)
                  Text(_myCurrentRide!.timeRemainingText, style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold))
                else if (distanceText.isNotEmpty)
                  Text(distanceText, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _myCurrentRide!.destination,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRideBottomPanel() {
    final isHost = _myCurrentRide!.creatorId == FirebaseAuth.instance.currentUser?.uid;

    return Positioned(
      bottom: 24, left: 16, right: 16,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15, spreadRadius: 5)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (isHost) ...[
                  Column(
                    children: [
                      const Icon(Icons.people, color: Colors.greenAccent, size: 28),
                      const SizedBox(height: 8),
                      Text('${_myCurrentRide!.passengers.length} Passengers Joined', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    onPressed: () {
                      _animateCameraToPosition(Position(
                        latitude: _myCurrentRide!.lat, longitude: _myCurrentRide!.lng,
                        timestamp: DateTime.now(), accuracy: 1, altitude: 0, altitudeAccuracy: 1, heading: 0, headingAccuracy: 1, speed: 0, speedAccuracy: 1,
                      ));
                    },
                    icon: const Icon(Icons.my_location, color: Colors.cyanAccent),
                    label: const Text('Host', style: TextStyle(color: Colors.cyanAccent)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.cyanAccent)),
                  ),
                ],
                ElevatedButton.icon(
                  onPressed: _leaveOrCancelRide,
                  icon: Icon(isHost ? Icons.cancel_outlined : Icons.logout),
                  label: Text(isHost ? 'Cancel Ride' : 'Leave Ride', style: const TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Loading screen
    if (_isLoading || _currentPosition == null || _mapStyleJson == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.greenAccent.withValues(alpha: 0.8),
                      Colors.greenAccent.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.explore, size: 60, color: Colors.greenAccent),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'GeoRide',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2),
              ),
              const SizedBox(height: 16),
              Text(
                _loadingMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                SizedBox(
                  width: 40, height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.greenAccent.withValues(alpha: 0.8)),
                  ),
                ),
              if (!_isLoading && _currentPosition == null) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() { _isLoading = true; _loadingMessage = 'Retrying...'; });
                    _initLocation();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent, foregroundColor: Colors.black,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Main map screen
    return Scaffold(
      body: Stack(
        children: [
          // ─── MAP ───────────────────────────────────────────────────
          MapLibreMap(
            styleString: _mapStyleJson!,
            initialCameraPosition: CameraPosition(
              target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
              zoom: _currentZoom,
              tilt: _is3DMode ? 60.0 : 0.0,
            ),
            myLocationEnabled: false,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onMapClick: (point, latlng) => _handleMapTap(latlng),
            trackCameraPosition: true,
            compassEnabled: false,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
          ),

          // ─── TOP STATUS BAR OR HUD ─────────────────────────────────
          if (_myCurrentRide != null)
            _buildActiveRideHUD()
          else
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
            left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3), width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.greenAccent),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'GeoRide',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  const Spacer(),
                  // Active rides count
                  if (_activeRides.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_taxi, color: Colors.orangeAccent, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${_activeRides.length}',
                            style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    _is3DMode ? Icons.view_in_ar : Icons.map,
                    color: Colors.greenAccent.withValues(alpha: 0.7), size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _is3DMode ? '3D' : '2D',
                    style: TextStyle(color: Colors.greenAccent.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),

          // ─── FABs (bottom-right) ───────────────────────────────────
          Positioned(
            right: 16,
            bottom: _myCurrentRide != null ? 180 : 100,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_myCurrentRide == null) ...[
                  // Host Ride FAB
                  _buildFab(
                  heroTag: 'host_ride',
                  icon: Icons.add_location_alt,
                  tooltip: 'Host Ride',
                  onPressed: _showHostRideDialog,
                  color: Colors.orangeAccent,
                  mini: false,
                ),
                const SizedBox(height: 12),
                ],
                // 3D/2D toggle
                _buildFab(
                  heroTag: 'toggle_3d',
                  icon: _is3DMode ? Icons.layers : Icons.map,
                  tooltip: _is3DMode ? 'Switch to 2D' : 'Switch to 3D',
                  onPressed: _toggle3DMode,
                  color: Colors.greenAccent,
                ),
                const SizedBox(height: 12),
                // My Location
                _buildFab(
                  heroTag: 'my_location',
                  icon: Icons.my_location,
                  tooltip: 'My Location',
                  onPressed: _goToMyLocation,
                  color: Colors.cyanAccent,
                ),
              ],
            ),
          ),

          // ─── GPS COORDS (debug) ────────────────────────────────────
          Positioned(
            bottom: 24, left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentPosition!.latitude.toStringAsFixed(5)}, '
                '${_currentPosition!.longitude.toStringAsFixed(5)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11, fontFamily: 'monospace',
                ),
              ),
            ),
          ),

          // ─── ACTIVE RIDE BOTTOM PANEL ──────────────────────────────
          if (_myCurrentRide != null)
            _buildActiveRideBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildFab({
    required String heroTag, required IconData icon, required String tooltip,
    required VoidCallback onPressed, required Color color, bool mini = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 2)],
      ),
      child: FloatingActionButton(
        heroTag: heroTag, mini: mini,
        backgroundColor: mini ? Colors.black.withValues(alpha: 0.7) : color,
        foregroundColor: mini ? color : Colors.white,
        elevation: 0, onPressed: onPressed, tooltip: tooltip,
        child: Icon(icon, size: mini ? 20 : 26),
      ),
    );
  }
}

// =============================================================================
// HOST RIDE DIALOG
// =============================================================================

class _HostRideDialog extends StatefulWidget {
  @override
  State<_HostRideDialog> createState() => _HostRideDialogState();
}

class _HostRideDialogState extends State<_HostRideDialog> {
  final _destinationController = TextEditingController();
  int _selectedSeats = 2;
  int _selectedWaitMinutes = 30;
  final List<int> _seatOptions = [1, 2, 3, 4, 5, 6];
  final List<int> _waitOptions = [15, 30, 45, 60];

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.orangeAccent.withValues(alpha: 0.15), blurRadius: 30, spreadRadius: 5)],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_location_alt, color: Colors.orangeAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Host a Ride', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text('Share your ride with others', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Destination
              const Text('DESTINATION', style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              TextField(
                controller: _destinationController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Where are you going?',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  prefixIcon: Icon(Icons.place, color: Colors.orangeAccent.withValues(alpha: 0.6)),
                  filled: true, fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orangeAccent, width: 1.5)),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 20),

              // Seats
              const Text('SEATS AVAILABLE', style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
              const SizedBox(height: 10),
              Row(
                children: _seatOptions.map((seats) {
                  final isSelected = _selectedSeats == seats;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedSeats = seats),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.orangeAccent : Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: isSelected ? null : Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Center(
                          child: Text('$seats', style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Wait Time
              const Text('WAIT TIME', style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
              const SizedBox(height: 10),
              Row(
                children: _waitOptions.map((mins) {
                  final isSelected = _selectedWaitMinutes == mins;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedWaitMinutes = mins),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.orangeAccent : Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: isSelected ? null : Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Center(
                          child: Text('${mins}m', style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final dest = _destinationController.text.trim();
                        if (dest.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a destination'), backgroundColor: Colors.red),
                          );
                          return;
                        }
                        Navigator.of(context).pop({
                          'destination': dest, 'seats': _selectedSeats, 'waitMinutes': _selectedWaitMinutes,
                        });
                      },
                      icon: const Icon(Icons.rocket_launch, size: 18),
                      label: const Text('Create Ride', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// RIDE BOTTOM SHEET (PHASE 4)
// =============================================================================

class _RideBottomSheet extends StatefulWidget {
  final String rideId;
  final String currentUserId;

  const _RideBottomSheet({required this.rideId, required this.currentUserId});

  @override
  State<_RideBottomSheet> createState() => _RideBottomSheetState();
}

class _RideBottomSheetState extends State<_RideBottomSheet> {
  bool _isProcessing = false;

  Future<void> _joinRide(SharingPoint ride) async {
    if (widget.currentUserId.isEmpty) {
      _showError('Authentication error. Please restart the app.');
      return;
    }
    
    // Check if user is already in another active ride
    final query = await FirebaseFirestore.instance
        .collection('sharing_points')
        .where('passengers', arrayContains: widget.currentUserId)
        .where('status', whereIn: ['active', 'full', 'ongoing'])
        .get();
        
    if (query.docs.isNotEmpty) {
       _showError('You are already in another ride. Leave it first.');
       return;
    }

    setState(() => _isProcessing = true);
    try {
      final docRef = FirebaseFirestore.instance.collection('sharing_points').doc(widget.rideId);
      
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) throw Exception("Ride does not exist!");
        
        final currentRide = SharingPoint.fromMap(snapshot.id, snapshot.data()!);
        
        if (currentRide.passengers.contains(widget.currentUserId)) {
          throw Exception("You are already in this ride!");
        }
        if (currentRide.seatsAvailable <= 0) {
          throw Exception("Ride is full!");
        }
        if (currentRide.isExpired) {
          throw Exception("Ride has expired!");
        }

        final newSeats = currentRide.seatsAvailable - 1;
        transaction.update(docRef, {
          'passengers': FieldValue.arrayUnion([widget.currentUserId]),
          'seatsAvailable': newSeats,
          'status': newSeats <= 0 ? 'full' : currentRide.status,
        });
      });
      Navigator.of(context).pop();
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _leaveRide() async {
    setState(() => _isProcessing = true);
    try {
      final docRef = FirebaseFirestore.instance.collection('sharing_points').doc(widget.rideId);
      
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) throw Exception("Ride does not exist!");
        
        final currentRide = SharingPoint.fromMap(snapshot.id, snapshot.data()!);
        if (!currentRide.passengers.contains(widget.currentUserId)) {
            return; // Not in ride anyway
        }

        final newSeats = currentRide.seatsAvailable + 1;
        transaction.update(docRef, {
          'passengers': FieldValue.arrayRemove([widget.currentUserId]),
          'seatsAvailable': newSeats,
          'status': currentRide.status == 'full' ? 'active' : currentRide.status,
        });
      });
      Navigator.of(context).pop();
    } catch (e) {
      _showError('Error leaving ride: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _cancelRide() async {
    setState(() => _isProcessing = true);
    try {
      await FirebaseFirestore.instance
          .collection('sharing_points')
          .doc(widget.rideId)
          .update({'status': 'expired'});
      Navigator.of(context).pop();
    } catch (e) {
      _showError('Error cancelling ride: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('sharing_points').doc(widget.rideId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final ride = SharingPoint.fromMap(snapshot.data!.id, snapshot.data!.data() as Map<String, dynamic>);
        final isHost = ride.creatorId == widget.currentUserId;
        final isPassenger = ride.passengers.contains(widget.currentUserId);
        
        // Safety close if expired while viewing
        if (ride.isExpired && !isHost) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.canPop(context)) Navigator.pop(context);
          });
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20, spreadRadius: 5)],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isHost ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.orangeAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isHost ? 'YOUR RIDE' : 'AVAILABLE PORTAL',
                    style: TextStyle(
                      color: isHost ? Colors.blueAccent : Colors.orangeAccent,
                      fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Destination
                const Text('DESTINATION', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.place, color: Colors.orangeAccent, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ride.destination,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Stats row
                Row(
                  children: [
                    _buildStatBlock(
                      icon: Icons.group,
                      label: 'SEATS LEFT',
                      value: '${ride.seatsAvailable}/${ride.totalSeats}',
                      color: ride.seatsAvailable > 0 ? Colors.greenAccent : Colors.redAccent,
                    ),
                    const SizedBox(width: 16),
                    _buildStatBlock(
                      icon: Icons.timer,
                      label: 'EXPIRES IN',
                      value: ride.timeRemainingText,
                      color: Colors.cyanAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Action Buttons
                if (_isProcessing)
                  const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
                else if (isHost)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _cancelRide,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel Ride'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  )
                else if (isPassenger)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _leaveRide,
                      icon: const Icon(Icons.logout),
                      label: const Text('Leave Ride', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  )
                else if (ride.seatsAvailable > 0)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _joinRide(ride),
                      icon: const Icon(Icons.rocket_launch, size: 20),
                      label: const Text('Join Ride', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 8,
                        shadowColor: Colors.orangeAccent.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text('RIDE FULL', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatBlock({required IconData icon, required String label, required String value, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

