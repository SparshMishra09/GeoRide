import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vibration/vibration.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/photon_service.dart';
import '../services/osrm_service.dart';
import '../services/corridor_service.dart';
import '../services/rtdb_service.dart';
import 'direction_arrow_painter.dart';

class _ArRideChatSheet extends StatefulWidget {
  final String rideId;
  const _ArRideChatSheet({required this.rideId});

  @override
  State<_ArRideChatSheet> createState() => _ArRideChatSheetState();
}

class _ArRideChatSheetState extends State<_ArRideChatSheet> {
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
     final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
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

enum NavState { search, lobby, navigation }

class ArNavigationOverlay extends StatefulWidget {
  final MapLibreMapController? mapController;
  /// Live stream of GPS positions — the overlay subscribes internally.
  final Stream<Position> positionStream;
  /// The most recent position at the time the overlay was opened (used for
  /// the initial route fetch and RTDB push before the stream fires).
  final Position initialPosition;
  final ValueNotifier<LatLng?> mapTapNotifier;
  final VoidCallback onExit;
  final Function(List<LatLng>)? onRouteFetched;
  final Function(List<CorridorRider>)? onNearbyRidersUpdated;
  final Function(Position)? onNavigationStarted;
  final Function(List<LatLng>, LatLng)? onUpdateSegmentedPath;
  final Function(List<LatLng>)? onToggleOverview;

  const ArNavigationOverlay({
    super.key,
    required this.mapController,
    required this.positionStream,
    required this.initialPosition,
    required this.mapTapNotifier,
    required this.onExit,
    this.onRouteFetched,
    this.onNearbyRidersUpdated,
    this.onNavigationStarted,
    this.onUpdateSegmentedPath,
    this.onToggleOverview,
  });

  @override
  State<ArNavigationOverlay> createState() => _ArNavigationOverlayState();
}

class _ArNavigationOverlayState extends State<ArNavigationOverlay> {
  NavState _state = NavState.search;

  // Live position (updated via stream subscription)
  late Position _currentPosition;
  StreamSubscription<Position>? _positionSubscription;

  // Search/Selection state
  final TextEditingController _originController = TextEditingController(text: "Current Location");
  final TextEditingController _destController = TextEditingController();
  final PublishSubject<String> _searchSubject = PublishSubject<String>();
  
  PhotonResult? _origin;
  PhotonResult? _destination;
  
  List<PhotonResult> _searchResults = [];
  bool _isSearching = false;
  bool _isPickingOnMap = false;
  bool _isFocusingOrigin = false; // true = origin field, false = destination field

  // Ride hosting options
  int _selectedSeats = 3;
  int _selectedWaitMinutes = 15;
  final List<int> _seatOptions = [1, 2, 3, 4];
  final List<int> _waitOptions = [5, 10, 15, 30];

  // Navigation/Lobby state
  OsrmRoute? _currentRoute;
  List<CorridorRider> _nearbyRiders = [];
  StreamSubscription? _rtdbSubscription;
  Timer? _lobbyTimeoutTimer;
  Timer? _screenPositionRefreshTimer;

  // Firestore subscriptions — 4 separate, never share a variable.
  StreamSubscription? _hostAcceptedSubscription;    // Host: my match was accepted → navigate
  StreamSubscription? _hostPendingSubscription;     // Host: someone wants to join same route → show dialog
  StreamSubscription? _riderCorridorSubscription;   // Rider: Host invited me via corridor → show dialog
  StreamSubscription? _riderAcceptedSubscription;   // Rider: my join request accepted → navigate

  bool _joinDialogOpen = false;          // Guard: corridor invite dialog open
  bool _hostRequestDialogOpen = false;   // Guard: same-route accept dialog open
  bool _awaitingSameRouteAcceptance = false; // Rider waiting for host to accept same-route match
  String? _currentRouteId;
  String? _matchedRiderId;
  List<String> _passengers = [];
  final Map<String, Point> _riderScreenPositions = {};
  int _currentWaypointIndex = 0;
  double _distanceToNextWaypoint = 0.0;
  double _relativeAngle = 0.0;

  // Haptic guard: prevent repeated buzzes when near a turn
  bool _hasBuzzedForCurrentWaypoint = false;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.initialPosition;
    
    // Initial origin is "Current Location"
    _origin = PhotonResult(
      displayName: "Current Location",
      lat: _currentPosition.latitude,
      lng: _currentPosition.longitude,
      type: "current_location",
      country: "",
    );

    _setupSearchDebounce(); // RESTORED SEARCH
    _subscribeToPositionStream();
    _startScreenPositionRefresh();
    
    // Listen to map taps via notifier
    widget.mapTapNotifier.addListener(_onMapTapChanged);
  }

  void _onMapTapChanged() {
    final latLng = widget.mapTapNotifier.value;
    if (latLng != null) {
      if (_state == NavState.lobby) {
        // Find if a rider was tapped
        try {
          final tappedRider = _nearbyRiders.firstWhere((r) => r.position == latLng);
          _joinRide(tappedRider);
        } catch (_) {
          _handleMapClick(null, latLng);
        }
      } else {
        _handleMapClick(null, latLng);
      }
    }
  }

  void _joinRide(CorridorRider rider) async {
    Vibration.vibrate(duration: 300);
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentRouteId == null) return;

    final matchRef = FirebaseFirestore.instance.collection('matches').doc();
    await matchRef.set({
      'routeId': _currentRouteId,
      'hostId': user.uid,
      'riderId': rider.userId,
      'status': 'pending',
      'matchType': 'corridor',  // Corridor-based invite
      'hostName': user.displayName ?? 'Host',
      'riderName': rider.displayName ?? 'Rider',
      'destination': _destination?.displayName ?? 'your destination',
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Invite sent to ${rider.displayName ?? 'Rider'}..."),
          backgroundColor: Colors.blueAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _animateSwoop() async {
    if (widget.mapController == null) return;
    
    // Phase 1: High-altitude top-down (already in this state usually, but ensure)
    await widget.mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(_currentPosition.latitude, _currentPosition.longitude),
          zoom: 15.0,
          tilt: 0.0,
        ),
      ),
      duration: const Duration(milliseconds: 500),
    );

    await Future.delayed(const Duration(milliseconds: 200));

    // Phase 2: Cinematic swoop to street level
    await widget.mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(_currentPosition.latitude, _currentPosition.longitude),
          zoom: 18.5,
          tilt: 65.0,
          bearing: _currentPosition.heading,
        ),
      ),
      duration: const Duration(milliseconds: 2500),
    );
  }

  void _onMatchAccepted(DocumentSnapshot match) async {
    if (_state == NavState.navigation) return; // Already there

    final data = match.data() as Map<String, dynamic>;
    final riderId = data['riderId'];
    final hostId = data['hostId'];
    final routeId = data['routeId'];

    Vibration.vibrate(pattern: [0, 150, 100, 150]);
    
    // Instantly show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.greenAccent),
            SizedBox(width: 10),
            Text("Ride Confirmed! Synchronizing..."),
          ],
        ),
        backgroundColor: Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Synchronize RTDB state for both devices
    // Device 2 (Rider) needs to link to the routeId
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.uid == riderId) {
      await RTDBService.pushLocation(
        lat: _currentPosition.latitude,
        lng: _currentPosition.longitude,
        bearing: _currentPosition.heading,
        routeId: routeId,
        displayName: user.displayName,
        force: true,
      );
    }

    // Trigger the cinematic transition
    await _animateSwoop();

    if (mounted) {
      setState(() {
        _state = NavState.navigation;
        _currentRouteId = routeId;
        _matchedRiderId = (user?.uid == riderId) ? hostId : riderId;
      });
      _startScreenPositionRefresh();
      if (widget.onNavigationStarted != null) {
        widget.onNavigationStarted!(_currentPosition);
      }
    }
  }

  void _handleMapClick(Point? point, LatLng latLng) async {
    if (!_isPickingOnMap || !mounted) return;

    setState(() => _isSearching = true);
    
    try {
      final result = await PhotonService.reverseSearch(latLng.latitude, latLng.longitude);
      if (result != null && mounted) {
        if (_isFocusingOrigin) {
          _origin = result;
          _originController.text = result.displayName;
        } else {
          _destination = result;
          _destController.text = result.displayName;
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingOnMap = false;
          _isSearching = false;
        });
      }
    }
  }

  void _subscribeToPositionStream() {
    _positionSubscription = widget.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _currentPosition = pos);
      // Update navigation metrics on every GPS update
      if (_state == NavState.navigation) {
        _updateNavigationMetrics(pos);
        if (widget.onUpdateSegmentedPath != null && _currentRoute != null) {
           widget.onUpdateSegmentedPath!(_currentRoute!.points, LatLng(pos.latitude, pos.longitude));
        }
      }
      // Throttled RTDB write handled internally by RTDBService
      if (_state != NavState.search) {
        RTDBService.pushLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          bearing: pos.heading,
          routeId: _state == NavState.navigation ? _currentRouteId : null,
          displayName: FirebaseAuth.instance.currentUser?.displayName,
        );
      }
    });
  }

  @override
  void dispose() {
    _searchSubject.close();
    _originController.dispose();
    _destController.dispose();
    _positionSubscription?.cancel();
    _rtdbSubscription?.cancel();
    _hostAcceptedSubscription?.cancel();
    _hostPendingSubscription?.cancel();
    _riderCorridorSubscription?.cancel();
    _riderAcceptedSubscription?.cancel();
    _lobbyTimeoutTimer?.cancel();
    _screenPositionRefreshTimer?.cancel();
    widget.mapTapNotifier.removeListener(_onMapTapChanged);
    RTDBService.removeLocation();
    super.dispose();
  }

  void _setupSearchDebounce() {
    _searchSubject
        .debounceTime(const Duration(milliseconds: 600))
        .distinct()
        .listen((query) {
      if (query.length >= 3) {
        _performSearch(query);
      } else {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isSearching = true);
    try {
      final results = await PhotonService.search(
        query,
        nearLat: _currentPosition.latitude,
        nearLng: _currentPosition.longitude,
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // If navigating, show full-screen HUD. If searching, show floating navbar.
    if (_state == NavState.navigation) {
      return _buildNavigationUI();
    }

    return Stack(
      children: [
        // 1. TOP NAV BAR (Floating Search)
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 15,
          right: 15,
          child: _state == NavState.search ? _buildFloatingSearchCard() : const SizedBox.shrink(),
        ),

        // 2. LOBBY UI
        if (_state == NavState.lobby) ...[
          // Top Summary Card
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 15,
            right: 15,
            child: _buildLobbyTopCard(),
          ),
          // Bottom Matching Card
          Positioned(
            bottom: 30,
            left: 15,
            right: 15,
            child: _buildLobbyBottomCard(),
          ),
        ],

        // 3. NAVIGATION UI EXTRAS
        if (_state == NavState.navigation) ...[
           // Top Left Co-Rider Card
           Positioned(
             top: MediaQuery.of(context).padding.top + 10,
             left: 15,
             child: _buildCoRiderCard(),
           ),
           // Top Right Compass/Toggle
           Positioned(
             top: MediaQuery.of(context).padding.top + 10,
             right: 15,
             child: _buildNavControls(),
           ),
           // Bottom Right Chat
           Positioned(
             bottom: 120,
             right: 15,
             child: _buildChatButton(),
           ),
        ],

        // 3. CLOSE BUTTON (Only shown when not picking on map)
        if (!_isPickingOnMap)
          Positioned(
            bottom: 30,
            left: 30,
            child: FloatingActionButton(
              backgroundColor: Colors.redAccent,
              onPressed: widget.onExit,
              child: const Icon(Icons.close, color: Colors.white),
            ),
          ),
          
        // 4. MAP PICKING INSTRUCTIONS (Shown at bottom)
        if (_isPickingOnMap)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: _buildMapPickingInstruction(),
          ),
      ],
    );
  }

  Widget _buildMapPickingInstruction() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.cyanAccent,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10)],
      ),
      child: Row(
        children: [
          const Icon(Icons.touch_app, color: Colors.black),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Tap on map to set ${_isFocusingOrigin ? 'Start' : 'End'}",
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: () => setState(() => _isPickingOnMap = false),
          ),
        ],
      ),
    );
  }

  Widget _buildSeatsSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SEATS AVAILABLE', style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Row(
          children: _seatOptions.map((seats) {
            final isSelected = _selectedSeats == seats;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedSeats = seats),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.cyanAccent : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected ? null : Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Center(
                    child: Text('$seats', style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildWaitTimeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('WAIT TIME', style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Row(
          children: _waitOptions.map((mins) {
            final isSelected = _selectedWaitMinutes == mins;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedWaitMinutes = mins),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.cyanAccent : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected ? null : Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Center(
                    child: Text('${mins}m', style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFloatingSearchCard() {
    if (_isPickingOnMap) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              _buildLocationField(
                controller: _originController,
                label: "Starting point",
                icon: Icons.my_location,
                isOrigin: true,
              ),
              const SizedBox(height: 10),
              _buildLocationField(
                controller: _destController,
                label: "Destination",
                icon: Icons.place,
                isOrigin: false,
              ),
            ],
          ),
        ),
        
        // Search Results List (Floating below)
        if (_searchResults.isNotEmpty || _isSearching)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
            ),
            child: _isSearching 
              ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)))
              : ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final result = _searchResults[index];
                    return ListTile(
                      dense: true,
                      title: Text(result.displayName, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: Text(result.country, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                      onTap: () => _handleSearchResultTap(result),
                    );
                  },
                ),
          ),
          
        if (_origin != null && _destination != null && _searchResults.isEmpty && !_isSearching)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                _buildSeatsSelector(),
                const SizedBox(height: 16),
                _buildWaitTimeSelector(),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _startRouting,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    elevation: 10,
                    shadowColor: Colors.cyanAccent.withValues(alpha: 0.3),
                  ),
                  child: const Text("CREATE RIDE & CONFIRM", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                ),
              ],
            ),
          ),
      ],
    );
  }



  Widget _buildLocationField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isOrigin,
  }) {
    return SizedBox(
      height: 45,
      child: TextField(
        controller: controller,
        onChanged: (val) {
          setState(() => _isFocusingOrigin = isOrigin);
          _searchSubject.add(val);
        },
        onTap: () => setState(() => _isFocusingOrigin = isOrigin),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
          prefixIcon: Icon(icon, color: Colors.cyanAccent, size: 18),
          suffixIcon: IconButton(
            icon: const Icon(Icons.add_location_alt, color: Colors.cyanAccent, size: 18),
            padding: EdgeInsets.zero,
            onPressed: () => setState(() {
              _isPickingOnMap = true;
              _isFocusingOrigin = isOrigin;
              _searchResults = [];
            }),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 15),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  void _handleSearchResultTap(PhotonResult result) {
    if (_isFocusingOrigin) {
      _origin = result;
      _originController.text = result.displayName;
    } else {
      _destination = result;
      _destController.text = result.displayName;
    }
    setState(() {
      _searchResults = [];
    });
  }

  Future<void> _startRouting() async {
    if (_origin == null || _destination == null) return;
    
    setState(() {
      _state = NavState.lobby;
      _isSearching = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Not authenticated");

      final route = await OsrmService.fetchRoute(
        LatLng(_origin!.lat, _origin!.lng),
        LatLng(_destination!.lat, _destination!.lng),
      );
      
      // Create Firestore Route doc — store source & dest coords for same-route matching
      final routeRef = await FirebaseFirestore.instance.collection('routes').add({
        'creatorId': user.uid,
        'creatorName': user.displayName ?? 'Rider',
        'encodedPolyline': '',
        'status': 'waiting',
        'timestamp': FieldValue.serverTimestamp(),
        'destination': _destination?.displayName ?? 'Unknown',
        'sourceLat': _origin!.lat,
        'sourceLng': _origin!.lng,
        'destLat': _destination!.lat,
        'destLng': _destination!.lng,
      });

      // 2. Create SharingPoint doc (for general map discovery)
      final now = DateTime.now();
      final expiresAt = now.add(Duration(minutes: _selectedWaitMinutes));
      
      await FirebaseFirestore.instance.collection('sharing_points').add({
        'creatorId': user.uid,
        'lat': _origin!.lat,
        'lng': _origin!.lng,
        'destination': _destination?.displayName ?? 'Unknown',
        'seatsAvailable': _selectedSeats,
        'totalSeats': _selectedSeats,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'passengers': [],
        'arrivedPassengers': [],
        'routeId': routeRef.id, // Linked to the calculated route
      });

      if (mounted) {
        setState(() {
          _currentRouteId = routeRef.id;
          _matchedRiderId = null;
          _awaitingSameRouteAcceptance = false;
          _currentRoute = route;
          _isSearching = false;
          _state = NavState.lobby;
        });
        if (widget.onRouteFetched != null) {
          widget.onRouteFetched!(route.points);
        }
        _startLobbyLogic();
        // After lobby is set up, check for same-route matches asynchronously
        _checkForSameRouteMatch();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error fetching route: $e")),
        );
        setState(() => _state = NavState.search);
      }
    }
  }

  Future<void> _startLobbyLogic() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Clear any stale matches before starting lobby to prevent instant jump
    try {
      final staleMatches = await FirebaseFirestore.instance
          .collection('matches')
          .where('riderId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'accepted')
          .get();
      final hostMatches = await FirebaseFirestore.instance
          .collection('matches')
          .where('hostId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'accepted')
          .get();
      for (final doc in [...staleMatches.docs, ...hostMatches.docs]) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to clear stale matches: $e');
    }

    // 1. Push own location to RTDB immediately
    RTDBService.pushLocation(
      lat: _currentPosition.latitude,
      lng: _currentPosition.longitude,
      bearing: _currentPosition.heading,
      displayName: user.displayName ?? 'Rider',
      force: true,
    );

    // 2. Corridor scanner — scans RTDB for nearby riders on my polyline
    _rtdbSubscription?.cancel();
    _rtdbSubscription = RTDBService.listenToAllLocations(onUpdate: (locations) {
      if (_currentRoute != null && _state == NavState.lobby) {
        final matched = CorridorService.filterRidersInCorridor(
          polyline: _currentRoute!.points,
          candidates: locations,
          userPosition: LatLng(_currentPosition.latitude, _currentPosition.longitude),
        );
        if (mounted) {
          setState(() => _nearbyRiders = matched);
          if (widget.onNearbyRidersUpdated != null) {
            widget.onNearbyRidersUpdated!(matched);
          }
        }
      }
    });

    // 3. HOST — accepted: my corridor invite was accepted → navigate
    _hostAcceptedSubscription?.cancel();
    _hostAcceptedSubscription = FirebaseFirestore.instance
        .collection('matches')
        .where('hostId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty && _state != NavState.navigation && mounted) {
        _onMatchAccepted(snap.docs.first);
      }
    });

    // 4. HOST — pending sameRoute: someone found my route as same-route → ask me to accept
    _hostPendingSubscription?.cancel();
    _hostPendingSubscription = FirebaseFirestore.instance
        .collection('matches')
        .where('hostId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .where('matchType', isEqualTo: 'sameRoute')
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty && _state != NavState.navigation && !_hostRequestDialogOpen && mounted) {
        _showHostSameRouteDialog(snap.docs.first);
      }
    });

    // 5. RIDER — corridor: a Host has invited me → ask if I want to join
    _riderCorridorSubscription?.cancel();
    _riderCorridorSubscription = FirebaseFirestore.instance
        .collection('matches')
        .where('riderId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .where('matchType', isEqualTo: 'corridor')
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty && _state != NavState.navigation && !_joinDialogOpen && mounted) {
        _showJoinRequestDialog(snap.docs.first);
      }
    });

    // 6. RIDER — accepted: my same-route request was accepted by Host → navigate
    _riderAcceptedSubscription?.cancel();
    _riderAcceptedSubscription = FirebaseFirestore.instance
        .collection('matches')
        .where('riderId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty && _state != NavState.navigation && mounted) {
        _onMatchAccepted(snap.docs.first);
      }
    });

    // 7. 5-minute lobby timeout
    _lobbyTimeoutTimer?.cancel();
    _lobbyTimeoutTimer = Timer(const Duration(minutes: 5), () {
      if (_state == NavState.lobby && mounted) {
        _showTimeoutDialog();
      }
    });
  }

  /// Removes a passenger from the current ride.
  Future<void> _kickPassenger(String passengerId) async {
    if (_currentRouteId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('sharing_points')
          .doc(_currentRouteId)
          .update({
        'passengers': FieldValue.arrayRemove([passengerId]),
      });
      setState(() {
        _passengers.remove(passengerId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passenger removed'), backgroundColor: Color(0xFF43A047)),
      );
    } catch (e) {
      debugPrint('❌ Failed to kick passenger: $e');
    }
  }

  /// Queries Firestore for any waiting routes with the same source+destination
  /// as the current user. If found, creates a 'sameRoute' pending match.
  Future<void> _checkForSameRouteMatch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _origin == null || _destination == null) return;

    const double thresholdMeters = 1000.0; // 1km — same area counts as same route

    try {
      final snap = await FirebaseFirestore.instance
          .collection('routes')
          .where('status', isEqualTo: 'waiting')
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['creatorId'] == user.uid) continue; // skip own route

        final srcLat = (data['sourceLat'] as num?)?.toDouble();
        final srcLng = (data['sourceLng'] as num?)?.toDouble();
        final dstLat = (data['destLat'] as num?)?.toDouble();
        final dstLng = (data['destLng'] as num?)?.toDouble();
        if (srcLat == null || srcLng == null || dstLat == null || dstLng == null) continue;

        final sourceClose = Geolocator.distanceBetween(
          _origin!.lat, _origin!.lng, srcLat, srcLng,
        ) <= thresholdMeters;

        final destClose = Geolocator.distanceBetween(
          _destination!.lat, _destination!.lng, dstLat, dstLng,
        ) <= thresholdMeters;

        if (!sourceClose || !destClose) continue;

        // Guard: don't create duplicate matches between same pair of users
        final existingSnap = await FirebaseFirestore.instance
            .collection('matches')
            .where('hostId', isEqualTo: data['creatorId'])
            .where('riderId', isEqualTo: user.uid)
            .get();
        if (existingSnap.docs.isNotEmpty) continue;

        // Create the same-route match request
        await FirebaseFirestore.instance.collection('matches').add({
          'routeId': doc.id,
          'hostId': data['creatorId'],
          'riderId': user.uid,
          'hostName': data['creatorName'] ?? 'Rider',
          'riderName': user.displayName ?? 'Rider',
          'destination': _destination?.displayName ?? 'Unknown',
          'status': 'pending',
          'matchType': 'sameRoute',
          'timestamp': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          setState(() => _awaitingSameRouteAcceptance = true);
        }
        break; // Only match with one host at a time
      }
    } catch (e) {
      debugPrint('⚠️ Same-route match check failed: $e');
    }
  }

  /// Shown to the HOST when Device 2 has detected a same-route match.
  void _showHostSameRouteDialog(DocumentSnapshot match) {
    final data = match.data() as Map<String, dynamic>;
    final riderName = data['riderName'] ?? 'Someone';
    final dest = data['destination'] ?? 'your destination';

    setState(() => _hostRequestDialogOpen = true);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'HostSameRoute',
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (ctx, anim1, anim2) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.greenAccent.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 5,
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.route, color: Colors.greenAccent, size: 40),
                ),
                const SizedBox(height: 20),
                Text(
                  '$riderName is heading the same way!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                    children: [
                      const TextSpan(text: 'They are also heading to '),
                      TextSpan(
                        text: dest,
                        style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: '. Accept to share navigation and see each other live on the map.'),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          await match.reference.update({'status': 'rejected'});
                          if (mounted) {
                            Navigator.pop(ctx);
                            setState(() => _hostRequestDialogOpen = false);
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('DECLINE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await match.reference.update({'status': 'accepted'});
                          if (mounted) {
                            setState(() => _hostRequestDialogOpen = false);
                            Navigator.pop(ctx);
                            _onMatchAccepted(match);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text('ACCEPT & SHARE', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, anim1, anim2, child) => FadeTransition(
        opacity: anim1,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
    );
  }


  void _showTimeoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("No matches found"),
        content: const Text("Would you like to start the journey alone?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _state = NavState.navigation);
            },
            child: const Text("Start Alone"),
          ),
        ],
      ),
    );
  }
  Widget _buildLobbyTopCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.radar, color: Colors.cyanAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Route to ${_destination?.displayName}",
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  "🔍 Looking for riders on this route...",
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_location_alt, color: Colors.cyanAccent, size: 20),
            onPressed: () {
              setState(() => _state = NavState.search);
              _rtdbSubscription?.cancel();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLobbyBottomCard() {
    if (_isSearching) {
      return Container(
        height: 100,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(20)),
        child: const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
      );
    }

    // Device 2: same-route match was created, waiting for Host to accept
    if (_awaitingSameRouteAcceptance) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
          boxShadow: [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.1), blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
            const SizedBox(height: 16),
            const Text(
              'SAME ROUTE DETECTED',
              style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            const Text(
              'Request sent! Waiting for the originator to accept...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: widget.onExit,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('CANCEL', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.1), blurRadius: 20)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              const Text("CORRIDOR MATCHES", style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const Spacer(),
              Text("${_nearbyRiders.length} Nearby", style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 15),
          if (_nearbyRiders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                  SizedBox(height: 15),
                  Text("Waiting for riders to enter the 200m corridor...", style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _nearbyRiders.length,
                itemBuilder: (context, index) {
                  final rider = _nearbyRiders[index];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: const CircleAvatar(
                      backgroundColor: Colors.cyanAccent, 
                      radius: 14, 
                      child: Icon(Icons.person, color: Colors.black, size: 16)
                    ),
                    title: Text(rider.displayName ?? "Nearby Rider", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: Text("${rider.distanceFromUser.toInt()}m away", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    trailing: ElevatedButton(
                      onPressed: () => _joinRide(rider),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(60, 30),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: const Text("INVITE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onExit,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => setState(() => _state = NavState.navigation),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white24,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                  ),
                  child: const Text("SOLO START", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          if (_matchedRiderId == FirebaseAuth.instance.currentUser?.uid && _passengers.isNotEmpty)
            Column(
              children: [
                const SizedBox(height: 16),
                const Text('PASSENGERS', style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                ...List.generate(_passengers.length, (i) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Colors.cyanAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_passengers[i], style: const TextStyle(color: Colors.white))),
                        IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 20),
                          onPressed: () => _kickPassenger(_passengers[i]),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  /// Called from the position stream listener — safe to call setState.
  void _updateNavigationMetrics(Position pos) {
    if (_currentRoute == null) return;
    final waypoints = _currentRoute!.steps;
    if (_currentWaypointIndex >= waypoints.length) return;

    final target = waypoints[_currentWaypointIndex].endLocation;
    final userPos = LatLng(pos.latitude, pos.longitude);

    final distance = Geolocator.distanceBetween(
      pos.latitude, pos.longitude,
      target.latitude, target.longitude,
    );
    final bearingToTarget = CorridorService.bearingTo(userPos, target);
    final relativeAngle = (bearingToTarget - pos.heading + 360) % 360;

    setState(() {
      _distanceToNextWaypoint = distance;
      _relativeAngle = relativeAngle;
      _hasBuzzedForCurrentWaypoint = distance > 30.0
          ? false  // reset guard when far from waypoint
          : _hasBuzzedForCurrentWaypoint;
    });

    if (distance <= 15.0) {
      _advanceWaypoint();
    } else if (distance <= 30.0 && !_hasBuzzedForCurrentWaypoint) {
      _triggerHaptic(isTurnNear: true);
      setState(() => _hasBuzzedForCurrentWaypoint = true);
    }
  }

  void _advanceWaypoint() {
    Vibration.vibrate(pattern: [0, 150, 100, 150]); // Double buzz
    setState(() {
      _currentWaypointIndex++;
      _hasBuzzedForCurrentWaypoint = false;
    });
    if (_currentWaypointIndex >= _currentRoute!.steps.length) {
      _showArrivalDialog();
    }
  }

  void _triggerHaptic({bool isTurnNear = false}) {
    if (isTurnNear) {
      Vibration.vibrate(duration: 200); // Single buzz near turn
    }
  }

  void _showArrivalDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Arrived!"),
        content: const Text("You have reached your destination."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onExit();
            },
            child: const Text("Finish"),
          ),
        ],
      ),
    );
  }

  Widget _buildCoRiderCard() {
    CorridorRider? partner;
    if (_matchedRiderId != null) {
      try {
        partner = _nearbyRiders.firstWhere((r) => r.userId == _matchedRiderId);
      } catch (_) {}
    }

    if (partner == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withValues(alpha: 0.2),
            blurRadius: 15,
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              const CircleAvatar(
                backgroundColor: Colors.cyanAccent,
                radius: 16,
                child: Icon(Icons.person, color: Colors.black, size: 20),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                partner.displayName ?? 'Partner',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Text(
                "${partner.distanceFromUser.toInt()}m away",
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavControls() {
    return Column(
      children: [
        FloatingActionButton.small(
          onPressed: () {
            if (widget.onToggleOverview != null && _currentRoute != null) {
              widget.onToggleOverview!(_currentRoute!.points);
            }
          },
          backgroundColor: Colors.black.withValues(alpha: 0.7),
          child: const Icon(Icons.layers, color: Colors.cyanAccent),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), shape: BoxShape.circle),
          child: const Icon(Icons.explore, color: Colors.cyanAccent, size: 20),
        ),
      ],
    );
  }

  Widget _buildChatButton() {
    return FloatingActionButton(
      onPressed: () {
        if (_currentRouteId != null) {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (ctx) => _ArRideChatSheet(rideId: _currentRouteId!),
          );
        }
      },
      backgroundColor: Colors.cyanAccent,
      child: const Icon(Icons.chat_bubble, color: Colors.black),
    );
  }

  Widget _buildNavigationUI() {
    // ... rest of the navigation UI code
    final route = _currentRoute;
    if (route == null) return const SizedBox.shrink();

    final maneuver = _currentWaypointIndex < route.steps.length
        ? route.steps[_currentWaypointIndex].maneuver.toUpperCase()
        : 'ARRIVING';

    return Stack(
      children: [
        // 1. AR Rider Cards (Projected in 3D space)
        ..._buildArRiderCards(),

        // 2. Direction Arrow (Bottom Center)
        Align(
          alignment: const Alignment(0, 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               DirectionArrowWidget(
                 relativeAngleDegrees: _relativeAngle,
                 distanceToNextMeters: _distanceToNextWaypoint,
                 isNearTurn: _distanceToNextWaypoint <= 30.0,
               ),
               const SizedBox(height: 20),
               // Distance Chip + Waypoint Instruction
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                 decoration: BoxDecoration(
                   color: Colors.black.withValues(alpha: 0.9),
                   borderRadius: BorderRadius.circular(30),
                   border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
                 ),
                 child: Column(
                   children: [
                     Text(
                       maneuver,
                       style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold),
                     ),
                     Text(
                       "${_distanceToNextWaypoint.toInt()} meters away",
                       style: const TextStyle(color: Colors.white70, fontSize: 12),
                     ),
                   ],
                 ),
               ),
            ],
          ),
        ),

        // End Ride Button
        Positioned(
          bottom: 40,
          left: 20,
          child: ElevatedButton.icon(
            onPressed: () {
               widget.onExit();
            },
            icon: const Icon(Icons.stop, color: Colors.white),
            label: const Text("END RIDE"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ),
      ],
    );
  }

  /// Refresh screen positions for all nearby riders every 500ms.
  /// This avoids calling toScreenLocation() inside build() on every frame.
  void _startScreenPositionRefresh() {
    _screenPositionRefreshTimer?.cancel();
    _screenPositionRefreshTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (widget.mapController == null || !mounted) return;
      final updated = <String, Point>{};
      for (final rider in _nearbyRiders) {
        try {
          final pt = await widget.mapController!.toScreenLocation(rider.position);
          updated[rider.userId] = pt;
        } catch (_) {
          // Map not ready yet; skip this rider
        }
      }
      if (mounted) {
        setState(() => _riderScreenPositions
          ..clear()
          ..addAll(updated));
      }
    });
  }

  List<Widget> _buildArRiderCards() {
    // Sort: furthest first so nearer riders render on top
    final riders = _nearbyRiders.toList()
      ..sort((a, b) => b.distanceFromUser.compareTo(a.distanceFromUser));

    return riders
        .where((r) => _riderScreenPositions.containsKey(r.userId))
        .map((rider) {
      final pt = _riderScreenPositions[rider.userId]!;
      final double distance = rider.distanceFromUser;
      final double scale = (1.0 - (distance / 500.0)).clamp(0.5, 1.0);

      return Positioned(
        left: pt.x.toDouble() - 50 * scale,
        top: pt.y.toDouble() - 80 * scale,
        child: GestureDetector(
          onTap: () {
            if (_state == NavState.lobby) _joinRide(rider);
          },
          child: Opacity(
            opacity: scale,
            child: Transform.scale(
              scale: scale,
              child: Column(
                children: [
                  // Label with Distance
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.cyanAccent, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyanAccent.withValues(alpha: 0.4),
                          blurRadius: 8,
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          rider.displayName ?? 'GeoRider',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          "${distance.toInt()}m ahead",
                          style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Glowing Marker
                  const Icon(Icons.location_on, color: Colors.cyanAccent, size: 32),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  void _showJoinRequestDialog(DocumentSnapshot match) {
    final data = match.data() as Map<String, dynamic>;
    final hostName = data['hostName'] ?? 'A Rider';
    final dest = data['destination'] ?? 'your destination';

    // Bug fix #4: mark dialog as open so listener does not stack duplicates
    setState(() => _joinDialogOpen = true);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "JoinRequest",
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (ctx, anim1, anim2) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 5,
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_pin_circle, color: Colors.cyanAccent, size: 40),
                ),
                const SizedBox(height: 20),
                Text(
                  "$hostName is heading your way!",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                    children: [
                      const TextSpan(text: "They are on the route to "),
                      TextSpan(
                        text: dest,
                        style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: ". Would you like to join them for a shared AR navigation experience?"),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          await match.reference.update({'status': 'rejected'});
                          if (mounted) {
                            Navigator.pop(ctx);
                            setState(() => _joinDialogOpen = false);
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("DECLINE", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await match.reference.update({'status': 'accepted'});
                          if (mounted) {
                            setState(() => _joinDialogOpen = false);
                            Navigator.pop(ctx);
                            _onMatchAccepted(match);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text("ACCEPT & JOIN", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: child,
          ),
        );
      },
    );
  }
}

