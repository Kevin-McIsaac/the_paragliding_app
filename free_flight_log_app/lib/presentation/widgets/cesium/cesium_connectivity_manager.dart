import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../services/logging_service.dart';

/// Manages network connectivity for Cesium 3D map
/// 
/// This class handles:
/// - Connectivity monitoring
/// - Network state changes
/// - Connection recovery
class CesiumConnectivityManager {
  final void Function(bool hasInternet) onConnectivityChanged;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _hasInternet = true;
  bool _isDisposed = false;
  
  CesiumConnectivityManager({required this.onConnectivityChanged});
  
  /// Gets current internet connectivity status
  bool get hasInternet => _hasInternet;
  
  /// Starts monitoring connectivity
  void startMonitoring() {
    if (_isDisposed) return;
    
    // Check initial connectivity
    checkConnectivity();
    
    // Listen for changes
    _subscription = Connectivity()
        .onConnectivityChanged
        .listen(_updateConnectionStatus);
    
    LoggingService.debug('CesiumConnectivityManager: Started monitoring');
  }
  
  /// Checks current connectivity status
  Future<void> checkConnectivity() async {
    if (_isDisposed) return;
    
    try {
      final result = await Connectivity().checkConnectivity();
      _updateConnectionStatus(result);
    } catch (e) {
      LoggingService.error('CesiumConnectivityManager', 'Error checking connectivity: $e');
      // Assume connected if we can't check
      _setConnectivityStatus(true);
    }
  }
  
  /// Updates connection status based on connectivity results
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    if (_isDisposed) return;
    
    final hasConnection = results.isNotEmpty && 
                         !results.contains(ConnectivityResult.none);
    
    _setConnectivityStatus(hasConnection);
    
    if (!hasConnection) {
      LoggingService.warning('CesiumConnectivityManager: No internet connection detected');
    } else if (!_hasInternet && hasConnection) {
      LoggingService.info('CesiumConnectivityManager: Internet connection restored');
    }
  }
  
  /// Sets connectivity status and notifies callback
  void _setConnectivityStatus(bool hasConnection) {
    if (_hasInternet != hasConnection) {
      _hasInternet = hasConnection;
      onConnectivityChanged(hasConnection);
    }
  }
  
  /// Disposes the connectivity manager
  void dispose() {
    if (_isDisposed) return;
    
    _isDisposed = true;
    _subscription?.cancel();
    
    LoggingService.debug('CesiumConnectivityManager: Disposed');
  }
}