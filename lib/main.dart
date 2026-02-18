import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'data/models/route_point.dart';
import 'data/models/run_session.dart';
import 'services/api_service.dart'; // ИСПРАВЛЕНО: убрано data/
import 'ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация Hive
  await Hive.initFlutter();
  
  // Регистрируем адаптеры (только для моделей, которые храним локально)
  Hive.registerAdapter(RoutePointAdapter());
  Hive.registerAdapter(RunSessionAdapter());
  
  // Открываем коробки
  await Hive.openBox<RoutePoint>('active_route');
  await Hive.openBox<RunSession>('run_sessions');
  
  // Инициализируем API (создаёт device_id)
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