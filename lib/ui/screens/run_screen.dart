import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../../services/location_service.dart';
import '../../services/kalman_filter.dart';
import '../../services/tts_service.dart';
import '../../services/background_service.dart' as bg;
import '../../services/run_repository.dart';
import '../../services/api_service.dart';
import '../../services/map_cache_service.dart';
import '../../services/map_cache_dialog.dart';
import '../../services/settings_service.dart';
import '../../core/speech_mode.dart';
import '../../data/models/route_point.dart';
import '../../data/models/run_session.dart';
import '../../data/models/poi.dart';
import '../../core/constants.dart';
import 'run_result_screen.dart';

enum RunState { initializing, searchingGps, ready, countdown, running, paused, finished }

class RunScreen extends StatefulWidget {
  const RunScreen({super.key});
  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final TtsService _ttsService = TtsService();
  final RunRepository _repository = RunRepository();
  final ApiService _apiService = ApiService();
  final SettingsService _settingsService = SettingsService();

  RunState _state = RunState.initializing;
  Position? _currentPosition;
  LatLng? _filteredPosition;
  double _heading = 0.0;

  final List<RoutePoint> _route = [];
  double _totalDistance = 0.0;
  Duration _elapsedTime = Duration.zero;
  int _factsCount = 0;

  Timer? _runTimer;
  StreamSubscription? _positionSubscription;
  Timer? _countdownTimer;
  int _countdown = 3;

  final KalmanFilter _kalman = KalmanFilter();
  DateTime? _lastKalmanTime;
  bool _followUser = true;

  bool _gpsDialogShown = false;

  // OSM POI
  List<OsmPoi> _nearbyPois = [];
  Set<int> _visitedOsmIds = {};
  bool _isSpeaking = false;

  // Кэш карты
  bool _hasCache = false;

  // Для ограничения частоты общих фактов (только статистика)
  DateTime? _lastGeneralFactTime;

  // НОВЫЕ ПЕРЕМЕННЫЕ ДЛЯ РЕЖИМОВ РЕЧИ
  late SpeechMode _speechMode;
  DateTime? _lastSpeechTime;      // время последней любой речи
  DateTime? _lastPoiSpeechTime;   // время последнего POI в кластере
  int _poiSpokenInCluster = 0;
  Timer? _speechTimer;             // таймер для проверки речи
  DateTime? _startTime;            // время начала тренировки (для первого факта)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locationService.onGpsEnabled = _onGpsAutoEnabled;
    _initApp();
  }

  Future<void> _initApp() async {
    await _repository.init();
    await _ttsService.init();
    await bg.initBackgroundService();
    await _apiService.init();
    _speechMode = await _settingsService.getSpeechMode();   // загружаем режим

    final hasPermission = await _locationService.checkPermission();
    if (!hasPermission) {
      setState(() => _state = RunState.searchingGps);
      if (mounted && !_gpsDialogShown) {
        _gpsDialogShown = true;
        _showGpsDialog();
      }
      return;
    }

    setState(() => _state = RunState.searchingGps);

    final position = await _locationService.getCurrentPosition();
    if (position != null && mounted) {
      setState(() {
        _currentPosition = position;
        _filteredPosition = LatLng(position.latitude, position.longitude);
        _state = RunState.ready;
      });
      _mapController.move(_filteredPosition!, 16);
      _detectCity(position.latitude, position.longitude);
      _checkCache();
    }
  }

  Future<void> _detectCity(double lat, double lon) async {
    final city = await _apiService.getCity(lat, lon);
    if (city != null) {
      print('🏙️ Город определён: ${city.name}');
      _apiService.setCityId(city.id);
      _apiService.setCityName(city.name);
    }
  }

  Future<void> _checkCache() async {
    try {
      final hasTiles = await MapCacheService.hasCache();
      if (mounted) {
        setState(() {
          _hasCache = hasTiles;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Cache check: $e');
    }
  }

  void _onGpsAutoEnabled() {
    if (!mounted) return;
    setState(() => _state = RunState.searchingGps);

    _locationService.getCurrentPosition().then((position) {
      if (position != null && mounted) {
        setState(() {
          _currentPosition = position;
          _filteredPosition = LatLng(position.latitude, position.longitude);
          _state = RunState.ready;
        });
        _mapController.move(_filteredPosition!, 16);
        _detectCity(position.latitude, position.longitude);
        _checkCache();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS определён! Готов к старту.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _showGpsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.gps_off, color: Colors.red.shade400),
            const SizedBox(width: 12),
            const Text('GPS отключён'),
          ],
        ),
        content: const Text(
          'Для работы приложения необходима геолокация.\n\n'
          '1. Нажмите "Открыть настройки"\n'
          '2. Включите геолокацию\n'
          '3. Вернитесь в приложение',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _locationService.openLocationSettings();
              _locationService.startGpsCheckLoop();
            },
            child: const Text('Открыть настройки'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _checkGpsAndRetry();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Проверить GPS'),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _state == RunState.searchingGps) {
      _checkGpsAndRetry();
    } else if (state == AppLifecycleState.paused &&
        _state == RunState.searchingGps &&
        !_locationService.isWaitingForGps) {
      _locationService.startGpsCheckLoop();
    }
  }

  Future<void> _checkGpsAndRetry() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (serviceEnabled) {
      _locationService.stopGpsCheckLoop();
      setState(() => _state = RunState.searchingGps);

      final position = await _locationService.getCurrentPosition();
      if (position != null && mounted) {
        setState(() {
          _currentPosition = position;
          _filteredPosition = LatLng(position.latitude, position.longitude);
          _state = RunState.ready;
        });
        _mapController.move(_filteredPosition!, 16);
        _detectCity(position.latitude, position.longitude);
        _checkCache();
      }
    } else {
      _locationService.startGpsCheckLoop();
      if (mounted && !_gpsDialogShown) {
        _gpsDialogShown = true;
        _showGpsDialog();
      }
    }
  }

  @override
  void dispose() {
    _speechTimer?.cancel();
    _runTimer?.cancel();
    _positionSubscription?.cancel();
    _countdownTimer?.cancel();
    _locationService.dispose();
    _apiService.dispose();
    _ttsService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _state = RunState.countdown;
      _countdown = 3;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        _startRun();
      }
    });
  }

  /// Определяет время суток (утро, день, вечер, ночь)
  String _getTimeOfDay() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'утро';
    if (hour >= 12 && hour < 18) return 'день';
    if (hour >= 18 && hour < 23) return 'вечер';
    return 'ночь';
  }

  /// Формирует персонализированное приветствие
  Future<String> _buildGreeting() async {
    final timeOfDay = _getTimeOfDay();
    final city = _apiService.currentCityName ?? 'твоём городе';
    
    final greeting = await _apiService.getGreeting(
      cityName: city,
      timeOfDay: timeOfDay,
    );

    return greeting ?? 'Доброе $timeOfDay! Сегодня в $city. Я уверен, мы отлично побегаем и много чего узнаем!';
  }

  Future<void> _startRun() async {
    setState(() {
      _state = RunState.running;
      _route.clear();
      _totalDistance = 0.0;
      _elapsedTime = Duration.zero;
      _factsCount = 0;
      _kalman.reset();
      _visitedOsmIds.clear();
      _isSpeaking = false;
      _lastGeneralFactTime = null;
      _lastSpeechTime = null;
      _lastPoiSpeechTime = null;
      _poiSpokenInCluster = 0;
      _startTime = DateTime.now(); // запоминаем время старта
    });

    await bg.startService();
    _positionSubscription = _locationService.getPositionStream().listen(_onPositionUpdate);
    FlutterBackgroundService().on('locationUpdate').listen(_onBackgroundLocation);

    _runTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state == RunState.running) {
        setState(() => _elapsedTime += const Duration(seconds: 1));
      }
    });

    _startSpeechTimer();

    if (_filteredPosition != null) {
      _loadNearbyPois(_filteredPosition!.latitude, _filteredPosition!.longitude);
    }

    // Приветствие
    String greeting = await _buildGreeting();
    await _ttsService.speak(greeting);
    await Future.delayed(const Duration(milliseconds: 800));

    await _ttsService.speak('Тренировка началась. Приятного бега!');

    if (_filteredPosition != null) {
      _route.add(RoutePoint(
        lat: _filteredPosition!.latitude,
        lon: _filteredPosition!.longitude,
        timestamp: DateTime.now(),
        speed: 0,
      ));
    }
  }

  Future<void> _loadNearbyPois(double lat, double lon) async {
    print('🗺️ Загрузка OSM POI: lat=$lat, lon=$lon');

    final pois = await _apiService.getOsmPois(lat, lon, radius: AppConstants.poiRadius);

    if (pois.isNotEmpty) {
      pois.sort((a, b) => a.distance.compareTo(b.distance));

      setState(() {
        _nearbyPois = pois;
      });

      print('✅ OSM POI загружено: ${pois.length}');
      for (int i = 0; i < pois.length && i < 5; i++) {
        final poi = pois[i];
        print('📍 POI #$i: ${poi.name} (${poi.distance}м, категория: ${poi.category})');
      }
    } else {
      print('⚠️ OSM POI не найдены');
    }
  }

  void _startSpeechTimer() {
    _speechTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_state != RunState.running || _isSpeaking) return;
      await _trySpeakSomething();
    });
  }

  /// Проверяет, можно ли сейчас говорить с учётом режима
  bool _canSpeak({bool isPoi = false}) {
    if (_isSpeaking) return false;

    final now = DateTime.now();
    final minInterval = _speechMode.minSpeechIntervalSeconds;

    if (_lastSpeechTime != null) {
      final secondsSinceLast = now.difference(_lastSpeechTime!).inSeconds;
      if (secondsSinceLast < minInterval) return false;
    }

    if (isPoi) {
      if (_poiSpokenInCluster >= _speechMode.maxPoiPerCluster) {
        if (_lastPoiSpeechTime != null) {
          final secondsSinceLastPoi = now.difference(_lastPoiSpeechTime!).inSeconds;
          if (secondsSinceLastPoi < _speechMode.clusterWindowSeconds) {
            return false;
          } else {
            _poiSpokenInCluster = 0;
          }
        }
      }
    }

    return true;
  }

  /// Возвращает ближайший неозвученный POI в радиусе (без проверки интервала)
  Future<OsmPoi?> _findBestUnvisitedPoi() async {
    if (_filteredPosition == null) return null;
    OsmPoi? best;
    double minDist = double.infinity;

    for (final poi in _nearbyPois) {
      final distance = Geolocator.distanceBetween(
        _filteredPosition!.latitude,
        _filteredPosition!.longitude,
        poi.lat,
        poi.lon,
      );

      if (distance >= AppConstants.poiTriggerRadius) continue;

      if (_visitedOsmIds.contains(poi.osmId)) continue;

      final wasVisited = await _repository.wasPoiVisited(poi.osmId);
      if (wasVisited) {
        setState(() {
          _visitedOsmIds.add(poi.osmId);
        });
        continue;
      }

      if (distance < minDist) {
        minDist = distance;
        best = poi;
      }
    }
    return best;
  }

  /// Проверяем POI при каждом движении
  Future<void> _checkNearbyPoisForAnnouncement() async {
    if (_isSpeaking || _filteredPosition == null) return;

    final sortedPois = List<OsmPoi>.from(_nearbyPois)
      ..sort((a, b) {
        final distA = Geolocator.distanceBetween(
          _filteredPosition!.latitude,
          _filteredPosition!.longitude,
          a.lat,
          a.lon,
        );
        final distB = Geolocator.distanceBetween(
          _filteredPosition!.latitude,
          _filteredPosition!.longitude,
          b.lat,
          b.lon,
        );
        return distA.compareTo(distB);
      });

    for (final poi in sortedPois) {
      final distance = Geolocator.distanceBetween(
        _filteredPosition!.latitude,
        _filteredPosition!.longitude,
        poi.lat,
        poi.lon,
      );

      if (distance >= AppConstants.poiTriggerRadius) continue;

      if (_visitedOsmIds.contains(poi.osmId)) continue;

      final wasVisited = await _repository.wasPoiVisited(poi.osmId);
      if (wasVisited) {
        setState(() {
          _visitedOsmIds.add(poi.osmId);
        });
        continue;
      }

      if (!_canSpeak(isPoi: true)) break;

      await _speakOsmPoiFact(poi);
      break;
    }
  }

  /// Пытается что-то сказать: сначала POI, если нет – общий факт (если разрешено)
  Future<void> _trySpeakSomething() async {
    if (_isSpeaking) return;

    if (!_canSpeak()) return;

    final bestPoi = await _findBestUnvisitedPoi();
    if (bestPoi != null && _canSpeak(isPoi: true)) {
      await _speakOsmPoiFact(bestPoi);
      return;
    }

    final factInterval = _speechMode.factIntervalSeconds;
    if (factInterval != null) {
      Duration sinceLastOrStart;
      if (_lastSpeechTime != null) {
        sinceLastOrStart = DateTime.now().difference(_lastSpeechTime!);
      } else if (_startTime != null) {
        sinceLastOrStart = DateTime.now().difference(_startTime!);
      } else {
        sinceLastOrStart = Duration.zero;
      }
      if (sinceLastOrStart.inSeconds >= factInterval) {
        await _speakGeneralFact();
      }
    }
  }

  Future<void> _speakOsmPoiFact(OsmPoi poi) async {
    if (_isSpeaking) return;
    _isSpeaking = true;

    try {
      print('🎯 Озвучиваем POI: ${poi.name} (категория: ${poi.category})');

      if (await _repository.wasPoiVisited(poi.osmId)) {
        print('⏭️ POI уже озвучивался ранее: ${poi.name}');
        setState(() {
          _visitedOsmIds.add(poi.osmId);
        });
        return;
      }

      final factText = await _apiService.getOsmPoiFact(
        osmId: poi.osmId,
        poiName: poi.name,
        category: poi.category,
        cityName: _apiService.currentCityName,
      );

      if (factText != null) {
        setState(() {
          _factsCount++;
          _visitedOsmIds.add(poi.osmId);
          _lastSpeechTime = DateTime.now();
          _lastPoiSpeechTime = DateTime.now();
          _poiSpokenInCluster++;
        });

        await _repository.savePoiVisit(poi.osmId, poi.name, factText: factText);

        await _ttsService.speak(poi.name);
        await Future.delayed(const Duration(milliseconds: 500));
        await _ttsService.speak(factText);

        print('✅ POI озвучен: ${poi.name}');
      } else {
        print('❌ Не удалось получить факт для POI: ${poi.name}');
      }
    } finally {
      _isSpeaking = false;
    }
  }

  Future<void> _speakGeneralFact() async {
    if (_isSpeaking) return;
    _isSpeaking = true;

    try {
      print('📢 Озвучиваем общий факт');

      final categories = ['sport', 'science', 'general'];
      final category = categories[_factsCount % categories.length];

      final factText = await _apiService.getGeneratedFact(
        type: 'general',
        category: category,
      );

      if (factText != null) {
        setState(() {
          _factsCount++;
          _lastGeneralFactTime = DateTime.now();
          _lastSpeechTime = DateTime.now();
        });
        await _ttsService.speak(factText);
        print('✅ Общий факт озвучен: $factText');
      } else {
        print('❌ Не удалось получить общий факт');
      }
    } finally {
      _isSpeaking = false;
    }
  }

  void _pauseRun() {
    _runTimer?.cancel();
    _positionSubscription?.pause();
    _speechTimer?.cancel();
    setState(() => _state = RunState.paused);
    _ttsService.speak('Тренировка на паузе');
  }

  void _resumeRun() {
    _runTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state == RunState.running) {
        setState(() => _elapsedTime += const Duration(seconds: 1));
      }
    });
    _positionSubscription?.resume();
    _startSpeechTimer();
    setState(() => _state = RunState.running);
    _ttsService.speak('Продолжаем');
  }

  Future<void> _stopRun() async {
    _runTimer?.cancel();
    _positionSubscription?.cancel();
    _speechTimer?.cancel();
    await bg.stopService();

    final session = RunSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      distance: _totalDistance / 1000,
      duration: _elapsedTime.inSeconds,
      factsCount: _factsCount,
      route: _route,
      calories: _calculateCalories(),
    );

    await _repository.saveSession(session);
    await _ttsService.speak(
      'Тренировка окончена. '
      'Дистанция: ${(_totalDistance / 1000).toStringAsFixed(2)} километра. '
      'Услышано фактов: $_factsCount',
    );

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => RunResultScreen(session: session),
        ),
      );
    }
  }

  void _resetForNewRun() {
    setState(() {
      _state = RunState.ready;
      _route.clear();
      _totalDistance = 0.0;
      _elapsedTime = Duration.zero;
      _factsCount = 0;
      _kalman.reset();
      _visitedOsmIds.clear();
      _nearbyPois.clear();
      _lastGeneralFactTime = null;
      _lastSpeechTime = null;
      _lastPoiSpeechTime = null;
      _poiSpokenInCluster = 0;
      _startTime = null;
    });
    _repository.clearActiveRoute();
  }

  void _onPositionUpdate(FilteredPosition data) {
    if (_state != RunState.running || data.isJump) return;

    setState(() {
      _currentPosition = data.raw;
      _filteredPosition = data.filtered;
      _heading = data.heading;
      _route.add(RoutePoint(
        lat: data.filtered.latitude,
        lon: data.filtered.longitude,
        timestamp: data.raw.timestamp ?? DateTime.now(),
        speed: data.raw.speed,
      ));
    });

    if (_route.length >= 2) {
      final last = _route[_route.length - 2];
      final distance = Geolocator.distanceBetween(
        last.lat,
        last.lon,
        data.filtered.latitude,
        data.filtered.longitude,
      );
      setState(() => _totalDistance += distance);
    }

    if (_followUser) _moveCamera(data.filtered, data.raw.speed);

    _checkNearbyPoisForAnnouncement();

    final now = DateTime.now();
    if (_lastSpeechTime != null && now.difference(_lastSpeechTime!).inSeconds > 30) {
      _loadNearbyPois(data.filtered.latitude, data.filtered.longitude);
    }
  }

  void _onBackgroundLocation(dynamic data) {
    if (!mounted || data['lat'] == null) return;

    final lat = data['lat'] as double;
    final lon = data['lon'] as double;
    final speed = (data['speed'] as num?)?.toDouble() ?? 0.0;
    final now = DateTime.now();
    final dt = _lastKalmanTime != null
        ? now.difference(_lastKalmanTime!).inMilliseconds / 1000.0
        : 1.0;
    _lastKalmanTime = now;

    final filtered = _kalman.process(lat, lon, 10.0, dt);

    setState(() {
      _filteredPosition = filtered;
      _heading = _kalman.heading;
      if (_state == RunState.running) {
        _route.add(RoutePoint(
          lat: filtered.latitude,
          lon: filtered.longitude,
          timestamp: DateTime.now(),
          speed: speed,
        ));
      }
    });
  }

  void _moveCamera(LatLng position, double speed) {
    final distance = math.min(speed * 0.3, 4.0);
    final rad = _heading * math.pi / 180;
    final dLat = (distance / 111111) * math.cos(rad);
    final dLon = (distance / (111111 * math.cos(position.latitude * math.pi / 180))) * math.sin(rad);
    final target = LatLng(position.latitude + dLat, position.longitude + dLon);
    _mapController.move(target, _calculateZoom(speed));
  }

  double _calculateZoom(double speed) {
    if (speed < 2.0) return 17.0;
    if (speed < 4.0) return 16.5;
    if (speed < 6.0) return 16.0;
    return 15.5;
  }

  String get _currentPace {
    if (_totalDistance <= 0) return '--';
    final secondsPerKm = _elapsedTime.inSeconds / (_totalDistance / 1000);
    final minutes = (secondsPerKm / 60).floor();
    final seconds = (secondsPerKm % 60).round();
    return '$minutes:${seconds.toString().padLeft(2, "0")}';
  }

  int _calculateCalories() {
    final hours = _elapsedTime.inSeconds / 3600;
    return (AppConstants.runningMet * AppConstants.defaultWeightKg * hours).round();
  }

  // --- Загрузка карты (кнопка) ---
  Future<void> _downloadMapCache() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Местоположение ещё не определено'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.only(bottom: 100, left: 10, right: 10), // Чтобы не залезала на кнопку
        ),
      );
      return;
    }

    if (_hasCache) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Карта для этого района уже загружена'),
          backgroundColor: Colors.blue,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.only(bottom: 100, left: 10, right: 10),
        ),
      );
      return;
    }

    try {
      final success = await showMapCacheDialog(
        context,
        position: _currentPosition,
        radiusKm: 10.0,
      );

      if (success == true) {
        await _checkCache();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Карта загружена! Теперь работает без интернета.'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.only(bottom: 100, left: 10, right: 10), // Чтобы не залезала на кнопку
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 100, left: 10, right: 10),
          ),
        );
      }
    }
  }

  Widget _buildCacheButton() {
    // Показываем кнопку только в состояниях, когда тренировка еще не началась
    if (_state != RunState.initializing && 
        _state != RunState.searchingGps && 
        _state != RunState.ready) {
      return const SizedBox.shrink();
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final topPosition = statusBarHeight + (screenHeight * 0.40);

    return Positioned(
      top: topPosition,
      right: 16,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        color: _hasCache ? Colors.green : Colors.deepPurple,
        child: InkWell(
          onTap: _downloadMapCache,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 64,
            height: 80,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _hasCache ? Icons.offline_bolt : Icons.download,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(height: 2),
                if (!_hasCache) ...[
                  const Text(
                    'СКАЧАТЬ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Text(
                    'КАРТУ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Text(
                    '~30 МБ',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 8,
                      height: 1.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  const Text(
                    'ЕСТЬ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'КАРТА',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 8,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),

          if (_state == RunState.running || _state == RunState.paused)
            _buildStatsPanel(),
            
          if (_state == RunState.searchingGps)
            _buildGpsIndicator(),
            
          if (_state == RunState.ready)
            _buildReadyIndicator(),
            
          if (_state == RunState.countdown)
            _buildCountdown(),

          _buildControlButtons(),

          // Кнопка кэша управляется внутри своего виджета
          _buildCacheButton(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _filteredPosition ?? const LatLng(AppConstants.defaultLat, AppConstants.defaultLon),
        initialZoom: AppConstants.defaultZoom,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.runguide.app',
        ),
        if (_route.isNotEmpty) PolylineLayer(polylines: _buildSpeedPolylines()),
        if (_filteredPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _filteredPosition!,
                width: 40,
                height: 40,
                child: Transform.rotate(
                  angle: _heading * math.pi / 180,
                  child: const Icon(Icons.navigation, color: Colors.deepPurple, size: 32),
                ),
              ),
            ],
          ),
        if (_nearbyPois.isNotEmpty)
          MarkerLayer(
            markers: _nearbyPois.map((poi) => Marker(
                  point: poi.location,
                  width: 30,
                  height: 30,
                  child: Icon(
                    Icons.location_on,
                    color: _visitedOsmIds.contains(poi.osmId) ? Colors.grey : Colors.red,
                    size: 30,
                  ),
                )).toList(),
          ),
      ],
    );
  }

  List<Polyline> _buildSpeedPolylines() {
    final polylines = <Polyline>[];

    for (int i = 1; i < _route.length; i++) {
      final p1 = _route[i - 1];
      final p2 = _route[i];

      Color color;
      final speed = p2.speed;

      if (speed < 2.0) {
        color = Colors.green;
      } else if (speed < 4.0) {
        color = Colors.blue;
      } else if (speed < 5.5) {
        color = Colors.orange;
      } else {
        color = Colors.red;
      }

      polylines.add(Polyline(
        points: [LatLng(p1.lat, p1.lon), LatLng(p2.lat, p2.lon)],
        color: color,
        strokeWidth: 5,
      ));
    }

    return polylines;
  }

  Widget _buildStatsPanel() {
    return Positioned(
      top: 50,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              '${(_totalDistance / 1000).toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const Text('КМ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(Icons.access_time, _formatDuration(_elapsedTime), 'Время'),
                _buildStatItem(Icons.speed, _currentPace, 'Темп'),
                _buildStatItem(Icons.local_fire_department, _calculateCalories().toString(), 'Ккал'),
                _buildStatItem(Icons.lightbulb, _factsCount.toString(), 'Фактов'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(children: [
      Icon(icon, color: Colors.white70, size: 20),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500)),
    ]);
  }

  // --- УНИФИЦИРОВАННЫЙ СТИЛЬ ИНДИКАТОРОВ ---

  Widget _buildGpsIndicator() {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, spreadRadius: 2),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade300),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Определяем местоположение...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadyIndicator() {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.green.shade600.withOpacity(0.9),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(color: Colors.green.shade800.withOpacity(0.3), blurRadius: 10, spreadRadius: 1),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Text(
                'Готов к старту',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdown() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.85),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_countdown > 0) ...[
                // Большая цифра в круге
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.deepPurple.shade300, width: 4),
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple.shade600, Colors.deepPurple.shade900],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withOpacity(0.5),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _countdown.toString(),
                      style: const TextStyle(
                        fontSize: 80,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  'Приготовьтесь!',
                  style: TextStyle(
                    fontSize: 22,
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
              ] else ...[
                // Надпись СТАРТ
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade500,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.green.shade600.withOpacity(0.6), blurRadius: 20, spreadRadius: 2),
                    ],
                  ),
                  child: const Text(
                    'СТАРТ!',
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  'Начинайте бег!',
                  style: TextStyle(
                    fontSize: 22,
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Positioned(
      bottom: 30,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_state == RunState.ready)
            ElevatedButton(
              onPressed: _startCountdown,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(180, 65),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 8,
                shadowColor: Colors.green.withOpacity(0.4),
              ),
              child: const Text('СТАРТ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          if (_state == RunState.running)
            ElevatedButton(
              onPressed: _pauseRun,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(180, 65),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 8,
                shadowColor: Colors.orange.withOpacity(0.4),
              ),
              child: const Text('ПАУЗА', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          if (_state == RunState.paused)
            Row(children: [
              ElevatedButton(
                onPressed: _resumeRun,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(130, 65),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 8,
                ),
                child: const Text('ДАЛЬШЕ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _stopRun,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(130, 65),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 8,
                ),
                child: const Text('СТОП', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ]),
          if (_state == RunState.finished)
            ElevatedButton(
              onPressed: _resetForNewRun,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(220, 65),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 8,
              ),
              child: const Text('Новая тренировка', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}