import 'package:cloud_firestore/cloud_firestore.dart';

class SharingPoint {
  final String id;
  final String creatorId;
  final double lat;
  final double lng;
  final String destination;
  final int seatsAvailable;
  final String status;
  final DateTime createdAt;
  final List<String> passengers;

  SharingPoint({
    required this.id,
    required this.creatorId,
    required this.lat,
    required this.lng,
    required this.destination,
    required this.seatsAvailable,
    required this.status,
    required this.createdAt,
    required this.passengers,
  });

  factory SharingPoint.fromMap(String documentId, Map<String, dynamic> map) {
    return SharingPoint(
      id: documentId,
      creatorId: map['creatorId'] ?? '',
      lat: (map['lat'] ?? 0.0).toDouble(),
      lng: (map['lng'] ?? 0.0).toDouble(),
      destination: map['destination'] ?? '',
      seatsAvailable: map['seatsAvailable'] ?? 0,
      status: map['status'] ?? 'active',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
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
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'passengers': passengers,
    };
  }
}
