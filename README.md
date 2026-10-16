# Ledger USB Plus

Forked of [ledger_usb](https://pub.dev/packages/ledger_usb) to add WEB support (using [WebHID APIs](https://developer.mozilla.org/en-US/docs/Web/API/WebHID_API) when available, otherwise [WebUSB APIs](https://developer.mozilla.org/en-US/docs/Web/API/WebUSB_API))

On web, listing devices returns the Ledger devices already permitted for the origin and only shows the browser chooser when none is permitted. Set `LedgerUsb.webDeviceChooserEnabled = false` to never show the chooser (for example in pages without a user gesture).

For usage, check [ledger_flutter_plus](https://pub.dev/packages/ledger_flutter_plus)
