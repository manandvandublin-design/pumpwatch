import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import 'report_screen.dart';
import 'station_screen.dart';

class MapScreen extends StatefulWidget {
  final VoidCallback onOpenSettings;
  const MapScreen({super.key, required this.onOpenSettings});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final map = MapController();
  bool _centredOnce = false;

  void openStation(Station s) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => StationScreen(station: s)));

  Future<void> openReport() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen()));
    app.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (app.haveLocation && !_centredOnce) {
          _centredOnce = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              map.move(LatLng(app.lat, app.lon), 14);
            } catch (_) {}
          });
        }
        final cheapest = app.cheapest;
        final markers = <Marker>[
          for (final s in app.stations) _priceMarker(s, s.id == cheapest?.id),
          Marker(
            point: LatLng(app.lat, app.lon),
            width: 24,
            height: 24,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2F6FDB),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ),
        ];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Expanded(child: Text('PumpWatch', style: titleStyle)),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () => app.refresh(),
                    icon: app.loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                FuelChips(value: app.fuel, onChanged: app.setFuel),
                const Spacer(),
                Text('Within ${app.radiusKm.round()} km', style: const TextStyle(color: muted)),
              ]),
            ),
            if (app.alertHit)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFDDEFE4), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    '${app.fuel == 'petrol' ? 'Petrol' : 'Diesel'} below ${euro(app.alertBelow)} nearby: ${cheapest!.name}',
                    style: const TextStyle(color: cheap, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: map,
                        options: MapOptions(initialCenter: LatLng(app.lat, app.lon), initialZoom: 13),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'app.viptech.pumpwatch',
                          ),
                          MarkerLayer(markers: markers),
                          const RichAttributionWidget(
                            attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                          ),
                        ],
                      ),
                      Positioned(
                        right: 12,
                        bottom: 40,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            FloatingActionButton.extended(
                              heroTag: 'report',
                              onPressed: openReport,
                              backgroundColor: amber,
                              foregroundColor: ink,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Report a price', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(height: 10),
                            FloatingActionButton.small(
                              heroTag: 'me',
                              tooltip: 'Centre on me',
                              backgroundColor: Colors.white,
                              foregroundColor: ink,
                              onPressed: () async {
                                await app.refresh(relocate: true);
                                map.move(LatLng(app.lat, app.lon), 14);
                              },
                              child: const Icon(Icons.my_location),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.all(12), child: _bottomCard(cheapest)),
          ],
        );
      },
    );
  }

  Marker _priceMarker(Station s, bool isCheapest) {
    final p = s.priceFor(app.fuel, app.maxAgeDays);
    return Marker(
      point: LatLng(s.lat, s.lon),
      width: 86,
      height: 36,
      child: GestureDetector(
        onTap: () => openStation(s),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isCheapest ? cheap : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isCheapest ? cheap : (p == null ? muted : line)),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Color(0x33000000), offset: Offset(0, 1))],
          ),
          child: Text(
            p == null ? 'No price' : euro(p.price),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: isCheapest ? Colors.white : (p == null ? muted : ink),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomCard(Station? cheapest) {
    if (app.error != null) {
      return Card2(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(app.error!, style: const TextStyle(color: muted)),
        ]),
      );
    }
    if (cheapest == null) {
      return const Card2(
        child: Text(
          'No prices reported near you yet. Be the first: tap "Report a price" at a filling station.',
          style: TextStyle(color: muted),
        ),
      );
    }
    final p = cheapest.priceFor(app.fuel, app.maxAgeDays)!;
    return Card2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('CHEAPEST NEAR YOU', style: capsStyle),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cheapest.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Text('${km(cheapest.distanceKm)} · ${sourceLabel(p.source)} · ${ago(p.reportedAt)}',
                  style: const TextStyle(fontSize: 13, color: muted)),
            ]),
          ),
          Text(euro(p.price), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cheap)),
        ]),
        const SizedBox(height: 10),
        FilledButton(onPressed: () => openStation(cheapest), child: const Text('View station')),
      ]),
    );
  }
}
