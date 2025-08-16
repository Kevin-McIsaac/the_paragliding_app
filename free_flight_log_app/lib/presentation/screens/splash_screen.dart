import 'package:flutter/material.dart';
import 'flight_list_screen.dart';
import '../../utils/startup_performance_tracker.dart';
import '../../services/logging_service.dart';

/// Lightweight splash screen that shows loading and then navigates
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate to main screen after a brief delay
    _navigateToMain();
  }

  Future<void> _navigateToMain() async {
    final perfTracker = StartupPerformanceTracker();
    
    // OPTIMIZATION: Removed 500ms artificial delay - navigate immediately
    // This saves 500ms from startup time
    perfTracker.recordTimestamp('Navigating to Main Screen (No Delay)');
    
    // Use a microtask to ensure the splash screen renders at least once
    await Future.microtask(() {});
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const FlightListScreen(),
        ),
      );
      
      // Print performance report after navigation
      final report = perfTracker.generateReport();
      LoggingService.info(report);
      print(report); // Also print to console for visibility
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show simple loading screen
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App icon
            Icon(
              Icons.flight_takeoff,
              size: 80,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            const SizedBox(height: 24),
            
            // App name
            Text(
              'Free Flight Log',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 48),
            
            // Simple loading indicator
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}