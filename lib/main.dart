import 'dart:async';
import 'dart:typed_data';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'permissions.dart';
import 'settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SimpleThermalPrinterApp());
}

class SimpleThermalPrinterApp extends StatelessWidget {
  const SimpleThermalPrinterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Thermal Printer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const PrinterHomePage(),
    );
  }
}

class PrinterHomePage extends StatefulWidget {
  const PrinterHomePage({super.key});

  @override
  State<PrinterHomePage> createState() => _PrinterHomePageState();
}

class _PrinterHomePageState extends State<PrinterHomePage> {
  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> devices = [];
  BluetoothDevice? selectedDevice;
  bool isConnected = false;
  bool isScanning = false;
  bool isWakeLockEnabled = false;

  // Custom text input
  final TextEditingController textController = TextEditingController(text: 'Hello from Flutter!');

  // Settings
  PaperSize _paperSize = PaperSize.mm58;
  String _codeTable = 'CP1252';

  // Subscriptions
  StreamSubscription? _intentDataStreamSubscription;
  StreamSubscription? _bluetoothStateSubscription;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initBluetooth();
    _initSharedIntent();
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    _bluetoothStateSubscription?.cancel();
    // Disable wake lock when app is disposed
    unawaited(WakelockPlus.disable().catchError((error) {
      debugPrint('Error disabling wake lock in dispose: $error');
    }));
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final size = await AppSettings.getPaperSize();
    final table = await AppSettings.getCodeTable();
    setState(() {
      _paperSize = (size == 'mm80') ? PaperSize.mm80 : PaperSize.mm58;
      _codeTable = table ?? 'CP1252';
    });
  }

  void _initSharedIntent() {
    // For sharing text when app is already opened
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty && mounted) {
        // Extract text from SharedMediaFile
        // For text shares, the content is in the 'path' property
        // For media with captions, check the 'message' property
        final SharedMediaFile media = value.first;
        final String sharedText = media.message?.isNotEmpty == true ? media.message! : media.path;
        if (sharedText.isNotEmpty) {
          setState(() {
            textController.text = sharedText;
          });
          _showSharedContentDialog(sharedText);
        }
      }
    }, onError: (err) {
      debugPrint("Error receiving shared intent: $err");
    });

    // For sharing text when app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile>? value) {
      if (value != null && value.isNotEmpty && mounted) {
        // Extract text from SharedMediaFile
        // For text shares, the content is in the 'path' property
        // For media with captions, check the 'message' property
        final SharedMediaFile media = value.first;
        final String sharedText = media.message?.isNotEmpty == true ? media.message! : media.path;
        if (sharedText.isNotEmpty) {
          setState(() {
            textController.text = sharedText;
          });
          _showSharedContentDialog(sharedText);
        }
      }
    }).catchError((error) {
      debugPrint("Error getting initial shared intent: $error");
    });
  }

  void _showSharedContentDialog(String sharedText) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Shared Content Received'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('The following text was shared with the printer app:'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      sharedText,
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isConnected 
                      ? 'Ready to print!' 
                      : 'Connect to a printer first to print this content.',
                    style: TextStyle(
                      color: isConnected ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                if (isConnected)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _printText(sharedText);
                    },
                    icon: const Icon(Icons.print),
                    label: const Text('Print Now'),
                  ),
              ],
            );
          },
        );
      }
    });
  }

  Future<void> _initBluetooth() async {
    // Attempt auto-reconnect to last device
    await _attemptAutoReconnect();

    bool? connected = await bluetooth.isConnected;
    if (mounted) {
      setState(() {
        isConnected = connected == true;
      });
    }

    // Enable wake lock if already connected
    if (isConnected) {
      await _enableWakeLock();
    }

    _bluetoothStateSubscription = bluetooth.onStateChanged().listen((state) {
      final newConnectedState = state == BlueThermalPrinter.CONNECTED;
      if (mounted) {
        setState(() {
          isConnected = newConnectedState;
        });
      }

      // Enable/disable wake lock based on connection state
      // Use unawaited to avoid blocking the stream, errors are handled in the methods
      if (newConnectedState) {
        unawaited(_enableWakeLock().catchError((error) {
          debugPrint('Error enabling wake lock in state listener: $error');
        }));
      } else {
        unawaited(_disableWakeLock().catchError((error) {
          debugPrint('Error disabling wake lock in state listener: $error');
        }));
      }
    });
  }

  Future<void> _enableWakeLock() async {
    try {
      await WakelockPlus.enable();
      if (mounted) {
        setState(() {
          isWakeLockEnabled = true;
        });
      }
      debugPrint('Wake lock enabled - printer will stay connected');
    } catch (e) {
      debugPrint('Failed to enable wake lock: $e');
    }
  }

  Future<void> _disableWakeLock() async {
    try {
      await WakelockPlus.disable();
      if (mounted) {
        setState(() {
          isWakeLockEnabled = false;
        });
      }
      debugPrint('Wake lock disabled');
    } catch (e) {
      debugPrint('Failed to disable wake lock: $e');
    }
  }

  Future<void> _attemptAutoReconnect() async {
    final prefs = await SharedPreferences.getInstance();
    final lastAddr = prefs.getString('last_device_address');
    if (lastAddr == null) return;

    try {
      final ok = await BluetoothPermissions.ensure();
      if (!ok) return;

      final bonded = await bluetooth.getBondedDevices();
      final match = bonded.firstWhere(
        (d) => (d.address ?? '') == lastAddr,
        orElse: () => BluetoothDevice(null, null),
      );

      if ((match.address ?? '').isNotEmpty) {
        await bluetooth.connect(match);
        if (mounted) {
          setState(() {
            selectedDevice = match;
            isConnected = true;
          });
        }
        // Enable wake lock after successful auto-reconnect
        await _enableWakeLock();
      }
    } catch (_) {
      // Silently ignore auto-reconnect failures
    }
  }

  Future<void> _scan() async {
    setState(() {
      isScanning = true;
    });
    try {
      final ok = await BluetoothPermissions.ensure();
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth permissions not granted')),
        );
        return;
      }
      final bonded = await bluetooth.getBondedDevices();
      setState(() {
        devices = bonded;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e')),
      );
    } finally {
      setState(() {
        isScanning = false;
      });
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    try {
      await bluetooth.connect(device);
      setState(() {
        selectedDevice = device;
        isConnected = true;
      });
      // Persist last device address for auto-reconnect
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_device_address', device.address ?? '');

      // Enable wake lock to keep connection alive
      await _enableWakeLock();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${device.name ?? device.address}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connect failed: $e')),
      );
    }
  }

  Future<void> _disconnect() async {
    try {
      await bluetooth.disconnect();
      setState(() {
        selectedDevice = null;
        isConnected = false;
      });
      
      // Disable wake lock when disconnected
      await _disableWakeLock();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnect failed: $e')),
      );
    }
  }

  Generator _generatorForSettings(CapabilityProfile profile) {
    return Generator(_paperSize, profile);
  }

  Future<void> _printText(String text) async {
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to a printer')),
      );
      return;
    }
    try {
      final profile = await CapabilityProfile.load();
      final generator = _generatorForSettings(profile);
      List<int> bytes = [];

      bytes += generator.setGlobalCodeTable(_codeTable);
      bytes += generator.text(
        text,
        styles: const PosStyles(align: PosAlign.left),
        linesAfter: 2,
      );
      bytes += generator.cut();

      await bluetooth.writeBytes(Uint8List.fromList(bytes));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printed text')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  Future<void> _printSample() async {
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to a printer')),
      );
      return;
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = _generatorForSettings(profile);

      List<int> bytes = [];

      bytes += generator.setGlobalCodeTable(_codeTable);
      bytes += generator.text(
        'SIMPLE THERMAL PRINTER',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.text('Powered by Flutter',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.hr();
      bytes += generator.row([
        PosColumn(text: 'Item', width: 6),
        PosColumn(text: 'Qty', width: 3, styles: const PosStyles(align: PosAlign.right)),
        PosColumn(text: 'Price', width: 3, styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Coffee', width: 6),
        PosColumn(text: '1', width: 3, styles: const PosStyles(align: PosAlign.right)),
        PosColumn(text: '\$2.50', width: 3, styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Donut', width: 6),
        PosColumn(text: '2', width: 3, styles: const PosStyles(align: PosAlign.right)),
        PosColumn(text: '\$3.00', width: 3, styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.hr();
      bytes += generator.row([
        PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(bold: true)),
        PosColumn(text: '', width: 3),
        PosColumn(text: '\$5.50', width: 3, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);
      bytes += generator.hr(ch: '=', linesAfter: 1);

      bytes += generator.qrcode('https://example.com/order/12345',
          size: QRSize.Size4, align: PosAlign.center);
      bytes += generator.text('Thank you!', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(2);
      bytes += generator.cut();

      await bluetooth.writeBytes(Uint8List.fromList(bytes));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printed sample receipt')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceTiles = devices
        .map(
          (d) => ListTile(
            title: Text(d.name ?? 'Unknown'),
            subtitle: Text(d.address ?? ''),
            trailing: ElevatedButton(
              onPressed: () => _connect(d),
              child: const Text('Connect'),
            ),
          ),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Thermal Printer'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ).then((_) => _loadSettings()); // Reload after returning
            },
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
          IconButton(
            onPressed: isConnected ? _disconnect : null,
            icon: const Icon(Icons.bluetooth_disabled),
            tooltip: 'Disconnect',
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection actions
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isScanning ? null : _scan,
                    icon: const Icon(Icons.bluetooth_searching),
                    label: const Text('Scan paired devices'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnected ? _printSample : null,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Print sample'),
                  ),
                ),
              ],
            ),
          ),

          // Connected device indicator
          if (selectedDevice != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bluetooth_connected, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Connected: ${selectedDevice!.name ?? selectedDevice!.address}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        isWakeLockEnabled ? Icons.power : Icons.power_off,
                        color: isWakeLockEnabled ? Colors.green : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isWakeLockEnabled 
                          ? 'Keep-alive: ON (Printer stays connected)' 
                          : 'Keep-alive: OFF',
                        style: TextStyle(
                          color: isWakeLockEnabled ? Colors.green : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // Custom text input and print
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: textController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Custom text to print',
                    border: OutlineInputBorder(),
                    hintText: 'Enter text to print on your thermal printer',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isConnected
                            ? () => _printText(textController.text.trim().isEmpty
                                ? ' '
                                : textController.text.trim())
                            : null,
                        icon: const Icon(Icons.print),
                        label: const Text('Print text'),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Paper: ${_paperSize == PaperSize.mm80 ? '80mm' : '58mm'}, Code Table: $_codeTable',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Device list
          Expanded(
            child: ListView(
              children: deviceTiles.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No paired devices found.\nPair your thermal printer in system Bluetooth settings first, then tap Scan.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ]
                  : deviceTiles,
            ),
          ),
        ],
      ),
    );
  }
}
