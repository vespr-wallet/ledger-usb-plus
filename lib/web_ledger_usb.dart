import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:ledger_usb/usb.web.dart';
import 'package:ledger_usb/usb_device.dart';
import 'ledger_usb_platform_interface.dart';

class WebLedgerUsb extends LedgerUsbPlatform {
  final List<USBDevice> _foundDevices = [];
  ({USBDevice device, int inEndpointNumber, int outEndpointNumber})? _activeDevice;

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

      _foundDevices.clear(); // Clear the list before adding new devices
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
      print("Searching for the device in the found devices list...");
      final activeDevice = _foundDevices
          .firstWhere((e) => e.serialNumber == usbDevice.identifier);
      print("Device found. Attempting to open the device...");

      await activeDevice.open();
      print("Device opened successfully.");

      print("Fetching device configuration...");
      final configuration = await activeDevice.configuration;
      if (configuration == null) {
        throw Exception("No configuration found");
      }
      print("Configuration found: ${configuration.configurationValue}. Selecting configuration...");
      await activeDevice.selectConfiguration(configuration.configurationValue);

      print("Retrieving device interfaces...");
      final interfaces = await activeDevice.interfaces;
      if (interfaces.isEmpty) {
        throw Exception("No interfaces found");
      }

      bool interfaceClaimed = false;
      USBInterface? claimedInterface;
      for (final interface in interfaces) {
        if (!interface.claimed) {
          print("Unclaimed interface found: ${interface.interfaceNumber}. Attempting to claim interface...");
          try {
            await activeDevice.claimInterface(interface.interfaceNumber);
            interfaceClaimed = true;
            claimedInterface = interface;
            print("Interface ${interface.interfaceNumber} claimed successfully.");
            break;
          } catch (e) {
            if (e.toString().contains('SecurityError')) {
              print("SecurityError: The requested interface implements a protected class. Skipping...");
            } else {
              throw e;
            }
          }
        }
      }

      if (!interfaceClaimed || claimedInterface == null) {
        throw Exception("No claimable interfaces found.");
      }

      print("Accessing interface endpoints...");
      final endpoints = claimedInterface.alternate.endpoints.toDart;
      final inEndpoint = endpoints.firstWhere((e) => e.direction == 'in', orElse: () => throw Exception("IN endpoint not found"));
      final outEndpoint = endpoints.firstWhere((e) => e.direction == 'out', orElse: () => throw Exception("OUT endpoint not found"));

      print("Usable IN endpoint found: ${inEndpoint.endpointNumber}");
      print("Usable OUT endpoint found: ${outEndpoint.endpointNumber}");

      _activeDevice = (
        device: activeDevice,
        inEndpointNumber: inEndpoint.endpointNumber,
        outEndpointNumber: outEndpoint.endpointNumber
      );
      print("Device is now active with IN endpoint: ${inEndpoint.endpointNumber} and OUT endpoint: ${outEndpoint.endpointNumber}");
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
        throw Exception("No active device; use open() first");
      }
      final device = activeDevice.device;
      final endpointNumber = activeDevice.inEndpointNumber;

      if (!device.opened) {
        print("Device is not open. Attempting to reopen...");
        await device.open();
      }

      print("Calling transferIn on activeDevice with packetSize: $packetSize");
      final result = await device.transferIn(endpointNumber, packetSize);
      print("Result from transferIn: ${result.status}");
      final jsDataView = result.data;
      if (jsDataView != null) {
        final byteData = jsDataView.toDart;
        return byteData.buffer.asUint8List();
      }
      return null;
    } catch (e) {
      print("Error in transferIn: $e");
      if (e.toString().contains('InvalidStateError')) {
        print("Device is in an invalid state. Attempting to reopen...");
        await _reopenDevice();
        // Retry the transfer after reopening
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
        throw Exception("No active device; use open() first");
      }
      final device = activeDevice.device;
      final endpointNumber = activeDevice.outEndpointNumber;

      if (!device.opened) {
        print("Device is not open. Attempting to reopen...");
        await device.open();
      }

      print(
          "Calling transferOut on activeDevice with data length: ${data.length}");
      final result = await device.transferOut(endpointNumber, data.toJS);
      print("Result from transferOut: ${result.status}");
      return result.bytesWritten;
    } catch (e) {
      print("Error in transferOut: $e");
      if (e.toString().contains('InvalidStateError')) {
        print("Device is in an invalid state. Attempting to reopen...");
        await _reopenDevice();
        // Retry the transfer after reopening
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
      // Re-claim the interface and set up the endpoint
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
      print("Error closing device: $e");
      return false;
    }
  }
}
