// lib/services/tts_service.dart

import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audio_session/audio_session.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  final _speechController = StreamController<String>.broadcast();
  
  bool _isSpeaking = false;
  bool _isPaused = false;
  bool _isInitialized = false;

  // Очередь сообщений
  final List<String> _queue = [];
  bool _isProcessingQueue = false;

  // Для управления аудио сессией (ducking)
  AudioSession? _audioSession;

  /// Инициализация TTS
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Настраиваем аудио сессию для ducking
      _audioSession = await AudioSession.instance;
      await _audioSession?.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ));

      await _tts.setLanguage('ru-RU');
      await _tts.setSpeechRate(0.45); // Скорость речи
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      // Обработчики состояний
      _tts.setStartHandler(() {
        _isSpeaking = true;
        _isPaused = false;
        _speechController.add('start');
        print('🎙️ TTS начал говорить');
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        _isPaused = false;
        _speechController.add('complete');
        print('🎙️ TTS закончил');
        _processNextInQueue();
      });

      _tts.setErrorHandler((error) {
        _isSpeaking = false;
        _isPaused = false;
        print('❌ TTS ошибка: $error');
        _speechController.add('error');
        _processNextInQueue();
      });

      _tts.setCancelHandler(() {
        _isSpeaking = false;
        _isPaused = false;
        _speechController.add('cancel');
      });

      _isInitialized = true;
      print('✅ TTS инициализирован с ducking');
    } catch (e) {
      print('❌ Ошибка инициализации TTS: $e');
    }
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
    
    await _speakWithDucking(text);
  }

  /// Обработка очереди
  Future<void> _processNextInQueue() async {
    if (_queue.isEmpty || _isSpeaking) {
      _isProcessingQueue = false;
      return;
    }

    _isProcessingQueue = true;
    final text = _queue.removeAt(0);
    
    await _speakWithDucking(text);
  }

  /// Озвучивание с приглушением фоновой музыки
  Future<void> _speakWithDucking(String text) async {
    try {
      // Запрашиваем аудио фокус (это приглушит музыку)
      final session = await AudioSession.instance;
      await session.setActive(true);
      
      print('🔊 Говорим: ${text.substring(0, text.length > 50 ? 50 : text.length)}...');
      await _tts.speak(text);
      
      // Ждём окончания речи
      await _waitForSpeechComplete();
      
      // Освобождаем аудио фокус (музыка вернётся)
      await session.setActive(false);
      
    } catch (e) {
      print('❌ Ошибка озвучивания с ducking: $e');
      _isSpeaking = false;
    }
  }

  /// Ожидание завершения речи
  Future<void> _waitForSpeechComplete() async {
    final completer = Completer<void>();
    late StreamSubscription sub;
    
    sub = _speechController.stream.listen((event) {
      if (event == 'complete' || event == 'error') {
        sub.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    
    // Таймаут на случай если TTS зависнет
    await Future.any([
      completer.future,
      Future.delayed(const Duration(seconds: 30)),
    ]);
    
    sub.cancel();
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
    
    // Освобождаем аудио фокус
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e) {
      print('❌ Ошибка освобождения аудио фокуса: $e');
    }
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
    _speechController.close();
    _tts.stop();
    _queue.clear();
  }
}