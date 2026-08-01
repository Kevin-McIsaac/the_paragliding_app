import 'package:flutter/material.dart';
import 'main_navigation_screen.dart';
import '../../services/logging_service.dart';
import '../../services/app_initialization_service.dart';
import '../../utils/preferences_helper.dart';

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

    // Create the PGE tables so queries never hit a missing table. The ~11k row
    // data import is deferred to the Sites screen, which is what needs it.
    await AppInitializationService.instance.ensureTables();

    // Resolve the tab to open here, so MainNavigationScreen can build it
    // directly instead of showing a blank frame while preferences load
    final initialIndex = await _lastNavigationIndex();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => MainNavigationScreen(initialIndex: initialIndex),
        ),
      );

      LoggingService.info('App startup completed with bottom navigation');
    }
  }

  /// Last selected tab, validated against the four navigation destinations
  Future<int> _lastNavigationIndex() async {
    try {
      final savedIndex = await PreferencesHelper.getLastNavigationIndex();
      if (savedIndex >= 0 && savedIndex < 4) {
        return savedIndex;
      }
    } catch (error, stackTrace) {
      LoggingService.error(
        'Failed to load last navigation index, using default',
        error,
        stackTrace,
      );
    }
    return 0; // Sites tab
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