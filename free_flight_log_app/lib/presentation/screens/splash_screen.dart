import 'package:flutter/material.dart';
import 'flight_list_screen.dart';
import '../../services/logging_service.dart';
import '../../services/app_initialization_service.dart';

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
    // Use a microtask to ensure the splash screen renders at least once
    await Future.microtask(() {});

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const FlightListScreen(),
        ),
      );

      LoggingService.info('App startup completed');

      // Start background initialization after navigation
      // This includes downloading PGE sites on first launch
      AppInitializationService.instance.initializeInBackground();
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