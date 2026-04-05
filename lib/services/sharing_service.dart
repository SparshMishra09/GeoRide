import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../models/sharing_point.dart';

class SharingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get currentUserId => _auth.currentUser?.uid ?? 'unknown';

  // Create a new Sharing Point Host
  Future<void> createSharingPoint({
    required double lat,
    required double lng,
    required String destination,
    required int seatsAvailable,
  }) async {
    // Verify user is authenticated
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User is not authenticated. Please sign in first.');
    }
    
    debugPrint('Auth UID: ${user.uid}');
    debugPrint('Creating sharing point with creatorId: ${user.uid}');
    
    final pointData = {
      'creatorId': user.uid,
      'lat': lat,
      'lng': lng,
      'destination': destination,
      'seatsAvailable': seatsAvailable,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'passengers': <String>[],
    };

    debugPrint('Attempting Firestore write...');
    try {
      final docRef = await _firestore.collection('sharing_points').add(pointData);
      debugPrint('Success! Document created with ID: ${docRef.id}');
    } catch (e) {
      debugPrint('Firestore error: $e');
      rethrow;
    }
  }

  // Stream of nearby active rides (radius filtered locally initially)
  Stream<List<SharingPoint>> getNearbyActivePoints(Position currentPos) {
    return _firestore
        .collection('sharing_points')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      final points = snapshot.docs.map((doc) => SharingPoint.fromMap(doc.id, doc.data())).toList();
      
      // Client-side manual radius filtering
      return points.where((p) {
        // Hide very old ones (e.g. forgot to delete, 60 mins max)
        if (DateTime.now().difference(p.createdAt).inMinutes > 60) return false;

        // Radius constraint: 5km (5000 meters)
        double distance = Geolocator.distanceBetween(currentPos.latitude, currentPos.longitude, p.lat, p.lng);
        return distance <= 5000;
      }).toList();
    });
  }

  // Instant Join System
  Future<bool> joinRide(SharingPoint point) async {
    if (point.seatsAvailable <= 0) return false;
    if (point.passengers.contains(currentUserId)) return false; // Already in

    // Check if user is already a passenger in another active ride
    final existingRides = await _firestore.collection('sharing_points')
        .where('passengers', arrayContains: currentUserId)
        .where('status', isEqualTo: 'active')
        .get();

    if (existingRides.docs.isNotEmpty) {
      // User is already in a different ride!
      return false;
    }

    // Process Instant Join
    final newSeats = point.seatsAvailable - 1;
    final newStatus = newSeats == 0 ? 'full' : 'active';

    try {
      await _firestore.collection('sharing_points').doc(point.id).update({
        'seatsAvailable': newSeats,
        'status': newStatus,
        'passengers': FieldValue.arrayUnion([currentUserId])
      });
      return true;
    } catch (e) {
      debugPrint('Error joining ride: $e');
      return false;
    }
  }

  // Mark passenger as near the pickup point
  Future<void> markPassengerNear(SharingPoint point) async {
    try {
      // This could be expanded to add a notification system
      // For now, we'll add a simple timestamp to show the host when passengers are near
      await _firestore.collection('sharing_points').doc(point.id).update({
        'passengersNear': FieldValue.arrayUnion([{
          'userId': currentUserId,
          'timestamp': FieldValue.serverTimestamp(),
        }])
      });
    } catch (e) {
      debugPrint('Error marking passenger near: $e');
      rethrow;
    }
  }
}
