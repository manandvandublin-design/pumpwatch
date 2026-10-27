import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_uvc_camera/flutter_uvc_camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ocr.dart';
import '../state.dart';
import 'stations.dart';

/// One price read by the dashcam during this session.
class DashPrice {
  final DateTime time;
  final String station;
  final double? petrol;
  final double? diesel;
  String status; // uploaded | waiting | skipped
  DashPrice(this.time, this.station, this.petrol, this.diesel, this.status);
}

class Clip {
  final File file;
  final bool saved;
  final DateTime time;
  final int bytes;
  Clip(this.file, this.saved, this.time, this.bytes);
}

/// Records loop video from the car camera and reads price signs when the van
/// passes a filling station. Prices are saved to Firebase as source "dashcam".
class DashcamController extends ChangeNotifier {
  // ---- settings (saved on the radio) ----
  int clipMinutes = 3;
  int storageLimitGb = 16;
  bool readPrices = true;
  bool recordSound = false;
  String? cameraName;
  /// Camera driver: auto | android | usb
  String driver = 'auto';
  /// USB picture format: 1 = MJPEG (default), 0 = YUV (try if the picture is black)
  int usbFormat = 1;
  /// Off = read prices only (for dashcams that record to their own memory card).
  bool recordVideo = true;

  // ---- live state ----
  /// Direct USB (UVC) camera, used when the radio hides the dashcam from normal apps.
  UVCCameraController? uvc;
  bool usbMode = false, usbOpened = false;
  String? usbMessage;
  bool _autoUsbFailed = false;
  bool _cameraPermissionChecked = false;
  Future<String?>? _uvcRec;
  Timer? _usbWatchdog;
  List<CameraDescription> cameras = [];
  CameraController? camera;
  bool recording = false;
  String? problem;
  String? note;
  DateTime? recordingSince;
  double lat = dublinLat, lon = dublinLon, speedKmh = 0;
  bool haveFix = false;
  (KnownStation, double)? near;
  bool readingNow = false;
  DashPrice? lastSaved;
  final List<DashPrice> today = [];
  int skipped = 0;

  late SharedPreferences _prefs;
  StationIndex stations = StationIndex(const []);
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  StreamSubscription<Position>? _gps;
  Timer? _clipTimer, _retryTimer;
  bool _busy = false, _starting = false, _rotating = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  String? _visitKey;
  final List<ReadPrices> _visitReads = [];
  final Map<String, DateTime> _doneAt = {};
  final List<Map<String, dynamic>> _pending = [];
  Directory? _loopDir, _savedDir;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    clipMinutes = _prefs.getInt('dc_clipMinutes') ?? 3;
    storageLimitGb = _prefs.getInt('dc_storageGb') ?? 16;
    readPrices = _prefs.getBool('dc_readPrices') ?? true;
    recordSound = _prefs.getBool('dc_sound') ?? false;
    cameraName = _prefs.getString('dc_camera');
    driver = _prefs.getString('dc_driver') ?? 'auto';
    usbFormat = _prefs.getInt('dc_usbFormat') ?? 1;
    recordVideo = _prefs.getBool('dc_record') ?? true;
    try {
      final p = _prefs.getString('dc_pending');
      if (p != null) _pending.addAll((jsonDecode(p) as List).cast<Map<String, dynamic>>());
    } catch (_) {}
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    _loopDir = Directory('${base.path}/PumpWatchDVR/loop')..createSync(recursive: true);
    _savedDir = Directory('${base.path}/PumpWatchDVR/saved')..createSync(recursive: true);
    stations = await StationIndex.load();
    _retryTimer = Timer.periodic(const Duration(seconds: 60), (_) => _flushPending());
  }

  Future<void> saveSettings() async {
    await _prefs.setInt('dc_clipMinutes', clipMinutes);
    await _prefs.setInt('dc_storageGb', storageLimitGb);
    await _prefs.setBool('dc_readPrices', readPrices);
    await _prefs.setBool('dc_sound', recordSound);
    if (cameraName != null) await _prefs.setString('dc_camera', cameraName!);
    await _prefs.setString('dc_driver', driver);
    await _prefs.setInt('dc_usbFormat', usbFormat);
    await _prefs.setBool('dc_record', recordVideo);
    notifyListeners();
  }

  String get folderPath => _loopDir?.parent.path ?? '';

  // ---------------- camera ----------------

  Future<void> setDriver(String d) async {
    driver = d;
    _autoUsbFailed = false;
    await saveSettings();
    await stop();
    await start();
  }

  Future<void> start() async {
    if (_starting || camera != null || uvc != null) return;
    _starting = true;
    problem = null;
    notifyListeners();
    try {
      cameras = await availableCameras();
    } catch (e) {
      cameras = [];
    }
    // Android 10 only lets an app open a USB camera if it also holds the Camera
    // permission. Opening any built-in camera for a moment makes Android ask for it.
    if (!_cameraPermissionChecked && cameras.isNotEmpty) {
      _cameraPermissionChecked = true;
      final probe = CameraController(cameras.first, ResolutionPreset.low, enableAudio: recordSound);
      try {
        await probe.initialize();
      } catch (e) {
        if (e.toString().toLowerCase().contains('access')) {
          problem = 'Camera permission is off. Allow it in Settings > Apps > PumpWatch > Permissions, then tap Retry.';
          _cameraPermissionChecked = false;
          await probe.dispose();
          _starting = false;
          notifyListeners();
          return;
        }
      }
      await probe.dispose();
    }
    final hasExternal = cameras.any((c) => c.lensDirection == CameraLensDirection.external);
    if (driver == 'usb' || (driver == 'auto' && !hasExternal && !_autoUsbFailed)) {
      _startUsb();
      _starting = false;
      return;
    }
    if (cameras.isEmpty) {
      problem = 'No camera found. Check the USB dashcam is plugged in, then tap Retry.';
      _starting = false;
      notifyListeners();
      return;
    }
    CameraDescription pick = cameras.first;
    final saved = cameras.where((c) => c.name == cameraName);
    final external = cameras.where((c) => c.lensDirection == CameraLensDirection.external);
    final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
    if (saved.isNotEmpty) {
      pick = saved.first;
    } else if (external.isNotEmpty) {
      pick = external.first;
    } else if (back.isNotEmpty) {
      pick = back.first;
    }
    cameraName = pick.name;

    final c = CameraController(
      pick,
      ResolutionPreset.veryHigh, // 1080p
      enableAudio: recordSound,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    try {
      await c.initialize();
    } catch (e) {
      problem = 'Could not open the camera ($e). Close any other dashcam app and tap Retry.';
      await c.dispose();
      _starting = false;
      notifyListeners();
      return;
    }
    camera = c;
    _startGps();
    await _beginClip();
    _starting = false;
    notifyListeners();
  }

  // ---------------- direct USB (UVC) driver ----------------

  void _startUsb() {
    usbMode = true;
    usbOpened = false;
    usbMessage = null;
    final u = UVCCameraController();
    u.cameraStateCallback = (state) {
      _log('State: ${state.name}');
      if (state == UVCCameraState.opened) {
        _onUsbOpened();
      } else if (state == UVCCameraState.error) {
        _usbFailed(u.getCameraErrorMsg);
      }
    };
    u.msgCallback = (m) {
      usbMessage = m;
      _log(m);
      notifyListeners();
    };
    uvc = u;
    _startGps();
    // The screen shows the USB camera view, which opens the camera. If nothing
    // happens in 15 seconds, the USB camera isn't there (or wasn't allowed).
    _usbWatchdog?.cancel();
    _usbWatchdog = Timer(const Duration(seconds: 40), () {
      if (!usbOpened) _usbFailed('The USB camera did not open. Allow USB access if the radio asked.');
    });
    notifyListeners();
  }

  /// Last USB camera messages, newest first (shown in Dashcam settings).
  final List<String> usbLog = [];
  void _log(String m) {
    final t = DateTime.now();
    usbLog.insert(0, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}  $m');
    if (usbLog.length > 15) usbLog.removeLast();
  }

  void _onUsbOpened() {
    if (usbOpened) return;
    usbOpened = true;
    _usbWatchdog?.cancel();
    problem = null;
    _beginUsbClip();
  }

  int _usbRetries = 0;

  Future<void> _usbFailed(String why) async {
    _usbWatchdog?.cancel();
    _log('Failed: $why');
    // The USB library reports "Permission denied" while Android is still showing the
    // Camera/Storage permission box. Give the driver time to tap Allow, then try again.
    if (why.toLowerCase().contains('permission') && _usbRetries < 6) {
      _usbRetries++;
      usbMessage = 'Waiting for permission… tap Allow if asked (try $_usbRetries of 6)';
      notifyListeners();
      await _closeUsb();
      usbMode = true; // keep showing the USB status while we wait
      notifyListeners();
      await Future.delayed(const Duration(seconds: 5));
      _startUsb();
      return;
    }
    _usbRetries = 0;
    final noDevice = why.toLowerCase().contains('no device') || why.toLowerCase().contains('did not open');
    if (driver == 'auto' && noDevice) {
      // Auto: no USB camera, so fall back to the normal Android camera.
      _autoUsbFailed = true;
      await _closeUsb();
      await start();
      return;
    }
    usbMessage = why;
    problem = 'USB camera: $why\nTry: unplug and replug the dashcam, then tap Retry. If the picture stays black, set USB picture format to YUV.';
    notifyListeners();
  }

  void _beginUsbClip() {
    final u = uvc;
    if (u == null) return;
    _photoTimer?.cancel();
    if (recordVideo) {
      _uvcRec = u.captureVideo().catchError((_) => null);
      recording = true;
    } else {
      _uvcRec = null;
      recording = false;
    }
    readMode = 'photo';
    note = null;
    recordingSince = DateTime.now();
    _photoTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _photoTick());
    _clipTimer?.cancel();
    _clipTimer = Timer(Duration(minutes: clipMinutes), () => rotate());
    notifyListeners();
  }

  /// Stops the USB recording and returns the saved file path.
  Future<String?> _stopUsbClip() async {
    final u = uvc, f = _uvcRec;
    if (u == null || f == null || !recording) return null;
    // A second captureVideo() call stops recording; the first call's result is the file.
    unawaited(u.captureVideo().catchError((_) => null));
    recording = false;
    try {
      return await f.timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  Future<void> _closeUsb() async {
    _photoTimer?.cancel();
    _clipTimer?.cancel();
    final path = await _stopUsbClip();
    if (path != null) await _storePath(path, save: false);
    try {
      uvc?.closeCamera();
      uvc?.dispose();
    } catch (_) {}
    uvc = null;
    usbMode = false;
    usbOpened = false;
    _uvcRec = null;
    notifyListeners();
  }

  /// How frames reach the price reader on this camera.
  String readMode = 'stream'; // stream | photo | streamOnly
  Timer? _photoTimer;

  Future<void> _beginClip() async {
    final c = camera;
    if (c == null) return;
    _photoTimer?.cancel();
    note = null;
    if (!recordVideo) {
      recording = false;
      readMode = 'streamOnly';
      try {
        if (!c.value.isStreamingImages) await c.startImageStream(_onFrame);
      } catch (_) {}
      notifyListeners();
      return;
    }
    // 1) Record and stream frames together (best).
    try {
      await c.startVideoRecording(onAvailable: _onFrame);
      recording = true;
      readMode = 'stream';
    } catch (e1) {
      // 2) Many phones/radios can't do both: record, and read prices from still photos.
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      try {
        await c.startVideoRecording();
        recording = true;
        readMode = 'photo';
        _photoTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _photoTick());
      } catch (e2) {
        // 3) Recording not possible at all: at least keep reading prices.
        recording = false;
        readMode = 'streamOnly';
        note = 'Recording failed on this camera: $e2';
        try {
          if (!c.value.isStreamingImages) await c.startImageStream(_onFrame);
        } catch (_) {}
      }
    }
    recordingSince = DateTime.now();
    _clipTimer?.cancel();
    _clipTimer = Timer(Duration(minutes: clipMinutes), () => rotate());
    notifyListeners();
  }

  Future<void> _photoTick() async {
    if (_busy || _rotating || !_shouldRead) return;
    final c = camera, u = uvc;
    if (c == null && u == null) return;
    if (c != null && c.value.isTakingPicture) return;
    _busy = true;
    readingNow = true;
    notifyListeners();
    try {
      final String? path = c != null ? (await c.takePicture()).path : await u!.takePicture();
      if (path == null) throw Exception('no photo');
      await _readInput(InputImage.fromFilePath(path));
      try {
        await File(path).delete();
      } catch (_) {}
    } catch (_) {
      readingNow = false;
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  /// Ends the current clip and starts a new one. With [save], the clip is kept
  /// in the "saved" folder so loop recording never deletes it.
  Future<void> rotate({bool save = false}) async {
    if (usbMode) {
      if (uvc == null || _rotating) return;
      _rotating = true;
      final path = await _stopUsbClip();
      if (path != null) await _storePath(path, save: save);
      await Future.delayed(const Duration(milliseconds: 500));
      _beginUsbClip();
      _rotating = false;
      _trimStorage();
      return;
    }
    final c = camera;
    if (c == null || _rotating) return;
    _rotating = true;
    try {
      if (recording && c.value.isRecordingVideo) {
        final x = await c.stopVideoRecording();
        await _store(x, save: save);
      }
    } catch (_) {}
    recording = false;
    await _beginClip();
    _rotating = false;
    _trimStorage();
  }

  Future<void> _store(XFile x, {required bool save}) => _storePath(x.path, save: save);

  Future<void> _storePath(String path, {required bool save}) async {
    final dir = save ? _savedDir! : _loopDir!;
    final t = recordingSince ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}.mp4';
    final src = File(path);
    try {
      await src.copy('${dir.path}/$name');
      await src.delete();
    } catch (_) {}
  }

  void _trimStorage() {
    final dir = _loopDir;
    if (dir == null) return;
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    var total = files.fold<int>(0, (s, f) => s + f.lengthSync());
    final limit = storageLimitGb * 1024 * 1024 * 1024;
    while (total > limit && files.isNotEmpty) {
      final f = files.removeAt(0);
      total -= f.lengthSync();
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  List<Clip> clips() {
    final out = <Clip>[];
    for (final (dir, saved) in [(_savedDir, true), (_loopDir, false)]) {
      if (dir == null || !dir.existsSync()) continue;
      for (final f in dir.listSync().whereType<File>()) {
        final st = f.statSync();
        out.add(Clip(f, saved, st.modified, st.size));
      }
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  (int used, int free) storage() {
    var used = 0;
    for (final c in clips()) {
      used += c.bytes;
    }
    return (used, storageLimitGb * 1024 * 1024 * 1024);
  }

  Future<void> switchCamera(String name) async {
    cameraName = name;
    await saveSettings();
    await stop();
    await start();
  }

  Future<void> stop() async {
    _usbWatchdog?.cancel();
    if (usbMode) {
      await _gps?.cancel();
      _gps = null;
      await _closeUsb();
      return;
    }
    _clipTimer?.cancel();
    _photoTimer?.cancel();
    await _gps?.cancel();
    _gps = null;
    final c = camera;
    camera = null;
    if (c != null) {
      try {
        if (c.value.isRecordingVideo) {
          final x = await c.stopVideoRecording();
          await _store(x, save: false);
        } else if (c.value.isStreamingImages) {
          await c.stopImageStream();
        }
      } catch (_) {}
      await c.dispose();
    }
    recording = false;
    notifyListeners();
  }

  // ---------------- GPS ----------------

  void _startGps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        note = 'Location is off, so prices can\'t be matched to stations.';
        notifyListeners();
        return;
      }
    } catch (_) {}
    _gps = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((p) {
      lat = p.latitude;
      lon = p.longitude;
      speedKmh = (p.speed.isNaN || p.speed < 0) ? 0 : p.speed * 3.6;
      haveFix = true;
      near = stations.all.isEmpty ? null : stations.nearest(lat, lon);
      final key = near == null ? null : '${near!.$1.lat},${near!.$1.lon}';
      if (key != _visitKey) {
        _visitKey = key;
        _visitReads.clear();
      }
      notifyListeners();
    });
  }

  // ---------------- price reading ----------------

  bool get _shouldRead {
    if (!readPrices || !haveFix || speedKmh > 90) return false;
    if (stations.all.isEmpty) return speedKmh < 40; // no station list: read when slow
    final n = near;
    if (n == null) return false;
    final done = _doneAt['${n.$1.lat},${n.$1.lon}'];
    return done == null || DateTime.now().difference(done).inMinutes > 30;
  }

  void _onFrame(CameraImage img) {
    final now = DateTime.now();
    if (_busy || now.difference(_lastFrame).inMilliseconds < 700 || !_shouldRead) return;
    _lastFrame = now;
    _busy = true;
    if (!readingNow) {
      readingNow = true;
      notifyListeners();
    }
    _read(img).whenComplete(() => _busy = false);
  }

  Future<void> _read(CameraImage img) async {
    final input = _toInputImage(img);
    if (input == null) {
      readingNow = false;
      return;
    }
    await _readInput(input);
  }

  Future<void> _readInput(InputImage input) async {
    try {
      final result = await _recognizer.processImage(input);
      final lines = <String>[for (final b in result.blocks) for (final l in b.lines) l.text];
      final r = parsePriceLines(lines);
      if (r.petrol == null && r.diesel == null) return;
      _visitReads.add(r);
      final agreed = _agreement();
      if (agreed != null) await _savePrice(agreed);
    } catch (_) {
    } finally {
      readingNow = false;
      notifyListeners();
    }
  }

  /// Two readings with the same numbers = a trustworthy price.
  ReadPrices? _agreement() {
    for (var i = 0; i < _visitReads.length; i++) {
      for (var j = i + 1; j < _visitReads.length; j++) {
        final a = _visitReads[i], b = _visitReads[j];
        if (a.petrol == b.petrol && a.diesel == b.diesel && (a.petrol != null || a.diesel != null)) return a;
      }
    }
    return null;
  }

  Future<void> _savePrice(ReadPrices r) async {
    final n = near;
    final name = n?.$1.name ?? 'Station near ${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
    final sLat = n?.$1.lat ?? lat, sLon = n?.$1.lon ?? lon;
    _doneAt[n == null ? '$lat,$lon' : '${n.$1.lat},${n.$1.lon}'] = DateTime.now();
    _visitReads.clear();
    final entry = DashPrice(DateTime.now(), name, r.petrol, r.diesel, 'waiting');
    today.insert(0, entry);
    lastSaved = entry;
    notifyListeners();
    final job = {'lat': sLat, 'lon': sLon, 'petrol': r.petrol, 'diesel': r.diesel, 'name': name};
    if (await _upload(job)) {
      entry.status = 'uploaded';
    } else {
      _pending.add(job);
      await _prefs.setString('dc_pending', jsonEncode(_pending));
    }
    notifyListeners();
  }

  Future<bool> _upload(Map<String, dynamic> j) async {
    try {
      await app.api.report(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        petrol: (j['petrol'] as num?)?.toDouble(),
        diesel: (j['diesel'] as num?)?.toDouble(),
        stationName: j['name'] as String?,
        source: 'dashcam',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _flushPending() async {
    if (_pending.isEmpty) return;
    final done = <Map<String, dynamic>>[];
    for (final j in List.of(_pending)) {
      if (await _upload(j)) {
        done.add(j);
        for (final e in today) {
          if (e.station == j['name'] && e.status == 'waiting') e.status = 'uploaded';
        }
      }
    }
    _pending.removeWhere(done.contains);
    await _prefs.setString('dc_pending', jsonEncode(_pending));
    notifyListeners();
  }

  int get waiting => _pending.length;

  InputImage? _toInputImage(CameraImage img) {
    final c = camera;
    if (c == null || img.planes.isEmpty) return null;
    final Uint8List bytes;
    if (img.planes.length == 1) {
      bytes = img.planes.first.bytes;
    } else {
      final b = WriteBuffer();
      for (final p in img.planes) {
        b.putUint8List(p.bytes);
      }
      bytes = b.done().buffer.asUint8List();
    }
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(img.width.toDouble(), img.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(c.description.sensorOrientation) ??
            InputImageRotation.rotation0deg,
        format: InputImageFormatValue.fromRawValue(img.format.raw as int) ?? InputImageFormat.nv21,
        bytesPerRow: img.planes.first.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _clipTimer?.cancel();
    _photoTimer?.cancel();
    _usbWatchdog?.cancel();
    _gps?.cancel();
    _recognizer.close();
    camera?.dispose();
    super.dispose();
  }

  static Future<void> landscape() =>
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  static Future<void> anyOrientation() => SystemChrome.setPreferredOrientations([]);
}
