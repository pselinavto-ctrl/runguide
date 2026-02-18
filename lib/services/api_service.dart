import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';
import '../data/models/poi.dart';
import '../data/models/fact.dart';

/// Сервис для работы с API сервера RunGuide
class ApiService {
  final http.Client _client = http.Client();
  String? _deviceId;
  int? _currentCityId;

  /// Инициализация - создаёт или загружает ID устройства
  Future<void> init() async {
    final box = await Hive.openBox('settings');
    _deviceId = box.get('device_id');
    
    if (_deviceId == null) {
      _deviceId = 'user_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      await box.put('device_id', _deviceId);
      print('🆔 Создан новый ID: $_deviceId');
    } else {
      print('🆔 Загружен ID: $_deviceId');
    }
  }
  
  String get userId => _deviceId ?? 'unknown';

  /// Установка ID устройства
  void setDeviceId(String deviceId) {
    _deviceId = deviceId;
  }

  /// Установка ID текущего города
  void setCityId(int? cityId) {
    _currentCityId = cityId;
  }

  /// Определить город по координатам
  Future<CityInfo?> getCity(double lat, double lon) async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.apiUrl}/get_city.php?lat=$lat&lon=$lon'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data']['found'] == true) {
          final cityData = data['data']['city'];
          _currentCityId = cityData['id'];
          return CityInfo(
            id: cityData['id'],
            name: cityData['name'],
            country: cityData['country'],
          );
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка определения города: $e');
      return null;
    }
  }

  /// Получить POI рядом с координатами (из БД)
  Future<List<Poi>> getNearbyPois(double lat, double lon, {int radius = 500}) async {
    try {
      String url = '${AppConstants.apiUrl}/get_pois.php?lat=$lat&lon=$lon&radius=$radius';
      if (_currentCityId != null) {
        url += '&city_id=$_currentCityId';
      }

      final response = await _client.get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> poisData = data['data']['pois'];
          return poisData.map((p) => Poi.fromJson(p)).toList();
        }
      }
      return [];
    } catch (e) {
      print('❌ Ошибка получения POI: $e');
      return [];
    }
  }

  /// Получить POI из OpenStreetMap
  Future<List<OsmPoi>> getOsmPois(double lat, double lon, {int radius = 1000}) async {
    try {
      print('🗺️ Запрос OSM POI: lat=$lat, lon=$lon, radius=$radius');
      
      final response = await _client.get(
        Uri.parse('${AppConstants.apiUrl}/get_osm_pois.php?lat=$lat&lon=$lon&radius=$radius'),
      ).timeout(const Duration(seconds: 30));

      print('📦 OSM ответ: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> poisData = data['data']['pois'];
          print('✅ OSM POI найдено: ${poisData.length}');
          return poisData.map((p) => OsmPoi.fromJson(p)).toList();
        } else {
          print('❌ OSM ошибка: ${data['error']}');
        }
      }
      return [];
    } catch (e) {
      print('❌ Ошибка получения OSM POI: $e');
      return [];
    }
  }

  /// Получить факт о конкретном POI
  Future<PoiFact?> getPoiFact(int poiId) async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.apiUrl}/get_poi_fact.php?poi_id=$poiId&user_id=$userId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data']['found'] == true) {
          final factData = data['data']['fact'];
          return PoiFact(
            id: factData['id'],
            poiId: poiId,
            text: factData['fact_text'],
          );
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка получения факта POI: $e');
      return null;
    }
  }

  /// Получить уникальный факт о POI из OSM
  Future<String?> getOsmPoiFact({
    required int osmId,
    required String poiName,
    required String category,
  }) async {
    try {
      final url = '${AppConstants.apiUrl}/generate_fact.php?type=poi'
          '&osm_id=$osmId'
          '&name=${Uri.encodeComponent(poiName)}'
          '&category=$category'
          '&user_id=$userId';

      print('🗺️ Запрос факта о POI: $poiName');

      final response = await _client.get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final source = data['data']['source'] ?? 'unknown';
          final new_ = data['data']['new'] ?? true;
          print('📝 POI факт: source=$source, new=$new_');
          return data['data']['fact'];
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка получения факта POI: $e');
      return null;
    }
  }

  /// Получить общий факт
  Future<GeneralFact?> getGeneralFact({String? category}) async {
    try {
      String url = '${AppConstants.apiUrl}/get_general_fact.php?user_id=$userId';
      if (_currentCityId != null) {
        url += '&city_id=$_currentCityId';
      }
      if (category != null) {
        url += '&category=$category';
      }

      final response = await _client.get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data']['found'] == true) {
          final factData = data['data']['fact'];
          return GeneralFact(
            id: factData['id'],
            text: factData['fact_text'],
            category: factData['category'],
          );
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка получения общего факта: $e');
      return null;
    }
  }

  /// Сохранить посещение POI
  Future<bool> saveVisit(int poiId, int? factId) async {
    try {
      final response = await _client.post(
        Uri.parse('${AppConstants.apiUrl}/save_visit.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': userId,
          'poi_id': poiId,
          'fact_id': factId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Ошибка сохранения посещения: $e');
      return false;
    }
  }

  /// Получить сгенерированный факт через DeepSeek
  Future<String?> getGeneratedFact({
    required String type,
    int? poiId,
    String? category,
    String? cityName,
    int? osmId,
    String? poiName,
  }) async {
    try {
      String url = '${AppConstants.apiUrl}/generate_fact.php?type=$type';
      
      // ДОБАВЛЯЕМ USER_ID - ЭТО БЫЛО ПРОПУЩЕНО!
      url += '&user_id=$userId';
      
      if (poiId != null) {
        url += '&poi_id=$poiId';
      }
      if (osmId != null) {
        url += '&osm_id=$osmId';
      }
      if (poiName != null) {
        url += '&name=${Uri.encodeComponent(poiName)}';
      }
      if (category != null) {
        url += '&category=$category';
      }
      if (cityName != null) {
        url += '&city_name=${Uri.encodeComponent(cityName)}';
      }
      
      print('🤖 Запрос к DeepSeek: $url');
      
      final response = await _client.get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final source = data['data']['source'] ?? 'unknown';
          final generated = data['data']['generated'] ?? false;
          print('📝 Источник: $source, Сгенерирован: $generated');
          return data['data']['fact'];
        } else {
          print('❌ Ошибка API: ${data['error']}');
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка генерации факта: $e');
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}

/// Информация о городе
class CityInfo {
  final int id;
  final String name;
  final String country;

  CityInfo({required this.id, required this.name, required this.country});
}