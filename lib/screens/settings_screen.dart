import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state.dart';
import '../theme.dart';

/// True only in test APKs (built with --dart-define=PW_TEST=true), never in the Play Store bundle.
const isTestBuild = bool.fromEnvironment('PW_TEST');

const privacyUrl = 'https://viptech.app/privacy/pumpwatch';

/// Five well-spread points around Dublin for test data, clearly labelled TEST.
const _testStations = [
  ('TEST station – City Centre', 53.3498, -6.2603, 1.719, 1.689),
  ('TEST station – Rathmines', 53.3226, -6.2654, 1.749, 1.709),
  ('TEST station – Drumcondra', 53.3700, -6.2550, 1.769, 1.729),
  ('TEST station – Inchicore', 53.3402, -6.3150, 1.739, 1.699),
  ('TEST station – Clontarf', 53.3640, -6.2060, 1.789, 1.749),
];
const contactEmail = 'viptechviptech@gmail.com';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController alertCtl = TextEditingController(text: app.alertBelow.toStringAsFixed(3));
  bool seeding = false;
  String? seedMsg;

  Future<void> addTestPrices() async {
    setState(() {
      seeding = true;
      seedMsg = null;
    });
    var ok = 0;
    String? err;
    for (final t in _testStations) {
      try {
        await app.api.report(lat: t.$2, lon: t.$3, petrol: t.$4, diesel: t.$5, stationName: t.$1);
        ok++;
      } catch (e) {
        err = e.toString();
      }
    }
    await app.refresh();
    if (!mounted) return;
    setState(() {
      seeding = false;
      seedMsg = err == null ? 'Added $ok test stations around Dublin.' : 'Added $ok of 5. Problem: $err';
    });
  }

  @override
  void dispose() {
    alertCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const Text('Settings', style: titleStyle),
          const SizedBox(height: 16),
          const Text('PREFERENCES', style: capsStyle),
          const SizedBox(height: 8),
          Card2(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              Row(children: [
                const Expanded(child: Text('Default fuel', style: TextStyle(fontSize: 15))),
                FuelChips(value: app.fuel, onChanged: app.setFuel),
              ]),
              const Divider(height: 20),
              Row(children: [
                const Expanded(child: Text('Search radius', style: TextStyle(fontSize: 15))),
                Text('${app.radiusKm.round()} km', style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
              Slider(
                value: app.radiusKm,
                min: 1,
                max: 30,
                divisions: 29,
                activeColor: ink,
                label: '${app.radiusKm.round()} km',
                onChanged: (v) {
                  app.radiusKm = v;
                  app.save();
                },
                onChangeEnd: (_) => app.refresh(),
              ),
              const Divider(height: 8),
              Row(children: [
                const Expanded(child: Text('Hide prices older than', style: TextStyle(fontSize: 15))),
                DropdownButton<int>(
                  value: app.maxAgeDays,
                  underline: const SizedBox(),
                  items: const [1, 3, 7, 14, 30]
                      .map((d) => DropdownMenuItem(value: d, child: Text(d == 1 ? '1 day' : '$d days')))
                      .toList(),
                  onChanged: (d) {
                    app.maxAgeDays = d ?? 14;
                    app.save();
                  },
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          const Text('ALERTS', style: capsStyle),
          const SizedBox(height: 8),
          Card2(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show when a price is low'),
                value: app.alertOn,
                activeColor: cheap,
                onChanged: (v) {
                  app.alertOn = v;
                  app.save();
                },
              ),
              Row(children: [
                const Expanded(child: Text('Alert below', style: TextStyle(fontSize: 15))),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: alertCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(prefixText: '€ ', isDense: true),
                    onChanged: (v) {
                      final d = double.tryParse(v.replaceAll(',', '.'));
                      if (d != null && d > 0.5 && d < 4) {
                        app.alertBelow = d;
                        app.save();
                      }
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ]),
          ),
          if (isTestBuild) ...[
            const SizedBox(height: 16),
            const Text('TEST BUILD', style: capsStyle),
            const SizedBox(height: 8),
            Card2(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text(
                  'Adds 5 stations named "TEST station" around Dublin with sample prices, so you can try the map and lists. '
                  'This button is not in the Google Play version.',
                  style: TextStyle(color: muted, height: 1.4),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: seeding ? null : addTestPrices,
                  child: Text(seeding ? 'Adding…' : 'Add test prices'),
                ),
                if (seedMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(seedMsg!, style: const TextStyle(color: muted)),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 16),
          const Text('ABOUT', style: capsStyle),
          const SizedBox(height: 8),
          Card2(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Prices from drivers', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                'Prices come from photos drivers take in the app. The text on the sign is read on your phone; '
                'the photo itself is never uploaded. Always check the pump before filling up.',
                style: TextStyle(color: muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => launchUrl(Uri.parse(privacyUrl), mode: LaunchMode.externalApplication),
                child: const Text('Privacy policy'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => launchUrl(Uri.parse('mailto:$contactEmail?subject=PumpWatch')),
                child: const Text('Contact us'),
              ),
              const SizedBox(height: 8),
              const Text('PumpWatch by VIP Tech · version 1.0.0',
                  textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
        ],
      ),
    );
  }
}
