import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/run_session.dart';
import '../../data/models/route_point.dart';

class RunResultScreen extends StatelessWidget {
  final RunSession session;

  const RunResultScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final points = session.route.map((p) => LatLng(p.lat, p.lon)).toList();
    final center = points.isNotEmpty 
        ? points[points.length ~/ 2] 
        : const LatLng(47.23, 39.72);

    return Scaffold(
      body: Stack(
        children: [
          // Карта с треком
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.runguide.app',
              ),
              if (points.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: points,
                      color: Colors.deepPurple,
                      strokeWidth: 5,
                    ),
                  ],
                ),
              // Маркеры старта и финиша
              if (points.isNotEmpty)
                MarkerLayer(
                  markers: [
                    // Старт
                    Marker(
                      point: points.first,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                        child: const Icon(Icons.flag, color: Colors.white, size: 20),
                      ),
                    ),
                    // Финиш
                    Marker(
                      point: points.last,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                        child: const Icon(Icons.stop, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          
          // Панель с результатами
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Заголовок
                  const Text(
                    'Тренировка завершена!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Основная статистика
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatItem(
                        icon: Icons.route,
                        value: session.distance.toStringAsFixed(2),
                        unit: 'км',
                        label: 'Дистанция',
                        color: Colors.deepPurple,
                      ),
                      _buildStatItem(
                        icon: Icons.timer,
                        value: session.formattedDuration,
                        unit: '',
                        label: 'Время',
                        color: Colors.blue,
                      ),
                      _buildStatItem(
                        icon: Icons.speed,
                        value: session.avgPace,
                        unit: '/км',
                        label: 'Темп',
                        color: Colors.orange,
                      ),
                      _buildStatItem(
                        icon: Icons.local_fire_department,
                        value: session.calories.toString(),
                        unit: 'ккал',
                        label: 'Калории',
                        color: Colors.red,
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Дополнительная информация
                  if (session.factsCount > 0 || session.route.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (session.factsCount > 0) ...[
                            Icon(Icons.headphones, color: Colors.purple.shade300, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              '${session.factsCount} фактов',
                              style: TextStyle(color: Colors.purple.shade300),
                            ),
                            const SizedBox(width: 16),
                          ],
                          if (session.route.isNotEmpty) ...[
                            Icon(Icons.route, color: Colors.grey.shade500, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              '${session.route.length} точек',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 20),
                  
                  // Кнопки
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).popUntil((route) => route.isFirst);
                          },
                          icon: const Icon(Icons.home),
                          label: const Text('На главную'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Ещё раз'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Кнопка закрыть
          Positioned(
            top: 40,
            right: 16,
            child: SafeArea(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.close, color: Colors.black54),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String unit,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            if (unit.isNotEmpty)
              Text(
                ' $unit',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
          ],
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}