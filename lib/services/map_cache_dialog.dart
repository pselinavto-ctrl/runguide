import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'map_cache_service.dart';

class MapCacheDownloadDialog extends StatefulWidget {
  final Position? position;
  final double radiusKm;
  final int minZoom;
  final int maxZoom;

  const MapCacheDownloadDialog({
    super.key,
    this.position,
    this.radiusKm = 10.0, // Изменено с 15.0 на 10.0
    this.minZoom = 10,
    this.maxZoom = 17,
  });

  @override
  State<MapCacheDownloadDialog> createState() => _MapCacheDownloadDialogState();
}

class _MapCacheDownloadDialogState extends State<MapCacheDownloadDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  double _progress = 0.0;
  String _statusText = 'Проверка подключения...';
  bool _isComplete = false;
  bool _hasError = false;
  String _errorMessage = '';

  StreamSubscription<DownloadProgress>? _subscription;
  bool _isCancelled = false;
  bool _isCancelling = false;
  bool _isMinimized = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    _startDownload();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    try {
      setState(() {
        _statusText = 'Проверка подключения...';
      });

      final hasInternet = await MapCacheService.hasInternetConnection();
      if (!hasInternet) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Нет подключения к интернету.\nПодключитесь к Wi-Fi или мобильной сети.';
          _statusText = 'Нет интернета';
        });
        return;
      }

      // Проверяем, не идёт ли уже скачивание
      if (MapCacheService.isDownloading) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Загрузка уже выполняется в другом окне.\nДождитесь завершения.';
          _statusText = 'Уже скачивается';
        });
        return;
      }

      setState(() {
        _statusText = 'Определение местоположения...';
      });

      _currentPosition = widget.position ?? await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      if (_isCancelled) return;

      setState(() {
        _statusText = 'Подготовка к загрузке...';
      });

      final stream = MapCacheService.downloadArea(
        _currentPosition!,
        radiusKm: widget.radiusKm,
        minZoom: widget.minZoom,
        maxZoom: widget.maxZoom,
      );

      _subscription = stream.listen(
        (event) {
          if (!mounted || _isCancelled) return;

          setState(() {
            _progress = event.percentageProgress / 100;

            final isComplete = event.remainingTilesCount == 0 || 
                              event.percentageProgress >= 100;

            if (isComplete) {
              _isComplete = true;
              _statusText = 'Загрузка завершена!';
              _pulseController.stop();
            } else {
              final percent = event.percentageProgress.toStringAsFixed(0);
              final remaining = event.remainingTilesCount;
              _statusText = 'Загрузка: $percent% (осталось $remaining тайлов)';
            }
          });
        },
        onError: (error) {
          if (!mounted) return;
          
          if (_isCancelled || error.toString().contains('cancelled')) {
            debugPrint('⛔ Загрузка была отменена, игнорируем ошибку');
            return;
          }
          
          setState(() {
            _hasError = true;
            _errorMessage = _formatError(error);
            _statusText = 'Ошибка загрузки';
            _pulseController.stop();
          });
        },
        onDone: () {
          if (!mounted) return;
          if (!_isComplete && !_hasError && !_isCancelled) {
            setState(() {
              _isComplete = true;
              _progress = 1.0;
              _statusText = 'Загрузка завершена!';
            });
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (!mounted || _isCancelled) return;
      setState(() {
        _hasError = true;
        _errorMessage = _formatError(e);
        _statusText = 'Ошибка';
        _pulseController.stop();
      });
    }
  }

  String _formatError(dynamic error) {
    final errorStr = error.toString();
    
    if (errorStr.contains('cancelled') || errorStr.contains('отмен')) {
      return 'Загрузка отменена пользователем';
    }
    if (errorStr.contains('SocketException') || errorStr.contains('Connection failed')) {
      return 'Потеряно соединение с интернетом.\nПроверьте подключение и попробуйте снова.';
    }
    if (errorStr.contains('Скачивание уже идёт')) {
      return 'Загрузка уже выполняется.\nДождитесь завершения или перезапустите приложение.';
    }
    if (errorStr.contains('timeout')) {
      return 'Сервер карт не отвечает.\nПопробуйте позже.';
    }
    
    return 'Ошибка: $errorStr';
  }

  Future<void> _cancelDownload() async {
    if (_isCancelling || _isCancelled) return;
    
    setState(() {
      _isCancelling = true;
      _isCancelled = true;
      _statusText = 'Отмена загрузки...';
    });

    await _subscription?.cancel();
    await MapCacheService.cancelDownload();
    
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  void _minimizeAndRun() {
    setState(() {
      _isMinimized = true;
    });
    // Закрываем диалог, загрузка продолжится в фоне
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (!_isComplete && !_hasError && !_isCancelling) {
          return false;
        }
        return true;
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.deepPurple.shade50, Colors.white],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAnimatedIcon(),
              const SizedBox(height: 24),
              Text(
                _isComplete ? 'Готово!' : _hasError ? 'Ошибка' : 'Загрузка карты',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _hasError ? Colors.red : Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusText,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (!_isComplete && !_hasError) _buildProgressBar(),
              if (_isComplete) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.radiusKm.toInt()} × ${widget.radiusKm.toInt()} км загружено',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Теперь карта работает без интернета!',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (_hasError) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              
              // КНОПКИ: Отмена слева, Бегать! справа
              if (!_isComplete && !_hasError)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Кнопка Отмена (слева)
                    TextButton.icon(
                      onPressed: _isCancelling ? null : _cancelDownload,
                      icon: _isCancelling 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.close, color: Colors.grey),
                      label: Text(
                        _isCancelling ? 'Отмена...' : 'Отмена',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade600,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                    
                    // Кнопка Бегать! (справа) - зелёная
                    ElevatedButton.icon(
                      onPressed: _minimizeAndRun,
                      icon: const Icon(Icons.directions_run, color: Colors.white),
                      label: const Text(
                        'БЕГАТЬ!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ],
                ),
              
              if (_isComplete || _hasError)
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(_isComplete),
                  icon: Icon(_isComplete ? Icons.check : Icons.refresh),
                  label: Text(_isComplete ? 'Готово' : 'Закрыть'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isComplete ? Colors.green : Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedIcon() {
    if (_isComplete) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.green.shade100,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.download_done, size: 40, color: Colors.green.shade600),
      );
    }
    if (_hasError) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.error_outline, size: 40, color: Colors.red.shade600),
      );
    }
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) => Transform.scale(
        scale: _pulseAnimation.value,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [Colors.deepPurple.shade200, Colors.deepPurple.shade400],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  value: _progress,
                  strokeWidth: 4,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const Icon(Icons.map_outlined, size: 32, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _progress,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              Color.lerp(Colors.orange, Colors.green, _progress)!,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Офлайн-карта',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<bool> showMapCacheDialog(BuildContext context,
    {Position? position, double radiusKm = 10.0}) async { // Изменено с 15.0 на 10.0
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        MapCacheDownloadDialog(position: position, radiusKm: radiusKm),
  );
  return result ?? false;
}