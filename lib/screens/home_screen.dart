import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/location_service.dart';
import '../services/sharing_service.dart';
import '../models/sharing_point.dart';
import '../widgets/avatar_marker.dart';
import '../widgets/portal_marker.dart';
import '../widgets/ride_preview_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final SharingService _sharingService = SharingService();

  StreamSubscription<Position>? _positionStream;
  StreamSubscription<List<SharingPoint>>? _ridesSubscription;
  Timer? _expiryTimer;

  Position? _currentPosition;
  bool _isMapReady = false;
  bool _is3DMode = true;

  // Zoom tracking for counter-scaling avatar
  double _currentZoom = 16.0;
  static const double _baseZoom = 16.0;

  // Ride tracking
  List<SharingPoint> _allActiveRides = [];
  SharingPoint? _hostedRide;
  SharingPoint? _joinedRide;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _initRidesStream();
    _startExpiryTimer();
  }

  void _initRidesStream() {
    _ridesSubscription = _sharingService.getActiveRidesStream().listen((rides) {
      if (!mounted) return;

      final userId = FirebaseAuth.instance.currentUser?.uid;

      setState(() {
        _allActiveRides = rides;

        try {
          _hostedRide = rides.firstWhere((r) => r.creatorId == userId);
        } catch (_) {
          _hostedRide = null;
        }

        try {
          _joinedRide = rides.firstWhere((r) => r.passengers.contains(userId));
        } catch (_) {
          _joinedRide = null;
        }
      });
    });
  }

  Future<void> _initLocation() async {
    final hasPermission = await LocationService.requestPermission();
    if (hasPermission) {
      Position initialPosition = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = initialPosition;
        _currentZoom = _is3DMode ? 16.0 : 18.0;
      });

      _positionStream = LocationService.getLocationStream().listen((Position position) {
        setState(() {
          _currentPosition = position;
        });

        // Always keep map centered on player
        if (_isMapReady) {
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            _currentZoom,
          );
        }
      });
    }
  }

  void _startExpiryTimer() {
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sharingService.expireOldRides();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _ridesSubscription?.cancel();
    _expiryTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Counter-scale factor: keeps avatar at medium size.
  /// Upper clamp prevents growth when zooming out.
  double get _avatarScaleFactor {
    final currentZoom = _isMapReady ? _mapController.camera.zoom : _currentZoom;
    final zoomDiff = _baseZoom - currentZoom;
    double scale = math.pow(1.3, zoomDiff).toDouble();
    // Upper limit = 0.85 (never grows beyond medium)
    // Lower limit = 0.5 (doesn't shrink too small)
    return scale.clamp(0.5, 0.85);
  }

  void _snapBackToPlayer() {
    if (_currentPosition == null || !_isMapReady) return;
    _mapController.move(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      _currentZoom,
    );
  }

  void _navigateToRideLocation(SharingPoint ride) {
    _mapController.move(
      LatLng(ride.lat, ride.lng),
      _is3DMode ? 17.0 : 19.0,
    );
  }

  List<SharingPoint> _getNearbyRides() {
    if (_currentPosition == null) return [];

    return _allActiveRides.where((ride) {
      if (ride.isExpired) return false;
      if (ride.seatsAvailable <= 0) return false;
      if (DateTime.now().difference(ride.createdAt).inMinutes > 30) return false;

      double distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        ride.lat,
        ride.lng,
      );

      return distance <= 5000;
    }).toList();
  }

  void _showRidePreview(SharingPoint point) {
    if (_currentPosition == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => RidePreviewCard(
        ride: point,
        userPosition: _currentPosition!,
        onJoin: () {},
      ),
    );
  }

  void _hostRideDialog() {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not authenticated. Please restart the app.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_hostedRide != null && !_hostedRide!.isExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already have an active ride. Cancel it first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_joinedRide != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already in a ride. Leave it first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final destController = TextEditingController();
    int seats = 3;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1B2321),
          title: const Text('Host a Ride', style: TextStyle(color: Colors.white)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: destController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Where are you going?',
                    labelStyle: TextStyle(color: Colors.grey),
                    hintText: 'e.g., Andheri Station, Office',
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter destination';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    const Text('Available Seats:', style: TextStyle(color: Colors.white)),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.remove, color: Colors.greenAccent),
                      onPressed: () {
                        if (seats > 1) setDialogState(() => seats--);
                      },
                    ),
                    Text(
                      '$seats',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.greenAccent),
                      onPressed: () {
                        if (seats < 6) setDialogState(() => seats++);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Ride expires in 30 minutes',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  if (_currentPosition == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Waiting for location...')),
                    );
                    return;
                  }

                  try {
                    setDialogState(() {});

                    debugPrint('🚗 Creating ride: ${destController.text}, $seats seats');

                    await _sharingService.createSharingPoint(
                      lat: _currentPosition!.latitude,
                      lng: _currentPosition!.longitude,
                      destination: destController.text.trim(),
                      seatsAvailable: seats,
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🎉 Ride created! Waiting for passengers...'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint('❌ Error creating ride: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to create ride: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Create Portal'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPosition == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1B2321),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.greenAccent),
              SizedBox(height: 20),
              Text(
                'Getting your location...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    final nearbyRides = _getNearbyRides();
    final isInAnyRide = _joinedRide != null || _hostedRide != null;
    final playerLatLng = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    // Build ride markers (NO avatar marker here — it's a screen overlay)
    List<Marker> rideMarkers = nearbyRides.map((ride) {
      final isMyRide = ride.creatorId == userId;
      final isMarkerVisible = isMyRide || ride.seatsAvailable > 0;

      if (!isMarkerVisible) {
        return Marker(
          point: LatLng(ride.lat, ride.lng),
          width: 0,
          height: 0,
          child: const SizedBox.shrink(),
        );
      }

      return Marker(
        point: LatLng(ride.lat, ride.lng),
        width: _is3DMode ? 65.0 : 90.0,
        height: _is3DMode ? 65.0 : 90.0,
        alignment: Alignment.center,
        child: PortalMarker(
          size: _is3DMode ? 65.0 : 90.0,
          isActive: ride.seatsAvailable > 0,
          onTap: () => _showRidePreview(ride),
        ),
      );
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Stack(
        children: [
          // MAP
          Transform.scale(
            scale: _is3DMode ? 3.5 : 1.0,
            alignment: FractionalOffset.center,
            child: Transform(
              alignment: FractionalOffset.center,
              transform: _is3DMode
                  ? (Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateX(-0.65)
                      ..translate(0.0, 50.0))
                  : Matrix4.identity(),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: playerLatLng,
                  initialZoom: _is3DMode ? 16.0 : 18.0,
                  minZoom: 15.0,
                  maxZoom: 19.0,
                  keepAlive: true,
                  onMapReady: () {
                    _isMapReady = true;
                    _mapController.move(playerLatLng, _currentZoom);
                  },
                  onPositionChanged: (position, hasGesture) {
                    // Just update zoom tracking — no move() here to avoid feedback loop
                    if (position.zoom != null) {
                      _currentZoom = position.zoom!;
                    }
                    // Rebuild to update counter-scale
                    setState(() {});
                  },
                  interactionOptions: InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        "https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png",
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.example.georide',
                  ),
                  MarkerLayer(
                    markers: [
                      ...rideMarkers,
                      // User avatar marker with counter-scaling and mode-based sizing
                      Marker(
                        point: LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        ),
                        width: _is3DMode ? 50.0 : 140.0,
                        height: _is3DMode ? 50.0 : 140.0,
                        alignment: Alignment.center,
                        child: Transform.scale(
                          scale: _avatarScaleFactor,
                          child: AvatarMarker(size: _is3DMode ? 50.0 : 140.0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // TOP HUD
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: _buildHud(userId),
          ),

          // BOTTOM ride panels
          if (_joinedRide != null) _buildPassengerRidePanel(),
          if (_hostedRide != null && !_hostedRide!.isExpired) _buildHostRidePanel(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Host Ride Button
            if (!isInAnyRide)
              FloatingActionButton.extended(
                heroTag: "hostRideBtn",
                backgroundColor: Colors.blueAccent,
                onPressed: _hostRideDialog,
                icon: const Icon(Icons.add_location_alt, color: Colors.white),
                label: const Text(
                  "Host Ride",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              )
            else
              const SizedBox(),

            // Right Side Controls
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 3D Toggle
                FloatingActionButton(
                  heroTag: "toggle3DBtn",
                  backgroundColor: _is3DMode ? Colors.greenAccent : Colors.grey[300],
                  onPressed: () {
                    setState(() {
                      _is3DMode = !_is3DMode;
                    });
                    _snapBackToPlayer();
                    if (_currentPosition != null) {
                      _mapController.move(
                        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                        _is3DMode ? 16.0 : 18.0,
                      );
                    }
                  },
                  child: Icon(
                    _is3DMode ? Icons.layers : Icons.map,
                    color: _is3DMode ? Colors.black : Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                // Recenter Button
                FloatingActionButton(
                  heroTag: "myLocationBtn",
                  backgroundColor: Colors.greenAccent,
                  onPressed: _snapBackToPlayer,
                  child: const Icon(Icons.my_location, color: Colors.black),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHud(String? userId) {
    if (_hostedRide != null && !_hostedRide!.isExpired) {
      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blueAccent, width: 2),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.car_crash, color: Colors.blueAccent, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'YOUR HOSTED RIDE',
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'To: ${_hostedRide!.destination}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Passengers: ${_hostedRide!.passengers.length} | Seats: ${_hostedRide!.seatsAvailable}/${_hostedRide!.totalSeats}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Expires: ${_hostedRide!.timeRemainingText}',
              style: TextStyle(
                color: _hostedRide!.timeRemaining.inMinutes < 5 ? Colors.red : Colors.orangeAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    if (_joinedRide != null) {
      final distanceToHost = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _joinedRide!.lat,
        _joinedRide!.lng,
      );

      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.greenAccent, width: 2),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'ONGOING RIDE',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'To: ${_joinedRide!.destination}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Distance to Host: ${SharingService.formatDistance(distanceToHost)}',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Follow the map to reach host',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.radar, color: Colors.greenAccent),
          SizedBox(width: 10),
          Text(
            'GeoRide Scanner Active',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerRidePanel() {
    if (_joinedRide == null || _currentPosition == null) return const SizedBox.shrink();

    final ride = _joinedRide!;
    final distanceToHost = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      ride.lat,
      ride.lng,
    );

    return Positioned(
      bottom: 100,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.greenAccent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.navigation, color: Colors.greenAccent, size: 20),
                SizedBox(width: 8),
                Text(
                  'NAVIGATING TO HOST',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.white, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Host Location',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    SharingService.formatDistance(distanceToHost),
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ride.destination,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _navigateToRideLocation(ride),
                    icon: const Icon(Icons.navigation),
                    label: const Text(
                      'Go to Host',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final success = await _sharingService.leaveRide(ride);
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Left the ride.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text(
                    'Leave',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostRidePanel() {
    if (_hostedRide == null) return const SizedBox.shrink();

    final ride = _hostedRide!;

    return Positioned(
      bottom: 100,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blueAccent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.person, color: Colors.blueAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'YOUR RIDE',
                      style: TextStyle(
                        color: Colors.blueAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Text(
                  ride.timeRemainingText,
                  style: TextStyle(
                    color: ride.timeRemaining.inMinutes < 5 ? Colors.red : Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'To: ${ride.destination}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.group, color: Colors.grey, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${ride.passengers.length} passenger(s) | ${ride.seatsAvailable} seats left',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
            if (ride.passengers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: const Text(
                  'Passengers are on their way!',
                  style: TextStyle(color: Colors.green, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                final success = await _sharingService.cancelRide(ride);
                if (success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ride cancelled.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.cancel),
              label: const Text(
                'Cancel Ride',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
