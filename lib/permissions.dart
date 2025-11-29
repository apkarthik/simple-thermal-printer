import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

class BluetoothPermissions {
  static Future<bool> ensure() async {
    if (Platform.isAndroid) {
      final statusScan = await Permission.bluetoothScan.request();
      final statusConnect = await Permission.bluetoothConnect.request();
      final statusLocation = await Permission.locationWhenInUse.request();

      return statusScan.isGranted && statusConnect.isGranted && statusLocation.isGranted;
    }
    return true;
  }
}
