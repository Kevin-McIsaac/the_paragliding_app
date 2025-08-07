import 'package:get_it/get_it.dart';
import '../data/datasources/database_helper.dart';
import '../data/repositories/flight_repository.dart';
import '../data/repositories/site_repository.dart';
import '../data/repositories/wing_repository.dart';
import '../data/services/flight_query_service.dart';
import '../data/services/flight_statistics_service.dart';
import '../providers/flight_provider.dart';
import '../providers/site_provider.dart';
import '../providers/wing_provider.dart';
import '../services/logging_service.dart';

/// Dependency injection service locator instance
final GetIt serviceLocator = GetIt.instance;

/// Configure all dependencies for the application
/// This should be called once at app startup
Future<void> configureDependencies() async {
  LoggingService.info('DI: Configuring dependencies');
  
  // Register core services first
  _registerCoreServices();
  
  // Register data sources
  await _registerDataSources();
  
  // Register repositories  
  _registerRepositories();
  
  // Register business services
  _registerServices();
  
  // Register providers (state management)
  _registerProviders();
  
  LoggingService.info('DI: Dependencies configured successfully');
}

/// Register core services like logging
void _registerCoreServices() {
  LoggingService.debug('DI: Registering core services');
  
  // LoggingService is static, no registration needed
  // Add other services here as needed
}

/// Register data sources (database, network, etc.)
Future<void> _registerDataSources() async {
  LoggingService.debug('DI: Registering data sources');
  
  // Register DatabaseHelper as singleton to ensure single database instance
  serviceLocator.registerSingletonAsync<DatabaseHelper>(
    () async {
      final dbHelper = DatabaseHelper.instance;
      // Initialize the database to ensure it's ready
      await dbHelper.database;
      LoggingService.info('DI: DatabaseHelper initialized');
      return dbHelper;
    },
  );
  
  // Wait for database to be ready before proceeding
  await serviceLocator.isReady<DatabaseHelper>();
}

/// Register repositories with proper dependency injection
void _registerRepositories() {
  LoggingService.debug('DI: Registering repositories');
  
  // Register FlightRepository with DatabaseHelper dependency
  serviceLocator.registerLazySingleton<FlightRepository>(
    () => FlightRepository(serviceLocator<DatabaseHelper>()),
  );
  
  // Register SiteRepository with DatabaseHelper dependency
  serviceLocator.registerLazySingleton<SiteRepository>(
    () => SiteRepository(serviceLocator<DatabaseHelper>()),
  );
  
  // Register WingRepository with DatabaseHelper dependency  
  serviceLocator.registerLazySingleton<WingRepository>(
    () => WingRepository(serviceLocator<DatabaseHelper>()),
  );
}

/// Register business services with proper dependency injection
void _registerServices() {
  LoggingService.debug('DI: Registering business services');
  
  // Register FlightQueryService with DatabaseHelper dependency
  serviceLocator.registerLazySingleton<FlightQueryService>(
    () => FlightQueryService(serviceLocator<DatabaseHelper>()),
  );
  
  // Register FlightStatisticsService with DatabaseHelper dependency
  serviceLocator.registerLazySingleton<FlightStatisticsService>(
    () => FlightStatisticsService(serviceLocator<DatabaseHelper>()),
  );
}

/// Register providers (state management) with repository dependencies
void _registerProviders() {
  LoggingService.debug('DI: Registering providers');
  
  // Register FlightProvider with FlightRepository dependency
  serviceLocator.registerFactory<FlightProvider>(
    () => FlightProvider(serviceLocator<FlightRepository>()),
  );
  
  // Register SiteProvider with SiteRepository dependency
  serviceLocator.registerFactory<SiteProvider>(
    () => SiteProvider(serviceLocator<SiteRepository>()),
  );
  
  // Register WingProvider with WingRepository dependency
  serviceLocator.registerFactory<WingProvider>(
    () => WingProvider(serviceLocator<WingRepository>()),
  );
}

/// Reset all dependencies (useful for testing)
Future<void> resetDependencies() async {
  LoggingService.debug('DI: Resetting dependencies');
  await serviceLocator.reset();
}

/// Register mock implementations for testing
/// This should only be called in test environments
void registerMockDependencies() {
  LoggingService.debug('DI: Registering mock dependencies for testing');
  
  // This would be implemented for testing purposes
  // Example:
  // serviceLocator.registerSingleton<DatabaseHelper>(MockDatabaseHelper());
  // serviceLocator.registerSingleton<FlightRepository>(MockFlightRepository());
  
  throw UnimplementedError('Mock dependencies not yet implemented');
}

/// Check if all required dependencies are registered
bool get dependenciesConfigured {
  return serviceLocator.isRegistered<DatabaseHelper>() &&
         serviceLocator.isRegistered<FlightRepository>() &&
         serviceLocator.isRegistered<SiteRepository>() &&
         serviceLocator.isRegistered<WingRepository>() &&
         serviceLocator.isRegistered<FlightQueryService>() &&
         serviceLocator.isRegistered<FlightStatisticsService>() &&
         serviceLocator.isRegistered<FlightProvider>() &&
         serviceLocator.isRegistered<SiteProvider>() &&
         serviceLocator.isRegistered<WingProvider>();
}