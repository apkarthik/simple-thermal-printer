import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static const String keyPaperSize = 'paper_size';
  static const String keyCodeTable = 'code_table';

  static Future<void> savePaperSize(String size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyPaperSize, size);
  }

  static Future<void> saveCodeTable(String table) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyCodeTable, table);
  }

  static Future<String?> getPaperSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyPaperSize);
  }

  static Future<String?> getCodeTable() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyCodeTable);
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _paperSize = 'mm58';
  String _codeTable = 'CP1252';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final size = await AppSettings.getPaperSize();
    final table = await AppSettings.getCodeTable();
    setState(() {
      _paperSize = size ?? 'mm58';
      _codeTable = table ?? 'CP1252';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Paper Size', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _paperSize,
            items: const [
              DropdownMenuItem(value: 'mm58', child: Text('58mm')), 
              DropdownMenuItem(value: 'mm80', child: Text('80mm')), 
            ],
            onChanged: (v) => setState(() => _paperSize = v ?? 'mm58'),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Text('Code Table', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _codeTable,
            items: const [
              DropdownMenuItem(value: 'CP1252', child: Text('CP1252 (Western)')),
              DropdownMenuItem(value: 'CP437', child: Text('CP437 (USA)')),
              DropdownMenuItem(value: 'CP936', child: Text('CP936 (Chinese GBK)')),
              DropdownMenuItem(value: 'CP850', child: Text('CP850 (Latin-1)')),
            ],
            onChanged: (v) => setState(() => _codeTable = v ?? 'CP1252'),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              await AppSettings.savePaperSize(_paperSize);
              await AppSettings.saveCodeTable(_codeTable);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings saved')),
                );
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
