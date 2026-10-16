// ignore_for_file: prefer_void_to_null, unnecessary_library_name

@JS("window.navigator")
library hid;

import 'dart:js_interop';
import 'dart:typed_data';

/// `navigator.hid`, or `null` when the browser does not support WebHID.
@JS()
external WebHID? get hid;

extension type WebHID._(JSObject o) implements JSObject {
  @JS('getDevices')
  external JSPromise<JSArray<HIDDevice>> _getDevices();

  @JS('requestDevice')
  external JSPromise<JSArray<HIDDevice>> _requestDevice(
    HIDDeviceRequestOptions options,
  );

  Future<List<HIDDevice>> getDevices() async {
    final jsDevices = await _getDevices().toDart;
    return jsDevices.toDart;
  }

  Future<List<HIDDevice>> requestDevice(HIDDeviceRequestOptions options) async {
    final jsDevices = await _requestDevice(options).toDart;
    return jsDevices.toDart;
  }
}

extension type HIDDevice._(JSObject o) implements JSObject {
  @JS('open')
  external JSPromise<Null> _open();

  @JS('close')
  external JSPromise<Null> _close();

  @JS('sendReport')
  external JSPromise<Null> _sendReport(int reportId, JSUint8Array data);

  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);

  external String get productName;
  external int get vendorId;
  external int get productId;

  external bool get opened;

  @JS('collections')
  external JSArray<HIDCollectionInfo> get _collections;

  List<HIDCollectionInfo> get collections => _collections.toDart;

  Future<void> open() async {
    if (!opened) {
      await _open().toDart;
    }
  }

  Future<void> sendReport(int reportId, Uint8List data) async {
    await _sendReport(reportId, data.toJS).toDart;
  }

  Future<void> close() async {
    if (opened) {
      await _close().toDart;
    }
  }
}

extension type HIDCollectionInfo._(JSObject o) implements JSObject {
  external int get usagePage;
  external int get usage;
}

extension type HIDInputReportEvent._(JSObject o) implements JSObject {
  external int get reportId;

  @JS('data')
  external JSDataView get _data;

  Uint8List get data {
    final byteData = _data.toDart;
    return byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
  }
}

extension type HIDDeviceRequestOptions._(JSObject o) implements JSObject {
  external HIDDeviceRequestOptions({
    required JSArray<HIDDeviceFilter> filters,
  });
}

extension type HIDDeviceFilter._(JSObject o) implements JSObject {
  external HIDDeviceFilter({
    int? vendorId,
    int? productId,
    int? usagePage,
    int? usage,
  });
}
