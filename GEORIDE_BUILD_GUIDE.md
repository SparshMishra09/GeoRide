# GeoRide — Complete Build Guide for AI Assistants

> **Created:** 11 April 2026
> **Purpose:** This document contains EVERYTHING an AI coding assistant needs to build the GeoRide Flutter app from a clean Firebase-connected repo. It captures all specifications, hard-won lessons from 3 failed implementation attempts (2 Qwen Code sessions + 1 Antigravity session), the exact Firebase configuration, the complete Firestore data model, the exact map style JSON, and a phased implementation plan with the correct code patterns.
>
> **GIVE THIS ENTIRE DOCUMENT to the AI assistant at the start of the session.**

---

## TABLE OF CONTENTS

1. [Project Summary](#1-project-summary)
2. [What Already Exists in the Repo](#2-what-already-exists-in-the-repo)
3. [Tech Stack & Versions](#3-tech-stack--versions)
4. [Firebase Configuration (CRITICAL — DO NOT CHANGE)](#4-firebase-configuration)
5. [Architecture Rules (MANDATORY)](#5-architecture-rules)
6. [HARD-WON LESSONS — READ BEFORE WRITING CODE](#6-hard-won-lessons)
7. [Complete Feature Specification](#7-complete-feature-specification)
8. [Firestore Data Model](#8-firestore-data-model)
9. [Firestore Security Rules](#9-firestore-security-rules)
10. [Map Style JSON](#10-map-style-json)
11. [Android Configuration](#11-android-configuration)
12. [Phased Implementation Plan](#12-phased-implementation-plan)
13. [Code Patterns That WORK](#13-code-patterns-that-work)
14. [Code Patterns That FAIL](#14-code-patterns-that-fail)
15. [Testing Checklist](#15-testing-checklist)

---

## 1. PROJECT SUMMARY

**GeoRide** is a Pokémon GO–inspired real-time GPS ride-sharing Android app built with Flutter. Users see their position on a 3D map, can host rides to destinations, and other nearby users can join them. The app uses Firebase Anonymous Auth and Firestore for real-time sync.

**Core User Flow:**
1. User opens app → sees a 3D map with their avatar at their GPS position
2. User taps "Host Ride" → enters destination, seats, wait time → ride portal appears on the map
3. Other users (within 5km) see the glowing portal on their map
4. They tap it → see ride details (destination, seats, distance) → tap "Join"
5. Joined users get a route line to the host's location
6. Host sees passengers joining in real-time
7. Rides auto-expire after the set wait time (15–60 minutes)

---

## 2. WHAT ALREADY EXISTS IN THE REPO

When you clone the repo at its early state, you should have:

| File | Status | Notes |
|------|--------|-------|
| `pubspec.yaml` | ✅ Exists | May only have basic Flutter deps — you'll need to add the packages listed below |
| `lib/main.dart` | ✅ Exists | May have basic Firebase init — update as specified below |
| `lib/screens/home_screen.dart` | ⚠️ May exist | If it exists, it may be a skeleton — you'll rewrite it completely |
| `android/app/google-services.json` | ✅ MUST exist | Firebase config — NEVER delete or modify this file |
| `android/app/build.gradle.kts` | ✅ Exists | Must have `com.google.gms.google-services` plugin |
| `android/build.gradle.kts` | ✅ Exists | Must have google-services version `4.4.4` |
| `android/app/src/main/AndroidManifest.xml` | ✅ Exists | Must have location + internet permissions |
| `assets/style.json` | ⚠️ May not exist | You'll create this with the map style JSON provided below |
| `firestore.rules` | ⚠️ Reference only | Deploy via Firebase Console, not the app |

**First step:** Check what files exist, then fill in what's missing according to this guide.

---

## 3. TECH STACK & VERSIONS

### pubspec.yaml — EXACT dependencies to use:
```yaml
name: georide
description: "Pokemon GO inspired real-time GPS ride-sharing app."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.11.3

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  firebase_core: ^4.6.0
  maplibre_gl: 0.25.0
  geolocator: ^14.0.2
  permission_handler: ^12.0.1
  firebase_auth: ^6.3.0
  cloud_firestore: ^6.2.0
  http: ^1.3.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/style.json
```

> **IMPORTANT:** Do NOT add `flutter_compass`. It was added in a previous failed attempt and caused build issues on some devices. The compass heading is nice-to-have but not required. If you want compass, add it in a LATER phase after everything else works.

> **IMPORTANT:** Do NOT add `flutter_map` or `latlong2`. This project uses `maplibre_gl`, not `flutter_map`. They are completely different map libraries with incompatible APIs.

---

## 4. FIREBASE CONFIGURATION

### Firebase Project Details (DO NOT CHANGE):
- **Project ID:** `georide-7076c`
- **Project Number:** `897110757225`
- **Storage Bucket:** `georide-7076c.firebasestorage.app`
- **Package Name:** `com.example.georide`
- **App ID (Android):** `1:897110757225:android:8a0d207a2cc30d9a4fb7f8`
- **API Key:** `AIzaSyA4E8y4NmWYoknpJnKihaJofaiB6XzJ-9g`

### Authentication Method:
**Anonymous sign-in only.** No login screen, no email/password. Every user gets a unique UID automatically.

```dart
await FirebaseAuth.instance.signInAnonymously();
```

### google-services.json (MUST be at `android/app/google-services.json`):
```json
{
  "project_info": {
    "project_number": "897110757225",
    "project_id": "georide-7076c",
    "storage_bucket": "georide-7076c.firebasestorage.app"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:897110757225:android:8a0d207a2cc30d9a4fb7f8",
        "android_client_info": {
          "package_name": "com.example.georide"
        }
      },
      "oauth_client": [],
      "api_key": [
        {
          "current_key": "AIzaSyA4E8y4NmWYoknpJnKihaJofaiB6XzJ-9g"
        }
      ],
      "services": {
        "appinvite_service": {
          "other_platform_oauth_client": []
        }
      }
    }
  ],
  "configuration_version": "1"
}
```

---

## 5. ARCHITECTURE RULES (MANDATORY)

### Rule 1: FLAT FILE STRUCTURE
```
lib/
├── main.dart              # Firebase init, anonymous auth, MaterialApp
└── screens/
    └── home_screen.dart   # EVERYTHING ELSE goes here
```

**The entire app logic — the SharingPoint model, map rendering, avatar, portals, Firestore CRUD, ride dialogs, preview cards — ALL goes in `home_screen.dart`.** Do NOT create separate files for models, services, or widgets.

**Why:** Three previous AI sessions split code across 10+ files (models, services, widgets). The files inevitably drifted out of sync during iterative changes, creating compilation errors and logic bugs that were extremely difficult to trace. Keeping everything in one file eliminates this class of bugs entirely.

### Rule 2: TWO FILES ONLY
Only ever create/modify these two Dart files:
- `lib/main.dart`
- `lib/screens/home_screen.dart`

### Rule 3: MAPLIBRE, NOT FLUTTER_MAP
This project uses `maplibre_gl: 0.25.0` which renders a native map view. Do NOT use `flutter_map` (which is a completely different package with different APIs).

---

## 6. HARD-WON LESSONS — READ BEFORE WRITING CODE

These lessons come from 3 failed implementation attempts. Each one cost hours of debugging. **FOLLOW THEM EXACTLY.**

### 🚨 CRITICAL: maplibre_gl 0.25.0 API Limitations

1. **`SymbolOptions` does NOT have** `iconAllowOverlap` or `iconIgnorePlacement` parameters. If you try to use them, you get a compile error.

2. **`Symbol` objects do NOT have** a mutable `geometry` property. You CANNOT do `symbol.geometry = newLatLng`. To move a symbol, you must use `controller.updateSymbol(symbol, SymbolOptions(geometry: newLatLng))`.

3. **There is NO `onSymbolTapped`** or `onFeatureTapped` callback on the `MapLibreMap` widget. To detect portal taps, use the `onMapClick` callback and check proximity to each ride's coordinates manually.

4. **`toScreenLocation()` returns NATIVE coordinates**, not Flutter widget coordinates. Do NOT use it to position Flutter overlays — the positions will be wrong.

### 🚨 CRITICAL: Avatar Implementation

5. **Use a FIXED Flutter overlay for the avatar, NOT a MapLibre Symbol.** The avatar is a `CustomPaint` widget inside an `Align` widget in the Stack overlay. The map moves underneath it as GPS updates arrive. This creates the Pokémon GO third-person effect.

   - **3D mode (60° tilt):** `Alignment(0, 0.15)` — slightly below center
   - **2D mode (0° tilt):** `Alignment.center`

   **Why not a Symbol?** Symbols must be recreated to move (remove + add). This causes visible flickering on every GPS tick. A Flutter overlay is smooth.

6. **Use MapLibre Symbols for portal markers.** Portals need to stay anchored to geographic coordinates (lat/lng). Symbols are perfect for this since they stay in place when zooming/panning/tilting.

### 🚨 CRITICAL: Race Conditions

7. **The Firestore stream starts in `initState()` but the map may not be ready yet.** When `_updatePortalSymbols()` is called, guard it with `if (!_isMapReady || !_imagesRegistered) return;` BUT ALSO set a `_pendingPortalUpdate = true` flag. When the map finishes initializing, check this flag and replay the update. WITHOUT THIS, portals never appear. This was the bug that multiple sessions couldn't fix.

8. **The `onStyleLoadedCallback` fires AFTER `onMapCreated`.** Even though the map controller exists, the style may not be loaded yet. Register images and add symbols AFTER both callbacks have fired. The safest approach: register images in `onMapCreated`, then in `onStyleLoadedCallback`, check for pending updates.

### 🚨 CRITICAL: GPS & Camera

9. **Debounce camera animations to 2+ seconds.** GPS updates can come every 1–2 seconds. Each `animateCamera()` takes ~500ms. If they stack, the camera jerks wildly. Track `_lastCameraAnimateTime` and skip animations that are too frequent.

10. **Use `distanceFilter: 5` in location settings.** GPS naturally jitters ±3–5m even when stationary. A 5m filter suppresses noise.

11. **Smooth positions by averaging the last 3 GPS readings.** But if the spread between first and last is >100m, skip smoothing (indicates a real location change, not GPS noise).

### 🚨 CRITICAL: Error Handling

12. **Wrap ALL symbol operations in try-catch.** `addSymbol()`, `removeSymbol()`, and `updateSymbol()` can throw if the map is in a transitional state. One uncaught exception in a loop will kill the entire function (no more portals rendered).

13. **`_ensureAvatarOnTop()` must be in try-catch.** This function removes and recreates the avatar after updating portal symbols. If the old avatar was already removed (e.g., map was reset), `removeSymbol()` throws and breaks the entire portal update chain.

### 🚨 CRITICAL: Image Generation

14. **Generate marker images with `Canvas` + `PictureRecorder`.** Do NOT use PNG files. Draw the avatar/portal programmatically, convert to `ui.Image`, then to PNG bytes using `toByteData(format: ui.ImageByteFormat.png)`. Register with `controller.addImage('name', bytes)`.

15. **Register images in `onMapCreated` using `await`.** Do this BEFORE adding any symbols. The image name must match what you use in `SymbolOptions(iconImage: 'name')`.

---

## 7. COMPLETE FEATURE SPECIFICATION

### Feature 1: Firebase Init & Anonymous Auth (main.dart)
- Initialize Firebase
- Sign in anonymously
- Log success/failure
- Launch HomeScreen

### Feature 2: 3D Map Engine
- Load `assets/style.json` as the map style
- MapLibreMap widget with initial camera at user's GPS position
- 3D mode: zoom 16.0, tilt 60.0
- 2D mode: zoom 18.0, tilt 0.0
- `myLocationEnabled: false` (we draw our own avatar)

### Feature 3: Live GPS Tracking
- Request location permission using Geolocator
- Get initial position with `getCurrentPosition()`
- Subscribe to position stream with `distanceFilter: 5`
- Smooth positions using 3-point buffer averaging
- Animate camera to follow user (debounced to 2s intervals)

### Feature 4: User Avatar (Flutter Overlay)
- Animated `CustomPaint` widget positioned with `Align`
- Blue radial gradient core circle with glow rings
- Pulsing animation (3 concentric rings expanding outward)
- AnimationController with 2000ms duration, repeating
- Wrapped in `IgnorePointer` so taps pass through to the map

### Feature 5: Ride Hosting (Create Portal)
- FAB button "Host Ride"
- Dialog with: destination text field, seat selector (1–6), wait time selector (15/30/45/60 min)
- On create: validates input, writes to Firestore `sharing_points` collection
- Guards: must be authenticated, can't already be hosting, can't already be a passenger, GPS must be available

### Feature 6: Portal Markers (MapLibre Symbols)
- Listen to Firestore stream for active rides
- Generate portal image programmatically (orange/purple gradient, person icon)
- Register as 'portal-icon' with `addImage()`
- Add Symbol at each ride's (lat, lng) with `iconImage: 'portal-icon'`
- Clear and re-add all symbols when rides change
- **DEFERRED UPDATE PATTERN:** If map isn't ready when rides change, set `_pendingPortalUpdate = true` and replay later

### Feature 7: Portal Tap Detection
- `onMapClick` callback on MapLibreMap
- Calculate distance from click coords to each ride's (lat, lng) using `Geolocator.distanceBetween()`
- If distance < 200m, show ride preview for that ride

### Feature 8: Ride Preview Bottom Sheet
- `showModalBottomSheet` with ride details
- Shows: destination, seats remaining, distance to portal, time remaining
- Conditional buttons based on user role:
  - **Not joined:** "Join Ride" button
  - **Is host:** passenger count + "Cancel Ride" button
  - **Already joined:** "You're in this ride" confirmation
  - **Full/Expired:** status message

### Feature 9: Join/Leave/Cancel Ride
- **Join:** decrement seats, add userId to passengers array, set status to 'full' if 0 seats left
- **Leave:** increment seats, remove userId from passengers array
- **Cancel (host only):** set status to 'expired'

### Feature 10: Host Dashboard (when hosting)
- Top HUD: "YOUR HOSTED RIDE", destination, passenger count, expiry timer
- Bottom panel: ride details, "Cancel Ride" button, passenger status

### Feature 11: Passenger Navigation (when joined)
- Top HUD: "ONGOING RIDE", destination, distance to host
- Bottom panel: "Go to Host" button (animates camera), "Leave" button
- Route line from user to host position (fetched from OSRM API)

### Feature 12: Route Line
- Fetch route from OSRM public API: `https://router.project-osrm.org/route/v1/driving/{startLng},{startLat};{endLng},{endLat}?overview=full&geometries=geojson`
- Draw as a MapLibre `Line` with cyan color
- Refresh when user moves >50m
- Remove when user leaves ride

### Feature 13: 3D/2D Toggle
- FAB button with `Icons.layers`/`Icons.map`
- Toggles between 60° tilt (3D) and 0° tilt (2D)
- Animates camera smoothly

### Feature 14: Ride Expiry
- `Timer.periodic(Duration(seconds: 30))` queries active rides
- If `DateTime.now().isAfter(ride.expiresAt)`, updates status to 'expired'
- Expired rides disappear from all users' maps

---

## 8. FIRESTORE DATA MODEL

### Collection: `sharing_points`

| Field | Type | Description |
|-------|------|-------------|
| `creatorId` | String | UID of the creator |
| `lat` | Double | Pickup latitude |
| `lng` | Double | Pickup longitude |
| `destination` | String | Where the ride is going |
| `seatsAvailable` | Integer | Remaining seats (decrements on join) |
| `totalSeats` | Integer | Original seat count |
| `status` | String | `"active"`, `"full"`, `"ongoing"`, or `"expired"` |
| `createdAt` | Timestamp | When the ride was created |
| `expiresAt` | Timestamp | When it expires (createdAt + waitMinutes) |
| `passengers` | Array\<String\> | UIDs of joined users |

### SharingPoint Model (put inline in home_screen.dart):
```dart
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
```

---

## 9. FIRESTORE SECURITY RULES

Deploy these via the Firebase Console → Firestore → Rules:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /sharing_points/{pointId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update: if request.auth != null;
      allow delete: if request.auth != null && request.auth.uid == resource.data.creatorId;
    }
  }
}
```

---

## 10. MAP STYLE JSON

Save this as `assets/style.json`. This is a MapLibre Style Spec v8 using OpenFreeMap tiles. It gives a light green Pokémon GO-style map with 3D building extrusion:

```json
{"version":8,"name":"GeoRide Pokemon Go","sources":{"openmaptiles":{"type":"vector","url":"https://tiles.openfreemap.org/planet"},"ne2_shaded":{"maxzoom":6,"tileSize":256,"tiles":["https://tiles.openfreemap.org/natural_earth/ne2sr/{z}/{x}/{y}.png"],"type":"raster"}},"sprite":"https://tiles.openfreemap.org/sprites/ofm_f384/ofm","glyphs":"https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf","layers":[{"id":"background","type":"background","paint":{"background-color":"#81c784"}},{"id":"landcover-glacier","type":"fill","source":"openmaptiles","source-layer":"landcover","filter":["==",["get","subclass"],"glacier"],"paint":{"fill-color":"#ffffff","fill-opacity":["interpolate",["linear"],["zoom"],0,0.9,10,0.3]}},{"id":"landuse-residential","type":"fill","source":"openmaptiles","source-layer":"landuse","filter":["match",["get","class"],["neighbourhood","residential"],true,false],"paint":{"fill-color":["interpolate",["linear"],["zoom"],12,"hsla(43,60%,86%,0.5)",16,"hsla(43,60%,86%,0.3)"]}},{"id":"landuse-suburb","type":"fill","source":"openmaptiles","source-layer":"landuse","maxzoom":10,"filter":["==",["get","class"],"suburb"],"paint":{"fill-color":"hsla(43,60%,86%,0.4)" }},{"id":"landuse-commercial","type":"fill","source":"openmaptiles","source-layer":"landuse","filter":["==",["get","class"],"commercial"],"paint":{"fill-color":"#dce8a8"}},{"id":"landuse-industrial","type":"fill","source":"openmaptiles","source-layer":"landuse","filter":["match",["get","class"],["industrial","dam","garages"],true,false],"paint":{"fill-color":"#d0d8c8"}},{"id":"park","type":"fill","source":"openmaptiles","source-layer":"park","paint":{"fill-color":"#4caf50","fill-opacity":0.6}},{"id":"landcover-wood","type":"fill","source":"openmaptiles","source-layer":"landcover","filter":["==",["get","class"],"wood"],"paint":{"fill-color":"#388e3c","fill-opacity":0.3}},{"id":"landcover-grass","type":"fill","source":"openmaptiles","source-layer":"landcover","filter":["==",["get","class"],"grass"],"paint":{"fill-color":"#66bb6a","fill-opacity":0.5}},{"id":"landcover-sand","type":"fill","source":"openmaptiles","source-layer":"landcover","filter":["==",["get","class"],"sand"],"paint":{"fill-color":"#ffe082"}},{"id":"water","type":"fill","source":"openmaptiles","source-layer":"water","paint":{"fill-color":"#42a5f5"}},{"id":"waterway-river","type":"line","source":"openmaptiles","source-layer":"waterway","filter":["==",["get","class"],"river"],"paint":{"line-color":"#42a5f5","line-width":["interpolate",["exponential",1.2],["zoom"],10,0.8,20,6]}},{"id":"waterway-stream","type":"line","source":"openmaptiles","source-layer":"waterway","filter":["==",["get","class"],"stream"],"paint":{"line-color":"#64b5f6","line-width":["interpolate",["exponential",1.3],["zoom"],13,0.5,20,4]}},{"id":"building","type":"fill-extrusion","source":"openmaptiles","source-layer":"building","paint":{"fill-extrusion-color":"#e0e0e0","fill-extrusion-height":{"property":"render_height","type":"identity"},"fill-extrusion-base":{"property":"render_min_height","type":"identity"},"fill-extrusion-opacity":0.85},"minzoom":13},{"id":"building-top","type":"fill-extrusion","source":"openmaptiles","source-layer":"building","paint":{"fill-extrusion-color":"#bdbdbd","fill-extrusion-height":{"property":"render_height","type":"identity"},"fill-extrusion-base":{"property":"render_min_height","type":"identity"},"fill-extrusion-opacity":0.5},"minzoom":13},{"id":"tunnel-motorway","type":"line","source":"openmaptiles","source-layer":"transportation","filter":["all",["==",["get","brunnel"],"tunnel"],["==",["get","class"],"motorway"]],"paint":{"line-color":"#ffcc80","line-width":["interpolate",["exponential",1.2],["zoom"],6.5,0,20,18]}},{"id":"highway-path","type":"line","source":"openmaptiles","source-layer":"transportation","filter":["==",["get","class"],"path"],"paint":{"line-color":"#bcaaa4","line-dasharray":[1.5,0.75],"line-width":["interpolate",["exponential",1.2],["zoom"],15,1,20,4]}},{"id":"highway-minor","type":"line","source":"openmaptiles","source-layer":"transportation","filter":["match",["get","class"],["minor","service","track"],true,false],"paint":{"line-color":"#ffffff","line-width":["interpolate",["exponential",1.2],["zoom"],13.5,0,20,11]}},{"id":"highway-secondary","type":"line","source":"openmaptiles","source-layer":"transportation","filter":["match",["get","class"],["secondary","tertiary"],true,false],"paint":{"line-color":"#fff9c4","line-width":["interpolate",["exponential",1.2],["zoom"],8,0.5,20,13]}},{"id":"highway-primary","type":"line","source":"openmaptiles","source-layer":"transportation","filter":["==",["get","class"],"primary"],"paint":{"line-color":"#ffeb3b","line-width":["interpolate",["exponential",1.2],["zoom"],8.5,0,20,18]}},{"id":"highway-trunk","type":"line","source":"openmaptiles","source-layer":"transportation","filter":["==",["get","class"],"trunk"],"paint":{"line-color":"#ffcc80","line-width":["interpolate",["exponential",1.2],["zoom"],7,0.5,20,18]}},{"id":"highway-motorway","type":"line","source":"openmaptiles","source-layer":"transportation","filter":["==",["get","class"],"motorway"],"paint":{"line-color":"#ff9800","line-width":["interpolate",["exponential",1.2],["zoom"],6.5,0,20,20]}},{"id":"railway","type":"line","source":"openmaptiles","source-layer":"transportation","filter":["==",["get","class"],"rail"],"paint":{"line-color":"#bdbdbd","line-dasharray":[2,2],"line-width":["interpolate",["exponential",1.4],["zoom"],14,0.4,20,2]}},{"id":"bridge-motorway","type":"line","source":"openmaptiles","source-layer":"transportation","filter":["all",["==",["get","brunnel"],"bridge"],["==",["get","class"],"motorway"]],"paint":{"line-color":"#ff9800","line-width":["interpolate",["exponential",1.2],["zoom"],6.5,0,20,20]}},{"id":"place-label-village","type":"symbol","source":"openmaptiles","source-layer":"place","filter":["==",["get","class"],"suburb"],"layout":{"text-field":["get","name"],"text-font":["Noto Sans Regular"],"text-size":["interpolate",["linear"],["zoom"],10,10,15,14]},"paint":{"text-color":"#5d4037","text-halo-color":"#ffffff","text-halo-width":1.5}},{"id":"place-label-town","type":"symbol","source":"openmaptiles","source-layer":"place","filter":["match",["get","class"],["village","town"],true,false],"layout":{"text-field":["get","name"],"text-font":["Noto Sans Regular"],"text-size":["interpolate",["linear"],["zoom"],8,12,15,16]},"paint":{"text-color":"#4e342e","text-halo-color":"#ffffff","text-halo-width":2}},{"id":"place-label-city","type":"symbol","source":"openmaptiles","source-layer":"place","filter":["==",["get","class"],"city"],"layout":{"text-field":["get","name"],"text-font":["Noto Sans Bold"],"text-size":["interpolate",["linear"],["zoom"],6,14,12,20]},"paint":{"text-color":"#3e2723","text-halo-color":"#ffffff","text-halo-width":2.5}}]}
```

---

## 11. ANDROID CONFIGURATION

### `android/app/build.gradle.kts`:
```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.georide"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
    defaultConfig {
        applicationId = "com.example.georide"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter { source = "../.." }
```

### `android/build.gradle.kts`:
Must contain:
```kotlin
id("com.google.gms.google-services") version "4.4.4" apply false
```

### `android/app/src/main/AndroidManifest.xml` (must have these permissions):
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
```

---

## 12. PHASED IMPLEMENTATION PLAN

### PHASE 1: Foundation (Map + GPS + Avatar)
**Goal:** User sees a 3D map with their live GPS position marked by an animated avatar.

**Steps:**
1. Set up `pubspec.yaml` with all dependencies
2. Create `assets/style.json`
3. Write `lib/main.dart` (Firebase init + anonymous auth)
4. Write `lib/screens/home_screen.dart` with:
   - MapLibreMap loading `style.json`
   - GPS permission request + position stream with smoothing
   - Animated avatar as a Flutter `Align` overlay (NOT a Symbol)
   - Camera following user position with debounce
   - 3D/2D toggle FAB
   - "My Location" FAB

**Build & Test:** `flutter build apk --release` → Install on phone → Verify avatar shows and moves with you.

### PHASE 2: Ride Hosting (Create Portal in Firestore)
**Goal:** User can tap "Host Ride", enter details, and create a document in Firestore.

**Steps:**
1. Add "Host Ride" FAB button
2. Create host ride dialog (destination, seats, wait time)
3. Write Firestore create logic
4. Add validation (auth check, not already hosting, GPS available)
5. Add success/error snackbars

**Build & Test:** `flutter build apk --release` → Host a ride → Check Firestore Console to verify document was created with correct fields.

### PHASE 3: Portal Rendering (Show portals on map)
**Goal:** All users see glowing portal icons on the map for active rides.

**Steps:**
1. Add SharingPoint model class (inline in home_screen.dart)
2. Add Firestore stream listener for active rides
3. Generate portal image programmatically with Canvas
4. Register 'portal-icon' with `addImage()` in `onMapCreated`
5. Implement `_updatePortalSymbols()` with the **deferred update pattern** (see Lesson #7)
6. Add `onStyleLoadedCallback` → retry portal update
7. Add `onMapCreated` → register images → update portals
8. All symbol operations in try-catch
9. Add expiry timer

**Build & Test:** `flutter build apk --release` → Create a ride → Portal should appear immediately. Use two devices to verify other users see it.

### PHASE 4: Join Flow (Tap portal → Preview → Join)
**Goal:** Users can tap portals, see ride details, and join.

**Steps:**
1. Implement `_handleMapTap()` with proximity check
2. Build ride preview bottom sheet
3. Implement join/leave/cancel Firestore updates
4. Update bottom sheet to show conditional content (host vs passenger vs join)

**Build & Test:** `flutter build apk --release` → Create ride on device A → See portal on device B → Tap to join → Verify seats decrease in Firestore.

### PHASE 5: Dashboard Panels + Route Line
**Goal:** Host sees passenger panel, passengers see navigation with route line.

**Steps:**
1. Build host top HUD + bottom panel
2. Build passenger top HUD + bottom panel
3. Implement OSRM route fetching
4. Draw route line on map (cyan Line)
5. Auto-refresh route when user moves >50m
6. Clean up route on leave

**Build & Test:** `flutter build apk --release` → Full end-to-end test with two devices.

### PHASE 6: Live Passenger Location Tracking (Radar)
**Goal:** Hosts can see passengers moving in real-time on their map as they navigate to the portal.
**Steps:**
1. Passenger: On location update, throttle uploads to once every 5 seconds. Write GPS coordinates to `sharing_points/{pointId}/passenger_locations/{uid}`.
2. Host: Subscribe to the `passenger_locations` subcollection.
3. Host: Maintain state of passenger `Symbol`s, registering a `passenger-avatar` icon.
4. Alerts: Trigger a "reached sharing spot" warning when distance < 20m.
5. Cleanup: If someone leaves, remove their symbol from the map.

### PHASE 7: Authentication, Identity, & Timer Fix
**Goal:** Replace anonymous logic with proper Email/Password Auth, let users log out, and fix the frozen HUD countdown timer.
**Steps:**
1. Remove `signInAnonymously()` from `main.dart`. Use a `StreamBuilder` on `FirebaseAuth.instance.authStateChanges()`.
2. Build an `AuthScreen` (`auth_screen.dart` or handled cleanly inside `main.dart`) with Email/Password Signup and Login variants, plus Forgot Password.
3. Profile/Logout: Add an account icon in `HomeScreen` HUD. Opening it shows a BottomSheet with user Email, UID, and Logout button.
4. Timer Fix: Implement an internal `_LiveCountdownText` Stateful Widget that holds its own `Timer.periodic` and uses `setState()` every second, rather than relying on the 30-second global app refresh.

### PHASE 8: Real-Time Multiplayer Messaging
**Goal:** Passengers and hosts can chat directly inside the active ride panel.
**Steps:**
1. Set up a `messages` subcollection under the corresponding `sharing_points` document.
2. Build a chat interface overlay inside the `HomeScreen` bottom panel or as a standalone modal.
3. Automatically generate system messages ("Host cancelled", "Passenger left").
4. Sync the read/write operations to all active passengers.

### 🔑 CRITICAL REMINDER FOR EACH PHASE:
- After completing each phase, run `flutter build apk --release`
- Provide the APK to the user for manual testing
- APK location: `build/app/outputs/flutter-apk/app-release.apk`
- DO NOT move to the next phase until the current one is verified working

---

## 13. CODE PATTERNS THAT WORK

### Pattern A: Deferred Portal Update
```dart
bool _pendingPortalUpdate = false;

Future<void> _updatePortalSymbols() async {
  if (_mapController == null || !_isMapReady || !_imagesRegistered) {
    _pendingPortalUpdate = true;  // Will retry when ready
    return;
  }
  _pendingPortalUpdate = false;
  // ... add symbols ...
}

// In onMapCreated:
onMapCreated: (controller) async {
  _mapController = controller;
  _isMapReady = true;
  await _registerMarkerImages();  // Sets _imagesRegistered = true
  await _updatePortalSymbols();   // Will now succeed
  await _createAvatarOnce();
}

// In onStyleLoadedCallback:
onStyleLoadedCallback: () {
  if (_pendingPortalUpdate) {
    _updatePortalSymbols();  // Retry
  }
}

// In _registerMarkerImages, after setting _imagesRegistered = true:
if (_pendingPortalUpdate) {
  _pendingPortalUpdate = false;
  await _updatePortalSymbols();  // Retry
}
```

### Pattern B: Safe Symbol Operations
```dart
// Always try-catch symbol operations
try {
  final symbol = await _mapController!.addSymbol(options);
  _portalSymbols[ride.id] = symbol;
} catch (e) {
  debugPrint('Failed to add portal: $e');
}

// Safe removal
try {
  await _mapController!.removeSymbol(symbol);
} catch (_) {
  // May already be removed
}
```

### Pattern C: Avatar as Flutter Overlay (in the Stack)
```dart
// In build() → Stack children:
IgnorePointer(
  child: Align(
    alignment: _is3DMode ? const Alignment(0, 0.15) : Alignment.center,
    child: SizedBox(
      width: 50, height: 50,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (_, __) => CustomPaint(painter: _AvatarPainter(_pulseController.value)),
      ),
    ),
  ),
),
```

### Pattern D: Camera Animation with Debounce
```dart
DateTime? _lastCameraAnimateTime;
static const _minAnimateInterval = Duration(seconds: 2);

void _onPositionUpdate(Position pos) {
  final now = DateTime.now();
  final canAnimate = _lastCameraAnimateTime == null ||
      now.difference(_lastCameraAnimateTime!) >= _minAnimateInterval;

  if (_isMapReady && _mapController != null && canAnimate) {
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
```

---

## 14. CODE PATTERNS THAT FAIL

### ❌ DO NOT: Use separate files
```
lib/models/sharing_point.dart        ← NO
lib/services/sharing_service.dart    ← NO
lib/services/location_service.dart   ← NO
lib/widgets/avatar_marker.dart       ← NO
lib/widgets/portal_marker.dart       ← NO
```
**All code goes in `home_screen.dart`.**

### ❌ DO NOT: Use flutter_map
```dart
import 'package:flutter_map/flutter_map.dart';   // WRONG PACKAGE
import 'package:latlong2/latlong.dart';           // WRONG PACKAGE
```
**Use `maplibre_gl` instead.**

### ❌ DO NOT: Use Symbol for avatar
```dart
// This causes flickering on every GPS update:
_mapController.removeSymbol(avatarSymbol);
avatarSymbol = await _mapController.addSymbol(SymbolOptions(...));
```
**Use a Flutter overlay instead.**

### ❌ DO NOT: Silently drop portal updates
```dart
// BAD — update is lost forever:
Future<void> _updatePortalSymbols() async {
  if (!_isMapReady || !_imagesRegistered) return;  // ← Lost!
  ...
}
```
**Set a pending flag and retry later.**

### ❌ DO NOT: Use iconAllowOverlap (doesn't exist in 0.25.0)
```dart
SymbolOptions(
  iconAllowOverlap: true,       // ← COMPILE ERROR
  iconIgnorePlacement: true,    // ← COMPILE ERROR
)
```

### ❌ DO NOT: Use onSymbolTapped (doesn't exist in 0.25.0)
```dart
MapLibreMap(
  onSymbolTapped: (symbol) { ... },  // ← DOESN'T EXIST
)
```
**Use `onMapClick` with proximity checking instead.**

---

## 15. TESTING CHECKLIST

After each phase, verify:

### Phase 1:
- [ ] App launches without crash
- [ ] Location permission dialog appears
- [ ] 3D map loads with green terrain and buildings
- [ ] Animated blue avatar appears at user's position
- [ ] Avatar stays in place, map moves underneath when walking
- [ ] 3D/2D toggle works
- [ ] "My Location" button snaps camera back

### Phase 2:
- [ ] "Host Ride" FAB is visible
- [ ] Dialog opens with destination, seats, wait time
- [ ] Creating ride shows green success snackbar
- [ ] Document appears in Firestore Console with correct fields
- [ ] Cannot create ride if already hosting

### Phase 3:
- [ ] Portal icon appears on map at the hosted ride's location
- [ ] Portal is visible to other users within 5km
- [ ] Portal disappears when ride expires
- [ ] Portal disappears when ride is cancelled
- [ ] Creating a new ride → portal appears immediately (no refresh needed)

### Phase 4:
- [ ] Tapping near a portal opens the preview bottom sheet
- [ ] Preview shows destination, seats, distance, time
- [ ] "Join Ride" works — seats decrease, user added to passengers
- [ ] Cannot join own ride
- [ ] Cannot join full/expired ride

### Phase 5:
- [ ] Host sees top HUD with ride info
- [ ] Host sees bottom panel with passenger count
- [ ] Passenger sees navigation panel with distance to host
- [ ] Route line appears from passenger to host
- [ ] "Go to Host" animates camera to host location
- [ ] "Leave" removes passenger and clears route
- [ ] "Cancel Ride" (host) expires the ride for everyone

---

## END OF BUILD GUIDE

This document contains everything needed. Give the ENTIRE file to a new AI session and tell them:

> "Read GEORIDE_BUILD_GUIDE.md completely. Then check what files exist in the repo, and start implementing from Phase 1. Build a release APK after each phase so I can test."
