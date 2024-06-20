import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:ledger_usb/usb.web.dart';
import 'package:ledger_usb/usb_device.dart';
import 'ledger_usb_platform_interface.dart';

class WebLedgerUsb extends LedgerUsbPlatform {
  final List<USBDevice> _foundDevices = [];
  ({USBDevice device, int endpointNumber})? _activeDevice;

  @override
  Future<List<UsbDevice>> getDevices() async {
    try {
      print("Requesting device permission...");
      final device = await usb.requestDevice(RequestUSBDeviceFilters.dart([
        RequestUSBDeviceFilter(vendorId: 11415),
      ]));

      if (device == null) {
        print("No device selected.");
        return [];
      }

      print("Device selected: ${device.productName}");

      print("getDevices() call");
      final devices = await usb.getDevices();
      print("Requested devices with usb.getDevices(): $devices");
      for (final device in devices) {
        print(device);
      }

      _foundDevices.addAll(devices);

      return devices
          .map((e) => UsbDevice(
                manufacturerName: e.manufacturerName,
                deviceId: 0,
                vendorId: e.vendorId,
                productId: e.productId,
                productName: e.productName,
                configurationCount: 0,
                identifier: e.serialNumber,
                deviceName: e.productName,
              ))
          .toList();
    } catch (e) {
      print("Error getting devices: $e");
      return [];
    }
  }

  @override
  Future<bool> requestPermission(UsbDevice usbDevice) async {
    try {
      return true;
    } catch (e) {
      print("Error requesting permission: $e");
      return false;
    }
  }

  @override
  Future<bool> open(UsbDevice usbDevice) async {
    try {
      final activeDevice = _foundDevices
          .firstWhere((e) => e.serialNumber == usbDevice.identifier);
      // TODO: here you need to select configuration, claim interface
      final endpointNumber =
          999; // TODO, find the appropriate one based on interface that supports in and out
      await activeDevice.open();
      _activeDevice = (device: activeDevice, endpointNumber: endpointNumber);
      return true;
    } catch (e) {
      print("Error opening device: $e");
      return false;
    }
  }

  @override
  Future<Uint8List?> transferIn(int packetSize, int timeout) async {
    try {
      final activeDevice = _activeDevice;

      if (activeDevice == null) {
        throw Exception("No active device; use requestPermission first");
      }
      final device = activeDevice.device;
      final endpointNumber = activeDevice.endpointNumber;

      print("Calling transferIn on activeDevice with packetSize: $packetSize");
      final result = await device.transferIn(endpointNumber, packetSize);
      print("Result from transferIn: $result");
      final jsDataView = result.data;
      if (jsDataView != null) {
        final byteData = jsDataView.toDart;
        return byteData.buffer.asUint8List();
      }
      return null;
    } catch (e) {
      print("Error in transferIn: $e");
      return null;
    }
  }

  @override
  Future<int> transferOut(Uint8List data, int timeout) async {
    try {
      final activeDevice = _activeDevice;

      if (activeDevice == null) {
        throw Exception("No active device; use requestPermission first");
      }
      final device = activeDevice.device;
      final endpointNumber = activeDevice.endpointNumber;

      print(
          "Calling transferOut on activeDevice with data length: ${data.length}");
      final result = await device.transferOut(endpointNumber, data.toJS);
      print("Result from transferOut: $result");
      return result.bytesWritten;
    } catch (e) {
      print("Error in transferOut: $e");
      return -1;
    }
  }

  @override
  Future<bool> close() async {
    try {
      final activeDevice = _activeDevice;
      if (activeDevice != null) {
        await activeDevice.device.close();
        _activeDevice = null;
        _foundDevices.clear();
        return true;
      }
      return false;
    } catch (e) {
      print("Error closing device: $e");
      return false;
    }
  }
}
