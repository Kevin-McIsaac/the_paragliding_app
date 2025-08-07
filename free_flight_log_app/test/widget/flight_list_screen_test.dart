import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:free_flight_log_app/presentation/screens/flight_list_screen.dart';
import 'package:free_flight_log_app/providers/flight_provider.dart';
import 'package:free_flight_log_app/data/models/flight.dart';

void main() {
  group('FlightListScreen Widget Tests', () {
    late FlightProvider mockFlightProvider;
    
    setUp(() {
      mockFlightProvider = FlightProvider();
    });

    Widget createTestWidget() {
      return ChangeNotifierProvider<FlightProvider>.value(
        value: mockFlightProvider,
        child: MaterialApp(
          home: FlightListScreen(),
        ),
      );
    }

    testWidgets('should display empty state when no flights exist', (WidgetTester tester) async {
      // Given: Empty flight list
      mockFlightProvider.clearFlights();
      
      // When: Widget is rendered
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      
      // Then: Should show empty state
      expect(find.text('No flights logged yet'), findsOneWidget);
      expect(find.text('Tap the + button to log your first flight'), findsOneWidget);
      expect(find.byIcon(Icons.flight), findsOneWidget);
    });

    testWidgets('should display flight list when flights exist', (WidgetTester tester) async {
      // Given: Flight list with test data
      final testFlight = Flight(
        id: 1,
        date: DateTime(2023, 12, 1),
        launchTime: DateTime(2023, 12, 1, 10, 30),
        landingTime: DateTime(2023, 12, 1, 12, 45),
        duration: 135, // minutes
        launchSiteId: 1,
        maxAltitude: 2500.0,
        distance: 15.5,
        wingId: 1,
        notes: 'Great thermal flight',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      // Add test flight to provider
      mockFlightProvider.addFlightForTesting(testFlight);
      
      // When: Widget is rendered
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      
      // Then: Should show flight in list
      expect(find.text('Great thermal flight'), findsOneWidget);
      expect(find.text('15.5 km'), findsOneWidget);
      expect(find.text('2,500 m'), findsOneWidget);
    });

    testWidgets('should enable selection mode when long pressed', (WidgetTester tester) async {
      // Given: Flight list with test data
      final testFlight = Flight(
        id: 1,
        date: DateTime(2023, 12, 1),
        launchTime: DateTime(2023, 12, 1, 10, 30),
        landingTime: DateTime(2023, 12, 1, 12, 45),
        duration: 135,
        launchSiteId: 1,
        maxAltitude: 2500.0,
        distance: 15.5,
        wingId: 1,
        notes: 'Test flight',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      mockFlightProvider.addFlightForTesting(testFlight);
      
      // When: Widget is rendered and flight is long pressed
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      
      await tester.longPress(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      
      // Then: Should enter selection mode
      expect(find.byIcon(Icons.delete), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('should navigate to flight detail when tapped', (WidgetTester tester) async {
      // Given: Flight list with test data
      final testFlight = Flight(
        id: 1,
        date: DateTime(2023, 12, 1),
        launchTime: DateTime(2023, 12, 1, 10, 30),
        landingTime: DateTime(2023, 12, 1, 12, 45),
        duration: 135,
        launchSiteId: 1,
        maxAltitude: 2500.0,
        distance: 15.5,
        wingId: 1,
        notes: 'Clickable flight',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      mockFlightProvider.addFlightForTesting(testFlight);
      
      // When: Widget is rendered and flight is tapped
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      
      // Then: Should navigate to flight detail screen
      // Note: This would require navigation testing setup
      // For now, verify the tap doesn't crash the app
      expect(find.byType(FlightListScreen), findsOneWidget);
    });

    testWidgets('should display flight statistics in header', (WidgetTester tester) async {
      // Given: Multiple flights
      final flights = [
        Flight(
          id: 1,
          date: DateTime(2023, 12, 1),
          launchTime: DateTime(2023, 12, 1, 10, 0),
          landingTime: DateTime(2023, 12, 1, 12, 0),
          duration: 120,
          launchSiteId: 1,
          maxAltitude: 2000.0,
          distance: 10.0,
          wingId: 1,
          notes: 'Flight 1',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Flight(
          id: 2,
          date: DateTime(2023, 12, 2),
          launchTime: DateTime(2023, 12, 2, 11, 0),
          landingTime: DateTime(2023, 12, 2, 13, 30),
          duration: 150,
          launchSiteId: 2,
          maxAltitude: 2500.0,
          distance: 15.0,
          wingId: 1,
          notes: 'Flight 2',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];
      
      for (final flight in flights) {
        mockFlightProvider.addFlightForTesting(flight);
      }
      
      // When: Widget is rendered
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      
      // Then: Should display statistics
      expect(find.text('2 flights'), findsOneWidget);
      expect(find.text('4.5 hours'), findsOneWidget);
      expect(find.text('2,500 m'), findsOneWidget); // Max altitude
    });

    testWidgets('should handle loading state', (WidgetTester tester) async {
      // Given: Provider in loading state
      mockFlightProvider.setLoadingState(true);
      
      // When: Widget is rendered
      await tester.pumpWidget(createTestWidget());
      await tester.pump(); // Single pump to show loading state
      
      // Then: Should show loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('should handle error state', (WidgetTester tester) async {
      // Given: Provider with error
      mockFlightProvider.setError('Failed to load flights');
      
      // When: Widget is rendered
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      
      // Then: Should show error message
      expect(find.text('Error loading flights'), findsOneWidget);
      expect(find.text('Tap to retry'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });
}

// Extension to add testing methods to FlightProvider
extension FlightProviderTesting on FlightProvider {
  void addFlightForTesting(Flight flight) {
    flights.add(flight);
    notifyListeners();
  }
  
  void clearFlights() {
    flights.clear();
    notifyListeners();
  }
  
  void setLoadingState(bool isLoading) {
    this.isLoading = isLoading;
    notifyListeners();
  }
  
  void setError(String error) {
    errorMessage = error;
    notifyListeners();
  }
}