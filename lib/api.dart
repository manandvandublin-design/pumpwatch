import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firestore layout
///   stations/{id}  name, lat, lon, prices.{petrol|diesel}.{price, source, reportedAt}, updatedAt
///   reports/{id}   stationId, fuel, price, source, lat, lon, uid, reportedAt
/// Rules are in firestore.rules.

class FuelPrice {
  final double price;
  final String source;
  final DateTime reportedAt;

  FuelPrice(this.price, this.source, this.reportedAt);

  static FuelPrice? fromMap(Object? m) {
    if (m is! Map) return null;
    final p = m['price'];
    if (p is! num) return null;
    final t = m['reportedAt'];
    return FuelPrice(
      p.toDouble(),
      (m['source'] ?? 'photo').toString(),
      t is Timestamp ? t.toDate() : DateTime.now(),
    );
  }

  int get ageDays => DateTime.now().difference(reportedAt).inDays;
}

class Station {
  final String id;
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

  factory Station.fromDoc(DocumentSnapshot<Map<String, dynamic>> d, {double? fromLat, double? fromLon}) {
    final j = d.data() ?? {};
    final lat = (j['lat'] as num?)?.toDouble() ?? 0;
    final lon = (j['lon'] as num?)?.toDouble() ?? 0;
    final p = <String, FuelPrice>{};
    final raw = j['prices'];
    if (raw is Map) {
      for (final fuel in const ['petrol', 'diesel']) {
        final fp = FuelPrice.fromMap(raw[fuel]);
        if (fp != null) p[fuel] = fp;
      }
    }
    return Station(
      id: d.id,
      name: (j['name'] ?? 'Station').toString(),
      lat: lat,
      lon: lon,
      distanceKm: fromLat == null ? null : distanceM(fromLat, fromLon!, lat, lon) / 1000.0,
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

double distanceM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dp = rad(lat2 - lat1), dl = rad(lon2 - lon1);
  final a = math.pow(math.sin(dp / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dl / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _stations => _db.collection('stations');
  CollectionReference<Map<String, dynamic>> get _reports => _db.collection('reports');

  Future<String> _uid() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      try {
        await auth.signInAnonymously();
      } catch (_) {
        throw ApiException('Could not connect. Check your internet connection.');
      }
    }
    return auth.currentUser!.uid;
  }

  /// Stations within [radiusKm], nearest first. Uses one range query on latitude
  /// (no extra Firestore index needed) and filters longitude on the phone.
  Future<List<Station>> stations(double lat, double lon, double radiusKm) async {
    await _uid();
    final dLat = radiusKm / 111.0;
    try {
      final snap = await _stations
          .where('lat', isGreaterThanOrEqualTo: lat - dLat)
          .where('lat', isLessThanOrEqualTo: lat + dLat)
          .limit(500)
          .get()
          .timeout(const Duration(seconds: 20));
      final list = snap.docs
          .map((d) => Station.fromDoc(d, fromLat: lat, fromLon: lon))
          .where((s) => s.distanceKm! <= radiusKm)
          .toList()
        ..sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
      return list;
    } on FirebaseException catch (e) {
      throw ApiException('Could not load prices (${e.code}).');
    } catch (_) {
      throw ApiException('Could not load prices. Check your internet connection.');
    }
  }

  /// Saves a price report. Matches a known station within 150 m, or adds a new one.
  Future<Station> report({
    required double lat,
    required double lon,
    double? petrol,
    double? diesel,
    String? stationId,
    String? stationName,
    String source = 'photo',
  }) async {
    final uid = await _uid();
    if (source != 'photo' && source != 'dashcam') source = 'photo';
    for (final p in [petrol, diesel]) {
      if (p != null && (p < 0.5 || p > 4.0)) {
        throw ApiException('Prices must be in euro per litre, like 1.719');
      }
    }
    try {
      DocumentReference<Map<String, dynamic>>? ref = stationId == null ? null : _stations.doc(stationId);
      if (ref == null) {
        final near = await stations(lat, lon, 0.2);
        final close = near.where((s) => s.distanceKm! * 1000 <= 150).toList();
        if (close.isNotEmpty) ref = _stations.doc(close.first.id);
      }
      final batch = _db.batch();
      final now = FieldValue.serverTimestamp();
      final isNew = ref == null;
      ref ??= _stations.doc();
      final newPrices = <String, dynamic>{};
      final update = <String, dynamic>{'updatedAt': now};
      for (final e in {'petrol': petrol, 'diesel': diesel}.entries) {
        if (e.value == null) continue;
        final price = double.parse(e.value!.toStringAsFixed(3));
        final entry = {'price': price, 'source': source, 'reportedAt': now};
        newPrices[e.key] = entry;
        update['prices.${e.key}'] = entry;
        batch.set(_reports.doc(), {
          'stationId': ref.id,
          'fuel': e.key,
          'price': price,
          'source': source,
          'lat': lat,
          'lon': lon,
          'uid': uid,
          'reportedAt': now,
        });
      }
      if (isNew) {
        final name = (stationName ?? '').trim();
        batch.set(ref, {
          'name': name.isEmpty ? 'Station near ${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}' : name,
          'lat': lat,
          'lon': lon,
          'prices': newPrices,
          'createdBy': uid,
          'updatedAt': now,
        });
      } else {
        batch.update(ref, update);
      }
      await batch.commit().timeout(const Duration(seconds: 20));
      return Station.fromDoc(await ref.get(), fromLat: lat, fromLon: lon);
    } on FirebaseException catch (e) {
      throw ApiException('Could not save the price (${e.code}).');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Could not save the price. Check your internet connection.');
    }
  }
}
