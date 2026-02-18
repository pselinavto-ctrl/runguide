import 'package:latlong2/latlong.dart';

/// Модель POI (Point of Interest) - точка интереса
/// Не хранится в Hive, получается с сервера
class Poi {
  final int id;
  final int cityId;
  final String name;
  final String? description;
  final double lat;
  final double lon;
  final int radiusMeters;
  final String category;
  final String? cityName;
  final double distance;
  final bool inRange;

  Poi({
    required this.id,
    required this.cityId,
    required this.name,
    this.description,
    required this.lat,
    required this.lon,
    required this.radiusMeters,
    required this.category,
    this.cityName,
    this.distance = 0,
    this.inRange = false,
  });

  LatLng get location => LatLng(lat, lon);

  factory Poi.fromJson(Map<String, dynamic> json) {
    return Poi(
      id: json['id'] as int,
      cityId: json['city_id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      lat: double.parse(json['lat'].toString()),
      lon: double.parse(json['lon'].toString()),
      radiusMeters: json['radius_meters'] as int,
      category: json['category'] as String,
      cityName: json['city_name'] as String?,
      distance: (json['distance'] as num?)?.toDouble() ?? 0,
      inRange: json['in_range'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'city_id': cityId,
    'name': name,
    'description': description,
    'lat': lat,
    'lon': lon,
    'radius_meters': radiusMeters,
    'category': category,
    'city_name': cityName,
    'distance': distance,
    'in_range': inRange,
  };
}