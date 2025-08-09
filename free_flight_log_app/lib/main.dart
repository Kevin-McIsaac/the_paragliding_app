import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;
import 'presentation/screens/flight_list_screen.dart';
import 'services/timezone_service.dart';
import 'providers/flight_provider.dart';
import 'providers/site_provider.dart';
import 'providers/wing_provider.dart';
import 'core/dependency_injection.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize sqflite for desktop platforms
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  // Initialize timezone database
  TimezoneService.initialize();
  
  // Configure dependency injection
  await configureDependencies();
  
  runApp(const FreeFlightLogApp());
}

class FreeFlightLogApp extends StatelessWidget {
  const FreeFlightLogApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      child: MaterialApp(
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
        home: const FlightListScreen(),
      ),
    );
  }
}

