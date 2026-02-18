import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../data/models/poi.dart';
import '../data/models/fact.dart';

/// Сервис для работы с API сервера RunGuide
class ApiService {
  final http.Client _client = http.Client();
  String? _deviceId;
  int? _currentCityId;

  /// Установка ID устройства (для отслеживания прослушанных фактов)
  void setDeviceId(String deviceId) {
    _deviceId = deviceId;
  }

  /// Установка ID текущего города
  void setCityId(int? cityId) {
    _currentCityId = cityId;
  }

  String get _userId => _deviceId ?? 'device_${DateTime.now().millisecondsSinceEpoch}';

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

  /// Получить POI рядом с координатами
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

  /// Получить факт о конкретном POI
  Future<PoiFact?> getPoiFact(int poiId) async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.apiUrl}/get_poi_fact.php?poi_id=$poiId&user_id=${_userId}'),
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

  /// Получить общий факт
  Future<GeneralFact?> getGeneralFact({String? category}) async {
    try {
      String url = '${AppConstants.apiUrl}/get_general_fact.php?user_id=${_userId}';
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
          'user_id': _userId,
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
  }) async {
    try {
      String url = '${AppConstants.apiUrl}/generate_fact.php?type=$type';
      
      if (poiId != null) {
        url += '&poi_id=$poiId';
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
          final source = data['data']['source'];
          print('📝 Источник факта: $source');
          return data['data']['fact'];
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