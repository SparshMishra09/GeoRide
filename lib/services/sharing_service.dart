import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../models/sharing_point.dart';

class SharingService {
  static final SharingService _instance = SharingService._internal();
  factory SharingService() => _instance;
  SharingService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;
  User? get currentUser => _auth.currentUser;

  /// Create a new Sharing Point (Host a Ride)
  Future<String> createSharingPoint({
    required double lat,
    required double lng,
    required String destination,
    required int seatsAvailable,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw Exception('User is not authenticated. Please sign in first.');
    }

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 30));

    debugPrint('🚗 Creating sharing point:');
    debugPrint('   Creator: ${user.uid}');
    debugPrint('   Destination: $destination');
    debugPrint('   Seats: $seatsAvailable');
    debugPrint('   Location: $lat, $lng');
    debugPrint('   Expires at: ${expiresAt.toString()}');

    final pointData = {
      'creatorId': user.uid,
      'lat': lat,
      'lng': lng,
      'destination': destination,
      'seatsAvailable': seatsAvailable,
      'totalSeats': seatsAvailable,
      'status': 'active',
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'passengers': <String>[],
    };

    try {
      final docRef = await _firestore.collection('sharing_points').add(pointData);
      debugPrint('✅ Sharing point created with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ Firestore error creating sharing point: $e');
      rethrow;
    }
  }

  /// Stream of all active, non-expired, non-full sharing points
  Stream<List<SharingPoint>> getActiveRidesStream() {
    return _firestore
        .collection('sharing_points')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final rides = <SharingPoint>[];

      for (final doc in snapshot.docs) {
        final ride = SharingPoint.fromMap(doc.id, doc.data());

        // Skip expired rides
        if (now.isAfter(ride.expiresAt)) continue;

        // Skip full rides (no seats available)
        if (ride.seatsAvailable <= 0) continue;

        // Skip rides older than 30 minutes (safety fallback)
        if (now.difference(ride.createdAt).inMinutes > 30) continue;

        rides.add(ride);
      }

      debugPrint('📡 Active rides in Firestore: ${rides.length}');
      return rides;
    });
  }

  /// Get nearby active rides within radius (in meters)
  Stream<List<SharingPoint>> getNearbyActiveRides(Position currentPos, {double radiusMeters = 5000}) {
    return getActiveRidesStream().map((rides) {
      return rides.where((ride) {
        final distance = Geolocator.distanceBetween(
          currentPos.latitude,
          currentPos.longitude,
          ride.lat,
          ride.lng,
        );
        return distance <= radiusMeters;
      }).toList();
    });
  }

  /// Join a ride as a passenger
  /// Returns: 'success', 'already_joined', 'host_cannot_join_own', 'full', 'expired', 'already_in_ride', 'error'
  Future<String> joinRide(SharingPoint point) async {
    final userId = currentUserId;
    if (userId == null) return 'error';

    // Prevent host from joining their own ride
    if (point.creatorId == userId) {
      debugPrint('❌ Host cannot join their own ride');
      return 'host_cannot_join_own';
    }

    // Check if ride is full
    if (point.seatsAvailable <= 0) {
      debugPrint('❌ Ride is full');
      return 'full';
    }

    // Check if ride is expired
    if (point.isExpired) {
      debugPrint('❌ Ride has expired');
      return 'expired';
    }

    // Check if user is already a passenger in this ride
    if (point.passengers.contains(userId)) {
      debugPrint('⚠️ Already joined this ride');
      return 'already_joined';
    }

    // Check if user is already a passenger in another active ride
    try {
      final existingRides = await _firestore.collection('sharing_points')
          .where('passengers', arrayContains: userId)
          .where('status', whereIn: ['active', 'ongoing'])
          .get();

      if (existingRides.docs.isNotEmpty) {
        debugPrint('❌ Already in another ride: ${existingRides.docs.first.id}');
        return 'already_in_ride';
      }
    } catch (e) {
      debugPrint('Error checking existing rides: $e');
    }

    // Process the join
    final newSeats = point.seatsAvailable - 1;
    final newStatus = newSeats == 0 ? 'full' : 'active';

    try {
      await _firestore.collection('sharing_points').doc(point.id).update({
        'seatsAvailable': newSeats,
        'status': newStatus,
        'passengers': FieldValue.arrayUnion([userId]),
      });

      debugPrint('✅ Successfully joined ride: ${point.id}');
      return 'success';
    } catch (e) {
      debugPrint('❌ Error joining ride: $e');
      return 'error';
    }
  }

  /// Delete a sharing point (only the host can do this)
  Future<bool> deleteSharingPoint(SharingPoint point) async {
    final userId = currentUserId;
    if (userId == null) return false;

    if (point.creatorId != userId) {
      debugPrint('❌ Only the host can delete their ride');
      return false;
    }

    try {
      await _firestore.collection('sharing_points').doc(point.id).delete();
      debugPrint('✅ Ride deleted: ${point.id}');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting ride: $e');
      return false;
    }
  }

  /// Cancel a ride (marks as expired - only host)
  Future<bool> cancelRide(SharingPoint point) async {
    final userId = currentUserId;
    if (userId == null) return false;

    if (point.creatorId != userId) {
      debugPrint('❌ Only the host can cancel their ride');
      return false;
    }

    try {
      await _firestore.collection('sharing_points').doc(point.id).update({
        'status': 'expired',
      });
      debugPrint('✅ Ride cancelled: ${point.id}');
      return true;
    } catch (e) {
      debugPrint('❌ Error cancelling ride: $e');
      return false;
    }
  }

  /// Leave a ride (for passengers)
  Future<bool> leaveRide(SharingPoint point) async {
    final userId = currentUserId;
    if (userId == null) return false;

    if (!point.passengers.contains(userId)) {
      debugPrint('❌ Not a passenger in this ride');
      return false;
    }

    try {
      final newSeats = point.seatsAvailable + 1;
      await _firestore.collection('sharing_points').doc(point.id).update({
        'seatsAvailable': newSeats,
        'passengers': FieldValue.arrayRemove([userId]),
      });
      debugPrint('✅ Left ride: ${point.id}');
      return true;
    } catch (e) {
      debugPrint('❌ Error leaving ride: $e');
      return false;
    }
  }

  /// Mark passenger as near the pickup point
  Future<void> markPassengerNear(SharingPoint point) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      await _firestore.collection('sharing_points').doc(point.id).update({
        'passengersNear': FieldValue.arrayUnion([{
          'userId': userId,
          'timestamp': FieldValue.serverTimestamp(),
        }])
      });
      debugPrint('✅ Host notified passenger is near');
    } catch (e) {
      debugPrint('❌ Error marking passenger near: $e');
      rethrow;
    }
  }

  /// Expire old rides automatically (run periodically)
  Future<void> expireOldRides() async {
    try {
      final snapshot = await _firestore
          .collection('sharing_points')
          .where('status', whereIn: ['active', 'ongoing'])
          .get();

      final now = DateTime.now();
      int expiredCount = 0;

      for (final doc in snapshot.docs) {
        final ride = SharingPoint.fromMap(doc.id, doc.data());

        if (now.isAfter(ride.expiresAt)) {
          await _firestore.collection('sharing_points').doc(doc.id).update({
            'status': 'expired',
          });
          expiredCount++;
        }
      }

      if (expiredCount > 0) {
        debugPrint('🧹 Expired $expiredCount old rides');
      }
    } catch (e) {
      debugPrint('❌ Error expiring old rides: $e');
    }
  }

  /// Get distance between current location and a sharing point
  static double calculateDistanceToRide(Position currentPos, SharingPoint ride) {
    return Geolocator.distanceBetween(
      currentPos.latitude,
      currentPos.longitude,
      ride.lat,
      ride.lng,
    );
  }

  /// Format distance for display
  static String formatDistance(double distanceMeters) {
    if (distanceMeters < 1000) {
      return '${distanceMeters.toStringAsFixed(0)}m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
  }
}
