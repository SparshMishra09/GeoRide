import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class RTDBService {
  static final FirebaseDatabase _db = FirebaseDatabase.instance;
  static const String _locationsPath = 'active_locations';

  // Throttle: only write once every 10 seconds
  static DateTime? _lastWrite;
  static const Duration _writeInterval = Duration(seconds: 10);

  // Geohash encoder (simple implementation for length-7 hashes)
  static String _encodeGeohash(double lat, double lng, {int precision = 7}) {
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    double minLat = -90, maxLat = 90, minLng = -180, maxLng = 180;
    final buffer = StringBuffer();
    int bits = 0, hashValue = 0;
    bool isEven = true;

    while (buffer.length < precision) {
      if (isEven) {
        final mid = (minLng + maxLng) / 2;
        if (lng >= mid) { hashValue = (hashValue << 1) | 1; minLng = mid; }
        else { hashValue = hashValue << 1; maxLng = mid; }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (lat >= mid) { hashValue = (hashValue << 1) | 1; minLat = mid; }
        else { hashValue = hashValue << 1; maxLat = mid; }
      }
      isEven = !isEven;
      bits++;
      if (bits == 5) {
        buffer.write(base32[hashValue]);
        bits = 0;
        hashValue = 0;
      }
    }
    return buffer.toString();
  }

  /// Push the current user's location to RTDB (throttled to every 10s)
  static Future<void> pushLocation({
    required double lat,
    required double lng,
    required double bearing,
    String? routeId,
    String? displayName,
    bool force = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    if (!force &&
        _lastWrite != null &&
        now.difference(_lastWrite!) < _writeInterval) {
      return; // Throttled
    }
    _lastWrite = now;

    try {
      final ref = _db.ref('$_locationsPath/${user.uid}');
      await ref.set({
        'lat': lat,
        'lng': lng,
        'bearing': bearing,
        'geohash': _encodeGeohash(lat, lng),
        'routeId': routeId,
        'displayName': displayName ?? user.displayName ?? 'Rider',
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('⚠️ RTDB push error: $e');
    }
  }

  /// Remove the current user's location from RTDB (call on app exit / idle)
  static Future<void> removeLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _db.ref('$_locationsPath/${user.uid}').remove();
    } catch (e) {
      debugPrint('⚠️ RTDB remove error: $e');
    }
  }

  /// Stream all active locations (excluding current user).
  /// Caller is responsible for cancelling the subscription.
  static StreamSubscription<DatabaseEvent> listenToAllLocations({
    required void Function(Map<String, Map<String, dynamic>> locations) onUpdate,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    final myUid = user?.uid ?? '';

    return _db.ref(_locationsPath).onValue.listen((event) {
      final raw = event.snapshot.value as Map?;
      if (raw == null) {
        onUpdate({});
        return;
      }

      final result = <String, Map<String, dynamic>>{};
      for (final entry in raw.entries) {
        final uid = entry.key as String;
        if (uid == myUid) continue; // Skip self
        final data = Map<String, dynamic>.from(entry.value as Map);
        result[uid] = data;
      }
      onUpdate(result);
    }, onError: (e) => debugPrint('⚠️ RTDB stream error: $e'));
  }
}
