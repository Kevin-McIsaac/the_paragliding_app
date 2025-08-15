import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/flight_provider.dart';
import '../../providers/site_provider.dart';
import '../../providers/wing_provider.dart';
import '../../core/dependency_injection.dart';
import 'flight_list_screen.dart';

/// Splash screen that handles async initialization
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late Future<void> _initializationFuture;
  String _loadingMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initializationFuture = _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Step 1: Configure dependencies
      setState(() => _loadingMessage = 'Setting up services...');
      await configureDependencies();
      
      // Small delay to show the message
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Step 2: Initialize providers
      setState(() => _loadingMessage = 'Loading flight data...');
      
      // The actual data loading will happen in the main screen
      // This just ensures services are ready
      await Future.delayed(const Duration(milliseconds: 100));
      
      setState(() => _loadingMessage = 'Ready!');
    } catch (e) {
      setState(() => _loadingMessage = 'Error: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return _buildErrorScreen(snapshot.error.toString());
          }
          
          // Navigate to main app with providers
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
        
        // Show loading screen
        return _buildLoadingScreen();
      },
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App icon or logo
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
            
            // Loading indicator
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            const SizedBox(height: 24),
            
            // Loading message
            Text(
              _loadingMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(String error) {
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
                error,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loadingMessage = 'Retrying...';
                    _initializationFuture = _initializeApp();
                  });
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}