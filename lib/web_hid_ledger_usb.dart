import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ledger_usb_plus/hid.web.dart';
import 'package:ledger_usb_plus/ledger_usb.dart';
import 'package:ledger_usb_plus/usb_device.dart';
import 'ledger_usb_platform_interface.dart';

const _ledgerVendorId = 11415;

/// Usage page of the Ledger APDU HID collection (the FIDO/U2F one is 0xf1d0).
const _ledgerUsagePage = 0xffa0;

/// Ledger HID reports are 64 bytes and carry no report id.
const _ledgerReportId = 0;

const _inputReportEvent = 'inputreport';
const _disconnectEvent = 'disconnect';

/// WebHID backend. Same 64-byte packets as the WebUSB backend: every
/// [transferOut] sends one output report, every [transferIn] returns one
/// input report.
///
/// HID devices have no serial number, so [UsbDevice.identifier] is built from
/// the product id and the position in the last [getDevices] result.
class WebHidLedgerUsb extends LedgerUsbPlatform {
  WebHidLedgerUsb(this._hid);

  final WebHID _hid;
  final Map<String, HIDDevice> _foundDevices = {};
  ({
    HIDDevice device,
    JSFunction onInputReport,
    JSFunction onDisconnect,
  })? _activeDevice;

  final Queue<Uint8List> _inputReports = Queue();
  Completer<Uint8List>? _pendingTransferIn;

  @override
  Future<List<UsbDevice>> getDevices() async {
    try {
      // Same policy as the WebUSB backend: permitted devices first, the
      // chooser only when nothing is permitted yet (and the chooser is enabled).
      var devices = await _permittedLedgerDevices();

      if (devices.isEmpty && LedgerUsb.webDeviceChooserEnabled) {
        final granted = await _hid.requestDevice(
          HIDDeviceRequestOptions(
            filters: [HIDDeviceFilter(vendorId: _ledgerVendorId)].toJS,
          ),
        );

        if (granted.isEmpty) {
          return [];
        }

        devices = await _permittedLedgerDevices();
      }

      _foundDevices
        ..clear()
        ..addAll({
          for (final (index, device) in devices.indexed)
            _identifier(device, index): device,
        });

      return _foundDevices.entries
          .map((e) => UsbDevice(
                manufacturerName: 'Ledger',
                deviceId: 0,
                vendorId: e.value.vendorId,
                productId: e.value.productId,
                productName: e.value.productName,
                configurationCount: 0,
                identifier: e.key,
                deviceName: e.value.productName,
              ))
          .toList();
    } catch (e) {
      debugPrint('Error in getDevices: $e');
      return [];
    }
  }

  /// One [HIDDevice] exists per HID interface, so keep only the interface
  /// exposing the Ledger APDU collection.
  Future<List<HIDDevice>> _permittedLedgerDevices() async {
    final devices = await _hid.getDevices();
    return devices
        .where((e) =>
            e.vendorId == _ledgerVendorId &&
            e.collections.any((c) => c.usagePage == _ledgerUsagePage))
        .toList(growable: false);
  }

  String _identifier(HIDDevice device, int index) =>
      'hid-${device.productId}-$index';

  @override
  Future<bool> requestPermission(UsbDevice usbDevice) async {
    return true;
  }

  @override
  Future<bool> open(UsbDevice usbDevice) async {
    try {
      // The device from the last getDevices() while it is still connected (the
      // index of another Ledger may have shifted). An unplugged Ledger's
      // HIDDevice stays dead and a replugged one is a new HIDDevice: look it
      // up again by identifier.
      final permitted = await _permittedLedgerDevices();
      final cached = _foundDevices[usbDevice.identifier];
      final device =
          cached != null && permitted.any((d) => d.strictEquals(cached).toDart)
              ? cached
              : permitted.indexed
                  .where((e) => _identifier(e.$2, e.$1) == usbDevice.identifier)
                  .map((e) => e.$2)
                  .firstOrNull;
      if (device == null) {
        throw Exception('Device not found');
      }

      await device.open();

      _stopListening();
      final onInputReport = _onInputReport.toJS;
      final onDisconnect = _onDisconnect.toJS;
      device.addEventListener(_inputReportEvent, onInputReport);
      _hid.addEventListener(_disconnectEvent, onDisconnect);
      _activeDevice = (
        device: device,
        onInputReport: onInputReport,
        onDisconnect: onDisconnect,
      );
      return true;
    } catch (e) {
      debugPrint('Error in open: $e');
      return false;
    }
  }

  void _onDisconnect(HIDConnectionEvent event) {
    final activeDevice = _activeDevice;
    if (activeDevice != null &&
        event.device.strictEquals(activeDevice.device).toDart) {
      _stopListening();
    }
  }

  void _onInputReport(HIDInputReportEvent event) {
    final report = event.data;
    final pending = _pendingTransferIn;
    if (pending != null) {
      _pendingTransferIn = null;
      pending.complete(report);
    } else {
      _inputReports.add(report);
    }
  }

  /// Throws instead of returning `null`: `LedgerUsb.exchange` retries a `null`
  /// read forever, so a closed or unplugged device must fail the exchange.
  @override
  Future<Uint8List?> transferIn(int packetSize, int timeout) async {
    await _openActiveDevice();

    if (_inputReports.isNotEmpty) {
      return _inputReports.removeFirst();
    }

    final pending = Completer<Uint8List>();
    _pendingTransferIn = pending;
    return pending.future;
  }

  /// Throws instead of returning `-1`: `LedgerUsb.exchange` ignores the byte
  /// count and would wait for the reply to a report that was never sent.
  @override
  Future<int> transferOut(Uint8List data, int timeout) async {
    final activeDevice = await _openActiveDevice();
    try {
      await activeDevice.sendReport(_ledgerReportId, data);
    } catch (_) {
      // Unplugged before the disconnect event arrived.
      throw _connectionLost();
    }
    return data.length;
  }

  Future<HIDDevice> _openActiveDevice() async {
    final device = _activeDevice?.device;
    if (device == null) {
      throw _connectionLost();
    }
    if (!device.opened) {
      await device.open();
    }
    return device;
  }

  /// Detaches the listeners of the active device and fails a pending
  /// [transferIn], like a WebUSB transfer aborted by `close()` or unplugging.
  void _stopListening() {
    final activeDevice = _activeDevice;
    if (activeDevice != null) {
      activeDevice.device.removeEventListener(
        _inputReportEvent,
        activeDevice.onInputReport,
      );
      _hid.removeEventListener(_disconnectEvent, activeDevice.onDisconnect);
    }
    _activeDevice = null;
    _inputReports.clear();
    _pendingTransferIn?.completeError(_connectionLost());
    _pendingTransferIn = null;
  }

  @override
  Future<bool> close() async {
    try {
      final activeDevice = _activeDevice;
      if (activeDevice != null) {
        _stopListening();
        await activeDevice.device.close();
        _foundDevices.clear();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error in close: $e');
      return false;
    }
  }
}

/// The message `ledger_flutter_plus` maps to its `ConnectionLostException`.
PlatformException _connectionLost() => PlatformException(
      code: 'connectionLost',
      message: 'connectionLost',
      details: 'Ledger closed or disconnected',
    );
