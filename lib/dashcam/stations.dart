import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// A filling station from OpenStreetMap, bundled into the app at build time
/// (assets/stations.json, made by tool/fetch_stations.py).
class KnownStation {
  final String name;
  final double lat;
  final double lon;
  const KnownStation(this.name, this.lat, this.lon);
}

class StationIndex {
  final List<KnownStation> all;
  StationIndex(this.all);

  static Future<StationIndex> load() async {
    try {
      final raw = await rootBundle.loadString('assets/stations.json');
      final list = (jsonDecode(raw) as List)
          .map((e) => KnownStation((e[0] as String), (e[1] as num).toDouble(), (e[2] as num).toDouble()))
          .toList();
      return StationIndex(list);
    } catch (_) {
      return StationIndex(const []);
    }
  }

  /// Nearest station within [maxMetres], or null.
  (KnownStation, double)? nearest(double lat, double lon, {double maxMetres = 120}) {
    // Quick box filter first: about 0.002 degrees is 120-220 m in Ireland.
    final dLat = maxMetres / 111000.0;
    final dLon = maxMetres / (111000.0 * math.cos(lat * math.pi / 180));
    KnownStation? best;
    var bestD = double.infinity;
    for (final s in all) {
      if ((s.lat - lat).abs() > dLat || (s.lon - lon).abs() > dLon) continue;
      final d = metres(lat, lon, s.lat, s.lon);
      if (d < bestD && d <= maxMetres) {
        best = s;
        bestD = d;
      }
    }
    return best == null ? null : (best, bestD);
  }
}

double metres(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dp = rad(lat2 - lat1), dl = rad(lon2 - lon1);
  final a = math.pow(math.sin(dp / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dl / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}
