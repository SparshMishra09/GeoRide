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
  final List<String> arrivedPassengers;
  final List<String> ratedBy; // UIDs that have submitted their rating
  final double? toLat;
  final double? toLng;

  SharingPoint({
    required this.id, required this.creatorId, required this.lat,
    required this.lng, required this.destination, required this.seatsAvailable,
    required this.totalSeats, required this.status, required this.createdAt,
    required this.expiresAt, required this.passengers, required this.arrivedPassengers,
    required this.ratedBy,
    this.toLat, this.toLng,
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
      arrivedPassengers: List<String>.from(map['arrivedPassengers'] ?? []),
      ratedBy: List<String>.from(map['ratedBy'] ?? []),
      toLat: (map['toLat'] as num?)?.toDouble(),
      toLng: (map['toLng'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'creatorId': creatorId, 'lat': lat, 'lng': lng,
    'destination': destination, 'seatsAvailable': seatsAvailable,
    'totalSeats': totalSeats, 'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
    'expiresAt': Timestamp.fromDate(expiresAt),
    'passengers': passengers,
    'arrivedPassengers': arrivedPassengers,
    'ratedBy': ratedBy,
    'toLat': toLat,
    'toLng': toLng,
  };
}

// ============================================================================
// LIVE COUNTDOWN TIMER WIDGET (Phase 7)
// ============================================================================
class _LiveCountdownText extends StatefulWidget {
  final DateTime expiresAt;
  const _LiveCountdownText({required this.expiresAt});

  @override
  State<_LiveCountdownText> createState() => _LiveCountdownTextState();
}

class _LiveCountdownTextState extends State<_LiveCountdownText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (DateTime.now().isAfter(widget.expiresAt)) {
      return const Text('Expired', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold));
    }
    final diff = widget.expiresAt.difference(DateTime.now());
    final text = '${diff.inMinutes}m ${diff.inSeconds % 60}s';
    return Text(text, style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold));
  }
}

// ============================================================================
// CHAT MODAL SHEET (Phase 8)
// ============================================================================
class _ChatModalSheet extends StatefulWidget {
  final String rideId;
  const _ChatModalSheet({required this.rideId});

  @override
  State<_ChatModalSheet> createState() => _ChatModalSheetState();
}

class _ChatModalSheetState extends State<_ChatModalSheet> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final messagesRef = FirebaseFirestore.instance
        .collection('sharing_points')
        .doc(widget.rideId)
        .collection('messages');

    _messageController.clear();
    await messagesRef.add({
      'senderId': user.uid,
      'senderName': user.displayName ?? 'Trainer',
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'isSystem': false,
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.7 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            ),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble, color: Colors.greenAccent),
                const SizedBox(width: 8),
                const Text('Ride Chat', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
          ),
          
          // Messages List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('sharing_points')
                  .doc(widget.rideId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
                }
                
                final docs = snapshot.data!.docs;
                final currentUid = FirebaseAuth.instance.currentUser?.uid;

                // Auto-scroll to bottom
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No messages yet. Say hello!', style: TextStyle(color: Colors.white54)),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final isSystem = data['isSystem'] ?? false;
                    final isMe = data['senderId'] == currentUid;
                    
                    if (isSystem) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: Text(
                            data['text'] ?? '',
                            style: const TextStyle(color: Colors.orangeAccent, fontStyle: FontStyle.italic, fontSize: 13),
                          ),
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.greenAccent.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16).copyWith(
                              bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                              bottomLeft: !isMe ? const Radius.circular(0) : const Radius.circular(16),
                            ),
                            border: Border.all(
                              color: isMe ? Colors.greenAccent.withValues(alpha: 0.3) : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Text(
                                  data['senderName'] ?? 'Unknown',
                                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              Text(data['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 15)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // Input Area
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            color: Colors.black.withValues(alpha: 0.3),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.4),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.black),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ============================================================================
// HOME SCREEN â€” Phase 1 + 2 + 3: Map + Avatar + Hosting + Portals
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

  // ---------------------------------------------------------------------------
  // Phase 11: Glowing Path (host destination route)
  // ---------------------------------------------------------------------------
  Line? _glowLine;   // outer glow layer
  Line? _glowCore;   // inner bright core layer
  bool _isDrawingGlow = false;

  // ---------------------------------------------------------------------------
  // Phase 6: Live Passenger Tracking
  // ---------------------------------------------------------------------------
  final Map<String, Symbol> _passengerSymbols = {};
  StreamSubscription<QuerySnapshot>? _passengerLocationsSub;
  QuerySnapshot? _latestPassengerSnapshot;
  DateTime? _lastLocationUploadTime;
  bool _hasReachedPortal = false;
  final Set<String> _arrivedPassengers = {};

  // ---------------------------------------------------------------------------
  // Explore Mode: pauses auto-camera follow when user is panning the map
  // ---------------------------------------------------------------------------
  bool _userIsExploring = false;
  Timer? _exploreTimer;
  bool _isProgrammaticCameraMove = false; // prevents explore mode during auto-follow

  // ---------------------------------------------------------------------------
  // Phase 14: Solo Trip Mode
  // ---------------------------------------------------------------------------
  bool _isTripModeActive = false;
  LatLng? _tripDestination;
  String _tripDestinationName = '';
  final List<Line> _tripSegmentLines = []; // one Line per traffic-colored segment
  Timer? _tripRerouteTimer;
  bool _isDrawingTrip = false;

  // ---------------------------------------------------------------------------
  // Phase 16: Smooth Avatar Animation
  // ---------------------------------------------------------------------------
  LatLng? _avatarCurrentLatLng;
  LatLng? _avatarTargetLatLng;
  AnimationController? _avatarAnimController;
  Animation<double>? _avatarAnim;

  // ---------------------------------------------------------------------------
  // Phase 17: Weather & AQI Overlay
  // ---------------------------------------------------------------------------
  int? _currentAqi;
  double? _currentTempC;
  int? _weatherCode;
  double? _humidity;
  Timer? _weatherTimer;
  bool _showTemperature = false;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _initLocation();
    _startRidesStream();
    _startExpiryTimer();
    // Phase 17: start weather/AQI after a small delay so location is ready
    Future.delayed(const Duration(seconds: 3), _initWeatherAndAqi);
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _ridesStreamSub?.cancel();
    _passengerLocationsSub?.cancel();
    _expiryTimer?.cancel();
    _exploreTimer?.cancel();
    _tripRerouteTimer?.cancel();
    _weatherTimer?.cancel();
    _avatarAnimController?.dispose();
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
        debugPrint('âœ… Remote style loaded & themed');
      } else {
        setState(() => _mapStyleJson = 'https://tiles.openfreemap.org/styles/liberty');
      }
    } catch (e) {
      debugPrint('âš ï¸ Could not fetch remote style: $e');
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
      debugPrint('âŒ Location error: $e');
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
      onError: (e) => debugPrint('âŒ Position stream error: $e'),
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
    // Only auto-follow camera if user is NOT manually exploring the map
    if (!_userIsExploring) {
      _animateCameraToPosition(smoothed);
    }

    if (_myCurrentRide != null && _myCurrentRide!.creatorId != FirebaseAuth.instance.currentUser?.uid) {
      final ride = _myCurrentRide!;
      final user = FirebaseAuth.instance.currentUser;
      
      _checkAndFetchRoute(ride);

      // Phase 6 + Phase 10: Passenger proximity alert
      if (!_hasReachedPortal) {
        final distToHost = Geolocator.distanceBetween(smoothed.latitude, smoothed.longitude, ride.lat, ride.lng);
        if (distToHost <= 20) {
          _hasReachedPortal = true;
          _showSnackBar('You have reached the spot! Wait for everyone to arrive.', isError: false);
          if (user != null) {
            FirebaseFirestore.instance.collection('sharing_points').doc(ride.id).update({
              'arrivedPassengers': FieldValue.arrayUnion([user.uid])
            });
          }
        }
      }

      // Phase 6: Passenger GPS upload to host tracker
      final now = DateTime.now();
      if (user != null && (_lastLocationUploadTime == null || now.difference(_lastLocationUploadTime!).inSeconds >= 5)) {
        _lastLocationUploadTime = now;
        FirebaseFirestore.instance
            .collection('sharing_points')
            .doc(ride.id)
            .collection('passenger_locations')
            .doc(user.uid)
            .set({
          'lat': smoothed.latitude,
          'lng': smoothed.longitude,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
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

  Future<Uint8List> _generatePassengerAvatarImage() async {
    const double imgSize = 100;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(imgSize / 2, imgSize / 2);
    final coreRadius = imgSize * 0.3;

    // Cyan border
    canvas.drawCircle(center, coreRadius + 4, Paint()..color = Colors.cyanAccent..style = PaintingStyle.fill);

    // Dark grey core
    canvas.drawCircle(center, coreRadius, Paint()..color = const Color(0xFF263238)..style = PaintingStyle.fill);

    // Person icon
    final personPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx, center.dy - coreRadius * 0.2), coreRadius * 0.3, personPaint);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(center.dx, center.dy + coreRadius * 0.3), width: coreRadius * 1.2, height: coreRadius * 1.0),
      3.14159, 3.14159, true, personPaint,
    );

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

      final passengerBytes = await _generatePassengerAvatarImage();
      await _mapController!.addImage('passenger-avatar', passengerBytes);

      _imagesRegistered = true;
      debugPrint('âœ… Avatar + Portal + Passenger images registered');

      // Retry pending portal updates now that images are registered
      if (_pendingPortalUpdate) {
        _pendingPortalUpdate = false;
        await _updatePortalSymbols();
      }
      
      // Retry passenger locations if they arrived before images
      if (_latestPassengerSnapshot != null) {
        _processPassengerSnapshot(_latestPassengerSnapshot!);
      }
    } catch (e) {
      debugPrint('âŒ Failed to register images: $e');
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
      debugPrint('âœ… Avatar symbol placed');
    } catch (e) {
      debugPrint('âŒ Failed to create avatar symbol: $e');
    }
  }

  // Phase 16: Smooth avatar glide — lerps from current position to new target
  void _updateAvatarPosition(Position pos) {
    final target = LatLng(pos.latitude, pos.longitude);
    if (_mapController == null || _avatarSymbol == null) {
      _avatarCurrentLatLng = target;
      return;
    }

    if (_avatarCurrentLatLng == null) {
      _avatarCurrentLatLng = target;
      _mapController!.updateSymbol(_avatarSymbol!, SymbolOptions(geometry: target));
      return;
    }

    _avatarTargetLatLng = target;

    _avatarAnimController?.stop();
    _avatarAnimController?.dispose();

    final startLatLng = _avatarCurrentLatLng!;

    _avatarAnimController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _avatarAnim = CurvedAnimation(
      parent: _avatarAnimController!,
      curve: Curves.easeInOut,
    );

    _avatarAnimController!.addListener(() {
      final t = _avatarAnim!.value;
      final lerpLat = startLatLng.latitude + (target.latitude - startLatLng.latitude) * t;
      final lerpLng = startLatLng.longitude + (target.longitude - startLatLng.longitude) * t;
      final lerpLatLng = LatLng(lerpLat, lerpLng);
      _mapController?.updateSymbol(_avatarSymbol!, SymbolOptions(geometry: lerpLatLng));
    });

    _avatarAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _avatarCurrentLatLng = target;
        _avatarAnimController?.dispose();
        _avatarAnimController = null;
      }
    });

    _avatarAnimController!.forward();
  }

  // ===========================================================================
  // PHASE 3: PORTAL RENDERING
  // ===========================================================================

  /// Start listening to active rides from Firestore
  void _startRidesStream() {
    _ridesStreamSub = FirebaseFirestore.instance
        .collection('sharing_points')
        .where('status', whereIn: ['active', 'full', 'rating_phase'])
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

        if (myRide == null) {
          _stopPassengerLocationsStream();
          _clearPassengerSymbols();
          _arrivedPassengers.clear();
          _hasReachedPortal = false;
          // Clear both the passenger route line AND the host glowing path
          _clearRoute();
          _clearGlowingPath();
        } else if (myRide.creatorId == user?.uid) {
          _startPassengerLocationsStream(myRide.id);
          if (_latestPassengerSnapshot != null) {
            _processPassengerSnapshot(_latestPassengerSnapshot!);
          }
          
          // Phase 10: Trigger 'rating_phase' when ALL joined passengers have arrived
          // Use passengers.length (actual joined count), not totalSeats (capacity)
          if (myRide.status != 'rating_phase' &&
              myRide.passengers.isNotEmpty &&
              myRide.arrivedPassengers.length >= myRide.passengers.length) {
             FirebaseFirestore.instance.collection('sharing_points').doc(myRide.id).update({
               'status': 'rating_phase'
             });
          }
        }

        debugPrint('ðŸ“¡ Rides stream: ${rides.length} active rides');
      },
      onError: (e) => debugPrint('âŒ Rides stream error: $e'),
    );
  }

  /// Start a timer that checks for expired rides every 30s
  void _startExpiryTimer() {
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      // Remove expired rides from the list and update symbols
      final before = _activeRides.length;
      _activeRides.removeWhere((ride) => ride.isExpired);
      if (_activeRides.length != before) {
        debugPrint('â° Expiry check: removed ${before - _activeRides.length} expired rides');
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
          debugPrint('ðŸ—‘ï¸ Marked ride ${doc.id} as expired');
        }
      }
    } catch (e) {
      debugPrint('âš ï¸ Expiry cleanup error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // PHASE 6: LIVE PASSENGER LOCATION TRACKING
  // ---------------------------------------------------------------------------

  void _startPassengerLocationsStream(String rideId) {
    if (_passengerLocationsSub != null) return; // Already listening

    _passengerLocationsSub = FirebaseFirestore.instance
        .collection('sharing_points')
        .doc(rideId)
        .collection('passenger_locations')
        .snapshots()
        .listen(
      (snapshot) async {
        _latestPassengerSnapshot = snapshot;
        _processPassengerSnapshot(snapshot);
      },
      onError: (e) => debugPrint('âŒ Passenger stream error: $e'),
    );
  }

  Future<void> _processPassengerSnapshot(QuerySnapshot snapshot) async {
    if (_myCurrentRide == null) return;

    // Remove passengers that left the subcollection (i.e., disconnected or left ride)
    final incomingUids = snapshot.docs.map((d) => d.id).toSet();
    final currentSymbolUids = _passengerSymbols.keys.toSet();
    
    final toRemove = currentSymbolUids.difference(incomingUids);
    for (final uid in toRemove) {
      final sym = _passengerSymbols.remove(uid);
      if (sym != null) await _mapController?.removeSymbol(sym);
      _arrivedPassengers.remove(uid);
    }

    // Add or update passengers
    for (final doc in snapshot.docs) {
      // Double check they are actually part of the ride passengers array to be safe
      if (!_myCurrentRide!.passengers.contains(doc.id)) {
        final sym = _passengerSymbols.remove(doc.id);
        if (sym != null) await _mapController?.removeSymbol(sym);
        _arrivedPassengers.remove(doc.id);
        continue;
      }

      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final lat = data['lat'] as double;
      final lng = data['lng'] as double;

      // Proximity check (20m)
      if (_currentPosition != null && !_arrivedPassengers.contains(doc.id)) {
        final dist = Geolocator.distanceBetween(
          _currentPosition!.latitude, _currentPosition!.longitude,
          lat, lng,
        );
        if (dist <= 20) {
          _arrivedPassengers.add(doc.id);
          _showSnackBar('A passenger has reached the sharing spot!', isError: false);
        }
      }

      final existingSymbol = _passengerSymbols[doc.id];
      if (existingSymbol == null && _isMapReady && _imagesRegistered) {
        try {
          final newSym = await _mapController!.addSymbol(SymbolOptions(
            geometry: LatLng(lat, lng),
            iconImage: 'passenger-avatar',
            iconSize: 0.8,
          ));
          _passengerSymbols[doc.id] = newSym;
        } catch (_) {}
      } else if (existingSymbol != null) {
        try {
          await _mapController!.updateSymbol(
            existingSymbol,
            SymbolOptions(geometry: LatLng(lat, lng)),
          );
        } catch (_) {}
      }
    }
  }

  void _stopPassengerLocationsStream() {
    _passengerLocationsSub?.cancel();
    _passengerLocationsSub = null;
  }

  Future<void> _clearPassengerSymbols() async {
    if (_mapController == null) return;
    for (final sym in _passengerSymbols.values) {
      try {
        await _mapController!.removeSymbol(sym);
      } catch (_) {}
    }
    _passengerSymbols.clear();
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
        // Symbol exists â†’ update position (in case data changed)
        try {
          await _mapController!.updateSymbol(
            _portalSymbols[ride.id]!,
            SymbolOptions(
              geometry: LatLng(ride.lat, ride.lng),
            ),
          );
        } catch (e) {
          debugPrint('âš ï¸ Failed to update portal ${ride.id}: $e');
        }
      } else {
        // New ride â†’ add symbol
        try {
          final symbol = await _mapController!.addSymbol(SymbolOptions(
            geometry: LatLng(ride.lat, ride.lng),
            iconImage: 'portal-icon',
            iconSize: 0.85, // INCREASED FROM 0.5
            iconAnchor: 'center',
          ));
          _portalSymbols[ride.id] = symbol;
          debugPrint('ðŸ”® Portal placed for ride ${ride.id} â†’ ${ride.destination}');
        } catch (e) {
          debugPrint('âŒ Failed to add portal ${ride.id}: $e');
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
      _isProgrammaticCameraMove = true;
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: _currentZoom,
          tilt: _is3DMode ? 60.0 : 0.0,
        )),
        duration: const Duration(milliseconds: 500),
      ).then((_) => _isProgrammaticCameraMove = false)
       .catchError((_) => _isProgrammaticCameraMove = false);
      _lastCameraAnimateTime = now;
    }
  }

  /// Called whenever the camera moves. If it's a user gesture (not programmatic),
  /// pauses auto-camera follow for 8 seconds so the user can explore freely.
  void _onUserMapInteraction() {
    if (_isProgrammaticCameraMove) return; // ignore animated moves from code
    if (!_userIsExploring) {
      setState(() => _userIsExploring = true);
    }
    // Debounce: reset the 8s timer every frame the user moves the map
    _exploreTimer?.cancel();
    _exploreTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _userIsExploring = false);
    });
  }

  void _goToMyLocation() {
    if (_currentPosition == null || _mapController == null) return;
    // Cancel explore mode so auto-follow resumes immediately
    _exploreTimer?.cancel();
    setState(() => _userIsExploring = false);
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
    debugPrint('âœ… Map created');

    await _registerMarkerImages();
    await _updatePortalSymbols();
    await _createAvatarSymbol();
  }

  void _onStyleLoaded() {
    debugPrint('âœ… Map style loaded');
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

    // 1. Check if the tapped symbol belongs to a portal
    final portalEntry = _portalSymbols.entries.where((e) => e.value.id == symbol.id).toList();
    if (portalEntry.isNotEmpty) {
      final rideId = portalEntry.first.key;
      try {
        final ride = _activeRides.firstWhere((r) => r.id == rideId);
        _showRideBottomSheet(ride);
      } catch (e) {
        debugPrint('âš ï¸ Tapped portal ride data not found in _activeRides');
      }
      return;
    }

    // 2. Check if the tapped symbol belongs to a passenger
    final passEntry = _passengerSymbols.entries.where((e) => e.value.id == symbol.id).toList();
    if (passEntry.isNotEmpty) {
      final passengerUid = passEntry.first.key;
      _showPassengerActionSheet(passengerUid);
    }
  }

  // ===========================================================================
  // PHASE 9: PASSENGER ACTIONS & RATINGS
  // ===========================================================================
  
  void _showPassengerActionSheet(String passengerUid) {
    if (_myCurrentRide == null) return;
    
    final hasArrived = _arrivedPassengers.contains(passengerUid);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(passengerUid).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            if (data == null) return const SizedBox.shrink();

            final name = data['displayName'] ?? 'Passenger';
            final rating = (data['safetyRating'] as num?)?.toDouble() ?? 0.0;
            
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_circle, size: 64, color: Colors.cyanAccent),
                  const SizedBox(height: 16),
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 32),
                  if (hasArrived)
                    ElevatedButton.icon(
                      onPressed: () {
                         Navigator.pop(context);
                         _showRatingDialog(passengerUid, name);
                      },
                      icon: const Icon(Icons.star_rate),
                      label: const Text('Rate Passenger', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber, foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () async {
                         Navigator.pop(context);
                         _kickPassenger(passengerUid);
                      },
                      icon: const Icon(Icons.person_remove),
                      label: const Text('Kick Passenger', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent, foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _kickPassenger(String uid) async {
    if (_myCurrentRide == null) return;
    try {
      final docRef = FirebaseFirestore.instance.collection('sharing_points').doc(_myCurrentRide!.id);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;
        final currentRide = SharingPoint.fromMap(snapshot.id, snapshot.data()!);
        if (!currentRide.passengers.contains(uid)) return;
        
        transaction.update(docRef, {
          'passengers': FieldValue.arrayRemove([uid]),
          'seatsAvailable': currentRide.seatsAvailable + 1,
          'status': 'active', // reopen if it was full
        });
      });
      _showSnackBar('Passenger kicked.', isError: true);
    } catch (e) {
      _showSnackBar('Failed to kick: $e', isError: true);
    }
  }

  void _showRatingDialog(String targetUid, String targetName, {bool isPassengerRatingHost = false, SharingPoint? rideToLeave}) {
    int _rating = 0;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Rate $targetName', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('How was your experience?', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return IconButton(
                          icon: Icon(
                            index < _rating ? Icons.star : Icons.star_border,
                            color: index < _rating ? Colors.amber : Colors.white24, size: 40,
                          ),
                          onPressed: () => setDialogState(() => _rating = index + 1),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _rating > 0 ? () async {
                        Navigator.pop(context);
                        await _submitRating(targetUid, _rating);
                        if (isPassengerRatingHost && rideToLeave != null) {
                           _leaveRideAfterArrival(rideToLeave);
                        }
                      } : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 50)),
                      child: const Text('Submit Rating', style: TextStyle(fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  Future<void> _submitRating(String uid, int stars) async {
    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          transaction.set(docRef, {'displayName': 'Trainer', 'safetyRating': stars.toDouble(), 'ratingCount': 1, 'ratingSum': stars});
        } else {
          final data = snapshot.data()!;
          final int count = (data['ratingCount'] as num?)?.toInt() ?? 0;
          final int sum = (data['ratingSum'] as num?)?.toInt() ?? 0;
          final newCount = count + 1;
          final newSum = sum + stars;
          final newRating = newSum / newCount;
          transaction.update(docRef, {
            'ratingCount': newCount,
            'ratingSum': newSum,
            'safetyRating': newRating,
          });
        }
      });
      _showSnackBar('Rating submitted! Thanks for keeping GeoRide safe.');
    } catch (e) {
      debugPrint('Rating error: $e');
    }
  }

  Future<void> _leaveRideAfterArrival(SharingPoint ride) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final docRef = FirebaseFirestore.instance.collection('sharing_points').doc(ride.id);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;
        transaction.update(docRef, {
          'passengers': FieldValue.arrayRemove([user.uid]),
          // PHASE 9 CRITICAL: Do NOT increment seatsAvailable because the seat was consumed
        });
      });
      await _clearRoute();
      setState(() {
        _myCurrentRide = null;
        _hasReachedPortal = false;
      });
      _stopPassengerLocationsStream();
      _clearPassengerSymbols();
    } catch (e) {
      debugPrint('Error leaving: $e');
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

    final currentLatLng = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : null;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _HostRideDialog(currentPos: currentLatLng),
    );
    if (result == null) return;

    _isCreatingRide = true;
    try {
      final now = DateTime.now();
      final waitMinutes = result['waitMinutes'] as int;
      final expiresAt = now.add(Duration(minutes: waitMinutes));

      // From coords â€” either selected location or GPS
      final fromLat = (result['fromLat'] as double?) ?? _currentPosition!.latitude;
      final fromLng = (result['fromLng'] as double?) ?? _currentPosition!.longitude;
      final toLat = result['toLat'] as double?;
      final toLng = result['toLng'] as double?;
      final toName = result['toName'] as String? ?? '';
      final fromName = result['fromName'] as String? ?? 'Current Location';

      final rideData = SharingPoint(
        id: '', creatorId: user.uid,
        lat: fromLat, lng: fromLng,
        destination: toName,
        seatsAvailable: result['seats'] as int,
        totalSeats: result['seats'] as int,
        status: 'active', createdAt: now, expiresAt: expiresAt,
        passengers: [], arrivedPassengers: [],
        ratedBy: [],
        toLat: toLat, toLng: toLng,
      );

      final docRef = await FirebaseFirestore.instance
          .collection('sharing_points')
          .add(rideData.toMap());
      final newRideId = docRef.id;

      _showSnackBar('ðŸŽ‰ Ride created! Others can join for ${waitMinutes}min.');
      debugPrint('âœ… Ride created: $fromName â†’ $toName');

      // Draw glowing path for HOST only
      if (toLat != null && toLng != null) {
        final start = LatLng(fromLat, fromLng);
        final end = LatLng(toLat, toLng);
        await _drawGlowingPath(start, end);
      }

      // Phase 12: Check for matching ride (same from+to) from another host
      if (toLat != null && toLng != null && mounted) {
        await _checkForMatchingRide(
          newRideId: newRideId,
          fromLat: fromLat, fromLng: fromLng,
          toLat: toLat, toLng: toLng,
          currentUserId: user.uid,
        );
      }
    } catch (e) {
      debugPrint('âŒ Failed to create ride: $e');
      _showSnackBar('Failed to create ride: $e', isError: true);
    } finally {
      _isCreatingRide = false;
    }
  }

  void _showTripDialog() async {
    final currentLatLng = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : null;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TripDialog(currentPos: currentLatLng),
    );
    if (result == null) return;

    final toLat = result['toLat'] as double?;
    final toLng = result['toLng'] as double?;
    final toName = result['toName'] as String? ?? 'Destination';

    if (toLat != null && toLng != null) {
      _startTripMode(LatLng(toLat, toLng), toName);
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

  // ===========================================================================
  // PHASE 11: GLOWING PATH (Host destination route)
  // ===========================================================================

  Future<void> _clearGlowingPath() async {
    if (_mapController == null) return;
    try {
      if (_glowLine != null) {
        await _mapController!.removeLine(_glowLine!);
        _glowLine = null;
      }
      if (_glowCore != null) {
        await _mapController!.removeLine(_glowCore!);
        _glowCore = null;
      }
    } catch (e) {
      debugPrint('âš ï¸ Error clearing glow path: $e');
    }
  }

  Future<void> _drawGlowingPath(LatLng start, LatLng end) async {
    if (_mapController == null || _isDrawingGlow) return;
    _isDrawingGlow = true;

    try {
      // Clear any existing glow path first
      await _clearGlowingPath();

      // Fetch road route from OSRM
      final startLng = start.longitude.toStringAsFixed(6);
      final startLat = start.latitude.toStringAsFixed(6);
      final endLng = end.longitude.toStringAsFixed(6);
      final endLat = end.latitude.toStringAsFixed(6);

      final url = 'https://router.project-osrm.org/route/v1/driving/$startLng,$startLat;$endLng,$endLat?overview=full&geometries=geojson';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));

      List<LatLng> routePoints = [start, end]; // fallback: straight line

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final coords = data['routes'][0]['geometry']['coordinates'] as List;
          if (coords.isNotEmpty) {
            routePoints = coords.map((c) => LatLng(c[1] as double, c[0] as double)).toList();
          }
        }
      }

      if (!mounted || _mapController == null) return;

      // Draw outer glow (thick, semi-transparent cyan)
      _glowLine = await _mapController!.addLine(LineOptions(
        geometry: routePoints,
        lineColor: '#00E5FF',
        lineWidth: 14.0,
        lineOpacity: 0.35,
        lineJoin: 'round',
      ));

      // Draw inner core (sharp, bright)
      _glowCore = await _mapController!.addLine(LineOptions(
        geometry: routePoints,
        lineColor: '#00FFFF',
        lineWidth: 4.0,
        lineOpacity: 0.95,
        lineJoin: 'round',
      ));

      // Animate camera to show just the start of the route at a comfortable zoom.
      // We do NOT fit the whole route bounds â€” that would zoom out too far on long routes.
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target: start,
          zoom: 14.0, // comfortable overview zoom
          tilt: 0.0,
        )),
        duration: const Duration(milliseconds: 800),
      );

      debugPrint('âœ… Glowing path drawn with ${routePoints.length} points');
    } catch (e) {
      debugPrint('âš ï¸ Error drawing glow path: $e');
    } finally {
      if (mounted) _isDrawingGlow = false;
    }
  }

  // ===========================================================================
  // PHASE 12: SAME-DESTINATION HOST MATCHING
  // ===========================================================================

  /// After a host creates a ride, look for other active rides with very similar
  /// from (within 500m) and to (within 500m) coordinates, from a different host.
  Future<void> _checkForMatchingRide({
    required String newRideId,
    required double fromLat, required double fromLng,
    required double toLat, required double toLng,
    required String currentUserId,
  }) async {
    try {
      // Fetch all active rides (Firestore doesn't support geo-queries natively)
      final snapshot = await FirebaseFirestore.instance
          .collection('sharing_points')
          .where('status', whereIn: ['active', 'full'])
          .get();

      SharingPoint? match;
      for (final doc in snapshot.docs) {
        if (doc.id == newRideId) continue; // skip the ride we just created
        final ride = SharingPoint.fromMap(doc.id, doc.data());
        if (ride.creatorId == currentUserId) continue; // skip own rides
        if (ride.toLat == null || ride.toLng == null) continue;
        if (ride.isExpired) continue;

        // Check FROM proximity (~500m)
        final fromDist = Geolocator.distanceBetween(
          fromLat, fromLng, ride.lat, ride.lng,
        );
        if (fromDist > 500) continue;

        // Check TO proximity (~500m)
        final toDist = Geolocator.distanceBetween(
          toLat, toLng, ride.toLat!, ride.toLng!,
        );
        if (toDist > 500) continue;

        match = ride;
        break; // Use the first match found (earliest active ride)
      }

      if (match == null || !mounted) return;

      // Fetch the matching host's profile
      final hostDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(match.creatorId)
          .get();
      final hostData = hostDoc.data();
      final hostName = hostData?['displayName'] as String? ?? 'Another rider';
      final hostRating = (hostData?['safetyRating'] as num?)?.toDouble() ?? 0.0;

      if (!mounted) return;
      await _showMatchingRideDialog(
        myNewRideId: newRideId,
        matchingRide: match,
        hostName: hostName,
        hostRating: hostRating,
        currentUserId: currentUserId,
      );
    } catch (e) {
      debugPrint('âš ï¸ Matching ride check error: $e');
    }
  }

  Future<void> _showMatchingRideDialog({
    required String myNewRideId,
    required SharingPoint matchingRide,
    required String hostName,
    required double hostRating,
    required String currentUserId,
  }) async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.15), blurRadius: 40, spreadRadius: 4),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing icon
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.cyanAccent.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.cyanAccent, width: 2),
                ),
                child: const Icon(Icons.group, color: Colors.cyanAccent, size: 30),
              ),
              const SizedBox(height: 16),
              const Text(
                'SAME ROUTE DETECTED',
                style: TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                'Someone is already heading to the same destination!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
              ),
              const SizedBox(height: 20),
              // Host info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_circle, color: Colors.cyanAccent, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(hostName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                hostRating > 0 ? hostRating.toStringAsFixed(1) : 'No rating yet',
                                style: const TextStyle(color: Colors.amber, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'â†’ ${matchingRide.destination}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${matchingRide.seatsAvailable} seat${matchingRide.seatsAvailable != 1 ? 's' : ''} available',
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'If you join, your hosted ride will be cancelled.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orangeAccent.withValues(alpha: 0.8), fontSize: 11),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('DECLINE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 8,
                        shadowColor: Colors.cyanAccent.withValues(alpha: 0.4),
                      ),
                      child: const Text('JOIN THEIR RIDE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (accepted != true || !mounted) return;

    // --- User accepted: cancel my new ride, join the matching ride ---
    try {
      // 1. Cancel my freshly-created ride
      await FirebaseFirestore.instance
          .collection('sharing_points')
          .doc(myNewRideId)
          .update({'status': 'expired'});

      // 2. Clear glowing path since we're joining, not hosting
      await _clearGlowingPath();

      // 3. Join the matching ride as a passenger (same logic as _joinRide in bottom sheet)
      final matchRef = FirebaseFirestore.instance
          .collection('sharing_points')
          .doc(matchingRide.id);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(matchRef);
        if (!snapshot.exists) throw Exception('Ride no longer exists.');
        final currentRide = SharingPoint.fromMap(snapshot.id, snapshot.data()!);
        if (currentRide.seatsAvailable <= 0) throw Exception('Ride is now full.');
        if (currentRide.isExpired) throw Exception('Ride has expired.');
        final newSeats = currentRide.seatsAvailable - 1;
        transaction.update(matchRef, {
          'passengers': FieldValue.arrayUnion([currentUserId]),
          'seatsAvailable': newSeats,
          'status': newSeats <= 0 ? 'full' : currentRide.status,
        });
      });

      // 4. Push initial passenger location
      try {
        if (_currentPosition != null) {
          await matchRef
              .collection('passenger_locations')
              .doc(currentUserId)
              .set({
            'lat': _currentPosition!.latitude,
            'lng': _currentPosition!.longitude,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {}

      // 5. System message in matched ride's chat
      await matchRef.collection('messages').add({
        'senderId': 'system',
        'senderName': 'System',
        'text': '${FirebaseAuth.instance.currentUser?.displayName ?? 'A user'} joined from a matching route!',
        'timestamp': FieldValue.serverTimestamp(),
        'isSystem': true,
      });

      _showSnackBar('âœ… Joined $hostName\'s ride!');
      debugPrint('âœ… Phase 12: Joined matching ride ${matchingRide.id}');
    } catch (e) {
      debugPrint('âŒ Phase 12 join error: $e');
      _showSnackBar('Could not join ride: ${e.toString().replaceAll('Exception: ', '')}', isError: true);
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
      debugPrint('âš ï¸ Route fetch error: $e');
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
    final messagesRef = docRef.collection('messages');

    try {
      if (isHost) {
        await messagesRef.add({
          'senderId': 'system',
          'senderName': 'System',
          'text': 'Host has cancelled the ride.',
          'timestamp': FieldValue.serverTimestamp(),
          'isSystem': true,
        });
        await docRef.update({'status': 'expired'});
        _showSnackBar('Ride cancelled.');
      } else {
        await messagesRef.add({
          'senderId': 'system',
          'senderName': 'System',
          'text': '${user?.displayName ?? 'A passenger'} has left the ride.',
          'timestamp': FieldValue.serverTimestamp(),
          'isSystem': true,
        });
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(docRef);
          if (!snapshot.exists) return;
          final currentRide = SharingPoint.fromMap(snapshot.id, snapshot.data()!);
          
          if (!currentRide.passengers.contains(user?.uid)) return;
          
          final newSeats = currentRide.seatsAvailable + 1;
          transaction.update(docRef, {
            'passengers': FieldValue.arrayRemove([user?.uid]),
            'arrivedPassengers': FieldValue.arrayRemove([user?.uid]),
            'seatsAvailable': newSeats,
            'status': currentRide.status == 'full' ? 'active' : currentRide.status,
          });
        });
        _showSnackBar('Left the ride.');
      }
      // Clear both the passenger route line AND the host glowing path
      await _clearRoute();
      await _clearGlowingPath();
      setState(() => _myCurrentRide = null);
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    }
  }

  // ===========================================================================
  // PHASE 17: WEATHER & AQI
  // ===========================================================================
  void _initWeatherAndAqi() {
    _fetchWeatherAndAqi();
    _weatherTimer = Timer.periodic(const Duration(minutes: 10), (_) => _fetchWeatherAndAqi());
  }

  Future<void> _fetchWeatherAndAqi() async {
    if (_currentPosition == null) return;
    try {
      final lat = _currentPosition!.latitude.toStringAsFixed(4);
      final lng = _currentPosition!.longitude.toStringAsFixed(4);
      
      final url = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current=temperature_2m,relative_humidity_2m,weather_code&hourly=pm2_5');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _currentTempC = data['current']['temperature_2m'];
            _humidity = data['current']['relative_humidity_2m'];
            _weatherCode = data['current']['weather_code'];
            
            // Simple AQI proxy using PM2.5 (from hourly array, just grab first for demo)
            final pm25 = data['hourly']['pm2_5']?[0] ?? 0.0;
            _currentAqi = pm25.toInt();
          });
        }
      }
    } catch (e) {
      debugPrint("Phase 17 Weather fetch error: $e");
    }
  }

  Widget _buildWeatherAqiWidget() {
    if (_currentTempC == null) return const SizedBox.shrink();
    
    IconData weatherIcon = Icons.wb_sunny;
    Color weatherColor = Colors.orangeAccent;
    if (_weatherCode != null) {
      if (_weatherCode! >= 50 && _weatherCode! <= 69) {
        weatherIcon = Icons.water_drop;
        weatherColor = Colors.lightBlueAccent;
      } else if (_weatherCode! >= 70 && _weatherCode! <= 79) {
        weatherIcon = Icons.ac_unit;
        weatherColor = Colors.white;
      } else if (_weatherCode! >= 95) {
        weatherIcon = Icons.flash_on;
        weatherColor = Colors.yellow;
      } else if (_weatherCode! >= 1 && _weatherCode! <= 3) {
        weatherIcon = Icons.cloud;
        weatherColor = Colors.grey;
      }
    }

    Color aqiColor = Colors.greenAccent;
    if (_currentAqi! > 50) aqiColor = Colors.yellowAccent;
    if (_currentAqi! > 100) aqiColor = Colors.orangeAccent;
    if (_currentAqi! > 150) aqiColor = Colors.redAccent;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 80,
      right: 16,
      child: GestureDetector(
        onTap: () => setState(() => _showTemperature = !_showTemperature),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(weatherIcon, color: weatherColor, size: 20),
              if (_showTemperature) ...[
                const SizedBox(width: 8),
                Text('${_currentTempC?.toStringAsFixed(1)}°C', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                const Icon(Icons.water_drop_outlined, color: Colors.blueAccent, size: 16),
                Text('${_humidity?.toInt()}%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
              const SizedBox(width: 12),
              Container(width: 1, height: 20, color: Colors.white24),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('AQI', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  Text('$_currentAqi', style: TextStyle(color: aqiColor, fontWeight: FontWeight.bold)),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PHASE 14 & 15: TRIP MODE & TRAFFIC ROUTING
  // ===========================================================================
  void _startTripMode(LatLng destination, String name) {
    setState(() {
      _isTripModeActive = true;
      _tripDestination = destination;
      _tripDestinationName = name;
    });
    
    // Clear any existing ride stuff just in case
    _clearGlowingPath();
    _clearRoute();
    
    // Fetch traffic route
    _fetchTrafficRoute();
    
    // Start auto-rerouting every 10 seconds (Phase 15 requirement)
    _tripRerouteTimer?.cancel();
    _tripRerouteTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_isTripModeActive && !_isDrawingTrip) {
        _fetchTrafficRoute();
      }
    });
  }

  void _cancelTripMode() {
    setState(() {
      _isTripModeActive = false;
      _tripDestination = null;
      _tripDestinationName = '';
    });
    _tripRerouteTimer?.cancel();
    _clearTrafficRoute();
  }

  Future<void> _clearTrafficRoute() async {
    if (_mapController == null) return;
    for (final line in _tripSegmentLines) {
      await _mapController!.removeLine(line);
    }
    _tripSegmentLines.clear();
  }

  Future<void> _fetchTrafficRoute() async {
    if (_currentPosition == null || _mapController == null || _tripDestination == null) return;
    _isDrawingTrip = true;

    try {
      final startLng = _currentPosition!.longitude.toStringAsFixed(6);
      final startLat = _currentPosition!.latitude.toStringAsFixed(6);
      final endLng = _tripDestination!.longitude.toStringAsFixed(6);
      final endLat = _tripDestination!.latitude.toStringAsFixed(6);

      // Using speed annotations to fake traffic
      final url = 'https://router.project-osrm.org/route/v1/driving/$startLng,$startLat;$endLng,$endLat?overview=full&geometries=geojson&annotations=speed';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry']['coordinates'] as List;
          final annotations = route['legs'][0]['annotation']['speed'] as List?;
          
          await _drawTrafficRoute(geometry, annotations);
        }
      }
    } catch (e) {
      debugPrint("Traffic Route fetch error: $e");
    } finally {
      _isDrawingTrip = false;
    }
  }

  Future<void> _drawTrafficRoute(List geometry, List? speeds) async {
    if (_mapController == null) return;
    
    // First remove old lines
    await _clearTrafficRoute();
    
    // Draw segments. If speed is high -> blue, medium -> orange, low -> red
    List<LatLng> currentSegment = [];
    Color currentColor = Colors.blueAccent;
    
    for (int i = 0; i < geometry.length; i++) {
      final coord = geometry[i];
      currentSegment.add(LatLng(coord[1], coord[0]));
      
      if (i < geometry.length - 1 && speeds != null && i < speeds.length) {
        final speed = (speeds[i] as num).toDouble();
        Color nextColor;
        if (speed < 5.0) { // < 18 km/h -> heavy traffic
          nextColor = Colors.redAccent;
        } else if (speed < 11.0) { // < 40 km/h -> medium traffic
          nextColor = Colors.orangeAccent;
        } else {
          nextColor = Colors.blueAccent;
        }
        
        // If color changes or it's the last segment, flush the current segment
        if (nextColor != currentColor || i == geometry.length - 2) {
          if (currentSegment.length > 1) {
            final line = await _mapController!.addLine(LineOptions(
              geometry: List.from(currentSegment),
              lineColor: '#${currentColor.value.toRadixString(16).substring(2, 8)}',
              lineWidth: 6.0,
              lineOpacity: 0.9,
            ));
            _tripSegmentLines.add(line);
          }
          // Start next segment with the last point to connect them
          currentSegment = [LatLng(coord[1], coord[0])];
          currentColor = nextColor;
        }
      }
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
                  _LiveCountdownText(expiresAt: _myCurrentRide!.expiresAt)
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

  Widget _buildSynchronousRatingOverlay() {
    final ride = _myCurrentRide!;
    final user = FirebaseAuth.instance.currentUser;
    final isHost = ride.creatorId == user?.uid;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.95), // Obscure the map heavily
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxHeight: 500, maxWidth: 400),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 2),
              boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.2), blurRadius: 20)],
            ),
            child: isHost 
              ? _HostRatingPassengersForm(rideToLeave: ride)
              : _PassengerRatingHostForm(rideToLeave: ride),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveRideBottomPanel() {
    if (_myCurrentRide!.status == 'rating_phase') return const SizedBox.shrink(); // Hide panel during rating

    final isHost = _myCurrentRide!.creatorId == FirebaseAuth.instance.currentUser?.uid;

    if (!isHost && _hasReachedPortal) {
      return Positioned(
        bottom: 24, left: 16, right: 16,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5), width: 2),
            boxShadow: [BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.2), blurRadius: 15)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.cyanAccent, size: 40),
              const SizedBox(height: 8),
              const Text('You have arrived!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Waiting for ${(_myCurrentRide!.totalSeats - _myCurrentRide!.arrivedPassengers.length).clamp(0, 99)} more passengers...', 
                style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Container(
                    decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: IconButton(onPressed: _showChatSheet, icon: const Icon(Icons.chat_bubble_outline), color: Colors.greenAccent),
                  ),
                  ElevatedButton.icon(
                    onPressed: _leaveOrCancelRide,
                    icon: const Icon(Icons.logout),
                    label: const Text('Leave Ride', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                  ),
                ],
              )
            ],
          ),
        ),
      );
    }

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
                // Chat Button
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _showChatSheet,
                    icon: const Icon(Icons.chat_bubble_outline),
                    color: Colors.greenAccent,
                    tooltip: 'Open Chat',
                  ),
                ),
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
          // â”€â”€â”€ MAP â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            onCameraIdle: () {},
            onCameraMove: (_) => _onUserMapInteraction(),
            trackCameraPosition: true,
            compassEnabled: false,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
          ),

          // â”€â”€â”€ TOP STATUS BAR OR HUD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                  GestureDetector(
                    onTap: _showProfileSheet,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.greenAccent.withValues(alpha: 0.2),
                      ),
                      child: const Icon(Icons.account_circle, color: Colors.greenAccent, size: 24),
                    ),
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

          // â”€â”€â”€ FABs (bottom-right) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Positioned(
            right: 16,
            bottom: _myCurrentRide != null ? 180 : 100,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_myCurrentRide == null && !_isTripModeActive) ...[
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
                  // Solo Trip FAB
                  _buildFab(
                    heroTag: 'trip_mode',
                    icon: Icons.directions,
                    tooltip: 'Start Trip',
                    onPressed: _showTripDialog,
                    color: Colors.deepPurpleAccent,
                    mini: false,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_isTripModeActive) ...[
                  _buildFab(
                    heroTag: 'end_trip',
                    icon: Icons.close,
                    tooltip: 'End Trip',
                    onPressed: _cancelTripMode,
                    color: Colors.redAccent,
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

          // â”€â”€â”€ GPS COORDS (debug) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

          // â”€â”€â”€ ACTIVE RIDE BOTTOM PANEL â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_myCurrentRide != null)
            _buildActiveRideBottomPanel(),

          // â”€â”€â”€ PHASE 10: SYNCHRONOUS RATING â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_myCurrentRide != null && _myCurrentRide!.status == 'rating_phase')
            _buildSynchronousRatingOverlay(),
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

  void _showProfileSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        final user = FirebaseAuth.instance.currentUser;
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_circle, size: 64, color: Colors.greenAccent),
              const SizedBox(height: 16),
              const Text('Your Profile', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (user?.displayName != null && user!.displayName!.isNotEmpty) ...[
                Text(user.displayName!, style: const TextStyle(color: Colors.cyanAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
              ],
              Text(user?.email ?? 'Unknown Email', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16)),
              const SizedBox(height: 8),
              Text('UID: ${user?.uid}', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
              const SizedBox(height: 16),
              // Phase 10: Fetch Average Safety Rating
              if (user != null)
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    final rating = (data['safetyRating'] as num?)?.toDouble() ?? 0.0;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 20),
                        const SizedBox(width: 4),
                        Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await FirebaseAuth.instance.signOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showChatSheet() {
    if (_myCurrentRide == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChatModalSheet(rideId: _myCurrentRide!.id),
    );
  }
}

// =============================================================================
// HOST RIDE DIALOG
// =============================================================================

class _HostRideDialog extends StatefulWidget {
  final LatLng? currentPos;
  const _HostRideDialog({this.currentPos});

  @override
  State<_HostRideDialog> createState() => _HostRideDialogState();
}

class _HostRideDialogState extends State<_HostRideDialog> {
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  int _selectedSeats = 2;
  int _selectedWaitMinutes = 30;
  final List<int> _seatOptions = [1, 2, 3, 4, 5, 6];
  final List<int> _waitOptions = [15, 30, 45, 60];

  LatLng? _fromCoords;
  LatLng? _toCoords;
  List<dynamic> _fromSuggestions = [];
  List<dynamic> _toSuggestions = [];
  Timer? _debounce;
  bool _isLoadingFrom = false;
  bool _isLoadingTo = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentPos != null) {
      _fromController.text = "Current Location";
      _fromCoords = widget.currentPos;
    }
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchSuggestions(String query, bool isFrom) async {
    if (query.length < 3) {
      setState(() {
        if (isFrom) _fromSuggestions = [];
        else _toSuggestions = [];
      });
      return;
    }

    setState(() {
      if (isFrom) _isLoadingFrom = true;
      else _isLoadingTo = true;
    });

    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=5&addressdetails=1');
      final response = await http.get(url, headers: {'User-Agent': 'GeoRideApp'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          if (isFrom) _fromSuggestions = data;
          else _toSuggestions = data;
        });
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (isFrom) _isLoadingFrom = false;
          else _isLoadingTo = false;
        });
      }
    }
  }

  void _onSearchChanged(String query, bool isFrom) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(query, isFrom);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.orangeAccent.withValues(alpha: 0.1), blurRadius: 40, spreadRadius: 5)],
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
                    child: const Icon(Icons.rocket_launch, color: Colors.orangeAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Host a Ride', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text('Set your journey details', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // FROM Field
              _buildLocationField(
                label: 'FROM',
                controller: _fromController,
                hint: 'Starting point...',
                icon: Icons.my_location,
                isFrom: true,
                isLoading: _isLoadingFrom,
                suggestions: _fromSuggestions,
                onSelected: (item) {
                  setState(() {
                    _fromController.text = item['display_name'];
                    _fromCoords = LatLng(double.parse(item['lat']), double.parse(item['lon']));
                    _fromSuggestions = [];
                  });
                },
              ),
              const SizedBox(height: 16),

              // TO Field
              _buildLocationField(
                label: 'TO (DESTINATION)',
                controller: _toController,
                hint: 'Where are you going?',
                icon: Icons.place,
                isFrom: false,
                isLoading: _isLoadingTo,
                suggestions: _toSuggestions,
                onSelected: (item) {
                  setState(() {
                    _toController.text = item['display_name'];
                    _toCoords = LatLng(double.parse(item['lat']), double.parse(item['lon']));
                    _toSuggestions = [];
                  });
                },
              ),
              const SizedBox(height: 24),

              // Seats & Wait Time (compact)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('SEATS', style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        _buildSeatPicker(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('WAIT TIME', style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        _buildWaitPicker(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _validateAndSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 8,
                        shadowColor: Colors.orangeAccent.withValues(alpha: 0.3),
                      ),
                      child: const Text('CREATE RIDE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
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

  Widget _buildLocationField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isFrom,
    required bool isLoading,
    required List<dynamic> suggestions,
    required Function(dynamic) onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const Spacer(),
            if (isFrom)
              GestureDetector(
                onTap: () {
                  if (widget.currentPos != null) {
                    setState(() {
                      _fromController.text = "Current Location";
                      _fromCoords = widget.currentPos;
                      _fromSuggestions = [];
                    });
                  }
                },
                child: const Text('USE CURRENT', style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: (val) => _onSearchChanged(val, isFrom),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
            prefixIcon: Icon(icon, color: Colors.orangeAccent.withValues(alpha: 0.6), size: 18),
            suffixIcon: isLoading ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent))) : null,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: const Color(0xFF252545),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
              itemBuilder: (ctx, idx) {
                final item = suggestions[idx];
                return ListTile(
                  dense: true,
                  title: Text(item['display_name'], style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => onSelected(item),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSeatPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButton<int>(
        value: _selectedSeats,
        dropdownColor: const Color(0xFF1A1A2E),
        underline: const SizedBox.shrink(),
        isExpanded: true,
        icon: const Icon(Icons.arrow_drop_down, color: Colors.orangeAccent),
        items: _seatOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s Seats', style: const TextStyle(color: Colors.white, fontSize: 14)))).toList(),
        onChanged: (val) => setState(() => _selectedSeats = val!),
      ),
    );
  }

  Widget _buildWaitPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButton<int>(
        value: _selectedWaitMinutes,
        dropdownColor: const Color(0xFF1A1A2E),
        underline: const SizedBox.shrink(),
        isExpanded: true,
        icon: const Icon(Icons.arrow_drop_down, color: Colors.orangeAccent),
        items: _waitOptions.map((m) => DropdownMenuItem(value: m, child: Text('${m}m Wait', style: const TextStyle(color: Colors.white, fontSize: 14)))).toList(),
        onChanged: (val) => setState(() => _selectedWaitMinutes = val!),
      ),
    );
  }

  void _validateAndSubmit() {
    if (_fromCoords == null || _fromController.text.isEmpty) {
      _showError('Please select a valid starting point');
      return;
    }
    if (_toCoords == null || _toController.text.isEmpty) {
      _showError('Please select a valid destination');
      return;
    }

    Navigator.of(context).pop({
      'fromName': _fromController.text,
      'fromLat': _fromCoords!.latitude,
      'fromLng': _fromCoords!.longitude,
      'toName': _toController.text,
      'toLat': _toCoords!.latitude,
      'toLng': _toCoords!.longitude,
      'seats': _selectedSeats,
      'waitMinutes': _selectedWaitMinutes,
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }
}

// =============================================================================
// TRIP DIALOG (SOLO NAVIGATION)
// =============================================================================

class _TripDialog extends StatefulWidget {
  final LatLng? currentPos;
  const _TripDialog({this.currentPos});

  @override
  State<_TripDialog> createState() => _TripDialogState();
}

class _TripDialogState extends State<_TripDialog> {
  final _fromController = TextEditingController();
  final _toController = TextEditingController();

  LatLng? _fromCoords;
  LatLng? _toCoords;
  List<dynamic> _fromSuggestions = [];
  List<dynamic> _toSuggestions = [];
  Timer? _debounce;
  bool _isLoadingFrom = false;
  bool _isLoadingTo = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentPos != null) {
      _fromController.text = "Current Location";
      _fromCoords = widget.currentPos;
    }
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchSuggestions(String query, bool isFrom) async {
    if (query.length < 3) {
      setState(() {
        if (isFrom) _fromSuggestions = [];
        else _toSuggestions = [];
      });
      return;
    }

    setState(() {
      if (isFrom) _isLoadingFrom = true;
      else _isLoadingTo = true;
    });

    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=5&addressdetails=1');
      final response = await http.get(url, headers: {'User-Agent': 'GeoRideApp'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          if (isFrom) _fromSuggestions = data;
          else _toSuggestions = data;
        });
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (isFrom) _isLoadingFrom = false;
          else _isLoadingTo = false;
        });
      }
    }
  }

  void _onSearchChanged(String query, bool isFrom) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(query, isFrom);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.deepPurpleAccent.withValues(alpha: 0.1), blurRadius: 40, spreadRadius: 5)],
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
                      color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.directions, color: Colors.deepPurpleAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Start a Trip', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text('Navigate to your destination', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // FROM Field
              _buildLocationField(
                label: 'FROM',
                controller: _fromController,
                hint: 'Starting point...',
                icon: Icons.my_location,
                isFrom: true,
                isLoading: _isLoadingFrom,
                suggestions: _fromSuggestions,
                onSelected: (item) {
                  setState(() {
                    _fromController.text = item['display_name'];
                    _fromCoords = LatLng(double.parse(item['lat']), double.parse(item['lon']));
                    _fromSuggestions = [];
                  });
                },
              ),
              const SizedBox(height: 16),

              // TO Field
              _buildLocationField(
                label: 'TO (DESTINATION)',
                controller: _toController,
                hint: 'Where are you going?',
                icon: Icons.place,
                isFrom: false,
                isLoading: _isLoadingTo,
                suggestions: _toSuggestions,
                onSelected: (item) {
                  setState(() {
                    _toController.text = item['display_name'];
                    _toCoords = LatLng(double.parse(item['lat']), double.parse(item['lon']));
                    _toSuggestions = [];
                  });
                },
              ),
              const SizedBox(height: 32),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Start Trip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
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

  Widget _buildLocationField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isFrom,
    required bool isLoading,
    required List<dynamic> suggestions,
    required Function(dynamic) onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(color: Colors.white30),
                  prefixIcon: Icon(icon, color: Colors.deepPurpleAccent.withValues(alpha: 0.7)),
                  suffixIcon: isLoading
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.deepPurpleAccent))))
                      : isFrom
                          ? IconButton(
                              icon: const Icon(Icons.my_location, color: Colors.white54, size: 20),
                              onPressed: () {
                                if (widget.currentPos != null) {
                                  setState(() {
                                    controller.text = "Current Location";
                                    _fromCoords = widget.currentPos;
                                    _fromSuggestions = [];
                                  });
                                }
                              },
                            )
                          : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                onChanged: (val) => _onSearchChanged(val, isFrom),
              ),
              if (suggestions.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: suggestions.length,
                    itemBuilder: (ctx, i) {
                      final item = suggestions[i];
                      return ListTile(
                        leading: const Icon(Icons.location_on, color: Colors.white54, size: 16),
                        title: Text(item['display_name'], style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => onSelected(item),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _submit() {
    if (_fromCoords == null || _fromController.text.isEmpty) {
      _showError('Please select a valid starting point');
      return;
    }
    if (_toCoords == null || _toController.text.isEmpty) {
      _showError('Please select a valid destination');
      return;
    }

    Navigator.of(context).pop({
      'fromName': _fromController.text,
      'fromLat': _fromCoords!.latitude,
      'fromLng': _fromCoords!.longitude,
      'toName': _toController.text,
      'toLat': _toCoords!.latitude,
      'toLng': _toCoords!.longitude,
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
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
      
      // Push initial passenger location immediately upon joining.
      try {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        await FirebaseFirestore.instance
            .collection('sharing_points')
            .doc(widget.rideId)
            .collection('passenger_locations')
            .doc(widget.currentUserId)
            .set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      
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
                const SizedBox(height: 16),

                // Host Phase 9 Rating
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(ride.creatorId).snapshots(),
                  builder: (context, hostSnap) {
                    if (!hostSnap.hasData || !hostSnap.data!.exists) return const SizedBox.shrink();
                    final hostData = hostSnap.data!.data() as Map<String, dynamic>;
                    final rating = (hostData['safetyRating'] as num?)?.toDouble() ?? 0.0;
                    final hostName = hostData['displayName'] ?? 'Trainer';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Row(
                        children: [
                          const Icon(Icons.shield, color: Colors.greenAccent, size: 20),
                          const SizedBox(width: 8),
                          Text('Hosted by $hostName ', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          const Spacer(),
                          const Icon(Icons.star, color: Colors.amber, size: 18),
                          const SizedBox(width: 4),
                          Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    );
                  },
                ),

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

// =============================================================================
// PHASE 10: INDEPENDENT RATING FORMS
//
// Design: Both host and passengers submit independently. Each submission:
//   1. Writes to the target user(s) rating profile
//   2. Adds the submitter's UID to the ride's `ratedBy` array (arrayUnion)
//   3. If ratedBy.length >= arrivedPassengers.length + 1 (host + all arrived),
//      the transaction also sets status='expired' â€” only then does the ride end.
//
// This ensures NO single submission closes anyone else's form.
// =============================================================================

// -----------------------------------------------------------------------------
// Helper: submit a rating to a user's profile (shared by both forms)
// -----------------------------------------------------------------------------
Future<void> _submitUserRating(String uid, int stars) async {
  final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
  await FirebaseFirestore.instance.runTransaction((t) async {
    final snap = await t.get(docRef);
    if (!snap.exists) {
      t.set(docRef, {
        'safetyRating': stars.toDouble(),
        'ratingCount': 1,
        'ratingSum': stars,
      });
    } else {
      final data = snap.data()!;
      final count = (data['ratingCount'] as num?)?.toInt() ?? 0;
      final sum = (data['ratingSum'] as num?)?.toInt() ?? 0;
      t.update(docRef, {
        'ratingCount': count + 1,
        'ratingSum': sum + stars,
        'safetyRating': (sum + stars) / (count + 1),
      });
    }
  });
}

// -----------------------------------------------------------------------------
// Helper: mark this UID as having rated, and expire the ride if everyone has.
// Returns true if the ride was just expired (this person was last).
// -----------------------------------------------------------------------------
Future<bool> _markRatedAndMaybeExpire({
  required String rideId,
  required String submitterUid,
  required int totalArrivedPassengers, // does NOT include host
}) async {
  bool didExpire = false;
  final rideRef = FirebaseFirestore.instance.collection('sharing_points').doc(rideId);
  await FirebaseFirestore.instance.runTransaction((t) async {
    final snap = await t.get(rideRef);
    if (!snap.exists) return;
    final data = snap.data()!;
    final currentRatedBy = List<String>.from(data['ratedBy'] ?? []);
    if (currentRatedBy.contains(submitterUid)) return; // already submitted
    currentRatedBy.add(submitterUid);
    // Total raters = arrived passengers + 1 host
    final needed = totalArrivedPassengers + 1;
    if (currentRatedBy.length >= needed) {
      // Last person â€” expire the ride
      t.update(rideRef, {'ratedBy': currentRatedBy, 'status': 'expired'});
      didExpire = true;
    } else {
      t.update(rideRef, {'ratedBy': currentRatedBy});
    }
  });
  return didExpire;
}

// =============================================================================
// PASSENGER RATING FORM â€” rates the host
// =============================================================================

class _PassengerRatingHostForm extends StatefulWidget {
  final SharingPoint rideToLeave;
  const _PassengerRatingHostForm({required this.rideToLeave});

  @override
  State<_PassengerRatingHostForm> createState() => _PassengerRatingHostFormState();
}

class _PassengerRatingHostFormState extends State<_PassengerRatingHostForm> {
  int _rating = 0;
  bool _isSaving = false;
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    if (_isSaving) {
      return const Center(child: CircularProgressIndicator(color: Colors.amber));
    }

    if (_submitted) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 60),
          const SizedBox(height: 16),
          const Text('Rating Submitted!',
              style: TextStyle(color: Colors.greenAccent, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'You gave the host $_rating ${_rating == 1 ? 'star' : 'stars'}.\nWaiting for everyone to finish rating...',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 20),
          const CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.stars, color: Colors.amber, size: 48),
        const SizedBox(height: 16),
        const Text('Ride Completed!',
            style: TextStyle(color: Colors.cyanAccent, fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Rate your Host.', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) => IconButton(
            icon: Icon(
              i < _rating ? Icons.star : Icons.star_border,
              color: i < _rating ? Colors.amber : Colors.white24,
              size: 40,
            ),
            onPressed: () => setState(() => _rating = i + 1),
          )),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _rating > 0 ? () async {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;
            setState(() => _isSaving = true);
            try {
              // 1. Write host's rating
              await _submitUserRating(widget.rideToLeave.creatorId, _rating);
              // 2. Mark this passenger as rated; expire ride if everyone has rated
              await _markRatedAndMaybeExpire(
                rideId: widget.rideToLeave.id,
                submitterUid: user.uid,
                totalArrivedPassengers: widget.rideToLeave.arrivedPassengers.length,
              );
              setState(() { _isSaving = false; _submitted = true; });
            } catch (e) {
              debugPrint('Passenger rating error: $e');
              setState(() => _isSaving = false);
            }
          } : null,
          icon: const Icon(Icons.check),
          label: const Text('Submit Rating', style: TextStyle(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// HOST RATING FORM â€” rates all arrived passengers
// =============================================================================

class _HostRatingPassengersForm extends StatefulWidget {
  final SharingPoint rideToLeave;
  const _HostRatingPassengersForm({required this.rideToLeave});

  @override
  State<_HostRatingPassengersForm> createState() => _HostRatingPassengersFormState();
}

class _HostRatingPassengersFormState extends State<_HostRatingPassengersForm> {
  final Map<String, int> _ratings = {};
  late List<String> _passengersToRate;
  bool _isSaving = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _passengersToRate = List.from(widget.rideToLeave.arrivedPassengers);
    for (final uid in _passengersToRate) {
      _ratings[uid] = 0;
    }
  }

  bool get _allRated => _ratings.isNotEmpty && _ratings.values.every((v) => v > 0);

  @override
  Widget build(BuildContext context) {
    if (_isSaving) {
      return const Center(child: CircularProgressIndicator(color: Colors.amber));
    }

    if (_submitted) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 60),
          const SizedBox(height: 16),
          const Text('Ratings Submitted!',
              style: TextStyle(color: Colors.greenAccent, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Waiting for passengers to finish rating...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 20),
          const CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
        ],
      );
    }

    if (_passengersToRate.isEmpty) {
      // No passengers arrived â€” host can just end the ride immediately
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield, color: Colors.greenAccent, size: 48),
          const SizedBox(height: 16),
          const Text('Ride Completed!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('No passengers to rate.', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              setState(() => _isSaving = true);
              try {
                await FirebaseFirestore.instance
                    .collection('sharing_points')
                    .doc(widget.rideToLeave.id)
                    .update({'status': 'expired'});
              } catch (e) {
                debugPrint('Host end ride error: $e');
              }
            },
            icon: const Icon(Icons.check_circle),
            label: const Text('End Ride', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.shield, color: Colors.greenAccent, size: 48),
        const SizedBox(height: 12),
        const Text('Ride Completed!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.greenAccent, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Rate each passenger below.', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 12),
        SizedBox(
          height: (_passengersToRate.length * 100.0).clamp(80.0, 260.0),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _passengersToRate.length,
            itemBuilder: (ctx, index) {
              final pid = _passengersToRate[index];
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(pid).get(),
                builder: (context, snapshot) {
                  String name = 'Passenger';
                  if (snapshot.hasData && snapshot.data!.exists) {
                    name = (snapshot.data!.data() as Map<String, dynamic>?)?['displayName'] ?? 'Passenger';
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        Row(
                          children: List.generate(5, (starIdx) => IconButton(
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              starIdx < (_ratings[pid] ?? 0) ? Icons.star : Icons.star_border,
                              color: starIdx < (_ratings[pid] ?? 0) ? Colors.amber : Colors.white24,
                              size: 30,
                            ),
                            onPressed: () => setState(() => _ratings[pid] = starIdx + 1),
                          )),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _allRated ? () async {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;
            setState(() => _isSaving = true);
            try {
              // 1. Write ratings to each passenger's profile
              for (final pid in _ratings.keys) {
                await _submitUserRating(pid, _ratings[pid]!);
              }
              // 2. Mark host as rated; expire ride if everyone has rated
              await _markRatedAndMaybeExpire(
                rideId: widget.rideToLeave.id,
                submitterUid: user.uid,
                totalArrivedPassengers: widget.rideToLeave.arrivedPassengers.length,
              );
              setState(() { _isSaving = false; _submitted = true; });
            } catch (e) {
              debugPrint('Host rating error: $e');
              setState(() => _isSaving = false);
            }
          } : null,
          icon: const Icon(Icons.check_circle),
          label: const Text('Submit All & End Ride', style: TextStyle(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
      ],
    );
  }
}

