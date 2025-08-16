import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;
import 'presentation/screens/splash_screen.dart';
import 'utils/startup_performance_tracker.dart';
import 'data/datasources/database_helper.dart';

void main() {
  // Start performance tracking
  final perfTracker = StartupPerformanceTracker();
  perfTracker.startTracking();
  
  // Ensure Flutter is initialized
  final flutterInitWatch = perfTracker.startMeasurement('Flutter Binding Init');
  WidgetsFlutterBinding.ensureInitialized();
  perfTracker.completeMeasurement('Flutter Binding Init', flutterInitWatch);
  
  // Initialize sqflite for desktop platforms (lightweight, can stay in main)
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    final dbInitWatch = perfTracker.startMeasurement('SQLite FFI Init (Desktop)');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    perfTracker.completeMeasurement('SQLite FFI Init (Desktop)', dbInitWatch);
  }
  
  // OPTIMIZATION: Lazy load timezone data - only needed for IGC imports
  // Timezone initialization moved to when it's actually needed
  // This saves ~50-100ms from startup time
  // TimezoneService.initialize() will be called lazily in TimezoneService
  
  perfTracker.recordTimestamp('Starting App Widget');
  
  // Don't await heavy initialization - let splash screen handle it
  runApp(const FreeFlightLogApp());
}

class FreeFlightLogApp extends StatelessWidget {
  const FreeFlightLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppInitializer();
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final perfTracker = StartupPerformanceTracker();
    
    try {
      // Initialize database (very fast, just creates singleton)
      final dbWatch = perfTracker.startMeasurement('Database Init');
      final db = DatabaseHelper.instance;
      // Pre-warm database connection
      await db.database;
      perfTracker.completeMeasurement('Database Init', dbWatch);
      
      perfTracker.recordTimestamp('App Initialized');
      
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
    // If initialized, show the app
    if (_isInitialized) {
      return MaterialApp(
        title: 'Free Flight Log',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: const SplashScreen(),
      );
    }
    
    // Show loading or error within MaterialApp for theming
    return MaterialApp(
      title: 'Free Flight Log',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: _error != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text('Failed to initialize: $_error'),
                    const SizedBox(height: 16),
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
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

