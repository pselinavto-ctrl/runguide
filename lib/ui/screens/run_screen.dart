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
  
  // API и POI
  List<Poi> _nearbyPois = [];
  Set<int> _visitedPoiIds = {};  // Уже озвученные POI
  Timer? _poiCheckTimer;
  Timer? _generalFactTimer;
  DateTime? _lastPoiCheck;
  DateTime? _lastGeneralFact;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Устанавливаем колбэк для автоматического определения включения GPS
    _locationService.onGpsEnabled = _onGpsAutoEnabled;
    
    // Генерируем уникальный ID устройства
    _apiService.setDeviceId('device_${DateTime.now().millisecondsSinceEpoch}');
    
    _initApp();
  }

  Future<void> _initApp() async {
    await _repository.init();
    await _ttsService.init();
    await bg.initBackgroundService();
    
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
      
      // Определяем город при старте
      _detectCity(position.latitude, position.longitude);
    }
  }

  /// Определение города по координатам
  Future<void> _detectCity(double lat, double lon) async {
    final city = await _apiService.getCity(lat, lon);
    if (city != null) {
      print('🏙️ Город определён: ${city.name}');
      _apiService.setCityId(city.id);
    } else {
      print('🏙️ Город не определён, используем общие факты');
    }
  }

  /// Вызывается автоматически когда GPS включается
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
        
        // Определяем город
        _detectCity(position.latitude, position.longitude);
        
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
          '3. Вернитесь в приложение - GPS определится автоматически',
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Проверить GPS'),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_state == RunState.searchingGps) {
        _checkGpsAndRetry();
      }
    } else if (state == AppLifecycleState.paused) {
      if (_state == RunState.searchingGps && !_locationService.isWaitingForGps) {
        _locationService.startGpsCheckLoop();
      }
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
    _poiCheckTimer?.cancel();
    _generalFactTimer?.cancel();
    _locationService.dispose();
    _apiService.dispose();
    _ttsService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startCountdown() {
    setState(() { _state = RunState.countdown; _countdown = 3; });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) { setState(() => _countdown--); } 
      else { timer.cancel(); _startRun(); }
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
      _visitedPoiIds.clear();
    });
    
    await bg.startService();
    _positionSubscription = _locationService.getPositionStream().listen(_onPositionUpdate);
    FlutterBackgroundService().on('locationUpdate').listen(_onBackgroundLocation);
    
    _runTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state == RunState.running) {
        setState(() => _elapsedTime += const Duration(seconds: 1));
      }
    });
    
    // Запускаем проверку POI
    _startPoiChecking();
    
    // Запускаем периодические общие факты
    _startGeneralFactTimer();
    
    await _ttsService.speak('Тренировка началась. Приятного бега!');
    
    if (_filteredPosition != null) {
      _route.add(RoutePoint(
        lat: _filteredPosition!.latitude,
        lon: _filteredPosition!.longitude,
        timestamp: DateTime.now(),
        speed: 0
      ));
    }
  }

  /// Запуск периодической проверки POI
  void _startPoiChecking() {
    _lastPoiCheck = DateTime.now();
    
    _poiCheckTimer = Timer.periodic(
      Duration(seconds: (AppConstants.poiCheckIntervalSeconds).toInt()),
      (_) async {
        if (_state != RunState.running || _filteredPosition == null) return;
        
        // Обновляем список POI рядом
        _nearbyPois = await _apiService.getNearbyPois(
          _filteredPosition!.latitude,
          _filteredPosition!.longitude,
          radius: 200,  // Ищем в радиусе 200 метров
        );
        
        // Проверяем, не подошли ли мы к какому-то POI
        for (final poi in _nearbyPois) {
          if (poi.inRange && !_visitedPoiIds.contains(poi.id)) {
            _visitedPoiIds.add(poi.id);
            await _speakPoiFact(poi);
            break;  // Озвучиваем только один POI за раз
          }
        }
      },
    );
  }

  /// Озвучить факт о POI (через DeepSeek для уникальности)
  Future<void> _speakPoiFact(Poi poi) async {
    // Сначала пробуем DeepSeek
    String? factText = await _apiService.getGeneratedFact(
      type: 'poi',
      poiId: poi.id,
    );
    
    // Если DeepSeek не сработал - берём из базы
    if (factText == null) {
      final fact = await _apiService.getPoiFact(poi.id);
      factText = fact?.text;
    }
    
    if (factText != null) {
      setState(() => _factsCount++);
      
      // Сначала говорим название
      await _ttsService.speak(poi.name);
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Потом факт
      await _ttsService.speak(factText);
      
      // Сохраняем посещение
      _apiService.saveVisit(poi.id, null);
      
      print('🎯 Озвучен POI: ${poi.name}');
    }
  }

  /// Запуск таймера общих фактов
  void _startGeneralFactTimer() {
    _lastGeneralFact = DateTime.now();
    
    _generalFactTimer = Timer.periodic(
      Duration(minutes: AppConstants.generalFactIntervalMinutes.toInt()),
      (_) async {
        if (_state != RunState.running) return;
        
        await _speakGeneralFact();
      },
    );
  }

  /// Озвучить общий факт (через DeepSeek для уникальности)
  Future<void> _speakGeneralFact() async {
    // Чередуем категории
    final categories = ['sport', 'science', 'general'];
    final category = categories[_factsCount % categories.length];
    
    // Сначала пробуем DeepSeek для уникального факта
    String? factText = await _apiService.getGeneratedFact(
      type: 'general',
      category: category,
      cityName: 'Ростов-на-Дону',
    );
    
    // Если DeepSeek не сработал - берём из базы
    if (factText == null) {
      final fact = await _apiService.getGeneralFact(category: category);
      factText = fact?.text;
    }
    
    if (factText != null) {
      setState(() => _factsCount++);
      await _ttsService.speak(factText);
      print('📢 Озвучен факт: $factText');
    }
  }

  void _pauseRun() {
    _runTimer?.cancel();
    _positionSubscription?.pause();
    _poiCheckTimer?.cancel();
    _generalFactTimer?.cancel();
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
    _startPoiChecking();
    _startGeneralFactTimer();
    setState(() => _state = RunState.running);
    _ttsService.speak('Продолжаем');
  }

  Future<void> _stopRun() async {
    _runTimer?.cancel();
    _positionSubscription?.cancel();
    _poiCheckTimer?.cancel();
    _generalFactTimer?.cancel();
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
    await _ttsService.speak('Тренировка окончена. Дистанция: ${(_totalDistance / 1000).toStringAsFixed(2)} километра. Услышано фактов: $_factsCount');
    
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
      _visitedPoiIds.clear();
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
        speed: data.raw.speed
      ));
    });
    if (_route.length >= 2) {
      final last = _route[_route.length - 2];
      final distance = Geolocator.distanceBetween(
        last.lat, last.lon,
        data.filtered.latitude, data.filtered.longitude
      );
      setState(() => _totalDistance += distance);
    }
    if (_followUser) _moveCamera(data.filtered, data.raw.speed);
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
          speed: speed
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          if (_state == RunState.running || _state == RunState.paused) _buildStatsPanel(),
          if (_state == RunState.searchingGps) _buildGpsIndicator(),
          if (_state == RunState.ready) _buildReadyIndicator(),
          if (_state == RunState.countdown) _buildCountdown(),
          _buildControlButtons(),
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
          urlTemplate: 'https://tile.openstreetmap.org/  {z}/{x}/{y}.png',
          userAgentPackageName: 'com.runguide.app',
        ),
        if (_route.isNotEmpty)
          PolylineLayer(polylines: _buildSpeedPolylines()),
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
        // Показываем POI на карте
        if (_nearbyPois.isNotEmpty)
          MarkerLayer(
            markers: _nearbyPois.map((poi) => Marker(
              point: poi.location,
              width: 30,
              height: 30,
              child: Icon(
                Icons.location_on,
                color: _visitedPoiIds.contains(poi.id) ? Colors.grey : Colors.red,
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
      top: 50, left: 16, right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20)
        ),
        child: Column(
          children: [
            Text(
              '${(_totalDistance / 1000).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white)
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
      top: 50, left: 16, right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12)
        ),
        child: const Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue)),
          SizedBox(width: 12),
          Text('Определяем местоположение...', style: TextStyle(color: Colors.white))
        ]),
      ),
    );
  }

  Widget _buildReadyIndicator() {
    return Positioned(
      top: 50, left: 16, right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12)
        ),
        child: const Row(children: [
          Icon(Icons.check_circle, color: Colors.white),
          SizedBox(width: 8),
          Text('Готов к старту', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
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
                  color: _countdown > 0 ? Colors.yellow : Colors.green
                )
              ),
              const SizedBox(height: 20),
              Text(
                _countdown > 0 ? 'Приготовьтесь!' : 'Бегите!',
                style: const TextStyle(fontSize: 24, color: Colors.white)
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Positioned(
      bottom: 30, left: 16, right: 16,
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
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