import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

class OsrmRoute {
  final List<LatLng> points; // full decoded polyline
  final double distanceMeters;
  final double durationSeconds;
  final List<OsrmStep> steps;

  const OsrmRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
  });
}

class OsrmStep {
  final LatLng startLocation;
  final LatLng endLocation;
  final double distanceMeters;
  final String maneuver; // 'turn', 'depart', 'arrive', etc.

  const OsrmStep({
    required this.startLocation,
    required this.endLocation,
    required this.distanceMeters,
    required this.maneuver,
  });
}

class OsrmService {
  static const String _baseUrl =
      'https://router.project-osrm.org/route/v1/driving/';
  static const Duration _timeout = Duration(seconds: 4);

  // In-memory cache: key = "lng1,lat1;lng2,lat2"
  static final Map<String, OsrmRoute> _cache = {};

  /// Fetch a driving route between [origin] and [destination].
  /// Returns a cached route if available.
  /// Throws [OsrmException] on failure.
  static Future<OsrmRoute> fetchRoute(LatLng origin, LatLng destination) async {
    final key = '${origin.longitude.toStringAsFixed(5)},'
        '${origin.latitude.toStringAsFixed(5)};'
        '${destination.longitude.toStringAsFixed(5)},'
        '${destination.latitude.toStringAsFixed(5)}';

    if (_cache.containsKey(key)) {
      debugPrint('✅ OSRM cache hit: $key');
      return _cache[key]!;
    }

    final url = '$_baseUrl'
        '${origin.longitude.toStringAsFixed(6)},${origin.latitude.toStringAsFixed(6)};'
        '${destination.longitude.toStringAsFixed(6)},${destination.latitude.toStringAsFixed(6)}'
        '?overview=full&geometries=geojson&steps=true';

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {'User-Agent': 'GeoRide/1.0'},
          )
          .timeout(_timeout);

      if (response.statusCode == 429) {
        throw OsrmException('Rate limited. Using cached route if available.');
      }
      if (response.statusCode != 200) {
        throw OsrmException('OSRM HTTP ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        throw OsrmException('No route found between the two points.');
      }

      final route = routes[0] as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coords = geometry['coordinates'] as List;

      final points = coords
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      // Parse steps from the first leg
      final legs = route['legs'] as List? ?? [];
      final List<OsrmStep> steps = [];
      if (legs.isNotEmpty) {
        final firstLeg = legs[0] as Map<String, dynamic>;
        final rawSteps = firstLeg['steps'] as List? ?? [];
        for (final s in rawSteps) {
          final sMap = s as Map<String, dynamic>;
          final sl = sMap['maneuver']?['location'] as List?;
          final el = (sMap['intersections'] as List?)?.last?['location'] as List?;
          if (sl != null) {
            steps.add(OsrmStep(
              startLocation: LatLng((sl[1] as num).toDouble(), (sl[0] as num).toDouble()),
              endLocation: el != null
                  ? LatLng((el[1] as num).toDouble(), (el[0] as num).toDouble())
                  : LatLng((sl[1] as num).toDouble(), (sl[0] as num).toDouble()),
              distanceMeters: (sMap['distance'] as num?)?.toDouble() ?? 0,
              maneuver: (sMap['maneuver']?['type'] as String?) ?? 'straight',
            ));
          }
        }
      }

      final osrmRoute = OsrmRoute(
        points: points,
        distanceMeters: (route['distance'] as num).toDouble(),
        durationSeconds: (route['duration'] as num).toDouble(),
        steps: steps,
      );

      // Cache the result
      _cache[key] = osrmRoute;
      return osrmRoute;
    } on OsrmException {
      // Re-throw our own exceptions
      rethrow;
    } catch (e) {
      // Try to serve from cache if we have any cached key nearby
      if (_cache.isNotEmpty) {
        debugPrint('⚠️ OSRM error ($e). Serving last cached route.');
        return _cache.values.last;
      }
      throw OsrmException('Route fetch failed: $e');
    }
  }

  /// Clear the route cache
  static void clearCache() => _cache.clear();
}

class OsrmException implements Exception {
  final String message;
  OsrmException(this.message);
  @override
  String toString() => 'OsrmException: $message';
}
