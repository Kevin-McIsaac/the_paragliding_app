import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/models/paragliding_site.dart';
import 'package:the_paragliding_app/presentation/widgets/site_details_dialog.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';

/// The site sheet's tabs used to live in a fixed 450px box nested inside the
/// sheet's own scroll view. Two things followed, both visible on a phone:
/// content ran past the box and was clipped mid-widget - the "Open in PGE"
/// button sliced in half - and dragging the sheet taller added dead space
/// below the tabs instead of giving them the room.
///
/// The invariant that rules both out: the tab body is sized by the sheet, so
/// making the sheet taller makes the tab body taller. A fixed-height box
/// cannot satisfy it.
void main() {
  final site = ParaglidingSite(
    id: 9247,
    name: 'Manilla - Mt Borah - West launch',
    latitude: -30.6792,
    longitude: 150.6086,
    siteType: 'launch',
    windDirections: const ['W', 'NW'],
    source: 'pge:4632;siteguide_au:136-20',
  );

  setUp(() async {
    // The dialog reads favourites out of the catalogue table on open.
    await PgeSitesDatabaseService.instance.initializeTables();
  });

  /// Pump the sheet on a phone-shaped screen and let its loads fail.
  ///
  /// Every fetch the dialog starts (wind, forecast, PGE detail) fails in a
  /// test binding, which is what we want: the layout is the subject, and the
  /// error states are the smallest content a tab can have. pumpAndSettle is
  /// no use here - a CircularProgressIndicator animates forever - so the
  /// frames are pumped by hand.
  Future<void> pumpSheet(WidgetTester tester, {ParaglidingSite? which}) async {
    // A Pixel 9 in logical pixels: 1080x2424 at dpr 2.625. Layout bugs are
    // viewport-shaped, so the surface has to be a real one.
    tester.view.physicalSize = const Size(411, 923);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SiteDetailsDialog(
          paraglidingSite: which ?? site,
          maxWindSpeed: 25,
          cautionWindSpeed: 15,
        ),
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Drag the header, which is what resizes the sheet.
  ///
  /// The two gestures are deliberately different: the header's scroll view
  /// has no extent, so a drag there over-scrolls and the sheet grows, while a
  /// drag on a tab scrolls that tab and leaves the sheet alone.
  Future<void> dragSheetTaller(WidgetTester tester) async {
    await tester.drag(find.text('Launch Site'), const Offset(0, -400));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('a taller sheet gives the tab body more room', (tester) async {
    await pumpSheet(tester);

    final tabs = find.byType(TabBarView);
    expect(tabs, findsOneWidget);
    final beforeDrag = tester.getSize(tabs).height;

    await dragSheetTaller(tester);

    final afterDrag = tester.getSize(tabs).height;
    expect(
      afterDrag,
      greaterThan(beforeDrag),
      reason: 'the tab body must grow with the sheet, not stay a fixed height',
    );
  });

  testWidgets('the header stays put while a tab scrolls', (tester) async {
    await pumpSheet(tester);

    // The wind rose and title answer "is it on right now?". Scrolling a
    // guide must not take them off screen - the complaint that sent the
    // collapsing-header version back.
    final titleBefore = tester.getRect(find.text('Launch Site'));

    await tester.drag(find.byType(TabBarView), const Offset(0, -300));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(tester.getRect(find.text('Launch Site')), titleBefore);
  });

  /// The sheet's own surface: the rounded, shadowed panel. The wind rose also
  /// casts a shadow, but it is a circle and carries no border radius.
  Rect sheetRect(WidgetTester tester) => tester.getRect(find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).boxShadow != null &&
            (w.decoration as BoxDecoration).borderRadius != null,
      ));

  testWidgets('the tab body ends exactly at the sheet edge', (tester) async {
    await pumpSheet(tester);

    // Neither symptom, stated as one measurement. Too tall and the tab's
    // viewport hangs below the sheet, parking its last widget off screen
    // where no amount of inner scrolling can reach it; too short and the
    // gap below it is the dead space.
    final sheet = sheetRect(tester);
    final tabs = tester.getRect(find.byType(TabBarView));

    expect(tabs.bottom, closeTo(sheet.bottom, 1));
  });

  testWidgets('still ends at the sheet edge once dragged tall', (tester) async {
    await pumpSheet(tester);

    await dragSheetTaller(tester);

    final sheet = sheetRect(tester);
    final tabs = tester.getRect(find.byType(TabBarView));

    expect(tabs.bottom, closeTo(sheet.bottom, 1));
  });

  testWidgets('no hardcoded height wraps the tab body', (tester) async {
    await pumpSheet(tester);

    // The constant cannot come back: a SizedBox(height: 450) between the
    // sheet and the TabBarView is the whole bug, in one widget.
    final boxed = find.ancestor(
      of: find.byType(TabBarView),
      matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.height != null && w.height! > 0),
    );
    expect(boxed, findsNothing);
  });

  testWidgets('a site with no guides still renders', (tester) async {
    // The no-tabs fallback is the branch nobody looks at.
    await pumpSheet(
      tester,
      which: ParaglidingSite(
        id: 11526,
        name: 'Somewhere Unlisted',
        latitude: -30.6793,
        longitude: 150.6116,
        siteType: 'launch',
      ),
    );

    expect(find.text('Somewhere Unlisted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every guide gets a named tab', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Forecast'), findsOneWidget);
    expect(find.text('PGE'), findsOneWidget);
    expect(find.text('ANSG'), findsOneWidget);
  });
}
