import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class MapCacheService {
  static const String storeName = 'runguide_map_cache';

  static final TileLayer _tileLayer = TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.runguide.runguide',
  );

  // Состояние скачивания
  static bool _isDownloading = false;
  static bool get isDownloading => _isDownloading;

  // ❗ ID экземпляра загрузки для управления (cancel/pause/resume)
  static Object _currentInstanceId = 0;

  static Future<void> init() async {
    try {
      await FMTCObjectBoxBackend().initialise();

      final store = FMTCStore(storeName);
      final exists = await store.manage.ready;
      if (!exists) {
        await store.manage.create();
        debugPrint('✅ Map cache store created');
      } else {
        debugPrint('✅ Map cache store already exists');
      }
    } catch (e) {
      debugPrint('❌ MapCacheService init error: $e');
    }
  }

  static Future<CacheStats> getStats() async {
    try {
      final store = FMTCStore(storeName);
      final stats = store.stats;
      final length = await stats.length;
      final size = await stats.size;

      return CacheStats(
        tilesCount: length,
        sizeBytes: (size * 1024).toInt(),
      );
    } catch (e) {
      debugPrint('❌ Get stats error: $e');
      return CacheStats.empty();
    }
  }

  static Future<bool> hasCache() async {
    final stats = await getStats();
    return stats.tilesCount > 0;
  }

  /// Проверка подключения к интернету
  static Future<bool> hasInternetConnection() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      return false;
    }
    return true;
  }

  static Stream<DownloadProgress> downloadArea(
    Position position, {
    double radiusKm = 15.0,
    int minZoom = 10,
    int maxZoom = 17,
  }) {
    if (_isDownloading) {
      throw Exception('Скачивание уже идёт');
    }

    _isDownloading = true;
    // Генерируем уникальный ID для этой загрузки
    _currentInstanceId = DateTime.now().millisecondsSinceEpoch;

    final radiusDegrees = radiusKm / 111.0;
    final bounds = LatLngBounds(
      LatLng(position.latitude - radiusDegrees, position.longitude - radiusDegrees),
      LatLng(position.latitude + radiusDegrees, position.longitude + radiusDegrees),
    );

    final region = RectangleRegion(bounds);
    final downloadableRegion = region.toDownloadable(
      minZoom: minZoom,
      maxZoom: maxZoom,
      options: _tileLayer,
    );

    // Запускаем загрузку с уникальным instanceId
    final result = FMTCStore(storeName).download.startForeground(
          region: downloadableRegion,
          instanceId: _currentInstanceId,
        );

    // Возвращаем только stream прогресса
    return result.downloadProgress;
  }

  /// Отмена текущего скачивания
  static Future<void> cancelDownload() async {
    try {
      debugPrint('⛔ Запрос на отмену загрузки... (instanceId: $_currentInstanceId)');
      
      // Отменяем через StoreDownload с тем же instanceId
      await FMTCStore(storeName).download.cancel(instanceId: _currentInstanceId);
      
      _isDownloading = false;
      debugPrint('✅ Загрузка отменена');
    } catch (e) {
      debugPrint('❌ Ошибка отмены: $e');
      _isDownloading = false;
    }
  }

  static Future<void> clearCache() async {
    try {
      await FMTCStore(storeName).manage.delete();
      debugPrint('🗑️ Cache cleared');
    } catch (e) {
      debugPrint('❌ Clear cache error: $e');
    }
  }
}

class CacheStats {
  final int tilesCount;
  final int sizeBytes;

  CacheStats({
    required this.tilesCount,
    required this.sizeBytes,
  });

  factory CacheStats.empty() => CacheStats(
        tilesCount: 0,
        sizeBytes: 0,
      );

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  bool get hasCache => tilesCount > 0;

  @override
  String toString() => 'CacheStats(tiles: $tilesCount, size: $sizeFormatted)';
}