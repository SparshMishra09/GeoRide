import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/location_service.dart';
import '../services/sharing_service.dart';
import '../models/sharing_point.dart';
import '../widgets/avatar_marker.dart';
import '../widgets/sharing_marker.dart';
import '../widgets/ride_preview_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<QuerySnapshot>? _ridesSubscription;
  
  LatLng? _currentLocation;
  bool _isMapReady = false;
  bool _is3DMode = true;

  List<SharingPoint> _allActiveRides = [];
  SharingPoint? _activeRide;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _initRidesStream();
  }

  void _initRidesStream() {
    _ridesSubscription = FirebaseFirestore.instance
      .collection('sharing_points')
      .where('status', isEqualTo: 'active')
      .snapshots()
      .listen((snapshot) {
         if (!mounted) return;
         setState(() {
            _allActiveRides = snapshot.docs.map((doc) => SharingPoint.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList();
            // Check if we are currently in an active ride
            final me = SharingService().currentUserId;
            try {
              _activeRide = _allActiveRides.firstWhere((r) => r.passengers.contains(me));
            } catch(e) {
              _activeRide = null; 
            }
         });
      });
  }

  Future<void> _initLocation() async {
    final hasPermission = await LocationService.requestPermission();
    if (hasPermission) {
      Position initialPosition = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(initialPosition.latitude, initialPosition.longitude);
      });
      _positionStream = LocationService.getLocationStream().listen((Position position) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        if (_isMapReady) {
            _mapController.move(_currentLocation!, _mapController.camera.zoom);
        }
      });
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _ridesSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }
  
  List<SharingPoint> _getNearbyRides() {
    if (_currentLocation == null) return [];
    return _allActiveRides.where((p) {
       if (DateTime.now().difference(p.createdAt).inMinutes > 60) return false;
       double distance = Geolocator.distanceBetween(_currentLocation!.latitude, _currentLocation!.longitude, p.lat, p.lng);
       return distance <= 5000;
    }).toList();
  }

  void _showRidePreview(SharingPoint point) {
     showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => RidePreviewCard(
           ride: point, 
           onJoin: () {
             // UI will update automatically because of _ridesSubscription Stream
           }
        )
     );
  }

  void _hostRideDialog() {
     final user = FirebaseAuth.instance.currentUser;
     debugPrint('Host Ride - Current user: ${user?.uid}');
     debugPrint('Host Ride - Is anonymous: ${user?.isAnonymous}');
     
     if (user == null) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text('Not authenticated. Please restart the app.'),
           backgroundColor: Colors.red,
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
                     labelText: 'Destination', 
                     labelStyle: TextStyle(color: Colors.grey),
                     hintText: 'e.g., Andheri Station',
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
                     const Text('Seats:', style: TextStyle(color: Colors.white)),
                     const SizedBox(width: 10),
                     IconButton(
                       icon: const Icon(Icons.remove, color: Colors.greenAccent),
                       onPressed: () {
                         if (seats > 1) {
                           setDialogState(() => seats--);
                         }
                       },
                     ),
                     Text('$seats', style: const TextStyle(color: Colors.white, fontSize: 18)),
                     IconButton(
                       icon: const Icon(Icons.add, color: Colors.greenAccent),
                       onPressed: () {
                         if (seats < 6) {
                           setDialogState(() => seats++);
                         }
                       },
                     ),
                   ],
                 ),
               ],
             ),
           ),
           actions: [
             TextButton(
               onPressed: ()=> Navigator.pop(context), 
               child: const Text("Cancel")
             ),
             ElevatedButton(
               onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    if (_currentLocation == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Waiting for location...')),
                      );
                      return;
                    }
                    
                    try {
                      // Show loading
                      setDialogState(() {});
                      
                      debugPrint('Creating sharing point: dest=${destController.text}, seats=$seats, lat=${_currentLocation!.latitude}, lng=${_currentLocation!.longitude}');
                      
                      await SharingService().createSharingPoint(
                        lat: _currentLocation!.latitude,
                        lng: _currentLocation!.longitude,
                        destination: destController.text.trim(),
                        seatsAvailable: seats
                      );
                      
                      debugPrint('Sharing point created successfully!');
                      
                      if(context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ride created! Waiting for passengers...'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('Error creating sharing point: $e');
                      if(context.mounted) {
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
               child: const Text("Create Portal")
             )
           ],
         ),
       )
     );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentLocation == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1B2321),
        body: Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
      );
    }
    
    final nearbyRides = _getNearbyRides();
    
    // Convert rides to Map Markers
    List<Marker> rideMarkers = nearbyRides.map((ride) => Marker(
       point: LatLng(ride.lat, ride.lng),
       width: _is3DMode ? 40.0 : 60.0,
       height: _is3DMode ? 40.0 : 60.0,
       alignment: Alignment.center,
       child: Transform(
          alignment: FractionalOffset.center,
          transform: _is3DMode ? (Matrix4.identity()..rotateX(0.65)) : Matrix4.identity(),
          child: SharingMarker(size: _is3DMode ? 40.0 : 60.0, onTap: () => _showRidePreview(ride)),
       )
    )).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Stack(
        children: [
          Transform.scale(
            scale: _is3DMode ? 3.5 : 1.0, 
            alignment: FractionalOffset.center,
            child: Transform(
              alignment: FractionalOffset.center,
              transform: _is3DMode 
                  ? (Matrix4.identity()..setEntry(3, 2, 0.001)..rotateX(-0.65)..translate(0.0, 50.0))
                  : Matrix4.identity(),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation!,
                  initialZoom: _is3DMode ? 16.0 : 18.0, 
                  maxZoom: 22.0,
                  onMapReady: () {
                     _isMapReady = true;
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: "https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png",
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.example.georide',
                  ),
                  MarkerLayer(
                    markers: [
                      ...rideMarkers, // Add the ride portals
                      Marker(
                        point: _currentLocation!,
                        width: _is3DMode ? 25.0 : 70.0, 
                        height: _is3DMode ? 25.0 : 70.0,
                        alignment: Alignment.center,
                        child: Transform(
                            alignment: FractionalOffset.center,
                            transform: _is3DMode ? (Matrix4.identity()..rotateX(0.65)) : Matrix4.identity(),
                            child: AvatarMarker(size: _is3DMode ? 25.0 : 70.0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // HUD OVERLAY
          Positioned(
             top: 50,
             left: 20,
             right: 20,
             child: _activeRide != null 
               ? Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                     color: Colors.black.withOpacity(0.85),
                     borderRadius: BorderRadius.circular(20),
                     border: Border.all(color: Colors.blueAccent, width: 2),
                  ),
                  child: Column(
                    children: [
                       const Text("ONGOING RIDE", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                       const SizedBox(height: 5),
                       Text("Destination: ${_activeRide!.destination}", style: const TextStyle(color: Colors.white, fontSize: 16)),
                       // Simple distance ping
                       Text("Dist to Host: ${(Geolocator.distanceBetween(_currentLocation!.latitude, _currentLocation!.longitude, _activeRide!.lat, _activeRide!.lng)).toStringAsFixed(0)}m", style: const TextStyle(color: Colors.greenAccent)),
                    ]
                  )
               )
               : Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                     color: Colors.black.withOpacity(0.7),
                     borderRadius: BorderRadius.circular(15),
                     border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                       Icon(Icons.directions_car, color: Colors.greenAccent),
                       SizedBox(width: 10),
                       Text('GeoRide Scanner Active', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ]
                  )
               )
          ),

        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Left Side Button (Host Ride)
            _activeRide == null
              ? FloatingActionButton.extended(
                  heroTag: "hostRideBtn",
                  backgroundColor: Colors.blueAccent,
                  onPressed: _hostRideDialog,
                  icon: const Icon(Icons.add_location_alt, color: Colors.white),
                  label: const Text("Host", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              : const SizedBox(),

            // Right Side Column (Toggles)
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: "toggle3DBtn",
                  backgroundColor: _is3DMode ? Colors.greenAccent : Colors.grey[300],
                  onPressed: () {
                    setState(() {
                      _is3DMode = !_is3DMode;
                    });
                    if (_currentLocation != null) {
                      _mapController.move(_currentLocation!, _is3DMode ? 16.0 : 18.0);
                    }
                  },
                  child: Icon(_is3DMode ? Icons.layers : Icons.map, color: _is3DMode ? Colors.black : Colors.black87),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: "myLocationBtn",
                  backgroundColor: Colors.greenAccent,
                  onPressed: () {
                    if (_currentLocation != null) {
                      _mapController.move(_currentLocation!, _is3DMode ? 16.0 : 18.0);
                    }
                  },
                  child: const Icon(Icons.my_location, color: Colors.black),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
