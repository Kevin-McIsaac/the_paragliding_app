import 'package:get_it/get_it.dart';
import '../data/datasources/database_helper.dart';
import '../data/repositories/flight_repository.dart';
import '../data/repositories/site_repository.dart';
import '../data/repositories/wing_repository.dart';
import '../data/services/flight_query_service.dart';
import '../data/services/flight_statistics_service.dart';
import '../services/igc_import_service.dart';
import '../providers/flight_provider.dart';
import '../providers/site_provider.dart';
import '../providers/wing_provider.dart';
import '../services/logging_service.dart';
import '../utils/startup_performance_tracker.dart';

/// Dependency injection service locator instance
final GetIt serviceLocator = GetIt.instance;

/// Configure all dependencies for the application
/// This should be called once at app startup
/// Set [testing] to true for test environment
Future<void> configureDependencies({
  bool testing = false,
  StartupPerformanceTracker? perfTracker,
}) async {
  LoggingService.info('DI: Configuring dependencies${testing ? ' (testing mode)' : ''}');
  
  // Register core services first
  final coreWatch = perfTracker?.startMeasurement('Register Core Services');
  _registerCoreServices();
  if (coreWatch != null) perfTracker?.completeMeasurement('Register Core Services', coreWatch);
  
  // Register data sources
  final dataWatch = perfTracker?.startMeasurement('Register & Init Database');
  await _registerDataSources();
  if (dataWatch != null) perfTracker?.completeMeasurement('Register & Init Database', dataWatch);
  
  // Register repositories  
  final repoWatch = perfTracker?.startMeasurement('Register Repositories');
  _registerRepositories();
  if (repoWatch != null) perfTracker?.completeMeasurement('Register Repositories', repoWatch);
  
  // Register business services
  final servicesWatch = perfTracker?.startMeasurement('Register Services');
  _registerServices();
  if (servicesWatch != null) perfTracker?.completeMeasurement('Register Services', servicesWatch);
  
  // Register providers (state management)
  final providersWatch = perfTracker?.startMeasurement('Register Providers');
  _registerProviders();
  if (providersWatch != null) perfTracker?.completeMeasurement('Register Providers', providersWatch);
  
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
  
  // OPTIMIZATION: Register DatabaseHelper lazily - don't initialize until first use
  // This defers database initialization (schema creation, index creation) until
  // the first actual database query, saving 100-500ms from startup
  serviceLocator.registerLazySingleton<DatabaseHelper>(
    () {
      LoggingService.info('DI: DatabaseHelper created (lazy)');
      return DatabaseHelper.instance;
    },
  );
  
  // Don't wait for database - let it initialize on first use
  // This allows the app to show UI immediately
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
  
  // Register IgcImportService - it will get its dependencies from serviceLocator
  serviceLocator.registerLazySingleton<IgcImportService>(
    () => IgcImportService(),
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