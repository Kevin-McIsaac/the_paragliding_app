import 'package:flutter_test/flutter_test.dart';
import 'package:free_flight_log_app/services/database_service.dart';
import 'package:free_flight_log_app/data/models/flight.dart';
import 'package:free_flight_log_app/data/models/site.dart';
import 'package:free_flight_log_app/data/models/wing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    // Initialize FFI for testing
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseService - Flight Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = DatabaseService.instance;
    });

    test('should insert and retrieve a flight', () async {
      // Arrange
      final flight = Flight(
        date: DateTime.parse('2024-07-15'),
        launchTime: '10:00',
        landingTime: '12:00',
        duration: 120,
        launchSiteId: 1,
        wingId: 1,
        maxAltitude: 2000.0,
        distance: 15.5,
        notes: 'Test flight for database service',
        source: 'manual',
      );

      // Act
      final flightId = await databaseService.insertFlight(flight);
      final retrievedFlight = await databaseService.getFlight(flightId);

      // Assert
      expect(retrievedFlight, isNotNull);
      expect(retrievedFlight!.launchTime, equals('10:00'));
      expect(retrievedFlight.landingTime, equals('12:00'));
      expect(retrievedFlight.duration, equals(120));
      expect(retrievedFlight.maxAltitude, equals(2000.0));
    });

    test('should get all flights', () async {
      // Act
      final flights = await databaseService.getAllFlights();

      // Assert
      expect(flights, isA<List<Flight>>());
      // We can't predict exact count due to previous test data
      expect(flights.length, greaterThanOrEqualTo(0));
    });

    test('should get flight count', () async {
      // Act
      final count = await databaseService.getFlightCount();

      // Assert
      expect(count, isA<int>());
      expect(count, greaterThanOrEqualTo(0));
    });

    test('should update a flight', () async {
      // Arrange
      final originalFlight = Flight(
        date: DateTime.parse('2024-08-01'),
        launchTime: '09:30',
        landingTime: '11:00',
        duration: 90,
        notes: 'Original notes',
        source: 'manual',
      );
      
      final flightId = await databaseService.insertFlight(originalFlight);
      final insertedFlight = await databaseService.getFlight(flightId);
      
      final updatedFlight = insertedFlight!.copyWith(
        notes: 'Updated notes',
        maxAltitude: 2500.0,
      );

      // Act
      await databaseService.updateFlight(updatedFlight);
      final retrievedFlight = await databaseService.getFlight(flightId);

      // Assert
      expect(retrievedFlight!.notes, equals('Updated notes'));
      expect(retrievedFlight.maxAltitude, equals(2500.0));
    });

    test('should delete a flight', () async {
      // Arrange
      final flight = Flight(
        date: DateTime.parse('2024-09-01'),
        launchTime: '14:00',
        landingTime: '16:30',
        duration: 150,
        source: 'manual',
      );
      
      final flightId = await databaseService.insertFlight(flight);

      // Act
      await databaseService.deleteFlight(flightId);
      final deletedFlight = await databaseService.getFlight(flightId);

      // Assert
      expect(deletedFlight, isNull);
    });
  });

  group('DatabaseService - Site Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = DatabaseService.instance;
    });

    test('should insert and retrieve a site', () async {
      // Arrange
      final site = Site(
        name: 'Test Launch Site',
        latitude: 46.5197,
        longitude: 6.6323,
        altitude: 1500.0,
        country: 'Switzerland',
      );

      // Act
      final siteId = await databaseService.insertSite(site);
      final retrievedSite = await databaseService.getSite(siteId);

      // Assert
      expect(retrievedSite, isNotNull);
      expect(retrievedSite!.name, equals('Test Launch Site'));
      expect(retrievedSite.latitude, equals(46.5197));
      expect(retrievedSite.longitude, equals(6.6323));
      expect(retrievedSite.altitude, equals(1500.0));
    });

    test('should get all sites', () async {
      // Act
      final sites = await databaseService.getAllSites();

      // Assert
      expect(sites, isA<List<Site>>());
      expect(sites.length, greaterThanOrEqualTo(0));
    });

    test('should update a site', () async {
      // Arrange
      final originalSite = Site(
        name: 'Original Site Name',
        latitude: 47.0,
        longitude: 8.0,
        country: 'Switzerland',
      );
      
      final siteId = await databaseService.insertSite(originalSite);
      final insertedSite = await databaseService.getSite(siteId);
      
      final updatedSite = insertedSite!.copyWith(
        name: 'Updated Site Name',
        altitude: 1800.0,
      );

      // Act
      await databaseService.updateSite(updatedSite);
      final retrievedSite = await databaseService.getSite(siteId);

      // Assert
      expect(retrievedSite!.name, equals('Updated Site Name'));
      expect(retrievedSite.altitude, equals(1800.0));
    });

    test('should delete a site', () async {
      // Arrange
      final site = Site(
        name: 'Site to Delete',
        latitude: 45.0,
        longitude: 7.0,
      );
      
      final siteId = await databaseService.insertSite(site);

      // Act
      await databaseService.deleteSite(siteId);
      final deletedSite = await databaseService.getSite(siteId);

      // Assert
      expect(deletedSite, isNull);
    });
  });

  group('DatabaseService - Wing Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = DatabaseService.instance;
    });

    test('should insert and retrieve a wing', () async {
      // Arrange
      final wing = Wing(
        name: 'Test Wing',
        manufacturer: 'Advance',
        model: 'Epsilon 9',
        size: '27',
        notes: 'Test wing for database service',
      );

      // Act
      final wingId = await databaseService.insertWing(wing);
      final retrievedWing = await databaseService.getWing(wingId);

      // Assert
      expect(retrievedWing, isNotNull);
      expect(retrievedWing!.name, equals('Test Wing'));
      expect(retrievedWing.manufacturer, equals('Advance'));
      expect(retrievedWing.model, equals('Epsilon 9'));
      expect(retrievedWing.size, equals('27'));
    });

    test('should get all wings', () async {
      // Act
      final wings = await databaseService.getAllWings();

      // Assert
      expect(wings, isA<List<Wing>>());
      expect(wings.length, greaterThanOrEqualTo(0));
    });

    test('should get active wings', () async {
      // Arrange - Insert an active and inactive wing
      final activeWing = Wing(name: 'Active Wing', active: true);
      final inactiveWing = Wing(name: 'Inactive Wing', active: false);
      
      await databaseService.insertWing(activeWing);
      await databaseService.insertWing(inactiveWing);

      // Act
      final activeWings = await databaseService.getActiveWings();

      // Assert
      expect(activeWings, isA<List<Wing>>());
      expect(activeWings.where((w) => w.name == 'Active Wing'), hasLength(1));
      expect(activeWings.where((w) => w.name == 'Inactive Wing'), hasLength(0));
    });

    test('should update a wing', () async {
      // Arrange
      final originalWing = Wing(
        name: 'Original Wing',
        manufacturer: 'Test Manufacturer',
        model: 'Test Model',
      );
      
      final wingId = await databaseService.insertWing(originalWing);
      final insertedWing = await databaseService.getWing(wingId);
      
      final updatedWing = insertedWing!.copyWith(
        manufacturer: 'Updated Manufacturer',
        size: 'L',
      );

      // Act
      await databaseService.updateWing(updatedWing);
      final retrievedWing = await databaseService.getWing(wingId);

      // Assert
      expect(retrievedWing!.manufacturer, equals('Updated Manufacturer'));
      expect(retrievedWing.size, equals('L'));
    });

    test('should deactivate a wing', () async {
      // Arrange
      final wing = Wing(name: 'Wing to Deactivate', active: true);
      final wingId = await databaseService.insertWing(wing);

      // Act
      await databaseService.deactivateWing(wingId);
      final deactivatedWing = await databaseService.getWing(wingId);

      // Assert
      expect(deactivatedWing!.active, isFalse);
    });
  });

  group('DatabaseService - Statistics Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = DatabaseService.instance;
    });

    test('should get overall statistics', () async {
      // Act
      final stats = await databaseService.getOverallStatistics();

      // Assert
      expect(stats, isA<Map<String, dynamic>>());
    });

    test('should get yearly statistics', () async {
      // Act
      final yearlyStats = await databaseService.getYearlyStatistics();

      // Assert
      expect(yearlyStats, isA<List<Map<String, dynamic>>>());
    });

    test('should get site statistics', () async {
      // Act
      final siteStats = await databaseService.getSiteStatistics();

      // Assert
      expect(siteStats, isA<List<Map<String, dynamic>>>());
    });

    test('should get wing statistics', () async {
      // Act
      final wingStats = await databaseService.getWingStatistics();

      // Assert
      expect(wingStats, isA<List<Map<String, dynamic>>>());
    });
  });

  group('DatabaseService - Search Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = DatabaseService.instance;
    });

    test('should search flights by query', () async {
      // Arrange - Insert a flight with specific notes
      final searchableFlight = Flight(
        date: DateTime.parse('2024-10-01'),
        launchTime: '10:00',
        landingTime: '12:00',
        duration: 120,
        notes: 'Beautiful thermal flight over the Alps',
        source: 'manual',
      );
      await databaseService.insertFlight(searchableFlight);

      // Act
      final searchResults = await databaseService.searchFlights('Alps');

      // Assert
      expect(searchResults, isA<List<Flight>>());
      expect(searchResults.where((f) => f.notes?.contains('Alps') == true), isNotEmpty);
    });

    test('should find flight by filename', () async {
      // Arrange
      final flight = Flight(
        date: DateTime.parse('2024-11-01'),
        launchTime: '09:00',
        landingTime: '11:30',
        duration: 150,
        originalFilename: 'unique_test_file.igc',
        source: 'manual',
      );
      await databaseService.insertFlight(flight);

      // Act
      final foundFlight = await databaseService.findFlightByFilename('unique_test_file.igc');

      // Assert
      expect(foundFlight, isNotNull);
      expect(foundFlight!.originalFilename, equals('unique_test_file.igc'));
    });
  });
}