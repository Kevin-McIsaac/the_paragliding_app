import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/flight_provider.dart';
import '../../providers/site_provider.dart';
import '../../providers/wing_provider.dart';
import '../../core/dependency_injection.dart';
import 'flight_list_screen.dart';

/// Lightweight splash screen that handles async initialization
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Start initialization immediately
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Configure dependencies
      await configureDependencies();
      
      // If successful, navigate to main app
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If initialized, show the main app with providers
    if (_isInitialized) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => serviceLocator<FlightProvider>(),
          ),
          ChangeNotifierProvider(
            create: (_) => serviceLocator<SiteProvider>(),
          ),
          ChangeNotifierProvider(
            create: (_) => serviceLocator<WingProvider>(),
          ),
        ],
        child: const FlightListScreen(),
      );
    }
    
    // If error, show error screen
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to initialize app',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                    });
                    _initialize();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
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