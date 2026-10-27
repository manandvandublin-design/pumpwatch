import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../state.dart';
import 'dashcam_controller.dart';

const _bg = Color(0xFF0E0F10);
const _panel = Color(0xFF17191B);
const _card = Color(0xFF24272A);
const _muted = Color(0xFFB9B5AE);
const _amber = Color(0xFFE8A33D);
const _green = Color(0xFF1E7A4C);
const _red = Color(0xFFE5484D);

String _p(double? v) => v == null ? '—' : euro(v);
String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
String _dur(Duration d) =>
    '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
String _gb(int bytes) => (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);

/// Car radio screen: records loop video and reads petrol prices while driving.
class DashcamScreen extends StatefulWidget {
  const DashcamScreen({super.key});
  @override
  State<DashcamScreen> createState() => _DashcamScreenState();
}

class _DashcamScreenState extends State<DashcamScreen> with WidgetsBindingObserver {
  final dc = DashcamController();
  bool ready = false;
  DashPrice? shown;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DashcamController.landscape();
    WakelockPlus.enable();
    dc.addListener(_onChange);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    () async {
      await dc.init();
      if (!mounted) return;
      setState(() => ready = true);
      await dc.start();
    }();
  }

  void _onChange() {
    if (!mounted) return;
    if (dc.lastSaved != null && dc.lastSaved != shown) {
      shown = dc.lastSaved;
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted && shown == dc.lastSaved) setState(() => shown = null);
      });
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) dc.stop();
    if (s == AppLifecycleState.resumed && ready) dc.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    dc.removeListener(_onChange);
    dc.stop().whenComplete(dc.dispose);
    WakelockPlus.disable();
    DashcamController.anyOrientation();
    super.dispose();
  }

  void _open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final c = dc.camera;
    final (used, limit) = ready ? dc.storage() : (0, 1);
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Row(children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              Container(color: const Color(0xFF2A2D30)),
              if (c != null && c.value.isInitialized)
                Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: CameraPreview(c)))
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(dc.problem ?? 'Starting camera…',
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18)),
                      if (dc.problem != null) ...[
                        const SizedBox(height: 16),
                        FilledButton(onPressed: dc.start, child: const Text('Retry')),
                      ],
                    ]),
                  ),
                ),
              Positioned(
                left: 16,
                top: 16,
                child: Row(children: [
                  _chip(Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: dc.recording ? _red : _muted, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(
                      dc.recording && dc.recordingSince != null
                          ? 'REC ${_dur(DateTime.now().difference(dc.recordingSince!))}'
                          : 'Not recording',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ])),
                  const SizedBox(width: 8),
                  _chip(Text('${dc.speedKmh.round()} km/h', style: const TextStyle(color: Colors.white, fontSize: 15))),
                ]),
              ),
              if (dc.readingNow || dc.near != null)
                Positioned(
                  right: 16,
                  top: 16,
                  child: _chip(
                    Text(
                      dc.readingNow ? 'Reading price sign…' : 'Near ${dc.near!.$1.name}',
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    color: dc.readingNow ? _amber.withValues(alpha: 0.9) : null,
                  ),
                ),
              if (dc.note != null)
                Positioned(
                  left: 16,
                  top: 64,
                  right: 16,
                  child: _chip(Text(dc.note!, style: const TextStyle(color: Colors.white, fontSize: 14))),
                ),
              if (shown != null)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      const Text('PRICE SAVED',
                          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(shown!.station,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                      Text('Petrol ${_p(shown!.petrol)} · Diesel ${_p(shown!.diesel)}',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
            ]),
          ),
          Container(
            width: 260,
            color: _panel,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(
                    child: Text('PumpWatch',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
                IconButton(
                  tooltip: 'Exit dashcam mode',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ]),
              const SizedBox(height: 8),
              _box([
                const Text('Prices today', style: TextStyle(color: _muted, fontSize: 13)),
                Text('${dc.today.length}',
                    style: const TextStyle(color: _amber, fontSize: 34, fontWeight: FontWeight.w800)),
                Text(dc.waiting == 0 ? 'All uploaded' : '${dc.waiting} waiting to upload',
                    style: const TextStyle(color: _muted, fontSize: 13)),
              ]),
              const SizedBox(height: 10),
              _box([
                const Text('Storage', style: TextStyle(color: _muted, fontSize: 13)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (used / limit).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: const Color(0xFF3A3F44),
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text('${_gb(used)} GB of ${dc.storageLimitGb} GB · loop on',
                    style: const TextStyle(color: _muted, fontSize: 13)),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _red),
                  onPressed: dc.recording
                      ? () async {
                          await dc.rotate(save: true);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(content: Text('Clip saved. It won\'t be overwritten.')));
                          }
                        }
                      : null,
                  child: const Text('Save this clip', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                _nav('Clips', () => _open(_ClipsPage(dc))),
                const SizedBox(width: 8),
                _nav('Prices', () => _open(_PricesPage(dc))),
                const SizedBox(width: 8),
                _nav('Settings', () => _open(_SettingsPage(dc))),
              ]),
            ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chip(Widget child, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: color ?? Colors.black54, borderRadius: BorderRadius.circular(20)),
        child: child,
      );

  Widget _box(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _nav(String label, VoidCallback onTap) => Expanded(
        child: SizedBox(
          height: 56,
          child: TextButton(
            style: TextButton.styleFrom(
              backgroundColor: _card,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onTap,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
        ),
      );
}

class _DarkPage extends StatelessWidget {
  final String title;
  final Widget body;
  const _DarkPage(this.title, this.body);
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: SafeArea(child: body),
      );
}

class _ClipsPage extends StatefulWidget {
  final DashcamController dc;
  const _ClipsPage(this.dc);
  @override
  State<_ClipsPage> createState() => _ClipsPageState();
}

class _ClipsPageState extends State<_ClipsPage> {
  @override
  Widget build(BuildContext context) {
    final clips = widget.dc.clips();
    return _DarkPage(
      'Recordings',
      Column(children: [
        Expanded(
          child: clips.isEmpty
              ? const Center(child: Text('No clips yet.', style: TextStyle(color: _muted)))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 2.2),
                  itemCount: clips.length,
                  itemBuilder: (_, i) {
                    final c = clips[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(_hm(c.time),
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          if (c.saved)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(6)),
                              child: const Text('SAVED',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                        ]),
                        const Spacer(),
                        Text('${c.time.day}/${c.time.month} · ${(c.bytes / (1024 * 1024)).round()} MB',
                            style: const TextStyle(color: _muted, fontSize: 13)),
                      ]),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            'Videos are in: ${widget.dc.folderPath}\nOldest unsaved clips are replaced automatically.',
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ),
      ]),
    );
  }
}

class _PricesPage extends StatelessWidget {
  final DashcamController dc;
  const _PricesPage(this.dc);
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dc,
      builder: (context, _) => _DarkPage(
        'Prices collected today',
        dc.today.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No prices read yet. Drive past a filling station with the sign in view.',
                      textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 16)),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: dc.today.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final e = dc.today[i];
                  final (label, color) = switch (e.status) {
                    'uploaded' => ('Uploaded', const Color(0xFF7FD1A4)),
                    'waiting' => ('Waiting for internet', _amber),
                    _ => ('Skipped', _muted),
                  };
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      SizedBox(width: 70, child: Text(_hm(e.time), style: const TextStyle(color: _muted))),
                      Expanded(
                          child: Text(e.station,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
                      SizedBox(
                          width: 130,
                          child: Text('P ${_p(e.petrol)}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                      SizedBox(
                          width: 130,
                          child: Text('D ${_p(e.diesel)}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                      SizedBox(width: 170, child: Text(label, style: TextStyle(color: color))),
                    ]),
                  );
                },
              ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  final DashcamController dc;
  const _SettingsPage(this.dc);
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dc,
      builder: (context, _) {
        Widget section(String title, List<Widget> rows) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: _muted, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
                child: Column(children: rows),
              ),
            ]);
        Widget sw(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
              title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 17)),
              value: value,
              activeColor: _green,
              onChanged: onChanged,
            );
        Widget choice(String label, List<int> options, int value, String unit, ValueChanged<int> onChanged) => ListTile(
              title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 17)),
              trailing: Wrap(spacing: 6, children: [
                for (final o in options)
                  ChoiceChip(
                    label: Text('$o $unit'),
                    selected: value == o,
                    onSelected: (_) => onChanged(o),
                  ),
              ]),
            );
        return _DarkPage(
          'Dashcam settings',
          ListView(padding: const EdgeInsets.all(16), children: [
            section('RECORDING', [
              choice('Clip length', const [1, 3, 5], dc.clipMinutes, 'min', (v) {
                dc.clipMinutes = v;
                dc.saveSettings();
              }),
              choice('Storage limit', const [8, 16, 32, 48], dc.storageLimitGb, 'GB', (v) {
                dc.storageLimitGb = v;
                dc.saveSettings();
              }),
              sw('Record sound (applies next start)', dc.recordSound, (v) {
                dc.recordSound = v;
                dc.saveSettings();
              }),
            ]),
            const SizedBox(height: 16),
            section('PETROL PRICES', [
              sw('Read price signs while driving', dc.readPrices, (v) {
                dc.readPrices = v;
                dc.saveSettings();
              }),
              ListTile(
                title: const Text('Stations on file', style: TextStyle(color: Colors.white, fontSize: 17)),
                trailing: Text('${dc.stations.all.length}', style: const TextStyle(color: _muted, fontSize: 17)),
              ),
            ]),
            const SizedBox(height: 16),
            section('CAMERA', [
              for (final cam in dc.cameras)
                RadioListTile<String>(
                  value: cam.name,
                  groupValue: dc.cameraName,
                  activeColor: _green,
                  onChanged: (v) => v == null ? null : dc.switchCamera(v),
                  title: Text('Camera ${cam.name}', style: const TextStyle(color: Colors.white)),
                  subtitle: Text(_dir(cam.lensDirection), style: const TextStyle(color: _muted)),
                ),
              if (dc.cameras.isEmpty)
                const ListTile(title: Text('No cameras found', style: TextStyle(color: _muted))),
            ]),
            const SizedBox(height: 12),
            const Text(
              'Only prices are uploaded: station, petrol, diesel and time. Video stays on the radio.',
              style: TextStyle(color: _muted),
            ),
          ]),
        );
      },
    );
  }

  static String _dir(CameraLensDirection d) => switch (d) {
        CameraLensDirection.external => 'USB / external camera',
        CameraLensDirection.back => 'Built-in (back)',
        CameraLensDirection.front => 'Built-in (front)',
      };
}
