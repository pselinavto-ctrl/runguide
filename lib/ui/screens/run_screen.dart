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
  Timer? _factTimer;
  DateTime? _lastFactTime;
  bool _isSpeaking = false;

  // Кэш карты
  bool _hasCache = false;

  // Для ограничения частоты общих фактов
  DateTime? _lastGeneralFactTime; // ← ДОБАВЛЕНО

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
    _runTimer?.cancel();
    _positionSubscription?.cancel();
    _countdownTimer?.cancel();
    _factTimer?.cancel();
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
      _lastGeneralFactTime = null; // Сброс при старте новой тренировки
    });

    await bg.startService();
    _positionSubscription = _locationService.getPositionStream().listen(_onPositionUpdate);
    FlutterBackgroundService().on('locationUpdate').listen(_onBackgroundLocation);

    _runTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state == RunState.running) {
        setState(() => _elapsedTime += const Duration(seconds: 1));
      }
    });

    _startFactTimer();

    if (_filteredPosition != null) {
      _loadNearbyPois(_filteredPosition!.latitude, _filteredPosition!.longitude);
    }

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

  void _startFactTimer() {
    _lastFactTime = DateTime.now();

    _factTimer = Timer.periodic(
      Duration(minutes: AppConstants.generalFactIntervalMinutes.toInt()),
      (_) async {
        if (_state != RunState.running || _isSpeaking) return;

        await _speakNextFact();
      },
    );
  }

  Future<void> _speakNextFact() async {
    if (_isSpeaking) return;
    _isSpeaking = true;

    try {
      OsmPoi? nearestPoi;
      double minDistance = AppConstants.poiTriggerRadius.toDouble();

      for (final poi in _nearbyPois) {
        if (_visitedOsmIds.contains(poi.osmId)) continue;

        if (_filteredPosition != null) {
          final distance = Geolocator.distanceBetween(
            _filteredPosition!.latitude,
            _filteredPosition!.longitude,
            poi.lat,
            poi.lon,
          );

          if (distance < minDistance) {
            minDistance = distance;
            nearestPoi = poi;
          }
        }
      }

      if (nearestPoi != null) {
        await _speakOsmPoiFact(nearestPoi);
      } else {
        await _speakGeneralFact();
      }
    } finally {
      _isSpeaking = false;
    }
  }

  Future<void> _speakOsmPoiFact(OsmPoi poi) async {
    print('🎯 Озвучиваем POI: ${poi.name} (категория: ${poi.category})');

    // Проверяем локальную историю
    if (await _repository.wasPoiVisited(poi.osmId)) {
      print('⏭️ POI уже озвучивался ранее: ${poi.name}');
      // ИСПРАВЛЕНО: вместо return озвучиваем общий факт
      await _speakGeneralFact();
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
      });

      await _repository.savePoiVisit(poi.osmId, poi.name, factText: factText);

      await _ttsService.speak(poi.name);
      await Future.delayed(const Duration(milliseconds: 500));
      await _ttsService.speak(factText);

      print('✅ POI озвучен: ${poi.name}');
    } else {
      print('❌ Не удалось получить факт для POI: ${poi.name}');
      // ДОБАВЛЕНО: пробуем общий факт
      await _speakGeneralFact();
    }
  }

  Future<void> _speakGeneralFact() async {
    // ДОБАВЛЕНО: проверка интервала между общими фактами (минимум 2 минуты)
    if (_lastGeneralFactTime != null) {
      final secondsSinceLast = DateTime.now().difference(_lastGeneralFactTime!).inSeconds;
      if (secondsSinceLast < 120) {
        print('⏱️ Слишком рано для общего факта ($secondsSinceLast сек)');
        return;
      }
    }

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
        _lastGeneralFactTime = DateTime.now(); // ← ДОБАВЛЕНО
      });
      await _ttsService.speak(factText);
      print('✅ Общий факт озвучен: $factText');
    } else {
      print('❌ Не удалось получить общий факт');
    }
  }

  void _pauseRun() {
    _runTimer?.cancel();
    _positionSubscription?.pause();
    _factTimer?.cancel();
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
    _startFactTimer();
    setState(() => _state = RunState.running);
    _ttsService.speak('Продолжаем');
  }

  Future<void> _stopRun() async {
    _runTimer?.cancel();
    _positionSubscription?.cancel();
    _factTimer?.cancel();
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

    // ← ДОБАВЛЕНО: Проверяем POI при каждом движении
    _checkNearbyPoisForAnnouncement();

    final now = DateTime.now();
    if (_lastFactTime != null && now.difference(_lastFactTime!).inSeconds > 30) {
      _loadNearbyPois(data.filtered.latitude, data.filtered.longitude);
      _lastFactTime = now;
    }
  }

  /// Проверяем близость к POI и озвучиваем если нужно
  Future<void> _checkNearbyPoisForAnnouncement() async {
    if (_isSpeaking || _filteredPosition == null) return;

    for (final poi in _nearbyPois) {
      // Пропускаем уже озвученные
      if (_visitedOsmIds.contains(poi.osmId)) continue;

      // Считаем расстояние до POI
      final distance = Geolocator.distanceBetween(
        _filteredPosition!.latitude,
        _filteredPosition!.longitude,
        poi.lat,
        poi.lon,
      );

      // Если в радиусе 50 метров — озвучиваем!
      if (distance < 3000.0) {
        await _speakOsmPoiFact(poi);
        break; // Озвучиваем только один POI за раз
      }
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
        const SnackBar(
          content: Text('Местоположение ещё не определено'),
          backgroundColor: Colors.orange,
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
          ),
        );
      }
    }
  }

  Widget _buildCacheButton() {
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

          if (_state != RunState.finished)
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.85), borderRadius: BorderRadius.circular(20)),
        child: Column(
          children: [
            Text(
              '${(_totalDistance / 1000).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const Text('км', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
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
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
  }

  Widget _buildGpsIndicator() {
    return Positioned(
      top: 50,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue)),
          SizedBox(width: 12),
          Text('Определяем местоположение...', style: TextStyle(color: Colors.white)),
        ]),
      ),
    );
  }

  Widget _buildReadyIndicator() {
    return Positioned(
      top: 50,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.green.withOpacity(0.9), borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.check_circle, color: Colors.white),
          SizedBox(width: 8),
          Text('Готов к старту', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _buildCountdown() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.8),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _countdown > 0 ? _countdown.toString() : 'СТАРТ!',
                style: TextStyle(
                  fontSize: 80,
                  fontWeight: FontWeight.bold,
                  color: _countdown > 0 ? Colors.yellow : Colors.green,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _countdown > 0 ? 'Приготовьтесь!' : 'Бегите!',
                style: const TextStyle(fontSize: 24, color: Colors.white),
              ),
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
                minimumSize: const Size(150, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('СТАРТ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          if (_state == RunState.running)
            ElevatedButton(
              onPressed: _pauseRun,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(150, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('ПАУЗА', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          if (_state == RunState.paused)
            Row(children: [
              ElevatedButton(
                onPressed: _resumeRun,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(120, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: const Text('ДАЛЬШЕ', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _stopRun,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(120, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: const Text('СТОП', style: TextStyle(fontSize: 18)),
              ),
            ]),
          if (_state == RunState.finished)
            ElevatedButton(
              onPressed: _resetForNewRun,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('Новая тренировка', style: TextStyle(fontSize: 18)),
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