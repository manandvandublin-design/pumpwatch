import 'dart:convert';

import 'package:http/http.dart' as http;

class FuelPrice {
  final double price;
  final String source;
  final DateTime reportedAt;

  FuelPrice(this.price, this.source, this.reportedAt);

  factory FuelPrice.fromJson(Map<String, dynamic> j) => FuelPrice(
        (j['price'] as num).toDouble(),
        (j['source'] ?? 'photo') as String,
        DateTime.tryParse(j['reported_at'] ?? '')?.toLocal() ?? DateTime.now(),
      );

  int get ageDays => DateTime.now().difference(reportedAt).inDays;
}

class Station {
  final int id;
  final String name;
  final double lat;
  final double lon;
  final double? distanceKm;
  final Map<String, FuelPrice> prices;

  Station({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.distanceKm,
    required this.prices,
  });

  factory Station.fromJson(Map<String, dynamic> j) {
    final p = <String, FuelPrice>{};
    final raw = (j['prices'] ?? {}) as Map<String, dynamic>;
    raw.forEach((k, v) => p[k] = FuelPrice.fromJson(v as Map<String, dynamic>));
    return Station(
      id: j['id'] as int,
      name: j['name'] as String,
      lat: (j['lat'] as num).toDouble(),
      lon: (j['lon'] as num).toDouble(),
      distanceKm: (j['distance_km'] as num?)?.toDouble(),
      prices: p,
    );
  }

  /// The price for [fuel], or null when there is none or it is older than [maxAgeDays].
  FuelPrice? priceFor(String fuel, int maxAgeDays) {
    final p = prices[fuel];
    if (p == null || p.ageDays > maxAgeDays) return null;
    return p;
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  final String baseUrl;
  Api(String base) : baseUrl = base.trim().replaceAll(RegExp(r'/+$'), '');

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? q]) async {
    if (baseUrl.isEmpty) throw ApiException('Set the server address in Settings first.');
    final http.Response r;
    try {
      r = await http.get(_u(path, q)).timeout(const Duration(seconds: 45));
    } catch (_) {
      throw ApiException('Can\'t reach the server at $baseUrl. Is it running, and is your phone on the same Wi-Fi?');
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) throw ApiException((body['error'] ?? 'Server error ${r.statusCode}').toString());
    return body;
  }

  Future<bool> health() async => (await _get('/api/health'))['ok'] == true;

  Future<List<Station>> stations(double lat, double lon, double radiusKm) async {
    final j = await _get('/api/stations', {
      'lat': '$lat',
      'lon': '$lon',
      'radius_km': '$radiusKm',
    });
    return (j['stations'] as List).map((e) => Station.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> hivemapperCheck(double lat, double lon) =>
      _get('/api/hivemapper/check', {'lat': '$lat', 'lon': '$lon'});

  Future<Station> report({
    required double lat,
    required double lon,
    double? petrol,
    double? diesel,
    int? stationId,
    String? stationName,
  }) async {
    if (baseUrl.isEmpty) throw ApiException('Set the server address in Settings first.');
    final http.Response r;
    try {
      r = await http
          .post(
            _u('/api/reports'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'lat': lat,
              'lon': lon,
              if (petrol != null) 'petrol': petrol,
              if (diesel != null) 'diesel': diesel,
              if (stationId != null) 'station_id': stationId,
              if (stationName != null && stationName.isNotEmpty) 'station_name': stationName,
              'source': 'photo',
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ApiException('Can\'t reach the server at $baseUrl.');
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) throw ApiException((body['error'] ?? 'Server error ${r.statusCode}').toString());
    return Station.fromJson(body);
  }
}
