import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Fetches real road-based routes using the free OSRM public API.
/// No API key required. Returns waypoints for drawing a polyline on the map.
class RouteService {
  static const String _baseUrl = 'https://router.project-osrm.org/route/v1';

  /// Fetches a driving/walking route between two points.
  /// Returns a list of LatLng waypoints for drawing a polyline.
  /// Returns empty list on failure.
  static Future<List<LatLng>> fetchRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    final url = Uri.parse(
      '$_baseUrl/driving/$startLng,$startLat;$endLng,$endLat?overview=full&geometries=geojson',
    );

    debugPrint('🗺️  Fetching route: $startLat,$startLng → $endLat,$endLng');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          final coordinates = geometry['coordinates'] as List;

          // OSRM returns [lng, lat] pairs, convert to LatLng (lat, lng)
          final waypoints = coordinates.map<LatLng>((coord) {
            return LatLng(coord[1].toDouble(), coord[0].toDouble());
          }).toList();

          debugPrint('✅ Route fetched: ${waypoints.length} waypoints');
          return waypoints;
        } else {
          debugPrint('⚠️ OSRM returned non-Ok code: ${data['code']}');
          return [];
        }
      } else {
        debugPrint('❌ OSRM HTTP error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('❌ Route fetch error: $e');
      return [];
    }
  }

  /// Calculates straight-line distance between two points (in meters).
  static double straightLineDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000; // meters
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }
}
