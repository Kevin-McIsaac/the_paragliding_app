import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;
import 'dart:async';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/igc_import_screen.dart';
import 'utils/file_sharing_handler.dart';
import 'data/datasources/database_helper.dart';

void main() {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize sqflite for desktop platforms
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  // OPTIMIZATION: Lazy load timezone data - only needed for IGC imports  
  // TimezoneService.initialize() will be called lazily in TimezoneService
  // Hot reload test comment
  
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
  StreamSubscription? _intentDataStreamSubscription;
  List<String>? _sharedFiles;

  // Shared theme configurations to avoid duplication
  static const TooltipThemeData _tooltipTheme = TooltipThemeData(
    triggerMode: TooltipTriggerMode.longPress,
    showDuration: Duration(seconds: 2),
    waitDuration: Duration(seconds: 1),
    preferBelow: false,
    verticalOffset: 20,
    margin: EdgeInsets.symmetric(horizontal: 16),
    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: BoxDecoration(
      color: Color(0x80000000),
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
    textStyle: TextStyle(
      fontSize: 9,
      height: 1.2,
      color: Colors.white,
      fontWeight: FontWeight.w500,
    ),
  );

  static const PopupMenuThemeData _popupMenuTheme = PopupMenuThemeData(
    color: Color(0x80000000),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
    textStyle: TextStyle(
      fontSize: 9,
      color: Colors.white,
      fontWeight: FontWeight.w500,
    ),
  );

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
        title: 'Free Flight Log',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          tooltipTheme: _tooltipTheme,
          popupMenuTheme: _popupMenuTheme,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          tooltipTheme: _tooltipTheme,
          popupMenuTheme: _popupMenuTheme,
        ),
          home: _sharedFiles != null && _sharedFiles!.isNotEmpty
              ? IgcImportScreen(initialFiles: _sharedFiles!)
              : const SplashScreen(),
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
        tooltipTheme: _tooltipTheme,
        popupMenuTheme: _popupMenuTheme,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        tooltipTheme: _tooltipTheme,
        popupMenuTheme: _popupMenuTheme,
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

