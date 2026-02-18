import 'package:flutter/material.dart';
import '../../services/run_repository.dart';
import '../../data/models/run_session.dart';
import 'run_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final RunRepository _repository = RunRepository();
  List<RunSession> _recentRuns = [];
  bool _isLoading = true;
  bool _isMenuOpen = false;
  
  double _dragExtent = 0;
  static const double _dragSensitivity = 1.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _repository.init();
    final runs = _repository.getSessionsSorted();
    setState(() {
      _recentRuns = runs.take(5).toList();
      _isLoading = false;
    });
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
    });
  }

  void _handleDragStart(DragStartDetails details) {
    _dragExtent = 0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _dragExtent += details.delta.dy;
  }

  void _handleDragEnd(DragEndDetails details) {
    final threshold = 50.0;
    
    if (_isMenuOpen) {
      // Если меню открыто, свайп вниз закрывает
      if (_dragExtent > threshold) {
        setState(() => _isMenuOpen = false);
      }
    } else {
      // Если меню закрыто, свайп вверх открывает
      if (_dragExtent < -threshold) {
        setState(() => _isMenuOpen = true);
      }
    }
    _dragExtent = 0;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onVerticalDragStart: _handleDragStart,
              onVerticalDragUpdate: _handleDragUpdate,
              onVerticalDragEnd: _handleDragEnd,
              child: Stack(
                children: [
                  // Фоновое изображение
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/runner_bg.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.deepPurple.shade800,
                                Colors.purple.shade600,
                                Colors.deepPurple.shade400,
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  
                  // Градиент затемнения
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.1),
                            Colors.black.withOpacity(0.4),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Основной контент (название)
                  SafeArea(
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Логотип/название
                                const Text(
                                  'RunGuide',
                                  style: TextStyle(
                                    fontSize: 56,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 4,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black38,
                                        blurRadius: 20,
                                        offset: Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Аудио-гид для бегунов',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.white70,
                                    letterSpacing: 2,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black38,
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                                
                                // Статистика (краткая)
                                if (_repository.sessionsCount > 0) ...[
                                  const SizedBox(height: 40),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.2),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildQuickStat(
                                          Icons.route,
                                          '${_repository.totalDistance.toStringAsFixed(1)} км',
                                        ),
                                        Container(
                                          width: 1,
                                          height: 20,
                                          margin: const EdgeInsets.symmetric(horizontal: 16),
                                          color: Colors.white30,
                                        ),
                                        _buildQuickStat(
                                          Icons.directions_run,
                                          '${_repository.sessionsCount} тренировок',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Раскрывающееся меню (ТЁМНАЯ ТЕМА)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    bottom: _isMenuOpen ? 0 : -screenHeight * 0.65,
                    left: 0,
                    right: 0,
                    height: screenHeight * 0.7,
                    child: GestureDetector(
                      onVerticalDragStart: _handleDragStart,
                      onVerticalDragUpdate: _handleDragUpdate,
                      onVerticalDragEnd: _handleDragEnd,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(32),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 30,
                              offset: const Offset(0, -10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Handle для перетаскивания
                            GestureDetector(
                              onTap: _toggleMenu,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 50,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade700,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _isMenuOpen ? 'Свайп вниз для закрытия' : '',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Column(
                                  children: [
                                    // Кнопка старт
                                    _buildMenuButton(
                                      icon: Icons.play_arrow_rounded,
                                      title: 'Начать тренировку',
                                      subtitle: 'Запустить аудио-гид',
                                      color: const Color(0xFF4CAF50),
                                      onTap: () {
                                        _toggleMenu();
                                        Future.delayed(
                                          const Duration(milliseconds: 300),
                                          () => _startRun(),
                                        );
                                      },
                                    ),
                                    
                                    const SizedBox(height: 16),
                                    
                                    _buildMenuButton(
                                      icon: Icons.history_rounded,
                                      title: 'История пробежек',
                                      subtitle: '${_repository.sessionsCount} тренировок',
                                      color: const Color(0xFF2196F3),
                                      onTap: () {
                                        _toggleMenu();
                                        Future.delayed(
                                          const Duration(milliseconds: 300),
                                          () => _openHistory(),
                                        );
                                      },
                                    ),
                                    
                                    const SizedBox(height: 16),
                                    
                                    _buildMenuButton(
                                      icon: Icons.settings_rounded,
                                      title: 'Настройки',
                                      subtitle: 'Голос, частота фактов',
                                      color: const Color(0xFFFF9800),
                                      onTap: () {
                                        _toggleMenu();
                                        _openSettings();
                                      },
                                    ),
                                    
                                    const SizedBox(height: 24),
                                    
                                    // Последняя пробежка
                                    if (_recentRuns.isNotEmpty) ...[
                                      Container(
                                        height: 1,
                                        margin: const EdgeInsets.symmetric(vertical: 8),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.transparent,
                                              Colors.grey.shade800,
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      _buildLastRunCard(),
                                      const SizedBox(height: 24),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Кнопка открытия меню (когда закрыто)
                  if (!_isMenuOpen)
                    Positioned(
                      bottom: 40,
                      left: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _toggleMenu,
                        onVerticalDragStart: _handleDragStart,
                        onVerticalDragUpdate: _handleDragUpdate,
                        onVerticalDragEnd: _handleDragEnd,
                        child: Center(
                          child: Column(
                            children: [
                              // Стрелка вверх
                              Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.keyboard_arrow_up_rounded,
                                  color: Colors.white70,
                                  size: 28,
                                ),
                              ),
                              // Кнопка
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 15,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.menu_rounded,
                                      color: Colors.grey.shade700,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Меню',
                                      style: TextStyle(
                                        color: Colors.grey.shade800,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildQuickStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF252542),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.grey.shade800,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.grey.shade700,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastRunCard() {
    final lastRun = _recentRuns.first;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF252542),
            const Color(0xFF1E1E36),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.deepPurple.shade900,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.deepPurple.shade400,
                  Colors.deepPurple.shade700,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.directions_run,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Последняя тренировка',
                  style: TextStyle(
                    color: Colors.deepPurple,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${lastRun.distance.toStringAsFixed(2)} км • ${lastRun.formattedDuration} • ${lastRun.avgPace} /км',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.deepPurple.shade400,
            size: 24,
          ),
        ],
      ),
    );
  }

  void _startRun() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RunScreen()),
    ).then((_) => _loadData());
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HistoryScreen()),
    ).then((_) => _loadData());
  }

  void _openSettings() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Настройки будут добавлены позже'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}