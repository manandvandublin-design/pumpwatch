import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

const dublinLat = 53.3498;
const dublinLon = -6.2603;

class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;

  String fuel = 'petrol';
  double radiusKm = 5;
  int maxAgeDays = 14;
  bool alertOn = true;
  double alertBelow = 1.70;

  double lat = dublinLat;
  double lon = dublinLon;
  bool haveLocation = false;

  List<Station> stations = [];
  bool loading = false;
  String? error;

  final Api api = Api();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    fuel = _prefs.getString('fuel') ?? 'petrol';
    radiusKm = _prefs.getDouble('radiusKm') ?? 5;
    maxAgeDays = _prefs.getInt('maxAgeDays') ?? 14;
    alertOn = _prefs.getBool('alertOn') ?? true;
    alertBelow = _prefs.getDouble('alertBelow') ?? 1.70;
  }

  Future<void> save() async {
    await _prefs.setString('fuel', fuel);
    await _prefs.setDouble('radiusKm', radiusKm);
    await _prefs.setInt('maxAgeDays', maxAgeDays);
    await _prefs.setBool('alertOn', alertOn);
    await _prefs.setDouble('alertBelow', alertBelow);
    notifyListeners();
  }

  void setFuel(String f) {
    fuel = f;
    save();
  }

  Future<void> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      lat = p.latitude;
      lon = p.longitude;
      haveLocation = true;
    } catch (_) {
      // keep the last known position (Dublin by default)
    }
    notifyListeners();
  }

  Future<void> refresh({bool relocate = false}) async {
    if (relocate || !haveLocation) await locate();
    loading = true;
    error = null;
    notifyListeners();
    try {
      stations = await api.stations(lat, lon, radiusKm);
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  /// Stations with a current price for the selected fuel, cheapest first.
  List<Station> get priced {
    final list = stations.where((s) => s.priceFor(fuel, maxAgeDays) != null).toList();
    list.sort((a, b) => a.priceFor(fuel, maxAgeDays)!.price.compareTo(b.priceFor(fuel, maxAgeDays)!.price));
    return list;
  }

  Station? get cheapest => priced.isEmpty ? null : priced.first;

  bool get alertHit {
    final c = cheapest;
    return alertOn && c != null && c.priceFor(fuel, maxAgeDays)!.price < alertBelow;
  }

  /// A known station within 150 m of the phone, if any.
  Station? get stationHere {
    Station? best;
    for (final s in stations) {
      final d = Geolocator.distanceBetween(lat, lon, s.lat, s.lon);
      if (d <= 150 && (best == null || d < Geolocator.distanceBetween(lat, lon, best.lat, best.lon))) best = s;
    }
    return best;
  }
}

final app = AppState();

String euro(double v) => '€${v.toStringAsFixed(3)}';

String ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 2) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  final w = d.inDays ~/ 7;
  return w == 1 ? '1 week ago' : '$w weeks ago';
}

String sourceLabel(String s) => switch (s) {
      'hivemapper' => 'dashcam',
      'demo' => 'demo data',
      _ => 'driver photo',
    };

String km(double? d) => d == null ? '' : (d < 1 ? '${(d * 1000).round()} m' : '${d.toStringAsFixed(1)} km');
