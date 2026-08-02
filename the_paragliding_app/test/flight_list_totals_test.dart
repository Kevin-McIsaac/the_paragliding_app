import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/models/flight.dart';
import 'package:the_paragliding_app/presentation/screens/flight_list_screen.dart';
import 'package:the_paragliding_app/presentation/widgets/common/app_stat_card.dart';
import 'package:the_paragliding_app/services/database_service.dart';

import 'helpers/test_helpers.dart';

/// The log book header must describe the rows actually listed: filtering by site
/// or date range has to move both totals, not just the table.
void main() {
  final db = DatabaseService.instance;

  setUpAll(() async {
    await TestHelpers.initializeDatabaseForTesting();

    await db.insertSite(TestHelpers.createTestSite(id: 1, name: 'Alpha Launch'));
    await db.insertSite(TestHelpers.createTestSite(id: 2, name: 'Bravo Hill'));

    final recent = DateTime.now().subtract(const Duration(days: 10));
    final old = DateTime.now().subtract(const Duration(days: 400));

    // TestHelpers.createTestFlight() sets source: 'test', which the flights
    // table's CHECK constraint rejects, so build the rows directly.
    Flight flight(
        {required DateTime date, required int duration, required int siteId}) {
      final now = DateTime.now();
      return Flight(
        date: date,
        launchTime: '10:00',
        landingTime: '12:00',
        duration: duration,
        launchSiteId: siteId,
        source: 'manual',
        createdAt: now,
        updatedAt: now,
      );
    }

    // Alpha: 60 + 30 = 1h 30m, both recent. Bravo: 90m recent, 45m long ago.
    await db.insertFlight(flight(date: recent, duration: 60, siteId: 1));
    await db.insertFlight(flight(date: recent, duration: 30, siteId: 1));
    await db.insertFlight(flight(date: recent, duration: 90, siteId: 2));
    await db.insertFlight(flight(date: old, duration: 45, siteId: 2));
  });

  /// Read a header card's value straight off the widget, so the assertion can't
  /// accidentally match an identical string in the table below it.
  String statValue(WidgetTester tester, String label) {
    return tester
        .widget<AppStatCard>(find.byWidgetPredicate(
            (w) => w is AppStatCard && w.label == label))
        .value;
  }

  /// The loading skeleton shimmers forever, so pumpAndSettle() never returns on
  /// this screen - pump a couple of frames instead.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpFlightList(WidgetTester tester) async {
    await tester.pumpWidget(
        TestHelpers.createTestApp(child: const FlightListScreen()));

    // The screen loads from sqlite in a post-frame callback: real I/O, so give
    // it real time (runAsync) rather than just pumping frames.
    for (var i = 0; i < 60; i++) {
      if (find.byType(AppStatCard).evaluate().isNotEmpty) return;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    fail('flight list never finished loading');
  }

  testWidgets('totals cover every flight when no filter is applied',
      (tester) async {
    await pumpFlightList(tester);

    expect(statValue(tester, 'Total Flights'), '4');
    expect(statValue(tester, 'Total Time'), '3h 45m'); // 60+30+90+45
  });

  testWidgets('totals follow the site search', (tester) async {
    await pumpFlightList(tester);

    await tester.enterText(find.byType(TextField), 'alpha');
    await settle(tester);

    expect(statValue(tester, 'Total Flights'), '2');
    expect(statValue(tester, 'Total Time'), '1h 30m');

    // Clearing the search restores the full totals.
    await tester.enterText(find.byType(TextField), '');
    await settle(tester);

    expect(statValue(tester, 'Total Flights'), '4');
    expect(statValue(tester, 'Total Time'), '3h 45m');
  });

  testWidgets('a search with no matches shows zeroed totals', (tester) async {
    await pumpFlightList(tester);

    await tester.enterText(find.byType(TextField), 'nowhere');
    await settle(tester);

    expect(statValue(tester, 'Total Flights'), '0');
    expect(statValue(tester, 'Total Time'), '0h 0m');
  });

  testWidgets('totals follow the date range filter', (tester) async {
    await pumpFlightList(tester);

    await tester.tap(find.byIcon(Icons.calendar_today));
    await settle(tester);
    await tester.tap(find.text('Last 3 months').last);
    await settle(tester);

    // The 400-day-old flight drops out.
    expect(statValue(tester, 'Total Flights'), '3');
    expect(statValue(tester, 'Total Time'), '3h 0m');
  });
}
