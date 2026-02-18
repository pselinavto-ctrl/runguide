import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'kalman_filter.dart';

class LocationService {
  final KalmanFilter _kalman = KalmanFilter();
  
  Position? _rawPosition;
  LatLng? _filteredPosition;
  DateTime? _lastUpdateTime;
  
  static const double _maxJumpMeters = 30.0;
  
  // Периодическая проверка GPS
  Timer? _gpsCheckTimer;
  bool _isWaitingForGps = false;
  
  Function(LatLng filtered, Position raw)? onLocationUpdate;
  Function(String error)? onError;
  Function()? onGpsDisabled;
  Function()? onGpsEnabled; // Новый колбэк когда GPS включился

  /// Проверка и запрос разрешений с автоматическим переходом в настройки
  Future<bool> checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    
    if (!serviceEnabled) {
      onError?.call('GPS отключён');
      onGpsDisabled?.call();
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      onError?.call('Разрешение отклонено');
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      onError?.call('Разрешение отклонено навсегда');
      await Geolocator.openAppSettings();
      return false;
    }

    return true;
  }

  /// Открыть настройки GPS
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// Запустить периодическую проверку GPS
  void startGpsCheckLoop() {
    _isWaitingForGps = true;
    _gpsCheckTimer?.cancel();
    
    _gpsCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_isWaitingForGps) {
        timer.cancel();
        return;
      }
      
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        timer.cancel();
        _isWaitingForGps = false;
        onGpsEnabled?.call(); // Уведомляем что GPS включился
      }
    });
  }

  /// Остановить проверку GPS
  void stopGpsCheckLoop() {
    _isWaitingForGps = false;
    _gpsCheckTimer?.cancel();
    _gpsCheckTimer = null;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));
      
      _rawPosition = position;
      _kalman.init(position.latitude, position.longitude, position.accuracy);
      _filteredPosition = LatLng(position.latitude, position.longitude);
      _lastUpdateTime = DateTime.now();
      
      return position;
    } catch (e) {
      onError?.call('Ошибка GPS: $e');
      return null;
    }
  }

  Stream<FilteredPosition> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).map((position) => _processPosition(position));
  }

  FilteredPosition _processPosition(Position position) {
    if (_rawPosition != null && _isGpsJump(_rawPosition!, position)) {
      return FilteredPosition(
        raw: position,
        filtered: _filteredPosition ?? LatLng(position.latitude, position.longitude),
        isJump: true,
        heading: _kalman.heading,
      );
    }

    _rawPosition = position;

    final now = DateTime.now();
    final dt = _lastUpdateTime != null
        ? now.difference(_lastUpdateTime!).inMilliseconds / 1000.0
        : 1.0;
    _lastUpdateTime = now;

    _filteredPosition = _kalman.process(
      position.latitude,
      position.longitude,
      position.accuracy.clamp(5.0, 30.0),
      dt,
    );
    
    _kalman.setSpeed(position.speed);

    return FilteredPosition(
      raw: position,
      filtered: _filteredPosition!,
      isJump: false,
      heading: _kalman.heading,
    );
  }

  bool _isGpsJump(Position prev, Position next) {
    final distance = Geolocator.distanceBetween(
      prev.latitude, prev.longitude,
      next.latitude, next.longitude,
    );
    return distance > _maxJumpMeters && prev.speed < 2.0;
  }

  void reset() {
    _kalman.reset();
    _rawPosition = null;
    _filteredPosition = null;
    _lastUpdateTime = null;
  }

  void dispose() {
    stopGpsCheckLoop();
    reset();
  }

  LatLng? get currentPosition => _filteredPosition;
  double get heading => _kalman.heading;
  bool get isWaitingForGps => _isWaitingForGps;
}

class FilteredPosition {
  final Position raw;
  final LatLng filtered;
  final bool isJump;
  final double heading;

  FilteredPosition({
    required this.raw,
    required this.filtered,
    required this.isJump,
    required this.heading,
  });
}