import 'package:cloud_firestore/cloud_firestore.dart';

class SharingPoint {
  final String id;
  final String creatorId;
  final double lat;
  final double lng;
  final String destination;
  final int seatsAvailable;
  final int totalSeats;
  final String status; // active, full, ongoing, expired
  final DateTime createdAt;
  final DateTime expiresAt; // 30 minutes from creation
  final List<String> passengers;

  SharingPoint({
    required this.id,
    required this.creatorId,
    required this.lat,
    required this.lng,
    required this.destination,
    required this.seatsAvailable,
    required this.totalSeats,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.passengers,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isHost => creatorId == ''; // Will be compared at runtime
  bool get isVisible => status == 'active' && !isExpired && seatsAvailable > 0;

  factory SharingPoint.fromMap(String documentId, Map<String, dynamic> map) {
    final now = DateTime.now();
    final createdAt = (map['createdAt'] as Timestamp?)?.toDate() ?? now;
    final expiresAt = (map['expiresAt'] as Timestamp?)?.toDate() ?? createdAt.add(const Duration(minutes: 30));

    return SharingPoint(
      id: documentId,
      creatorId: map['creatorId'] ?? '',
      lat: (map['lat'] ?? 0.0).toDouble(),
      lng: (map['lng'] ?? 0.0).toDouble(),
      destination: map['destination'] ?? '',
      seatsAvailable: map['seatsAvailable'] ?? 0,
      totalSeats: map['totalSeats'] ?? map['seatsAvailable'] ?? 0,
      status: map['status'] ?? 'active',
      createdAt: createdAt,
      expiresAt: expiresAt,
      passengers: List<String>.from(map['passengers'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'creatorId': creatorId,
      'lat': lat,
      'lng': lng,
      'destination': destination,
      'seatsAvailable': seatsAvailable,
      'totalSeats': totalSeats,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'passengers': passengers,
    };
  }

  Duration get timeRemaining {
    if (isExpired) return Duration.zero;
    return expiresAt.difference(DateTime.now());
  }

  String get timeRemainingText {
    if (isExpired) return 'Expired';
    final minutes = timeRemaining.inMinutes;
    final seconds = timeRemaining.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }
}
