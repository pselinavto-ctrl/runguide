import 'package:flutter/material.dart';
import '../../services/settings_service.dart';
import '../../core/speech_mode.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService();
  SpeechMode _currentMode = SpeechMode.balanced;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final mode = await _settingsService.getSpeechMode();
    setState(() {
      _currentMode = mode;
      _isLoading = false;
    });
  }

  Future<void> _saveMode(SpeechMode mode) async {
    await _settingsService.setSpeechMode(mode);
    setState(() {
      _currentMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Режим темпа речи',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...SpeechMode.values.map((mode) => _buildModeTile(mode)),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'Описание режимов:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...SpeechMode.values.map((mode) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${mode.displayName}: ',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(child: Text(mode.description)),
                        ],
                      ),
                    )),
              ],
            ),
    );
  }

  Widget _buildModeTile(SpeechMode mode) {
    return RadioListTile<SpeechMode>(
      title: Text(mode.displayName),
      subtitle: Text(mode.description),
      value: mode,
      groupValue: _currentMode,
      onChanged: (value) {
        if (value != null) {
          _saveMode(value);
        }
      },
      activeColor: Colors.deepPurple,
    );
  }
}