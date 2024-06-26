import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:ledger_usb/usb.web.dart';
import 'package:ledger_usb/usb_device.dart';
import 'ledger_usb_platform_interface.dart';

LedgerUsbPlatform createPlatformInstance() => WebLedgerUsb();

class WebLedgerUsb extends LedgerUsbPlatform {
  final List<USBDevice> _foundDevices = [];
  ({
    USBDevice device,
    int inEndpointNumber,
    int outEndpointNumber
  })? _activeDevice;

  @override
  Future<List<UsbDevice>> getDevices() async {
    try {
      final device = await usb.requestDevice(RequestUSBDeviceFilters.dart([
        RequestUSBDeviceFilter(vendorId: 11415),
      ]));

      if (device == null) {
        return [];
      }

      final devices = await usb.getDevices();

      _foundDevices
        ..clear()
        ..addAll(devices);

      return devices.map((e) => UsbDevice(
        manufacturerName: e.manufacturerName,
        deviceId: 0,
        vendorId: e.vendorId,
        productId: e.productId,
        productName: e.productName,
        configurationCount: 0,
        identifier: e.serialNumber,
        deviceName: e.productName,
      )).toList();
    } catch (e) {
      debugPrint('Error in getDevices: $e');
      return [];
    }
  }

  @override
  Future<bool> requestPermission(UsbDevice usbDevice) async {
    try {
      // Assuming permission is always granted for simplicity
      return true;
    } catch (e) {
      debugPrint('Error in requestPermission: $e');
      return false;
    }
  }

  @override
  Future<bool> open(UsbDevice usbDevice) async {
    try {
      final activeDevice = _foundDevices.firstWhere(
        (e) => e.serialNumber == usbDevice.identifier,
        orElse: () => throw Exception('Device not found'),
      );

      await activeDevice.open();

      final configuration = await activeDevice.configuration;
      if (configuration == null) {
        throw Exception('No configuration found');
      }
      await activeDevice.selectConfiguration(configuration.configurationValue);

      final interfaces = await activeDevice.interfaces;
      if (interfaces.isEmpty) {
        throw Exception('No interfaces found');
      }

      USBInterface? claimedInterface;
      for (final interface in interfaces) {
        if (!interface.claimed) {
          try {
            await activeDevice.claimInterface(interface.interfaceNumber);
            claimedInterface = interface;
            break;
          } catch (e) {
            if (e.toString().contains('SecurityError')) {
              continue;
            } else {
              throw e;
            }
          }
        }
      }

      if (claimedInterface == null) {
        throw Exception('No claimable interfaces found.');
      }

      final endpoints = claimedInterface.alternate.endpoints.toDart;
      final inEndpoint = endpoints.firstWhere(
        (e) => e.direction == 'in',
        orElse: () => throw Exception('IN endpoint not found'),
      );
      final outEndpoint = endpoints.firstWhere(
        (e) => e.direction == 'out',
        orElse: () => throw Exception('OUT endpoint not found'),
      );

      _activeDevice = (
        device: activeDevice,
        inEndpointNumber: inEndpoint.endpointNumber,
        outEndpointNumber: outEndpoint.endpointNumber
      );
      return true;
    } catch (e) {
      debugPrint('Error in open: $e');
      return false;
    }
  }

  @override
  Future<Uint8List?> transferIn(int packetSize, int timeout) async {
    try {
      final activeDevice = _activeDevice;
      if (activeDevice == null) {
        throw Exception('No active device; use open() first');
      }
      final device = activeDevice.device;
      final endpointNumber = activeDevice.inEndpointNumber;

      if (!device.opened) {
        await device.open();
      }

      final result = await device.transferIn(endpointNumber, packetSize);
      final jsDataView = result.data;
      if (jsDataView != null) {
        final byteData = jsDataView.toDart;
        return byteData.buffer.asUint8List();
      }
      return null;
    } catch (e) {
      debugPrint('Error in transferIn: $e');
      if (e.toString().contains('InvalidStateError')) {
        await _reopenDevice();
        return transferIn(packetSize, timeout);
      }
      return null;
    }
  }

  @override
  Future<int> transferOut(Uint8List data, int timeout) async {
    try {
      final activeDevice = _activeDevice;
      if (activeDevice == null) {
        throw Exception('No active device; use open() first');
      }
      final device = activeDevice.device;
      final endpointNumber = activeDevice.outEndpointNumber;

      if (!device.opened) {
        await device.open();
      }

      final result = await device.transferOut(endpointNumber, data.toJS);
      return result.bytesWritten;
    } catch (e) {
      debugPrint('Error in transferOut: $e');
      if (e.toString().contains('InvalidStateError')) {
        await _reopenDevice();
        return transferOut(data, timeout);
      }
      return -1;
    }
  }

  Future<void> _reopenDevice() async {
    final activeDevice = _activeDevice;
    if (activeDevice != null) {
      final device = activeDevice.device;
      await device.close();
      await device.open();
      await open(UsbDevice(
        manufacturerName: device.manufacturerName,
        deviceId: 0,
        vendorId: device.vendorId,
        productId: device.productId,
        productName: device.productName,
        configurationCount: 0,
        identifier: device.serialNumber,
        deviceName: device.productName,
      ));
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
      debugPrint('Error in close: $e');
      return false;
    }
  }
}