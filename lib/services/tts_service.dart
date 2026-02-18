// lib/services/tts_service.dart

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  
  bool _isSpeaking = false;
  bool _isPaused = false;
  bool _isInitialized = false;

  // Очередь сообщений
  final List<String> _queue = [];
  bool _isProcessingQueue = false;

  /// Инициализация TTS
  Future<void> init() async {
    if (_isInitialized) return;

    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.45); // Скорость речи
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // Обработчики состояний
    _tts.setStartHandler(() {
      _isSpeaking = true;
      _isPaused = false;
    });

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _isPaused = false;
      _processNextInQueue();
    });

    _tts.setErrorHandler((error) {
      _isSpeaking = false;
      _isPaused = false;
      print('TTS Error: $error');
      _processNextInQueue();
    });

    _tts.setCancelHandler(() {
      _isSpeaking = false;
      _isPaused = false;
    });

    _isInitialized = true;
    print('TTS инициализирован');
  }

  /// Произнести текст (с добавлением в очередь)
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    
    _queue.add(text);
    print('TTS: Добавлено в очередь (${_queue.length}): ${text.substring(0, text.length > 50 ? 50 : text.length)}...');
    
    if (!_isProcessingQueue) {
      await _processNextInQueue();
    }
  }

  /// Произнести текст немедленно (очищает очередь)
  Future<void> speakNow(String text) async {
    if (text.isEmpty) return;
    
    _queue.clear();
    await _tts.stop();
    _isSpeaking = false;
    _isPaused = false;
    
    await _tts.speak(text);
    _isSpeaking = true;
  }

  /// Обработка очереди
  Future<void> _processNextInQueue() async {
    if (_queue.isEmpty || _isSpeaking) {
      _isProcessingQueue = false;
      return;
    }

    _isProcessingQueue = true;
    final text = _queue.removeAt(0);
    
    await _tts.speak(text);
  }

  /// Пауза
  Future<void> pause() async {
    if (_isSpeaking && !_isPaused) {
      await _tts.pause();
      _isPaused = true;
    }
  }

  /// Остановка (очищает очередь)
  Future<void> stop() async {
    _queue.clear();
    await _tts.stop();
    _isSpeaking = false;
    _isPaused = false;
    _isProcessingQueue = false;
  }

  /// Пропустить текущее сообщение
  Future<void> skip() async {
    await _tts.stop();
    _isSpeaking = false;
    _isPaused = false;
  }

  /// Геттеры
  bool get isSpeaking => _isSpeaking;
  bool get isPaused => _isPaused;
  bool get isInitialized => _isInitialized;
  int get queueLength => _queue.length;

  /// Освобождение ресурсов
  void dispose() {
    _tts.stop();
    _queue.clear();
  }
}