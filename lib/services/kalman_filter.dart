import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class KalmanFilter {
  double _lat = 0.0;
  double _lon = 0.0;
  double _heading = 0.0;
  double _speed = 0.0;
  double _variance = -1.0;
  
  // Для сглаживания heading
  final List<double> _headingHistory = [];
  static const int _headingHistorySize = 5;
  
  // Для сглаживания позиции
  final List<LatLng> _positionHistory = [];
  static const int _positionHistorySize = 3;
  
  static const double _minAccuracy = 5.0;
  static const double _q = 0.5; // Уменьшил шум процесса
  
  bool _initialized = false;

  void init(double lat, double lon, double accuracy) {
    _lat = lat;
    _lon = lon;
    _variance = accuracy * accuracy;
    _initialized = true;
    _headingHistory.clear();
    _positionHistory.clear();
  }

  LatLng process(double lat, double lon, double accuracy, double dt) {
    if (!_initialized) {
      init(lat, lon, accuracy);
      return LatLng(lat, lon);
    }

    accuracy = math.max(accuracy, _minAccuracy);

    // Предсказание состояния
    if (dt > 0 && _speed > 0.5) {
      final distance = _speed * dt;
      final dLat = (distance / 111111) * math.cos(_heading * math.pi / 180);
      final dLon = (distance / (111111 * math.cos(_lat * math.pi / 180))) * 
                   math.sin(_heading * math.pi / 180);
      _lat += dLat;
      _lon += dLon;
    }

    _variance += dt * _q;
    final k = _variance / (_variance + accuracy * accuracy);
    
    _lat += k * (lat - _lat);
    _lon += k * (lon - _lon);
    _variance = (1 - k) * _variance;

    // Вычисляем heading с сглаживанием
    if (_speed > 0.5) {
      final newHeading = _calculateBearing(_lat, _lon, lat, lon);
      _smoothHeading(newHeading);
    }

    // Добавляем в историю позиций для сглаживания
    _positionHistory.add(LatLng(_lat, _lon));
    if (_positionHistory.length > _positionHistorySize) {
      _positionHistory.removeAt(0);
    }

    // Возвращаем сглаженную позицию
    return _getSmoothedPosition();
  }

  LatLng _getSmoothedPosition() {
    if (_positionHistory.isEmpty) return LatLng(_lat, _lon);
    
    double sumLat = 0;
    double sumLon = 0;
    for (final pos in _positionHistory) {
      sumLat += pos.latitude;
      sumLon += pos.longitude;
    }
    
    return LatLng(
      sumLat / _positionHistory.length,
      sumLon / _positionHistory.length,
    );
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * math.pi / 180;
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;

    final y = math.sin(dLon) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
              math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);

    var bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  void _smoothHeading(double newHeading) {
    // Нормализуем разницу углов (учитываем переход через 0/360)
    double smoothHeading = newHeading;
    
    if (_headingHistory.isNotEmpty) {
      final lastHeading = _headingHistory.last;
      var diff = newHeading - lastHeading;
      
      // Нормализуем разницу в диапазон [-180, 180]
      while (diff > 180) diff -= 360;
      while (diff < -180) diff += 360;
      
      // Плавный переход
      smoothHeading = lastHeading + diff * 0.3;
    }
    
    // Нормализуем результат
    while (smoothHeading < 0) smoothHeading += 360;
    while (smoothHeading >= 360) smoothHeading -= 360;
    
    _headingHistory.add(smoothHeading);
    if (_headingHistory.length > _headingHistorySize) {
      _headingHistory.removeAt(0);
    }
    
    // Усредняем по истории
    double sum = 0;
    for (final h in _headingHistory) {
      sum += h;
    }
    _heading = sum / _headingHistory.length;
  }

  void setSpeed(double speed) {
    // Сглаживание скорости
    _speed = _speed * 0.7 + speed * 0.3;
  }

  double get heading => _heading;
  LatLng get position => LatLng(_lat, _lon);
  double get accuracyRadius => math.sqrt(_variance);

  void reset() {
    _lat = 0.0;
    _lon = 0.0;
    _heading = 0.0;
    _speed = 0.0;
    _variance = -1.0;
    _initialized = false;
    _headingHistory.clear();
    _positionHistory.clear();
  }
}