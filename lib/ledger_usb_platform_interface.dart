import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ledger_usb/usb_device.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'ledger_usb_method_channel.dart';
import 'web_ledger_usb.dart';

abstract class LedgerUsbPlatform extends PlatformInterface {
  /// Constructs a LedgerUsbPlatform.
  LedgerUsbPlatform() : super(token: _token);

  static final Object _token = Object();

  static LedgerUsbPlatform _instance = kIsWeb ? WebLedgerUsb() : MethodChannelLedgerUsb();

  /// The default instance of [LedgerUsbPlatform] to use.
  ///
  /// Defaults to [MethodChannelLedgerUsb] or [WebLedgerUsb] if running on web.
  static LedgerUsbPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [LedgerUsbPlatform] when
  /// they register themselves.
  static set instance(LedgerUsbPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<List<UsbDevice>> getDevices();

  Future<bool> requestPermission(UsbDevice usbDevice);

  Future<bool> open(UsbDevice usbDevice);

  Future<Uint8List?> transferIn(int packetSize, int timeout);

  Future<int> transferOut(Uint8List data, int timeout);

  Future<bool> close();
}
