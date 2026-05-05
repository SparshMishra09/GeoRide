# Map Explore Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a feature where once the user is exploring on the map (manually moving the camera), the camera stays where the user is exploring unless clicked by user to relocate themselves, preventing GPS from auto-recentering the view.

**Architecture:** 
- Add a flag to track when user is manually exploring the map
- Add a programmatic move flag to ignore auto-centering animations
- Add a map controller listener (`addListener`) to detect camera movements
- Modify the GPS position update logic to skip auto-centering when exploring
- Update the existing "My Location" FAB to change color when in explore mode
- Reset explore mode when user clicks the "My Location" button

**Tech Stack:**
- Flutter/Dart
- Mapbox GL (maplibre_gl)
- Geolocator for GPS

---

### Task 1: Add explore mode state variables

**Files:**
- Modify: `C:\Users\Hp\Desktop\GeoRide/lib/screens/home_screen.dart`

- [ ] **Step 1: Add explore mode state variables**

```dart
// Add after existing state variables in _HomeScreenState class
bool _isUserExploringMap = false;
bool _isProgrammaticCameraMove = false;
static const _exploreModeDuration = Duration(seconds: 30); // Auto-reset explore mode after 30s
Timer? _exploreModeTimer;
```

- [ ] **Step 2: Initialize explore mode timer in initState**

```dart
@override
void initState() {
  super.initState();
  _loadMapStyle();
  _initLocation();
  _startRidesStream();
  _startExpiryTimer();
  // Initialize explore mode timer
  _exploreModeTimer = null;
}
```

- [ ] **Step 3: Clean up explore mode timer in dispose**

```dart
@override
void dispose() {
  _positionStreamSub?.cancel();
  _positionStreamController.close();
  _ridesStreamSub?.cancel();
  _passengerLocationsSub?.cancel();
  _expiryTimer?.cancel();
  _exploreModeTimer?.cancel();
  if (_mapController != null) {
    _mapController!.onSymbolTapped.remove(_onSymbolTapped);
    _mapController!.removeListener(_onCameraMove); // Remove camera listener
  }
  super.dispose();
}
```

---

### Task 2: Add map camera change listener

**Files:**
- Modify: `C:\Users\Hp\Desktop\GeoRide/lib/screens/home_screen.dart`

- [ ] **Step 1: Add camera move listener in _onMapCreated**

```dart
void _onMapCreated(MapLibreMapController controller) async {
  _mapController = controller;
  _isMapReady = true;
  _mapController!.onSymbolTapped.add(_onSymbolTapped);
  // Add camera move listener to detect when user is exploring
  _mapController!.addListener(_onCameraMove);
  debugPrint('✅ Map created');

  await _registerMarkerImages();
  await _updatePortalSymbols();
  await _createAvatarSymbol();
}
```

- [ ] **Step 2: Implement _onCameraMove callback**

```dart
// Add near other camera/map methods
void _onCameraMove() {
  // If the camera is moving due to our own code, ignore it
  if (_isProgrammaticCameraMove) return;

  // User is manually moving the map, enable explore mode
  if (!_isUserExploringMap) {
    setState(() => _isUserExploringMap = true);
    // Reset/cancel existing timer
    _exploreModeTimer?.cancel();
    // Start new timer to auto-disable explore mode after duration
    _exploreModeTimer = Timer(_exploreModeDuration, () {
      if (mounted) {
        setState(() => _isUserExploringMap = false);
      }
    });
  }
}
```

---

### Task 3: Modify GPS position update logic to respect explore mode

**Files:**
- Modify: `C:\Users\Hp\Desktop\GeoRide/lib/screens/home_screen.dart`

- [ ] **Step 1: Modify _onPositionUpdate to skip auto-centering when exploring**

```dart
// Modify the end of _onPositionUpdate
  setState(() => _currentPosition = smoothed);
  _positionStreamController.add(smoothed);
  _updateAvatarPosition(smoothed);
  
  // Only auto-center camera if user is not exploring the map
  if (!_isUserExploringMap) {
    _animateCameraToPosition(smoothed);
  }
}
```

---

### Task 4: Update existing "My Location" FAB

**Files:**
- Modify: `C:\Users\Hp\Desktop\GeoRide/lib/screens/home_screen.dart`

- [ ] **Step 1: Update "My Location" FAB to change color in explore mode**

```dart
// Inside the main build method, locate the My Location FAB
// Change the color based on explore mode state:
_buildFab(
  heroTag: 'my_location',
  icon: _isUserExploringMap ? Icons.my_location : Icons.my_location_outlined,
  tooltip: 'My Location',
  onPressed: _goToMyLocation,
  color: _isUserExploringMap ? Colors.greenAccent : Colors.cyanAccent,
),
```

- [ ] **Step 2: Update _goToMyLocation to disable explore mode**

```dart
void _goToMyLocation() {
  if (_currentPosition == null || _mapController == null) return;
  _lastCameraAnimateTime = null;
  // Disable explore mode when recentering
  setState(() => _isUserExploringMap = false);
  _exploreModeTimer?.cancel();
  _animateCameraToPosition(_currentPosition!);
}
```

---

### Task 5: Update AR Nav mode to respect explore mode

**Files:**
- Modify: `C:\Users\Hp\Desktop\GeoRide/lib/screens/home_screen.dart`

- [ ] **Step 1: Modify _animateCameraToPosition to handle programmatic moves**

```dart
void _animateCameraToPosition(Position pos) {
  if (!_isMapReady || _mapController == null) return;

  final now = DateTime.now();
  final canAnimate = _lastCameraAnimateTime == null ||
      now.difference(_lastCameraAnimateTime!) >= _minAnimateInterval ||
      _isArNavMode; // Always animate in AR Nav mode for smooth tracking

  // Don't auto-animate if user is exploring the map
  if (_isUserExploringMap && !_isArNavMode) {
    return;
  }

  if (canAnimate) {
    _isProgrammaticCameraMove = true;
    
    if (_isArNavMode) {
      // Pokemon GO Mode: Lock camera to user position and device heading
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 19.5, // Closer for AR feel
          tilt: 60.0,
          bearing: pos.heading, // World rotates around user
        )),
        duration: const Duration(milliseconds: 600),
      );
      
      // Reset programmatic flag after animation
      Future.delayed(const Duration(milliseconds: 650), () {
        if (mounted) _isProgrammaticCameraMove = false;
      });
    } else {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: _currentZoom,
          tilt: _is3DMode ? 60.0 : 0.0,
        )),
        duration: const Duration(milliseconds: 500),
      );
      
      // Reset programmatic flag after animation
      Future.delayed(const Duration(milliseconds: 550), () {
        if (mounted) _isProgrammaticCameraMove = false;
      });
    }
    _lastCameraAnimateTime = now;
  }
}
```

---

### Task 6: Add visual indicator for explore mode

**Files:**
- Modify: `C:\Users\Hp\Desktop\GeoRide/lib/screens/home_screen.dart`

- [ ] **Step 1: Add explore mode indicator to UI**

```dart
Widget _buildExploreModeIndicator() {
  if (!_isUserExploringMap) return const SizedBox.shrink();
  
  return Positioned(
    top: MediaQuery.of(context).padding.top + 70, // Below top status bar
    left: MediaQuery.of(context).size.width / 2 - 75, // Centered
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.greenAccent),
        boxShadow: [
          BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.2), blurRadius: 10)
        ]
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.explore, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 8),
          const Text(
            'Exploring Map',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 2: Add explore mode indicator to main build method**

```dart
// In home_screen.dart's build method, inside the main Stack:
  // ─── MAP ───────────────────────────────────────────────────
  MapLibreMap(...),

  // Add the indicator below the map
  _buildExploreModeIndicator(),

  // ─── TOP STATUS BAR OR HUD ─────────────────────────────────
```

---

### Task 7: Test and verify implementation

**Files:**
- None (testing task)

- [ ] **Step 1: Verify explore mode activates when user moves map**
- [ ] **Step 2: Verify auto-centering is disabled during explore mode**
- [ ] **Step 3: Verify re-center button works correctly**
- [ ] **Step 4: Verify explore mode auto-resets after timeout**
- [ ] **Step 5: Verify AR nav mode still works correctly**
- [ ] **Step 6: Run app and test all functionality**

---

## Plan Complete and Saved