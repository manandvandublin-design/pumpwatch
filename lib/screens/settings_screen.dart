import 'package:flutter/material.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController serverCtl = TextEditingController(text: app.serverUrl);
  late final TextEditingController alertCtl = TextEditingController(text: app.alertBelow.toStringAsFixed(3));
  String? serverMsg;
  String? hiveMsg;
  bool testing = false;
  bool checkingHive = false;

  @override
  void dispose() {
    serverCtl.dispose();
    alertCtl.dispose();
    super.dispose();
  }

  Future<void> saveServer() async {
    var v = serverCtl.text.trim();
    if (v.isNotEmpty && !v.startsWith('http')) v = 'http://$v';
    if (v.isNotEmpty && !RegExp(r':\d+').hasMatch(v.replaceFirst(RegExp(r'^https?://'), ''))) v = '$v:8080';
    serverCtl.text = v;
    app.serverUrl = v;
    await app.save();
    setState(() {
      testing = true;
      serverMsg = null;
    });
    try {
      await Api(v).health();
      serverMsg = 'Connected to the server.';
      app.refresh();
    } catch (e) {
      serverMsg = e.toString();
    }
    if (mounted) setState(() => testing = false);
  }

  Future<void> checkHivemapper() async {
    setState(() {
      checkingHive = true;
      hiveMsg = null;
    });
    try {
      await app.locate();
      final r = await app.api.hivemapperCheck(app.lat, app.lon);
      final n = r['features'] ?? 0;
      final signs = r['price_signs'] ?? 0;
      hiveMsg = n == 0
          ? 'Hivemapper has no map data within 1.2 km of you yet.'
          : 'Hivemapper has $n road features near you, including $signs price signs.';
    } catch (e) {
      hiveMsg = e.toString();
    }
    if (mounted) setState(() => checkingHive = false);
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
          const Text('SERVER', style: capsStyle),
          const SizedBox(height: 8),
          Card2(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: serverCtl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Server address',
                  hintText: 'http://192.168.1.20:8080',
                  helperText: 'Shown when you start server.py on your PC',
                ),
                onSubmitted: (_) => saveServer(),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: testing ? null : saveServer,
                child: Text(testing ? 'Connecting…' : 'Save and test'),
              ),
              if (serverMsg != null) ...[
                const SizedBox(height: 8),
                Text(serverMsg!, style: const TextStyle(color: muted)),
              ],
            ]),
          ),
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
          const SizedBox(height: 16),
          const Text('DATA', style: capsStyle),
          const SizedBox(height: 8),
          Card2(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Powered by drivers + Hivemapper',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                'Prices come from photos drivers take in the app. The text on the sign is read on your phone. '
                'Hivemapper dashcam data will be added where it covers Ireland.',
                style: TextStyle(color: muted, height: 1.4),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: checkingHive ? null : checkHivemapper,
                child: Text(checkingHive ? 'Checking…' : 'Check Hivemapper coverage here'),
              ),
              if (hiveMsg != null) ...[
                const SizedBox(height: 8),
                Text(hiveMsg!, style: const TextStyle(color: muted)),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}
