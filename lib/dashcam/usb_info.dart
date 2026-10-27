import 'package:flutter/services.dart';

class UsbInfo {
  final String name;
  final int vendorId, productId, deviceClass;
  final List<int> interfaceClasses;
  final String? product, maker;
  final bool hasPermission;
  UsbInfo(this.name, this.vendorId, this.productId, this.deviceClass, this.interfaceClasses, this.product, this.maker,
      this.hasPermission);

  /// USB class 14 = video (a standard UVC camera).
  bool get isCamera => interfaceClasses.contains(14) || deviceClass == 14;
  String get ids =>
      '${vendorId.toRadixString(16).padLeft(4, '0')}:${productId.toRadixString(16).padLeft(4, '0')}';
}

const _ch = MethodChannel('pumpwatch/usb');

Future<List<UsbInfo>> listUsb() async {
  try {
    final raw = await _ch.invokeMethod<List<dynamic>>('list') ?? [];
    return raw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return UsbInfo(
        m['name'] as String,
        m['vendorId'] as int,
        m['productId'] as int,
        m['deviceClass'] as int,
        (m['interfaceClasses'] as List).cast<int>(),
        m['product'] as String?,
        m['maker'] as String?,
        m['hasPermission'] as bool,
      );
    }).toList();
  } catch (_) {
    return [];
  }
}

Future<void> requestUsb(String name) async {
  try {
    await _ch.invokeMethod('request', {'name': name});
  } catch (_) {}
}
