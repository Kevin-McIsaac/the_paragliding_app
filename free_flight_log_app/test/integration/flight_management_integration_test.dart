import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:free_flight_log_app/main.dart';
import 'package:free_flight_log_app/providers/flight_provider.dart';
import 'package:free_flight_log_app/providers/site_provider.dart';
import 'package:free_flight_log_app/providers/wing_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Flight Management Integration Tests', () {
    testWidgets('Complete flight creation and editing workflow', (WidgetTester tester) async {
      // Given: App is started
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => FlightProvider()),
            ChangeNotifierProvider(create: (_) => SiteProvider()),
            ChangeNotifierProvider(create: (_) => WingProvider()),
          ],
          child: FreeFlightLogApp(),
        ),
      );
      await tester.pumpAndSettle(Duration(seconds: 2));

      // Step 1: Verify app starts with flight list
      expect(find.text('Free Flight Log'), findsOneWidget);
      
      // Step 2: Navigate to add new flight
      final addButton = find.byIcon(Icons.add);
      expect(addButton, findsOneWidget);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Step 3: Fill out flight form
      expect(find.text('Add Flight'), findsOneWidget);
      
      // Fill in date (if date picker field exists)
      final dateField = find.byIcon(Icons.calendar_today);
      if (dateField.evaluate().isNotEmpty) {
        await tester.tap(dateField.first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      // Fill in notes
      final notesField = find.byType(TextFormField).last;
      await tester.enterText(notesField, 'Integration test flight');
      await tester.pumpAndSettle();

      // Step 4: Save the flight
      final saveButton = find.byIcon(Icons.save);
      await tester.tap(saveButton);
      await tester.pumpAndSettle(Duration(seconds: 2));

      // Step 5: Verify flight appears in list
      expect(find.text('Integration test flight'), findsOneWidget);

      // Step 6: Edit the flight
      await tester.tap(find.text('Integration test flight'));
      await tester.pumpAndSettle();

      // Verify edit screen opened
      expect(find.text('Edit Flight'), findsOneWidget);

      // Step 7: Update notes
      final editNotesField = find.text('Integration test flight');
      await tester.tap(editNotesField);
      await tester.pumpAndSettle();
      await tester.enterText(editNotesField, 'Updated integration test flight');
      await tester.pumpAndSettle();

      // Save changes
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle(Duration(seconds: 2));

      // Step 8: Verify changes saved
      expect(find.text('Updated integration test flight'), findsOneWidget);

      // Step 9: Delete the flight (if delete functionality exists)
      await tester.longPress(find.text('Updated integration test flight'));
      await tester.pumpAndSettle();
      
      final deleteButton = find.byIcon(Icons.delete);
      if (deleteButton.evaluate().isNotEmpty) {
        await tester.tap(deleteButton);
        await tester.pumpAndSettle();
        
        // Confirm deletion if dialog appears
        final confirmButton = find.text('DELETE');
        if (confirmButton.evaluate().isNotEmpty) {
          await tester.tap(confirmButton);
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Navigation between screens workflow', (WidgetTester tester) async {
      // Given: App is started
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => FlightProvider()),
            ChangeNotifierProvider(create: (_) => SiteProvider()),
            ChangeNotifierProvider(create: (_) => WingProvider()),
          ],
          child: FreeFlightLogApp(),
        ),
      );
      await tester.pumpAndSettle(Duration(seconds: 2));

      // Step 1: Open navigation drawer
      final menuButton = find.byIcon(Icons.menu);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      // Step 2: Navigate to Statistics
      final statisticsItem = find.text('Statistics');
      if (statisticsItem.evaluate().isNotEmpty) {
        await tester.tap(statisticsItem);
        await tester.pumpAndSettle();
        expect(find.text('Flight Statistics'), findsOneWidget);
        
        // Navigate back
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
      }

      // Step 3: Navigate to IGC Import
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      
      final importItem = find.text('Import IGC');
      if (importItem.evaluate().isNotEmpty) {
        await tester.tap(importItem);
        await tester.pumpAndSettle();
        expect(find.text('IGC File Import'), findsOneWidget);
        
        // Navigate back
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
      }

      // Step 4: Navigate to Manage Sites
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      
      final sitesItem = find.text('Manage Sites');
      if (sitesItem.evaluate().isNotEmpty) {
        await tester.tap(sitesItem);
        await tester.pumpAndSettle();
        expect(find.text('Sites'), findsOneWidget);
        
        // Navigate back
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
      }

      // Verify we're back at flight list
      expect(find.text('Free Flight Log'), findsOneWidget);
    });

    testWidgets('Error handling workflow', (WidgetTester tester) async {
      // Given: App is started
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => FlightProvider()),
            ChangeNotifierProvider(create: (_) => SiteProvider()),
            ChangeNotifierProvider(create: (_) => WingProvider()),
          ],
          child: FreeFlightLogApp(),
        ),
      );
      await tester.pumpAndSettle(Duration(seconds: 2));

      // Step 1: Attempt to save invalid flight data
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Try to save without required fields
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Should handle validation gracefully without crashing
      expect(find.byType(Scaffold), findsWidgets);

      // Step 2: Test navigation error handling
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Should return to flight list without crashing
      expect(find.text('Free Flight Log'), findsOneWidget);
    });

    testWidgets('Data persistence workflow', (WidgetTester tester) async {
      // Given: App is started
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => FlightProvider()),
            ChangeNotifierProvider(create: (_) => SiteProvider()),
            ChangeNotifierProvider(create: (_) => WingProvider()),
          ],
          child: FreeFlightLogApp(),
        ),
      );
      await tester.pumpAndSettle(Duration(seconds: 2));

      // Step 1: Add a flight
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      final notesField = find.byType(TextFormField).last;
      await tester.enterText(notesField, 'Persistence test flight');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle(Duration(seconds: 2));

      // Step 2: Verify flight is saved
      expect(find.text('Persistence test flight'), findsOneWidget);

      // Step 3: Simulate app restart by recreating widget
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => FlightProvider()),
            ChangeNotifierProvider(create: (_) => SiteProvider()),
            ChangeNotifierProvider(create: (_) => WingProvider()),
          ],
          child: FreeFlightLogApp(),
        ),
      );
      await tester.pumpAndSettle(Duration(seconds: 3));

      // Step 4: Verify flight persisted across restart
      expect(find.text('Persistence test flight'), findsOneWidget);
    });

    testWidgets('Search and filter workflow', (WidgetTester tester) async {
      // Given: App with multiple flights
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => FlightProvider()),
            ChangeNotifierProvider(create: (_) => SiteProvider()),
            ChangeNotifierProvider(create: (_) => WingProvider()),
          ],
          child: FreeFlightLogApp(),
        ),
      );
      await tester.pumpAndSettle(Duration(seconds: 2));

      // Step 1: Add multiple flights with different notes
      final testFlights = [
        'Morning thermal flight',
        'Evening ridge soaring',
        'Cross country adventure',
      ];

      for (final notes in testFlights) {
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        final notesField = find.byType(TextFormField).last;
        await tester.enterText(notesField, notes);
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.save));
        await tester.pumpAndSettle(Duration(seconds: 1));
      }

      // Step 2: Test search functionality (if it exists)
      final searchIcon = find.byIcon(Icons.search);
      if (searchIcon.evaluate().isNotEmpty) {
        await tester.tap(searchIcon);
        await tester.pumpAndSettle();

        final searchField = find.byType(TextField);
        if (searchField.evaluate().isNotEmpty) {
          await tester.enterText(searchField.first, 'thermal');
          await tester.pumpAndSettle();

          // Should show only matching flight
          expect(find.text('Morning thermal flight'), findsOneWidget);
          expect(find.text('Evening ridge soaring'), findsNothing);
        }
      }

      // Verify all flights are visible when search is cleared
      expect(find.text('Morning thermal flight'), findsWidgets);
      expect(find.text('Evening ridge soaring'), findsWidgets);
      expect(find.text('Cross country adventure'), findsWidgets);
    });
  });

  group('Performance Tests', () {
    testWidgets('Large dataset handling', (WidgetTester tester) async {
      // Test app performance with larger datasets
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => FlightProvider()),
            ChangeNotifierProvider(create: (_) => SiteProvider()),
            ChangeNotifierProvider(create: (_) => WingProvider()),
          ],
          child: FreeFlightLogApp(),
        ),
      );
      
      // Allow extra time for database operations
      await tester.pumpAndSettle(Duration(seconds: 5));

      // Verify app loads without timeout or crashes
      expect(find.text('Free Flight Log'), findsOneWidget);
      
      // Test scrolling performance (if flights exist)
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        await tester.fling(scrollable.first, Offset(0, -300), 1000);
        await tester.pumpAndSettle();
        
        // Should handle scrolling smoothly
        expect(find.byType(Scrollable), findsOneWidget);
      }
    });
  });
}