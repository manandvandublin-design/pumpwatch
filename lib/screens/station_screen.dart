import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import 'report_screen.dart';

class StationScreen extends StatelessWidget {
  final Station station;
  const StationScreen({super.key, required this.station});

  @override
  Widget build(BuildContext context) {
    final petrol = station.prices['petrol'];
    final diesel = station.prices['diesel'];
    final latest = [petrol, diesel].whereType<FuelPrice>().fold<FuelPrice?>(
        null, (a, b) => a == null || b.reportedAt.isAfter(a.reportedAt) ? b : a);

    Widget priceTile(String label, FuelPrice? p, bool highlight) => Expanded(
          child: Card2(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 13, color: muted)),
              const SizedBox(height: 4),
              Text(
                p == null ? '—' : euro(p.price),
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: highlight ? cheap : ink),
              ),
              if (p != null)
                Text(
                  p.ageDays > app.maxAgeDays ? 'old · ${ago(p.reportedAt)}' : ago(p.reportedAt),
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
            ]),
          ),
        );

    Widget row(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: Text(a, style: const TextStyle(color: muted))),
            Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: Text(station.name, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            priceTile('Petrol', petrol, app.fuel == 'petrol'),
            const SizedBox(width: 12),
            priceTile('Diesel', diesel, app.fuel == 'diesel'),
          ]),
          const SizedBox(height: 12),
          Card2(
            child: Column(children: [
              if (latest != null) row('Last updated', ago(latest.reportedAt)),
              if (latest != null) row('Source', sourceLabel(latest.source)),
              if (station.distanceKm != null) row('Distance', km(station.distanceKm)),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: warnBg, borderRadius: BorderRadius.circular(14)),
            child: const Text(
              'Prices are read from photos taken by drivers. They may be out of date, so check the pump before filling up.',
              style: TextStyle(color: warnInk, height: 1.4),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  await Navigator.push(
                      context, MaterialPageRoute(builder: (_) => ReportScreen(station: station)));
                  app.refresh();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Update price'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                      'https://www.google.com/maps/dir/?api=1&destination=${station.lat},${station.lon}'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Directions'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
