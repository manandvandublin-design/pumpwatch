import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../ocr.dart';
import '../state.dart';
import '../theme.dart';

class ReportScreen extends StatefulWidget {
  final Station? station;
  const ReportScreen({super.key, this.station});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final petrolCtl = TextEditingController();
  final dieselCtl = TextEditingController();
  final nameCtl = TextEditingController();
  String? photoPath;
  bool reading = false;
  bool sending = false;
  String? note;
  Station? station;

  @override
  void initState() {
    super.initState();
    station = widget.station;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await app.locate();
      if (station == null && mounted) setState(() => station = app.stationHere);
      takePhoto();
    });
  }

  @override
  void dispose() {
    petrolCtl.dispose();
    dieselCtl.dispose();
    nameCtl.dispose();
    super.dispose();
  }

  Future<void> takePhoto() async {
    final XFile? x;
    try {
      x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2000, imageQuality: 90);
    } catch (e) {
      setState(() => note = 'Could not open the camera: $e');
      return;
    }
    if (x == null) return;
    setState(() {
      photoPath = x!.path;
      reading = true;
      note = null;
    });
    try {
      final r = await readPricesFromPhoto(x.path);
      petrolCtl.text = r.petrol?.toStringAsFixed(3) ?? '';
      dieselCtl.text = r.diesel?.toStringAsFixed(3) ?? '';
      note = (r.petrol == null && r.diesel == null)
          ? 'Couldn\'t read a price. Type it in, or retake the photo closer to the sign.'
          : 'Check these match the sign, and fix them if not.';
    } catch (e) {
      note = 'Couldn\'t read the photo. Type the prices in.';
    }
    if (mounted) setState(() => reading = false);
  }

  double? _parse(String s) {
    final t = s.trim().replaceAll(',', '.').replaceAll('€', '');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return double.nan;
    return v >= 100 ? v / 100 : v; // allow cents like 171.9
  }

  Future<void> submit() async {
    final p = _parse(petrolCtl.text);
    final d = _parse(dieselCtl.text);
    if ((p?.isNaN ?? false) || (d?.isNaN ?? false)) {
      setState(() => note = 'Prices must be numbers, like 1.719');
      return;
    }
    if (p == null && d == null) {
      setState(() => note = 'Enter at least one price.');
      return;
    }
    setState(() => sending = true);
    try {
      final s = await app.api.report(
        lat: station?.lat ?? app.lat,
        lon: station?.lon ?? app.lon,
        petrol: p,
        diesel: d,
        stationId: station?.id,
        stationName: nameCtl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Thanks! Price saved for ${s.name}.')));
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        sending = false;
        note = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report a price', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF2B2D30), borderRadius: BorderRadius.circular(18)),
              clipBehavior: Clip.antiAlias,
              child: photoPath == null
                  ? Center(
                      child: TextButton.icon(
                        onPressed: takePhoto,
                        icon: const Icon(Icons.photo_camera_outlined, color: Colors.white),
                        label: const Text('Take a photo of the price sign', style: TextStyle(color: Colors.white)),
                      ),
                    )
                  : Stack(fit: StackFit.expand, children: [
                      Image.file(File(photoPath!), fit: BoxFit.cover),
                      if (reading)
                        Container(
                          color: const Color(0x88000000),
                          alignment: Alignment.center,
                          child: const Text('Reading prices…',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                    ]),
            ),
          ),
          const SizedBox(height: 16),
          Card2(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('PRICES (€ PER LITRE)', style: capsStyle),
              const SizedBox(height: 10),
              _priceField('Petrol', petrolCtl),
              const SizedBox(height: 10),
              _priceField('Diesel', dieselCtl),
              const SizedBox(height: 12),
              if (station != null)
                Row(children: [
                  const Expanded(child: Text('Station', style: TextStyle(color: muted))),
                  Flexible(
                      child: Text(station!.name,
                          textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
                ])
              else
                TextField(
                  controller: nameCtl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Station name (optional)',
                    helperText: 'New station here: it will be added at your location.',
                  ),
                ),
            ]),
          ),
          if (note != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: warnBg, borderRadius: BorderRadius.circular(12)),
              child: Text(note!, style: const TextStyle(color: warnInk)),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: sending ? null : takePhoto, child: const Text('Retake'))),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: sending || reading ? null : submit,
                child: Text(sending ? 'Saving…' : 'Submit price'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _priceField(String label, TextEditingController c) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        SizedBox(
          width: 130,
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(prefixText: '€ ', hintText: '1.719', isDense: true),
          ),
        ),
      ]);
}
