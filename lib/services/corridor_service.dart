import 'dart:math' as math;
import 'package:maplibre_gl/maplibre_gl.dart';

/// Represents an active rider found within the 200m corridor.
class CorridorRider {
  final String userId;
  final LatLng position;
  final double bearing;
  final double distanceFromUser; // meters from the local user to this rider
  final String? displayName;

  const CorridorRider({
    required this.userId,
    required this.position,
    required this.bearing,
    required this.distanceFromUser,
    this.displayName,
  });
}

class CorridorService {
  static const double corridorRadiusMeters = 200.0;
  static const double _rdpEpsilonDegrees = 0.00005; // ~5m tolerance for simplification

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ──────────────────────────────────────────────────────────────────────────

  /// Given a route [polyline] and a list of [candidatePositions] ({userId: LatLng}),
  /// return only those that fall within the 200m corridor.
  static List<CorridorRider> filterRidersInCorridor({
    required List<LatLng> polyline,
    required Map<String, Map<String, dynamic>> candidates,
    required LatLng userPosition,
  }) {
    if (polyline.isEmpty || candidates.isEmpty) return [];

    final simplified = _rdpSimplify(polyline, _rdpEpsilonDegrees);
    final results = <CorridorRider>[];

    for (final entry in candidates.entries) {
      final data = entry.value;
      final riderPos = LatLng(
        (data['lat'] as num).toDouble(),
        (data['lng'] as num).toDouble(),
      );

      final minDist = _minDistToPolyline(riderPos, simplified);
      if (minDist <= corridorRadiusMeters) {
        final distFromUser = _haversineMeters(userPosition, riderPos);
        results.add(CorridorRider(
          userId: entry.key,
          position: riderPos,
          bearing: (data['bearing'] as num?)?.toDouble() ?? 0.0,
          distanceFromUser: distFromUser,
          displayName: data['displayName'] as String?,
        ));
      }
    }

    // Sort: closest riders first
    results.sort((a, b) => a.distanceFromUser.compareTo(b.distanceFromUser));
    return results;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // RAMER-DOUGLAS-PEUCKER POLYLINE SIMPLIFICATION
  // ──────────────────────────────────────────────────────────────────────────

  static List<LatLng> _rdpSimplify(List<LatLng> points, double epsilon) {
    if (points.length < 3) return points;

    double maxDist = 0;
    int maxIndex = 0;

    for (int i = 1; i < points.length - 1; i++) {
      final dist = _perpendicularDistanceDeg(
        points[i], points.first, points.last,
      );
      if (dist > maxDist) {
        maxDist = dist;
        maxIndex = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _rdpSimplify(points.sublist(0, maxIndex + 1), epsilon);
      final right = _rdpSimplify(points.sublist(maxIndex), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [points.first, points.last];
    }
  }

  /// Perpendicular distance in degrees (for RDP, not haversine — fast enough at road scale)
  static double _perpendicularDistanceDeg(
      LatLng point, LatLng lineStart, LatLng lineEnd) {
    final dx = lineEnd.longitude - lineStart.longitude;
    final dy = lineEnd.latitude - lineStart.latitude;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return 0;
    return ((dy * (point.longitude - lineStart.longitude) -
                dx * (point.latitude - lineStart.latitude)) /
            len)
        .abs();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PRECISE POINT-TO-SEGMENT MINIMUM DISTANCE (HAVERSINE)
  // ──────────────────────────────────────────────────────────────────────────

  /// Minimum distance from [point] to any segment of [polyline] in meters.
  static double _minDistToPolyline(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return double.infinity;
    if (polyline.length == 1) return _haversineMeters(point, polyline[0]);

    double minDist = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final d = _pointToSegmentDistanceMeters(point, polyline[i], polyline[i + 1]);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  /// Exact point-to-segment distance in meters.
  /// Uses dot-product clamping: if the perpendicular foot falls outside the
  /// segment endpoints A–B, it falls back to the nearer endpoint distance.
  static double _pointToSegmentDistanceMeters(
      LatLng p, LatLng a, LatLng b) {
    // Work in approximate flat-earth coords (ok for <5km corridors)
    const metersPerDegLat = 111320.0;
    final cosLat = math.cos(a.latitude * math.pi / 180.0);

    final px = (p.longitude - a.longitude) * metersPerDegLat * cosLat;
    final py = (p.latitude - a.latitude) * metersPerDegLat;
    final bx = (b.longitude - a.longitude) * metersPerDegLat * cosLat;
    final by = (b.latitude - a.latitude) * metersPerDegLat;

    final segLenSq = bx * bx + by * by;

    if (segLenSq == 0) {
      // Segment is a single point — return direct distance
      return math.sqrt(px * px + py * py);
    }

    // Project P onto line A→B, clamped to [0, 1]
    final t = ((px * bx + py * by) / segLenSq).clamp(0.0, 1.0);

    // Closest point on segment
    final cx = t * bx;
    final cy = t * by;

    // Distance from P to closest point
    final dx = px - cx;
    final dy = py - cy;
    return math.sqrt(dx * dx + dy * dy);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HAVERSINE DISTANCE
  // ──────────────────────────────────────────────────────────────────────────

  static double _haversineMeters(LatLng a, LatLng b) {
    const R = 6371000.0; // Earth radius in meters
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;

    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final av =
        sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLng * sinDLng;
    return 2 * R * math.atan2(math.sqrt(av), math.sqrt(1 - av));
  }

  /// Calculate bearing from [from] to [to] in degrees (0-360)
  static double bearingTo(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
