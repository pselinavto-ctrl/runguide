import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'data/models/route_point.dart';
import 'data/models/run_session.dart';
import 'services/api_service.dart';
import 'services/map_cache_service.dart';
import 'ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(RoutePointAdapter());
  Hive.registerAdapter(RunSessionAdapter());
  await Hive.openBox<RoutePoint>('active_route');
  await Hive.openBox<RunSession>('run_sessions');

  await MapCacheService.init();

  final apiService = ApiService();
  await apiService.init();

  runApp(const RunGuideApp());
}

class RunGuideApp extends StatelessWidget {
  const RunGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RunGuide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}