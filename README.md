# Simple Thermal Printer (Flutter)

A minimal app inspired by RawBT to print receipts to ESC/POS thermal printers using classic Bluetooth (Android).

## Features
- Scan paired Bluetooth devices
- Connect and print a sample receipt
- Print custom text via a simple input field
- Settings page for paper size (58mm/80mm) and code table (CP1252/CP437/CP936/CP850)
- Persist last connected device and auto-reconnect on app launch
- **Keep-alive mode**: Prevents printer from going idle/off when connected (uses wake lock)
- **Share intent support**: Receive and print text shared from any app

## Requirements
- Flutter SDK
- Android device with classic Bluetooth
- ESC/POS-compatible thermal printer (e.g., 58mm or 80mm)

## Setup

1. Create the project:
```bash
flutter create simple_thermal_printer
cd simple_thermal_printer
```

2. Replace `pubspec.yaml` and add files under `lib/` (`main.dart`, `permissions.dart`, `settings.dart`) with the contents in this repository.

3. Copy the `android/` directory to your project root, or update your existing AndroidManifest.xml with the required permissions and intent filters from `android/app/src/main/AndroidManifest.xml`.

4. Android permissions and features (see `android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<!-- Android 12+ -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- Some devices require location to discover or use Bluetooth APIs -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-feature android:name="android.hardware.bluetooth" android:required="false"/>
<!-- Wake lock to keep printer connection alive -->
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

The AndroidManifest.xml also includes intent filters to receive shared text from other apps.

5. Pair the printer in Android Bluetooth settings first (PIN often 0000 or 1234).

6. Run:
```bash
flutter run
```

## How it works
- Uses `blue_thermal_printer` to list bonded devices and manage connection.
- Uses `esc_pos_utils` to generate ESC/POS commands into bytes.
- Sends bytes over Bluetooth to print.
- Saves last device address to `SharedPreferences` and tries auto-reconnect on launch.
- Settings page stores paper size and code table in `SharedPreferences`.
- Uses `wakelock_plus` to keep the device awake and maintain printer connection when connected.
- Uses `receive_sharing_intent` to receive text shared from other apps via Android's share menu.

## Using Share Feature
1. Connect to your thermal printer in the app
2. Go to any app (notes, browser, messaging, etc.)
3. Select text you want to print
4. Tap the "Share" button
5. Choose "Simple Thermal Printer" from the share menu
6. The app will open with the shared text ready to print
7. Tap "Print Now" in the dialog or edit the text before printing

## Customizing
- Modify `_printSample()` in `lib/main.dart` to change the receipt layout, add items, logos (`generator.image`), or barcodes.
- Change default text in the input field or add templates for quick actions.
- Extend code tables if your language requires a specific one supported by your printer.

## Troubleshooting
- Not discovered: Ensure it’s paired in Android settings. This app lists bonded devices.
- Fails to connect on Android 12+: Verify Manifest + runtime permissions. Ensure Location is enabled.
- Garbled output: Pick the right code table (Settings). Also set paper size to match your printer (58mm or 80mm).
- Disconnects: Charge printer, stay close, verify SPP support (classic Bluetooth).

## Roadmap
- Discover unpaired devices and pair in-app (where supported)
- Wi‑Fi/TCP printing for network ESC/POS printers
- Image/logo printing and better Unicode handling
- Print templates and simple form-based receipts
