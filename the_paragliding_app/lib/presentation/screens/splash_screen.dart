import 'package:flutter/material.dart';
import 'main_navigation_screen.dart';
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

    // Initialize app data (downloads PGE sites on first launch)
    // This waits for initialization to complete, ensuring database is ready
    // before showing the main screen with the sites map
    await AppInitializationService.instance.initializeInBackground();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const MainNavigationScreen(),
        ),
      );

      LoggingService.info('App startup completed with bottom navigation');
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
              'The Paragliding App',
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