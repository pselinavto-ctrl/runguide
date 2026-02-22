import 'package:shared_preferences/shared_preferences.dart';
import '../core/speech_mode.dart';

class SettingsService {
  static const String _keySpeechMode = 'speechMode';

  Future<SpeechMode> getSpeechMode() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_keySpeechMode) ?? SpeechMode.balanced.index;
    return SpeechMode.values[index];
  }

  Future<void> setSpeechMode(SpeechMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySpeechMode, mode.index);
  }
}