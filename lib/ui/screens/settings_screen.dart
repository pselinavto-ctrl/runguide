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
    if (mounted) {
      setState(() {
        _currentMode = mode;
        _isLoading = false;
      });
    }
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
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white.withOpacity(0.8),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Настройки',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок секции
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 16),
                    child: Text(
                      'РЕЖИМ АУДИО-ГИДА',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),

                  // Список режимов красивыми карточками
                  Column(
                    children: SpeechMode.values.map((mode) {
                      return _buildModeCard(mode);
                    }).toList(),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Информационный блок внизу (опционально, для красоты)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Colors.grey.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Выберите частоту и детализацию голосовых уведомлений во время тренировки.',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildModeCard(SpeechMode mode) {
    final isSelected = _currentMode == mode;

    // Подбираем иконки и цвета под стиль приложения
    IconData icon;
    Color accentColor;

    switch (mode) {
      case SpeechMode.quiet:
        icon = Icons.volume_off_rounded;
        accentColor = Colors.blueGrey; // Спокойный цвет для тихого режима
        break;
      case SpeechMode.balanced:
        icon = Icons.balance_rounded;
        accentColor = Colors.deepPurple; // Основной цвет приложения
        break;
      case SpeechMode.talkative:
        icon = Icons.record_voice_over_rounded;
        accentColor = Colors.orange; // Активный цвет
        break;
    }

    return GestureDetector(
      onTap: () => _saveMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF252542),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? accentColor : Colors.grey.shade800,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Иконка
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(isSelected ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: isSelected ? accentColor : Colors.grey.shade600,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            
            // Текст (Название + Описание)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.displayName,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mode.description,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            
            // Индикатор выбора
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked_rounded,
                color: isSelected ? accentColor : Colors.grey.shade700,
                size: 26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}