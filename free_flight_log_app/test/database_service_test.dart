import 'package:flutter_test/flutter_test.dart';
import 'package:free_flight_log/services/database_service.dart';
import 'package:free_flight_log/data/models/flight.dart';
import 'package:free_flight_log/data/models/site.dart';
import 'package:free_flight_log/data/models/wing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'helpers/test_helpers.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Flight CRUD Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = await TestHelpers.initializeDatabaseForTesting();
    });

    tearDown(() async {
      await databaseService.close();
    });

    test('should insert a flight and retrieve it', () async {
      // Arrange
      final site = Site(
        id: 1,
        name: 'Test Launch',
        latitude: 46.0,
        longitude: 7.0,
      );
      await databaseService.insertSite(site);

      final wing = Wing(
        id: 1,
        name: 'Test Wing',
        manufacturer: 'Test Mfg',
        model: 'TestModel',
      );
      await databaseService.insertWing(wing);

      final flight = Flight(
        id: 1,
        date: '2023-07-15',
        launchSiteId: 1,
        wingId: 1,
        launchTime: '14:30',
        landingTime: '16:15',
        duration: 105,
        maxAltitude: 2500,
        igcFileName: 'test_flight.igc',
      );

      // Act
      await databaseService.insertFlight(flight);
      final retrievedFlight = await databaseService.getFlight(1);

      // Assert
      expect(retrievedFlight, isNotNull);
      expect(retrievedFlight!.id, equals(1));
      expect(retrievedFlight.date, equals('2023-07-15'));
      expect(retrievedFlight.launchSiteId, equals(1));
      expect(retrievedFlight.wingId, equals(1));
    });

    test('should update an existing flight', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Launch', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test Mfg', model: 'TestModel');
      await databaseService.insertWing(wing);

      final originalFlight = Flight(
        id: 1,
        date: '2023-07-15',
        launchSiteId: 1,
        wingId: 1,
        launchTime: '14:30',
        landingTime: '16:15',
        duration: 105,
        maxAltitude: 2500,
        igcFileName: 'test_flight.igc',
      );
      await databaseService.insertFlight(originalFlight);

      final updatedFlight = originalFlight.copyWith(
        duration: 120,
        maxAltitude: 2800,
        landingTime: '16:30',
      );

      // Act
      await databaseService.updateFlight(updatedFlight);
      final retrievedFlight = await databaseService.getFlight(1);

      // Assert
      expect(retrievedFlight!.duration, equals(120));
      expect(retrievedFlight.maxAltitude, equals(2800));
      expect(retrievedFlight.landingTime, equals('16:30'));
    });

    test('should delete a flight', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Launch', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test Mfg', model: 'TestModel');
      await databaseService.insertWing(wing);

      final flight = Flight(
        id: 1,
        date: '2023-07-15',
        launchSiteId: 1,
        wingId: 1,
        launchTime: '14:30',
        landingTime: '16:15',
        duration: 105,
        maxAltitude: 2500,
        igcFileName: 'test_flight.igc',
      );
      await databaseService.insertFlight(flight);

      // Act
      await databaseService.deleteFlight(1);
      final retrievedFlight = await databaseService.getFlight(1);

      // Assert
      expect(retrievedFlight, isNull);
    });

    test('should return null for non-existent flight', () async {
      // Act
      final flight = await databaseService.getFlight(999);

      // Assert
      expect(flight, isNull);
    });

    test('should get all flights ordered by date descending', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Launch', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test Mfg', model: 'TestModel');
      await databaseService.insertWing(wing);

      final flight1 = Flight(
        id: 1,
        date: '2023-07-15',
        launchSiteId: 1,
        wingId: 1,
        launchTime: '14:30',
        landingTime: '16:15',
        duration: 105,
        maxAltitude: 2500,
        igcFileName: 'flight1.igc',
      );

      final flight2 = Flight(
        id: 2,
        date: '2023-07-20',
        launchSiteId: 1,
        wingId: 1,
        launchTime: '15:00',
        landingTime: '17:30',
        duration: 150,
        maxAltitude: 3000,
        igcFileName: 'flight2.igc',
      );

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);

      // Act
      final flights = await databaseService.getAllFlights();

      // Assert
      expect(flights, hasLength(2));
      expect(flights.first.date, equals('2023-07-20')); // Most recent first
      expect(flights.last.date, equals('2023-07-15'));
    });

    test('should get flight count', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Launch', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test Mfg', model: 'TestModel');
      await databaseService.insertWing(wing);

      final flight = Flight(
        id: 1,
        date: '2023-07-15',
        launchSiteId: 1,
        wingId: 1,
        launchTime: '14:30',
        landingTime: '16:15',
        duration: 105,
        maxAltitude: 2500,
        igcFileName: 'test_flight.igc',
      );
      await databaseService.insertFlight(flight);

      // Act
      final count = await databaseService.getFlightCount();

      // Assert
      expect(count, equals(1));
    });

    test('should handle empty flights table', () async {
      // Act
      final flights = await databaseService.getAllFlights();
      final count = await databaseService.getFlightCount();

      // Assert
      expect(flights, isEmpty);
      expect(count, equals(0));
    });

    test('should handle invalid flight data gracefully', () async {
      // This test ensures the database handles constraint violations properly
      final invalidFlight = Flight(
        id: 1,
        date: '',  // Invalid empty date
        launchSiteId: 999,  // Non-existent site
        wingId: 999,  // Non-existent wing
        launchTime: '14:30',
        landingTime: '16:15',
        duration: 105,
        maxAltitude: 2500,
        igcFileName: 'test_flight.igc',
      );

      // Act & Assert
      expect(
        () => databaseService.insertFlight(invalidFlight),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Site Management Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = await TestHelpers.initializeDatabaseForTesting();
    });

    tearDown(() async {
      await databaseService.close();
    });

    test('should insert and retrieve a site', () async {
      // Arrange
      final site = Site(
        id: 1,
        name: 'Alpine Launch',
        latitude: 46.5,
        longitude: 7.8,
        altitude: 1200,
        description: 'Beautiful alpine launch site',
      );

      // Act
      await databaseService.insertSite(site);
      final retrievedSite = await databaseService.getSite(1);

      // Assert
      expect(retrievedSite, isNotNull);
      expect(retrievedSite!.name, equals('Alpine Launch'));
      expect(retrievedSite.latitude, equals(46.5));
      expect(retrievedSite.longitude, equals(7.8));
    });

    test('should update an existing site', () async {
      // Arrange
      final originalSite = Site(
        id: 1,
        name: 'Alpine Launch',
        latitude: 46.5,
        longitude: 7.8,
      );
      await databaseService.insertSite(originalSite);

      final updatedSite = originalSite.copyWith(
        name: 'Updated Alpine Launch',
        altitude: 1300,
        description: 'Updated description',
      );

      // Act
      await databaseService.updateSite(updatedSite);
      final retrievedSite = await databaseService.getSite(1);

      // Assert
      expect(retrievedSite!.name, equals('Updated Alpine Launch'));
      expect(retrievedSite.altitude, equals(1300));
      expect(retrievedSite.description, equals('Updated description'));
    });

    test('should delete a site when no flights reference it', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      // Act
      await databaseService.deleteSite(1);
      final retrievedSite = await databaseService.getSite(1);

      // Assert
      expect(retrievedSite, isNull);
    });

    test('should get all sites ordered alphabetically by name', () async {
      // Arrange
      final site1 = Site(id: 1, name: 'Zermatt Launch', latitude: 46.0, longitude: 7.0);
      final site2 = Site(id: 2, name: 'Alpine Launch', latitude: 46.5, longitude: 7.5);
      final site3 = Site(id: 3, name: 'Mountain Top', latitude: 47.0, longitude: 8.0);

      await databaseService.insertSite(site1);
      await databaseService.insertSite(site2);
      await databaseService.insertSite(site3);

      // Act
      final sites = await databaseService.getAllSites();

      // Assert
      expect(sites, hasLength(3));
      expect(sites[0].name, equals('Alpine Launch'));
      expect(sites[1].name, equals('Mountain Top'));
      expect(sites[2].name, equals('Zermatt Launch'));
    });

    test('should find site by coordinates within tolerance', () async {
      // Arrange
      final site = Site(
        id: 1,
        name: 'Exact Location',
        latitude: 46.5000,
        longitude: 7.8000,
      );
      await databaseService.insertSite(site);

      // Act - Search with coordinates very close to the original
      final foundSite = await databaseService.findSiteByCoordinates(
        46.5001,  // 0.0001 degrees difference
        7.8001,
        0.001,    // 0.001 tolerance should find it
      );

      // Assert
      expect(foundSite, isNotNull);
      expect(foundSite!.name, equals('Exact Location'));
    });

    test('should not find site by coordinates outside tolerance', () async {
      // Arrange
      final site = Site(
        id: 1,
        name: 'Exact Location',
        latitude: 46.5000,
        longitude: 7.8000,
      );
      await databaseService.insertSite(site);

      // Act - Search with coordinates far from the original
      final foundSite = await databaseService.findSiteByCoordinates(
        46.6000,  // 0.1 degrees difference
        7.9000,
        0.001,    // 0.001 tolerance should not find it
      );

      // Assert
      expect(foundSite, isNull);
    });

    test('should search sites by name pattern', () async {
      // Arrange
      final site1 = Site(id: 1, name: 'Alpine Launch Site', latitude: 46.0, longitude: 7.0);
      final site2 = Site(id: 2, name: 'Mountain Peak', latitude: 46.5, longitude: 7.5);
      final site3 = Site(id: 3, name: 'Alpine Valley', latitude: 47.0, longitude: 8.0);

      await databaseService.insertSite(site1);
      await databaseService.insertSite(site2);
      await databaseService.insertSite(site3);

      // Act
      final alpineSites = await databaseService.searchSites('Alpine');

      // Assert
      expect(alpineSites, hasLength(2));
      expect(alpineSites.any((s) => s.name.contains('Alpine Launch')), isTrue);
      expect(alpineSites.any((s) => s.name.contains('Alpine Valley')), isTrue);
    });

    test('should find or create site', () async {
      // Arrange
      final existingSite = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(existingSite);

      // Act - Find existing
      final foundSite = await databaseService.findOrCreateSite('Test Site', 46.0, 7.0);

      // Act - Create new
      final newSite = await databaseService.findOrCreateSite('New Site', 47.0, 8.0);

      // Assert
      expect(foundSite.id, equals(1));
      expect(foundSite.name, equals('Test Site'));
      expect(newSite.id, isNotNull);
      expect(newSite.name, equals('New Site'));
    });

    test('should get sites within bounding box', () async {
      // Arrange
      final site1 = Site(id: 1, name: 'Inside Box', latitude: 46.5, longitude: 7.5);
      final site2 = Site(id: 2, name: 'Outside Box', latitude: 48.0, longitude: 9.0);
      final site3 = Site(id: 3, name: 'Edge Case', latitude: 47.0, longitude: 8.0);

      await databaseService.insertSite(site1);
      await databaseService.insertSite(site2);
      await databaseService.insertSite(site3);

      // Act - Define bounding box that includes site1 and site3 but not site2
      final sitesInBox = await databaseService.getSitesInBoundingBox(
        46.0, 47.5,  // lat min, lat max
        7.0, 8.5,    // lng min, lng max
      );

      // Assert
      expect(sitesInBox, hasLength(2));
      expect(sitesInBox.any((s) => s.name == 'Inside Box'), isTrue);
      expect(sitesInBox.any((s) => s.name == 'Edge Case'), isTrue);
      expect(sitesInBox.any((s) => s.name == 'Outside Box'), isFalse);
    });
  });

  group('Wing Management Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = await TestHelpers.initializeDatabaseForTesting();
    });

    tearDown() async {
      await databaseService.close();
    });

    test('should insert and retrieve a wing', () async {
      // Arrange
      final wing = Wing(
        id: 1,
        name: 'Test Wing',
        manufacturer: 'Advance',
        model: 'Epsilon 9',
        size: '27',
        certification: 'EN-B',
        isActive: true,
      );

      // Act
      await databaseService.insertWing(wing);
      final retrievedWing = await databaseService.getWing(1);

      // Assert
      expect(retrievedWing, isNotNull);
      expect(retrievedWing!.name, equals('Test Wing'));
      expect(retrievedWing.manufacturer, equals('Advance'));
      expect(retrievedWing.model, equals('Epsilon 9'));
    });

    test('should update an existing wing', () async {
      // Arrange
      final originalWing = Wing(
        id: 1,
        name: 'Test Wing',
        manufacturer: 'Advance',
        model: 'Epsilon 9',
      );
      await databaseService.insertWing(originalWing);

      final updatedWing = originalWing.copyWith(
        size: '29',
        certification: 'EN-B',
        isActive: false,
      );

      // Act
      await databaseService.updateWing(updatedWing);
      final retrievedWing = await databaseService.getWing(1);

      // Assert
      expect(retrievedWing!.size, equals('29'));
      expect(retrievedWing.certification, equals('EN-B'));
      expect(retrievedWing.isActive, isFalse);
    });

    test('should delete a wing when no flights reference it', () async {
      // Arrange
      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      // Act
      await databaseService.deleteWing(1);
      final retrievedWing = await databaseService.getWing(1);

      // Assert
      expect(retrievedWing, isNull);
    });

    test('should get all wings ordered by name', () async {
      // Arrange
      final wing1 = Wing(id: 1, name: 'Zulu Wing', manufacturer: 'Test', model: 'Model1');
      final wing2 = Wing(id: 2, name: 'Alpha Wing', manufacturer: 'Test', model: 'Model2');
      final wing3 = Wing(id: 3, name: 'Beta Wing', manufacturer: 'Test', model: 'Model3');

      await databaseService.insertWing(wing1);
      await databaseService.insertWing(wing2);
      await databaseService.insertWing(wing3);

      // Act
      final wings = await databaseService.getAllWings();

      // Assert
      expect(wings, hasLength(3));
      expect(wings[0].name, equals('Alpha Wing'));
      expect(wings[1].name, equals('Beta Wing'));
      expect(wings[2].name, equals('Zulu Wing'));
    });

    test('should get only active wings', () async {
      // Arrange
      final activeWing = Wing(id: 1, name: 'Active Wing', manufacturer: 'Test', model: 'Model1', isActive: true);
      final inactiveWing = Wing(id: 2, name: 'Inactive Wing', manufacturer: 'Test', model: 'Model2', isActive: false);

      await databaseService.insertWing(activeWing);
      await databaseService.insertWing(inactiveWing);

      // Act
      final activeWings = await databaseService.getActiveWings();

      // Assert
      expect(activeWings, hasLength(1));
      expect(activeWings.first.name, equals('Active Wing'));
    });

    test('should deactivate wing', () async {
      // Arrange
      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model', isActive: true);
      await databaseService.insertWing(wing);

      // Act
      await databaseService.deactivateWing(1);
      final retrievedWing = await databaseService.getWing(1);

      // Assert
      expect(retrievedWing!.isActive, isFalse);
    });

    test('should find or create wing', () async {
      // Arrange
      final existingWing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(existingWing);

      // Act - Find existing
      final foundWing = await databaseService.findOrCreateWing('Test Wing', 'Test', 'Model');

      // Act - Create new
      final newWing = await databaseService.findOrCreateWing('New Wing', 'New', 'Model');

      // Assert
      expect(foundWing.id, equals(1));
      expect(foundWing.name, equals('Test Wing'));
      expect(newWing.id, isNotNull);
      expect(newWing.name, equals('New Wing'));
    });
  });

  group('Wing Alias Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = await TestHelpers.initializeDatabaseForTesting();
    });

    tearDown() async {
      await databaseService.close();
    });

    test('should add and retrieve wing aliases', () async {
      // Arrange
      final wing = Wing(id: 1, name: 'Primary Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      // Act
      await databaseService.addWingAlias(1, 'Wing Alias 1');
      await databaseService.addWingAlias(1, 'Wing Alias 2');
      final aliases = await databaseService.getWingAliases(1);

      // Assert
      expect(aliases, hasLength(2));
      expect(aliases, contains('Wing Alias 1'));
      expect(aliases, contains('Wing Alias 2'));
    });

    test('should remove wing alias', () async {
      // Arrange
      final wing = Wing(id: 1, name: 'Primary Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);
      await databaseService.addWingAlias(1, 'Temporary Alias');

      // Act
      await databaseService.removeWingAlias(1, 'Temporary Alias');
      final aliases = await databaseService.getWingAliases(1);

      // Assert
      expect(aliases, isEmpty);
    });

    test('should find wing by name or alias', () async {
      // Arrange
      final wing = Wing(id: 1, name: 'Primary Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);
      await databaseService.addWingAlias(1, 'Known Alias');

      // Act - Find by primary name
      final foundByName = await databaseService.findWingByNameOrAlias('Primary Wing');
      
      // Act - Find by alias
      final foundByAlias = await databaseService.findWingByNameOrAlias('Known Alias');

      // Assert
      expect(foundByName, isNotNull);
      expect(foundByName!.id, equals(1));
      expect(foundByAlias, isNotNull);
      expect(foundByAlias!.id, equals(1));
    });

    test('should return null for non-existent wing name or alias', () async {
      // Act
      final notFound = await databaseService.findWingByNameOrAlias('Non-existent');

      // Assert
      expect(notFound, isNull);
    });
  });

  group('Flight Statistics Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = await TestHelpers.initializeDatabaseForTesting();
    });

    tearDown() async {
      await databaseService.close();
    });

    test('should calculate overall flight statistics', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight1 = Flight(
        id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1,
        launchTime: '14:30', landingTime: '16:15', duration: 105,
        maxAltitude: 2500, igcFileName: 'flight1.igc',
      );

      final flight2 = Flight(
        id: 2, date: '2023-07-20', launchSiteId: 1, wingId: 1,
        launchTime: '15:00', landingTime: '17:30', duration: 150,
        maxAltitude: 3200, igcFileName: 'flight2.igc',
      );

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);

      // Act
      final stats = await databaseService.getOverallStatistics();

      // Assert
      expect(stats['totalFlights'], equals(2));
      expect(stats['totalHours'], equals(4.25)); // (105 + 150) / 60
      expect(stats['maxAltitude'], equals(3200));
      expect(stats['avgDuration'], equals(127.5)); // (105 + 150) / 2
    });

    test('should calculate yearly flight statistics', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      // 2023 flights
      final flight2023 = Flight(
        id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1,
        duration: 120, maxAltitude: 2500, igcFileName: 'flight2023.igc',
      );

      // 2024 flights
      final flight2024a = Flight(
        id: 2, date: '2024-06-10', launchSiteId: 1, wingId: 1,
        duration: 90, maxAltitude: 2800, igcFileName: 'flight2024a.igc',
      );

      final flight2024b = Flight(
        id: 3, date: '2024-08-20', launchSiteId: 1, wingId: 1,
        duration: 180, maxAltitude: 3100, igcFileName: 'flight2024b.igc',
      );

      await databaseService.insertFlight(flight2023);
      await databaseService.insertFlight(flight2024a);
      await databaseService.insertFlight(flight2024b);

      // Act
      final stats2023 = await databaseService.getYearlyStatistics(2023);
      final stats2024 = await databaseService.getYearlyStatistics(2024);

      // Assert
      expect(stats2023['totalFlights'], equals(1));
      expect(stats2023['totalHours'], equals(2.0)); // 120/60
      expect(stats2024['totalFlights'], equals(2));
      expect(stats2024['totalHours'], equals(4.5)); // (90+180)/60
    });

    test('should get flight hours by year', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight2023 = Flight(
        id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1,
        duration: 180, igcFileName: 'flight2023.igc', // 3 hours
      );

      final flight2024 = Flight(
        id: 2, date: '2024-06-10', launchSiteId: 1, wingId: 1,
        duration: 240, igcFileName: 'flight2024.igc', // 4 hours
      );

      await databaseService.insertFlight(flight2023);
      await databaseService.insertFlight(flight2024);

      // Act
      final hoursByYear = await databaseService.getFlightHoursByYear();

      // Assert
      expect(hoursByYear, hasLength(2));
      expect(hoursByYear.any((entry) => entry['year'] == 2023 && entry['hours'] == 3.0), isTrue);
      expect(hoursByYear.any((entry) => entry['year'] == 2024 && entry['hours'] == 4.0), isTrue);
    });

    test('should get statistics by wing', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing1 = Wing(id: 1, name: 'Wing One', manufacturer: 'Test', model: 'Model1');
      final wing2 = Wing(id: 2, name: 'Wing Two', manufacturer: 'Test', model: 'Model2');
      await databaseService.insertWing(wing1);
      await databaseService.insertWing(wing2);

      final flight1 = Flight(id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, duration: 120, igcFileName: 'f1.igc');
      final flight2 = Flight(id: 2, date: '2023-07-20', launchSiteId: 1, wingId: 1, duration: 180, igcFileName: 'f2.igc');
      final flight3 = Flight(id: 3, date: '2023-08-01', launchSiteId: 1, wingId: 2, duration: 90, igcFileName: 'f3.igc');

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);
      await databaseService.insertFlight(flight3);

      // Act
      final wingStats = await databaseService.getStatisticsByWing();

      // Assert
      expect(wingStats, hasLength(2));
      
      final wing1Stats = wingStats.firstWhere((s) => s['wingName'] == 'Wing One');
      expect(wing1Stats['flightCount'], equals(2));
      expect(wing1Stats['totalHours'], equals(5.0)); // (120+180)/60

      final wing2Stats = wingStats.firstWhere((s) => s['wingName'] == 'Wing Two');
      expect(wing2Stats['flightCount'], equals(1));
      expect(wing2Stats['totalHours'], equals(1.5)); // 90/60
    });

    test('should get statistics by site', () async {
      // Arrange
      final site1 = Site(id: 1, name: 'Site One', latitude: 46.0, longitude: 7.0);
      final site2 = Site(id: 2, name: 'Site Two', latitude: 46.5, longitude: 7.5);
      await databaseService.insertSite(site1);
      await databaseService.insertSite(site2);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight1 = Flight(id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, duration: 120, igcFileName: 'f1.igc');
      final flight2 = Flight(id: 2, date: '2023-07-20', launchSiteId: 1, wingId: 1, duration: 180, igcFileName: 'f2.igc');
      final flight3 = Flight(id: 3, date: '2023-08-01', launchSiteId: 2, wingId: 1, duration: 90, igcFileName: 'f3.igc');

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);
      await databaseService.insertFlight(flight3);

      // Act
      final siteStats = await databaseService.getStatisticsBySite();

      // Assert
      expect(siteStats, hasLength(2));
      
      final site1Stats = siteStats.firstWhere((s) => s['siteName'] == 'Site One');
      expect(site1Stats['flightCount'], equals(2));
      expect(site1Stats['totalHours'], equals(5.0)); // (120+180)/60

      final site2Stats = siteStats.firstWhere((s) => s['siteName'] == 'Site Two');
      expect(site2Stats['flightCount'], equals(1));
      expect(site2Stats['totalHours'], equals(1.5)); // 90/60
    });

    test('should get individual wing statistics', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight1 = Flight(id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, duration: 120, maxAltitude: 2500, igcFileName: 'f1.igc');
      final flight2 = Flight(id: 2, date: '2023-07-20', launchSiteId: 1, wingId: 1, duration: 180, maxAltitude: 3200, igcFileName: 'f2.igc');

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);

      // Act
      final wingStats = await databaseService.getWingStatistics(1);

      // Assert
      expect(wingStats['totalFlights'], equals(2));
      expect(wingStats['totalHours'], equals(5.0)); // (120+180)/60
      expect(wingStats['maxAltitude'], equals(3200));
      expect(wingStats['avgDuration'], equals(150.0)); // (120+180)/2
    });
  });

  group('Flight Query Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = await TestHelpers.initializeDatabaseForTesting();
    });

    tearDown() async {
      await databaseService.close();
    });

    test('should get flights by date range', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight1 = Flight(id: 1, date: '2023-07-10', launchSiteId: 1, wingId: 1, igcFileName: 'f1.igc');
      final flight2 = Flight(id: 2, date: '2023-07-15', launchSiteId: 1, wingId: 1, igcFileName: 'f2.igc');
      final flight3 = Flight(id: 3, date: '2023-07-25', launchSiteId: 1, wingId: 1, igcFileName: 'f3.igc');

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);
      await databaseService.insertFlight(flight3);

      // Act
      final flightsInRange = await databaseService.getFlightsByDateRange('2023-07-12', '2023-07-20');

      // Assert
      expect(flightsInRange, hasLength(1));
      expect(flightsInRange.first.date, equals('2023-07-15'));
    });

    test('should get flights by site', () async {
      // Arrange
      final site1 = Site(id: 1, name: 'Site One', latitude: 46.0, longitude: 7.0);
      final site2 = Site(id: 2, name: 'Site Two', latitude: 46.5, longitude: 7.5);
      await databaseService.insertSite(site1);
      await databaseService.insertSite(site2);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight1 = Flight(id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, igcFileName: 'f1.igc');
      final flight2 = Flight(id: 2, date: '2023-07-20', launchSiteId: 2, wingId: 1, igcFileName: 'f2.igc');
      final flight3 = Flight(id: 3, date: '2023-07-25', launchSiteId: 1, wingId: 1, igcFileName: 'f3.igc');

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);
      await databaseService.insertFlight(flight3);

      // Act
      final site1Flights = await databaseService.getFlightsBySite(1);

      // Assert
      expect(site1Flights, hasLength(2));
      expect(site1Flights.every((f) => f.launchSiteId == 1), isTrue);
    });

    test('should get flights by wing', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing1 = Wing(id: 1, name: 'Wing One', manufacturer: 'Test', model: 'Model1');
      final wing2 = Wing(id: 2, name: 'Wing Two', manufacturer: 'Test', model: 'Model2');
      await databaseService.insertWing(wing1);
      await databaseService.insertWing(wing2);

      final flight1 = Flight(id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, igcFileName: 'f1.igc');
      final flight2 = Flight(id: 2, date: '2023-07-20', launchSiteId: 1, wingId: 2, igcFileName: 'f2.igc');
      final flight3 = Flight(id: 3, date: '2023-07-25', launchSiteId: 1, wingId: 1, igcFileName: 'f3.igc');

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);
      await databaseService.insertFlight(flight3);

      // Act
      final wing1Flights = await databaseService.getFlightsByWing(1);

      // Assert
      expect(wing1Flights, hasLength(2));
      expect(wing1Flights.every((f) => f.wingId == 1), isTrue);
    });

    test('should detect duplicate by filename', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final existingFlight = Flight(
        id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, 
        igcFileName: 'duplicate_flight.igc'
      );
      await databaseService.insertFlight(existingFlight);

      // Act
      final isDuplicate = await databaseService.isDuplicateByFilename('duplicate_flight.igc');
      final isNotDuplicate = await databaseService.isDuplicateByFilename('unique_flight.igc');

      // Assert
      expect(isDuplicate, isTrue);
      expect(isNotDuplicate, isFalse);
    });

    test('should detect duplicate by date and time', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final existingFlight = Flight(
        id: 1, date: '2023-07-15', launchTime: '14:30', landingTime: '16:15',
        launchSiteId: 1, wingId: 1, igcFileName: 'existing.igc'
      );
      await databaseService.insertFlight(existingFlight);

      // Act
      final isDuplicate = await databaseService.isDuplicateByDateTime('2023-07-15', '14:30', '16:15');
      final isNotDuplicate = await databaseService.isDuplicateByDateTime('2023-07-15', '10:00', '12:00');

      // Assert
      expect(isDuplicate, isTrue);
      expect(isNotDuplicate, isFalse);
    });

    test('should search flights by text', () async {
      // Arrange
      final site1 = Site(id: 1, name: 'Alpine Launch', latitude: 46.0, longitude: 7.0);
      final site2 = Site(id: 2, name: 'Valley Site', latitude: 46.5, longitude: 7.5);
      await databaseService.insertSite(site1);
      await databaseService.insertSite(site2);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight1 = Flight(
        id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1,
        notes: 'Great alpine conditions', igcFileName: 'alpine_flight.igc'
      );
      final flight2 = Flight(
        id: 2, date: '2023-07-20', launchSiteId: 2, wingId: 1,
        notes: 'Valley wind was strong', igcFileName: 'valley_flight.igc'
      );

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);

      // Act - Search in notes
      final alpineFlights = await databaseService.searchFlights('alpine');
      
      // Act - Search in site name
      final valleyFlights = await databaseService.searchFlights('Valley');

      // Assert
      expect(alpineFlights, hasLength(1));
      expect(alpineFlights.first.notes, contains('alpine'));

      expect(valleyFlights, hasLength(1));
      expect(valleyFlights.first.launchSiteId, equals(2));
    });

    test('should get flights in launch coordinate bounding box', () async {
      // Arrange
      final site1 = Site(id: 1, name: 'Site In Box', latitude: 46.5, longitude: 7.5);
      final site2 = Site(id: 2, name: 'Site Outside Box', latitude: 48.0, longitude: 9.0);
      await databaseService.insertSite(site1);
      await databaseService.insertSite(site2);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight1 = Flight(id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, igcFileName: 'f1.igc');
      final flight2 = Flight(id: 2, date: '2023-07-20', launchSiteId: 2, wingId: 1, igcFileName: 'f2.igc');

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);

      // Act
      final flightsInBox = await databaseService.getFlightsInBoundingBox(
        46.0, 47.0,  // lat min, lat max
        7.0, 8.0,    // lng min, lng max
      );

      // Assert
      expect(flightsInBox, hasLength(1));
      expect(flightsInBox.first.launchSiteId, equals(1));
    });
  });

  group('Error Handling & Constraints', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = await TestHelpers.initializeDatabaseForTesting();
    });

    tearDown() async {
      await databaseService.close();
    });

    test('should handle concurrent flight insertions safely', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight1 = Flight(
        id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1,
        igcFileName: 'flight1.igc'
      );

      final flight2 = Flight(
        id: 2, date: '2023-07-20', launchSiteId: 1, wingId: 1,
        igcFileName: 'flight2.igc'
      );

      // Act - Insert flights concurrently (simulate concurrent operations)
      await Future.wait([
        databaseService.insertFlight(flight1),
        databaseService.insertFlight(flight2),
      ]);

      final allFlights = await databaseService.getAllFlights();

      // Assert
      expect(allFlights, hasLength(2));
    });

    test('should prevent site deletion when flights exist', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight = Flight(
        id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1,
        igcFileName: 'test_flight.igc'
      );
      await databaseService.insertFlight(flight);

      // Act & Assert
      expect(
        () => databaseService.deleteSite(1),
        throwsA(isA<Exception>()),
      );
    });

    test('should prevent wing deletion when flights exist', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight = Flight(
        id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1,
        igcFileName: 'test_flight.igc'
      );
      await databaseService.insertFlight(flight);

      // Act & Assert
      expect(
        () => databaseService.deleteWing(1),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle empty search results gracefully', () async {
      // Act
      final emptySearch = await databaseService.searchFlights('nonexistent');
      final emptyDateRange = await databaseService.getFlightsByDateRange('2020-01-01', '2020-01-02');
      final emptySiteFlights = await databaseService.getFlightsBySite(999);

      // Assert
      expect(emptySearch, isEmpty);
      expect(emptyDateRange, isEmpty);
      expect(emptySiteFlights, isEmpty);
    });
  });

  group('Site Relationship Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = await TestHelpers.initializeDatabaseForTesting();
    });

    tearDown() async {
      await databaseService.close();
    });

    test('should get flight count for each site', () async {
      // Arrange
      final site1 = Site(id: 1, name: 'Popular Site', latitude: 46.0, longitude: 7.0);
      final site2 = Site(id: 2, name: 'Less Popular Site', latitude: 46.5, longitude: 7.5);
      await databaseService.insertSite(site1);
      await databaseService.insertSite(site2);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      // Add multiple flights to site1, one flight to site2
      final flight1 = Flight(id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, igcFileName: 'f1.igc');
      final flight2 = Flight(id: 2, date: '2023-07-20', launchSiteId: 1, wingId: 1, igcFileName: 'f2.igc');
      final flight3 = Flight(id: 3, date: '2023-07-25', launchSiteId: 2, wingId: 1, igcFileName: 'f3.igc');

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);
      await databaseService.insertFlight(flight3);

      // Act
      final site1Count = await databaseService.getFlightCountForSite(1);
      final site2Count = await databaseService.getFlightCountForSite(2);

      // Assert
      expect(site1Count, equals(2));
      expect(site2Count, equals(1));
    });

    test('should reassign flights from one site to another', () async {
      // Arrange
      final site1 = Site(id: 1, name: 'Old Site', latitude: 46.0, longitude: 7.0);
      final site2 = Site(id: 2, name: 'New Site', latitude: 46.1, longitude: 7.1);
      await databaseService.insertSite(site1);
      await databaseService.insertSite(site2);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight1 = Flight(id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, igcFileName: 'f1.igc');
      final flight2 = Flight(id: 2, date: '2023-07-20', launchSiteId: 1, wingId: 1, igcFileName: 'f2.igc');

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);

      // Act
      await databaseService.reassignFlights(fromSiteId: 1, toSiteId: 2);

      // Assert
      final site1Flights = await databaseService.getFlightsBySite(1);
      final site2Flights = await databaseService.getFlightsBySite(2);

      expect(site1Flights, isEmpty);
      expect(site2Flights, hasLength(2));
    });

    test('should get sites with their flight counts', () async {
      // Arrange
      final site1 = Site(id: 1, name: 'Active Site', latitude: 46.0, longitude: 7.0);
      final site2 = Site(id: 2, name: 'Unused Site', latitude: 46.5, longitude: 7.5);
      await databaseService.insertSite(site1);
      await databaseService.insertSite(site2);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight = Flight(id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, igcFileName: 'f1.igc');
      await databaseService.insertFlight(flight);

      // Act
      final sitesWithCounts = await databaseService.getSitesWithFlightCounts();

      // Assert
      expect(sitesWithCounts, hasLength(2));

      final activeSite = sitesWithCounts.firstWhere((s) => s['siteName'] == 'Active Site');
      expect(activeSite['flightCount'], equals(1));

      final unusedSite = sitesWithCounts.firstWhere((s) => s['siteName'] == 'Unused Site');
      expect(unusedSite['flightCount'], equals(0));
    });
  });

  group('Wing Relationship Operations', () {
    late DatabaseService databaseService;

    setUp(() async {
      databaseService = await TestHelpers.initializeDatabaseForTesting();
    });

    tearDown() async {
      await databaseService.close();
    });

    test('should merge wings by reassigning flights', () async {
      // Arrange
      final site = Site(id: 1, name: 'Test Site', latitude: 46.0, longitude: 7.0);
      await databaseService.insertSite(site);

      final wing1 = Wing(id: 1, name: 'Primary Wing', manufacturer: 'Test', model: 'Model');
      final wing2 = Wing(id: 2, name: 'Duplicate Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing1);
      await databaseService.insertWing(wing2);

      final flight1 = Flight(id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, igcFileName: 'f1.igc');
      final flight2 = Flight(id: 2, date: '2023-07-20', launchSiteId: 1, wingId: 2, igcFileName: 'f2.igc');

      await databaseService.insertFlight(flight1);
      await databaseService.insertFlight(flight2);

      // Act - Merge wing2 into wing1
      await databaseService.mergeWings(fromWingId: 2, toWingId: 1);

      // Assert
      final wing1Flights = await databaseService.getFlightsByWing(1);
      final wing2Flights = await databaseService.getFlightsByWing(2);

      expect(wing1Flights, hasLength(2));
      expect(wing2Flights, isEmpty);
    });

    test('should find potential duplicate wings', () async {
      // Arrange
      final wing1 = Wing(id: 1, name: 'Advance Epsilon', manufacturer: 'Advance', model: 'Epsilon 9');
      final wing2 = Wing(id: 2, name: 'Advance Epsilon 9', manufacturer: 'Advance', model: 'Epsilon');
      final wing3 = Wing(id: 3, name: 'Different Wing', manufacturer: 'Other', model: 'Different');

      await databaseService.insertWing(wing1);
      await databaseService.insertWing(wing2);
      await databaseService.insertWing(wing3);

      // Act
      final duplicates = await databaseService.findPotentialDuplicateWings();

      // Assert - Should find wings with similar manufacturer/model combinations
      expect(duplicates, isNotEmpty);
      expect(duplicates.any((pair) => 
        (pair['wing1']['manufacturer'] == 'Advance' && pair['wing2']['manufacturer'] == 'Advance')
      ), isTrue);
    });

    test('should get sites used in flights', () async {
      // Arrange
      final site1 = Site(id: 1, name: 'Used Site', latitude: 46.0, longitude: 7.0);
      final site2 = Site(id: 2, name: 'Unused Site', latitude: 46.5, longitude: 7.5);
      await databaseService.insertSite(site1);
      await databaseService.insertSite(site2);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flight = Flight(id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, igcFileName: 'f1.igc');
      await databaseService.insertFlight(flight);

      // Act
      final usedSites = await databaseService.getSitesUsedInFlights();

      // Assert
      expect(usedSites, hasLength(1));
      expect(usedSites.first.name, equals('Used Site'));
    });

    test('should bulk update flight sites', () async {
      // Arrange
      final site1 = Site(id: 1, name: 'Old Site', latitude: 46.0, longitude: 7.0);
      final site2 = Site(id: 2, name: 'New Site', latitude: 46.1, longitude: 7.1);
      await databaseService.insertSite(site1);
      await databaseService.insertSite(site2);

      final wing = Wing(id: 1, name: 'Test Wing', manufacturer: 'Test', model: 'Model');
      await databaseService.insertWing(wing);

      final flights = [
        Flight(id: 1, date: '2023-07-15', launchSiteId: 1, wingId: 1, igcFileName: 'f1.igc'),
        Flight(id: 2, date: '2023-07-20', launchSiteId: 1, wingId: 1, igcFileName: 'f2.igc'),
      ];

      for (final flight in flights) {
        await databaseService.insertFlight(flight);
      }

      // Act
      await databaseService.bulkUpdateFlightSites([1, 2], 2);

      // Assert
      final updatedFlights = await databaseService.getAllFlights();
      expect(updatedFlights.every((f) => f.launchSiteId == 2), isTrue);
    });
  });
}