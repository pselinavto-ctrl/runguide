import 'package:hive/hive.dart';

part 'route_point.g.dart';

@HiveType(typeId: 0)
class RoutePoint extends HiveObject {
  @HiveField(0)
  final double lat;

  @HiveField(1)
  final double lon;

  @HiveField(2)
  final DateTime timestamp;

  @HiveField(3)
  final double speed;

  RoutePoint({
    required this.lat,
    required this.lon,
    required this.timestamp,
    this.speed = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lon': lon,
    'timestamp': timestamp.toIso8601String(),
    'speed': speed,
  };
}