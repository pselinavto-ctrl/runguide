import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'runguide_channel',
      initialNotificationTitle: 'RunGuide',
      initialNotificationContent: 'Тренировка активна',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: _onStart,
      onBackground: _onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  service.on('startRun').listen((_) {
    print('[BG] Старт тренировки');
  });

  _startLocationStream(service);
}

@pragma('vm:entry-point')
bool _onIosBackground(ServiceInstance service) {
  return true;
}

void _startLocationStream(ServiceInstance service) {
  print('[BG] Запуск GPS потока...');
  
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    ),
  ).listen(
    (Position position) {
      service.invoke('locationUpdate', {
        'lat': position.latitude,
        'lon': position.longitude,
        'timestamp': position.timestamp?.toIso8601String() ?? DateTime.now().toIso8601String(),
        'heading': position.heading,
        'speed': position.speed,
        'accuracy': position.accuracy,
      });
    },
    onError: (error) {
      print('[BG] Ошибка GPS: $error');
      Future.delayed(const Duration(seconds: 5), () {
        _startLocationStream(service);
      });
    },
    cancelOnError: false,
  );
}

Future<bool> startService() async {
  final service = FlutterBackgroundService();
  return await service.startService();
}

Future<void> stopService() async {
  final service = FlutterBackgroundService();
  service.invoke('stopService');
}

Future<bool> isServiceRunning() async {
  final service = FlutterBackgroundService();
  return await service.isRunning();
}