import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;
import 'dart:async';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/igc_import_screen.dart';
import 'utils/file_sharing_handler.dart';
import 'utils/performance_monitor.dart';
import 'data/datasources/database_helper.dart';
import 'services/api_keys.dart';
import 'services/performance_metrics_service.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize sqflite for desktop platforms
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize API keys from environment variables
  await ApiKeys.initialize();
  ApiKeys.logStatus(); // Log API key configuration status

  // OPTIMIZATION: Lazy load timezone data - only needed for IGC imports
  // TimezoneService.initialize() will be called lazily in TimezoneService

  // Initialize performance monitoring
  PerformanceMonitor.initializeFrameRateMonitoring();
  PerformanceMetricsService.initialize();  // Initialize the metrics service for periodic summaries

  runApp(const TheParaglidingApp());
}

class TheParaglidingApp extends StatelessWidget {
  const TheParaglidingApp({super.key});

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
  StreamSubscription? _intentDataStreamSubscription;
  List<String>? _sharedFiles;

  // Shared theme configurations to avoid duplication

  static const PopupMenuThemeData _popupMenuTheme = PopupMenuThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
    textStyle: TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w500,
    ),
  );

  static TooltipThemeData _getTooltipTheme(ColorScheme colorScheme) {
    return TooltipThemeData(
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: TextStyle(
        color: colorScheme.onInverseSurface,
        fontSize: 12, // Material Design 3 Body Small
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      preferBelow: false, // Position above by default
      verticalOffset: 8,
      waitDuration: const Duration(milliseconds: 500), // Desktop hover delay
      showDuration: const Duration(milliseconds: 1500), // Auto-dismiss on mobile
    );
  }

  @override
  void initState() {
    super.initState();
    _initialize();
    _handleIncomingFiles();
  }
  
  void _handleIncomingFiles() async {
    // Get initial shared files (if any)
    final initialFiles = await FileSharingHandler.initialize();
    if (initialFiles != null && initialFiles.isNotEmpty) {
      setState(() {
        _sharedFiles = initialFiles;
      });
    }
    
    // Listen for incoming shared files
    _intentDataStreamSubscription = FileSharingHandler.listen((files) {
      setState(() {
        _sharedFiles = files;
      });
    });
  }
  
  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      // Initialize database
      final db = DatabaseHelper.instance;
      // Pre-warm database connection
      await db.database;

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
        title: 'The Paragliding App',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          popupMenuTheme: _popupMenuTheme,
          tooltipTheme: _getTooltipTheme(ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          )),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          appBarTheme: AppBarTheme(
            backgroundColor: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ).surfaceContainer,
            foregroundColor: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ).onSurface,
          ),
          popupMenuTheme: _popupMenuTheme,
          tooltipTheme: _getTooltipTheme(ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          )),
        ),
          home: _sharedFiles != null && _sharedFiles!.isNotEmpty
              ? IgcImportScreen(initialFiles: _sharedFiles!)
              : const SplashScreen(),
      );
    }
    
    // Show loading or error within MaterialApp for theming
    return MaterialApp(
      title: 'The Paragliding App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        popupMenuTheme: _popupMenuTheme,
        tooltipTheme: _getTooltipTheme(ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        )),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ).surfaceContainer,
          foregroundColor: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ).onSurface,
        ),
        popupMenuTheme: _popupMenuTheme,
        tooltipTheme: _getTooltipTheme(ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        )),
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

