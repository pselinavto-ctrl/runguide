import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/run_repository.dart';
import '../../data/models/run_session.dart';
import '../../data/models/route_point.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final RunRepository _repository = RunRepository();
  List<RunSession> _runs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRuns();
  }

  Future<void> _loadRuns() async {
    await _repository.init();
    setState(() {
      _runs = _repository.getSessionsSorted();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История пробежек'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _runs.isEmpty
              ? _buildEmptyState()
              : _buildRunsList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_run, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Нет тренировок',
            style: TextStyle(fontSize: 20, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text(
            'Начните первую пробежку!',
            style: TextStyle(color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildRunsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _runs.length,
      itemBuilder: (context, index) {
        final run = _runs[index];
        return _buildRunCard(run);
      },
    );
  }

  Widget _buildRunCard(RunSession run) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showRunDetails(run),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDate(run.date),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _formatTime(run.date),
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildRunStat(icon: Icons.route, value: '${run.distance.toStringAsFixed(2)} км', color: Colors.blue),
                  const SizedBox(width: 16),
                  _buildRunStat(icon: Icons.timer, value: run.formattedDuration, color: Colors.green),
                  const SizedBox(width: 16),
                  _buildRunStat(icon: Icons.speed, value: run.avgPace, color: Colors.orange),
                  const SizedBox(width: 16),
                  _buildRunStat(icon: Icons.local_fire_department, value: '${run.calories}', color: Colors.red),
                ],
              ),
              if (run.factsCount > 0 || run.route.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      if (run.factsCount > 0) ...[
                        Icon(Icons.headphones, size: 14, color: Colors.purple.shade300),
                        const SizedBox(width: 4),
                        Text('${run.factsCount} фактов', style: TextStyle(color: Colors.purple.shade300, fontSize: 12)),
                        const SizedBox(width: 12),
                      ],
                      if (run.route.isNotEmpty)
                        Icon(Icons.map, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text('${run.route.length} точек', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRunStat({required IconData icon, required String value, required Color color}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      ],
    );
  }

  void _showRunDetails(RunSession run) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildDetailsSheet(run),
    );
  }

  Widget _buildDetailsSheet(RunSession run) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Тренировка ${_formatDate(run.date)}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _formatTime(run.date),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      
                      // Карта маршрута
                      if (run.route.isNotEmpty) ...[
                        _buildMiniMap(run.route),
                        const SizedBox(height: 20),
                      ],
                      
                      // Статистика
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildDetailItem('Дистанция', '${run.distance.toStringAsFixed(2)} км', Colors.blue),
                            _buildDetailItem('Время', run.formattedDuration, Colors.green),
                            _buildDetailItem('Темп', '${run.avgPace} /км', Colors.orange),
                            _buildDetailItem('Калории', '${run.calories}', Colors.red),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Факты и POI
                      if (run.factsCount > 0)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.headphones, color: Colors.purple, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Озвучено фактов',
                                      style: TextStyle(color: Colors.purple, fontSize: 12),
                                    ),
                                    Text(
                                      '${run.factsCount} интересных историй',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                      const SizedBox(height: 20),
                      
                      // Информация о маршруте
                      if (run.route.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.route, color: Colors.grey.shade600),
                              const SizedBox(width: 12),
                              Text(
                                'Записано ${run.route.length} точек маршрута',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      
                      const SizedBox(height: 30),
                      
                      // Кнопка удаления
                      Center(
                        child: TextButton.icon(
                          onPressed: () => _deleteRun(run),
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text('Удалить тренировку', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniMap(List<RoutePoint> route) {
    if (route.isEmpty) return const SizedBox.shrink();
    
    final points = route.map((p) => LatLng(p.lat, p.lon)).toList();
    final center = points[points.length ~/ 2];
    
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
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
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  color: Colors.deepPurple,
                  strokeWidth: 4,
                ),
              ],
            ),
            // Стартовый маркер
            MarkerLayer(
              markers: [
                Marker(
                  point: points.first,
                  width: 30,
                  height: 30,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.flag, color: Colors.white, size: 16),
                  ),
                ),
                Marker(
                  point: points.last,
                  width: 30,
                  height: 30,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.stop, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final runDate = DateTime(date.year, date.month, date.day);

    if (runDate == today) {
      return 'Сегодня';
    } else if (runDate == yesterday) {
      return 'Вчера';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _deleteRun(RunSession run) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить тренировку?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _repository.deleteSession(run.id);
      Navigator.pop(context);
      _loadRuns();
    }
  }
}