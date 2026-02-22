// lib/services/run_repository.dart

import 'package:hive/hive.dart';
import '../data/models/route_point.dart';
import '../data/models/run_session.dart';

/// Модель для хранения истории POI
class PoiHistoryItem {
  final int osmId;
  final String name;
  final DateTime visitedAt;
  final String? factText;

  PoiHistoryItem({
    required this.osmId,
    required this.name,
    required this.visitedAt,
    this.factText,
  });

  Map<String, dynamic> toJson() => {
    'osm_id': osmId,
    'name': name,
    'visited_at': visitedAt.toIso8601String(),
    'fact_text': factText,
  };

  factory PoiHistoryItem.fromJson(Map<String, dynamic> json) => PoiHistoryItem(
    osmId: json['osm_id'] as int,
    name: json['name'] as String,
    visitedAt: DateTime.parse(json['visited_at'] as String),
    factText: json['fact_text'] as String?,
  );
}

class RunRepository {
  static const String _sessionsBoxName = 'run_sessions';
  static const String _activeRouteBoxName = 'active_route';
  static const String _poiHistoryBoxName = 'poi_history'; // ← НОВОЕ

  Box<RunSession>? _sessionsBox;
  Box<RoutePoint>? _activeRouteBox;
  Box<dynamic>? _poiHistoryBox; // ← НОВОЕ

  /// Инициализация
  Future<void> init() async {
    _sessionsBox = await Hive.openBox<RunSession>(_sessionsBoxName);
    _activeRouteBox = await Hive.openBox<RoutePoint>(_activeRouteBoxName);
    _poiHistoryBox = await Hive.openBox(_poiHistoryBoxName); // ← НОВОЕ
  }

  // ==================== ПРОБЕЖКИ ====================

  /// Сохранить пробежку
  Future<void> saveSession(RunSession session) async {
    await _sessionsBox?.put(session.id, session);
    print('💾 Пробежка сохранена: ${session.id}');
  }

  /// Получить все пробежки
  List<RunSession> getAllSessions() {
    return _sessionsBox?.values.toList() ?? [];
  }

  /// Получить пробежки отсортированные по дате (новые первые)
  List<RunSession> getSessionsSorted() {
    final sessions = getAllSessions();
    sessions.sort((a, b) => b.date.compareTo(a.date));
    return sessions;
  }

  /// Получить пробежку по ID
  RunSession? getSession(String id) {
    return _sessionsBox?.get(id);
  }

  /// Удалить пробежку
  Future<void> deleteSession(String id) async {
    await _sessionsBox?.delete(id);
    print('🗑️ Пробежка удалена: $id');
  }

  /// Количество пробежек
  int get sessionsCount => _sessionsBox?.length ?? 0;

  // ==================== АКТИВНЫЙ МАРШРУТ ====================

  /// Добавить точку в активный маршрут
  Future<void> addRoutePoint(RoutePoint point) async {
    await _activeRouteBox?.add(point);
  }

  /// Получить активный маршрут
  List<RoutePoint> getActiveRoute() {
    return _activeRouteBox?.values.toList() ?? [];
  }

  /// Очистить активный маршрут
  Future<void> clearActiveRoute() async {
    await _activeRouteBox?.clear();
    print('🧹 Активный маршрут очищен');
  }

  /// Количество точек в активном маршруте
  int get activeRouteLength => _activeRouteBox?.length ?? 0;

  // ==================== ИСТОРИЯ POI (НОВОЕ) ====================

  /// Сохранить посещение POI
  Future<void> savePoiVisit(int osmId, String name, {String? factText}) async {
    final key = 'poi_$osmId';
    final item = PoiHistoryItem(
      osmId: osmId,
      name: name,
      visitedAt: DateTime.now(),
      factText: factText,
    );
    await _poiHistoryBox?.put(key, item.toJson());
    print('📍 POI сохранён в историю: $name (osmId: $osmId)');
  }

  /// Проверить, был ли POI уже озвучен
  bool wasPoiVisited(int osmId) {
    final key = 'poi_$osmId';
    return _poiHistoryBox?.containsKey(key) ?? false;
  }

  /// Получить историю посещений POI
  List<PoiHistoryItem> getPoiHistory() {
    final values = _poiHistoryBox?.values.toList() ?? [];
    return values.map((v) => PoiHistoryItem.fromJson(Map<String, dynamic>.from(v))).toList()
      ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
  }

  /// Очистить историю POI (например, при смене города)
  Future<void> clearPoiHistory() async {
    await _poiHistoryBox?.clear();
    print('🧹 История POI очищена');
  }

  // ==================== СТАТИСТИКА ====================

  /// Общая дистанция всех пробежек
  double get totalDistance {
    return getAllSessions().fold(0.0, (sum, s) => sum + s.distance);
  }

  /// Общее время всех пробежек (в секундах)
  int get totalDuration {
    return getAllSessions().fold(0, (sum, s) => sum + s.duration);
  }

  /// Общее количество фактов
  int get totalFacts {
    return getAllSessions().fold(0, (sum, s) => sum + s.factsCount);
  }

  /// Средний темп
  String get avgPace {
    if (totalDistance <= 0) return '--';
    final secondsPerKm = totalDuration / totalDistance;
    final minutes = (secondsPerKm / 60).floor();
    final seconds = (secondsPerKm % 60).round();
    return '$minutes:${seconds.toString().padLeft(2, "0")}';
  }
}