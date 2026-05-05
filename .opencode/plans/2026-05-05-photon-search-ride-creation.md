# Photon Search & Ride Creation Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate "seats available" and "wait time" selection into the Photon search results card in the AR Navigation Overlay, enabling users to create a public ride (`sharing_points`) when confirming a calculated route.

**Architecture:** 
- Add selection state for seats and wait time to `ArNavigationOverlay`.
- Implement `_buildSeatsSelector` and `_buildWaitTimeSelector` within `ArNavigationOverlay`, matching the project's cyan-accented theme.
- Modify `_buildFloatingSearchCard` to display these selectors when a valid route is ready for confirmation.
- Update `_startRouting` to create both a `routes` document and a corresponding `sharing_points` document in Firestore.

**Tech Stack:**
- Flutter
- Cloud Firestore
- Firebase Auth
- OSRM Service (already integrated)

---

### Task 1: State Initialization

**Files:**
- Modify: `c:\Users\Hp\Desktop\GeoRide\lib\widgets\ar_navigation_overlay.dart`

- [ ] **Step 1: Add state variables for ride options**

Add the following variables to `_ArNavigationOverlayState` class around line 70:
```dart
  // Ride hosting options
  int _selectedSeats = 3;
  int _selectedWaitMinutes = 15;
  final List<int> _seatOptions = [1, 2, 3, 4];
  final List<int> _waitOptions = [5, 10, 15, 30];
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/ar_navigation_overlay.dart
git commit -m "feat: add ride hosting state variables to ArNavigationOverlay"
```

---

### Task 2: Selector UI Components

**Files:**
- Modify: `c:\Users\Hp\Desktop\GeoRide\lib\widgets\ar_navigation_overlay.dart` (Add new methods before `_buildFloatingSearchCard`)

- [ ] **Step 1: Implement _buildSeatsSelector**

```dart
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
                    color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected ? null : Border.all(color: Colors.white.withOpacity(0.1)),
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
```

- [ ] **Step 2: Implement _buildWaitTimeSelector**

```dart
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
                    color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected ? null : Border.all(color: Colors.white.withOpacity(0.1)),
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
```

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/ar_navigation_overlay.dart
git commit -m "feat: implement seats and wait time selectors in ArNavigationOverlay"
```

---

### Task 3: Search Card Integration

**Files:**
- Modify: `c:\Users\Hp\Desktop\GeoRide\lib\widgets\ar_navigation_overlay.dart` (Update `_buildFloatingSearchCard`)

- [ ] **Step 1: Inject selectors into _buildFloatingSearchCard**

Update the condition where "Confirm Route" is shown (around line 522):
```dart
        if (_origin != null && _destination != null && _searchResults.isEmpty && !_isSearching)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.1)),
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
                    shadowColor: Colors.cyanAccent.withOpacity(0.3),
                  ),
                  child: const Text("CREATE RIDE & CONFIRM", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                ),
              ],
            ),
          ),
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/ar_navigation_overlay.dart
git commit -m "ui: integrate ride options into Photon search card"
```

---

### Task 4: Ride Creation Logic

**Files:**
- Modify: `c:\Users\Hp\Desktop\GeoRide\lib\widgets\ar_navigation_overlay.dart` (Update `_startRouting`)

- [ ] **Step 1: Update _startRouting to create sharing_points document**

Update the logic in `_startRouting` after `OsrmService.fetchRoute` and before `_startLobbyLogic` (around line 614):
```dart
      // 1. Create Firestore Route doc (for AR matching)
      final routeRef = await FirebaseFirestore.instance.collection('routes').add({
        'creatorId': user.uid,
        'creatorName': user.displayName ?? 'Rider',
        'encodedPolyline': '', // Could store encoded geometry here if needed
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/ar_navigation_overlay.dart
git commit -m "feat: create sharing_points document on route confirmation"
```

---

### Task 5: Verification

**Files:**
- Manual Testing

- [ ] **Step 1: Verify UI appearance**
  - Open AR Search.
  - Search and select a destination.
  - Verify "SEATS AVAILABLE" and "WAIT TIME" sections appear above the "CREATE RIDE & CONFIRM" button.
  - Test toggling different options.

- [ ] **Step 2: Verify Firestore data**
  - Click "CREATE RIDE & CONFIRM".
  - Check Firestore `routes` collection for the new document.
  - Check Firestore `sharing_points` collection for a new document with matching `creatorId`, `destination`, `seatsAvailable`, and `expiresAt`.

- [ ] **Step 3: Verify Map sync**
  - Use a second device/emulator.
  - Verify that a glowing dot (portal) appears at the origin location on the map.
  - Verify that tapping the dot shows the ride details with correct seats and destination.
