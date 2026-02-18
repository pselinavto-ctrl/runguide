class AppConstants {
  // API
  static const String apiUrl = 'https://partsview.ru/runguide';
  
  // Координаты по умолчанию
  static const double defaultLat = 47.2228;
  static const double defaultLon = 39.7150;
  static const double defaultZoom = 15.0;
  
  // Настройки бега
  static const double runningMet = 9.8;
  static const double defaultWeightKg = 70.0;
  
  // Настройки POI и фактов
  static const int poiRadius = 5000;              // Радиус поиска POI в метрах (5 км)
  static const int poiTriggerRadius = 5000;        // Радиус срабатывания POI в метрах
  static const int generalFactIntervalMinutes = 2; // Интервал между фактами в минутах
}