import 'dart:convert';
import 'package:http/http.dart' as http;

class PhotonResult {
  final String displayName;
  final double lat;
  final double lng;
  final String type; // city, street, house, etc.
  final String country;

  const PhotonResult({
    required this.displayName,
    required this.lat,
    required this.lng,
    required this.type,
    required this.country,
  });

  factory PhotonResult.fromFeature(Map<String, dynamic> feature) {
    final props = feature['properties'] as Map<String, dynamic>? ?? {};
    final coords = (feature['geometry']?['coordinates'] as List?) ?? [0.0, 0.0];

    final parts = <String>[];
    if (props['name'] != null) parts.add(props['name'] as String);
    if (props['street'] != null) parts.add(props['street'] as String);
    if (props['city'] != null) parts.add(props['city'] as String);
    if (props['state'] != null) parts.add(props['state'] as String);

    return PhotonResult(
      displayName: parts.isEmpty ? 'Unknown Place' : parts.join(', '),
      lat: (coords[1] as num).toDouble(),
      lng: (coords[0] as num).toDouble(),
      type: props['type'] as String? ?? '',
      country: props['country'] as String? ?? '',
    );
  }
}

class PhotonService {
  static const String _baseUrl = 'https://photon.komoot.io/api/';
  static const Duration _timeout = Duration(seconds: 5);

  /// Search for locations matching [query].
  /// Returns up to [limit] results.
  static Future<List<PhotonResult>> search(
    String query, {
    int limit = 5,
    double? nearLat,
    double? nearLng,
  }) async {
    if (query.trim().length < 3) return [];

    final params = <String, String>{
      'q': query.trim(),
      'limit': limit.toString(),
      'lang': 'en',
    };
    if (nearLat != null && nearLng != null) {
      params['lat'] = nearLat.toStringAsFixed(6);
      params['lon'] = nearLng.toStringAsFixed(6);
    }

    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'GeoRide/1.0',
        },
      ).timeout(_timeout);

      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List? ?? [];

      return features
          .map((f) => PhotonResult.fromFeature(f as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Reverse geocode a coordinate to a human-readable location.
  static Future<PhotonResult?> reverseSearch(double lat, double lng) async {
    final params = <String, String>{
      'lat': lat.toStringAsFixed(6),
      'lon': lng.toStringAsFixed(6),
      'limit': '1',
    };

    try {
      final uri = Uri.parse('https://photon.komoot.io/reverse').replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'GeoRide/1.0',
        },
      ).timeout(_timeout);

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List? ?? [];

      if (features.isEmpty) return null;
      return PhotonResult.fromFeature(features[0] as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
  }
}
