import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;
import 'presentation/screens/flight_list_screen.dart';
import 'services/timezone_service.dart';
import 'providers/flight_provider.dart';
import 'providers/site_provider.dart';
import 'providers/wing_provider.dart';
import 'data/repositories/flight_repository.dart';
import 'data/repositories/site_repository.dart';
import 'data/repositories/wing_repository.dart';

void main() {
  // Initialize sqflite for desktop platforms
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  // Initialize timezone database
  TimezoneService.initialize();
  
  runApp(const FreeFlightLogApp());
}

class FreeFlightLogApp extends StatelessWidget {
  const FreeFlightLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => FlightProvider(FlightRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => SiteProvider(SiteRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => WingProvider(WingRepository()),
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

