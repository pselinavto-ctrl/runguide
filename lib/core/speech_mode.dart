enum SpeechMode {
  quiet,
  balanced,
  talkative,
}

extension SpeechModeExtension on SpeechMode {
  String get displayName {
    switch (this) {
      case SpeechMode.quiet:
        return 'Тихий';
      case SpeechMode.balanced:
        return 'Баланс';
      case SpeechMode.talkative:
        return 'Разговорчивый';
    }
  }

  String get description {
    switch (this) {
      case SpeechMode.quiet:
        return 'Только интересные места, редко';
      case SpeechMode.balanced:
        return 'Места и факты, оптимально';
      case SpeechMode.talkative:
        return 'Частые факты и места';
    }
  }

  /// Минимальный интервал между любыми речевыми событиями (секунды)
  int get minSpeechIntervalSeconds {
    switch (this) {
      case SpeechMode.quiet:
        return 120;
      case SpeechMode.balanced:
        return 90;
      case SpeechMode.talkative:
        return 60;
    }
  }

  /// Интервал для общего факта, если нет POI (секунды). null = нет общих фактов
  int? get factIntervalSeconds {
    switch (this) {
      case SpeechMode.quiet:
        return null;
      case SpeechMode.balanced:
        return 120;
      case SpeechMode.talkative:
        return 60;
    }
  }

  /// Максимум POI в кластере за clusterWindowSeconds
  int get maxPoiPerCluster {
    switch (this) {
      case SpeechMode.quiet:
        return 2;
      case SpeechMode.balanced:
        return 3;
      case SpeechMode.talkative:
        return 4;
    }
  }

  /// Окно кластера (секунды) – общее для всех режимов
  int get clusterWindowSeconds => 120;
}