import 'package:hive/hive.dart';
import 'route_point.dart';

part 'run_session.g.dart';

@HiveType(typeId: 1)
class RunSession extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime date;

  @HiveField(2)
  final double distance;

  @HiveField(3)
  final int duration;

  @HiveField(4)
  final int factsCount;

  @HiveField(5)
  final List<RoutePoint> route;

  @HiveField(6)
  final int calories;

  RunSession({
    required this.id,
    required this.date,
    required this.distance,
    required this.duration,
    this.factsCount = 0,
    this.route = const [],
    this.calories = 0,
  });

  String get avgPace {
    if (distance <= 0) return '--';
    final secondsPerKm = duration / distance;
    final minutes = (secondsPerKm / 60).floor();
    final seconds = (secondsPerKm % 60).round();
    return '$minutes:${seconds.toString().padLeft(2, "0")}';
  }

  String get formattedDuration {
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}';
    }
    return '${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'distance_km': distance,
    'duration_seconds': duration,
    'facts_count': factsCount,
    'calories': calories,
    'route': route.map((p) => p.toJson()).toList(),
  };
}