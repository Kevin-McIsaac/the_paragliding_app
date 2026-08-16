import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/models/guide.dart';
import 'package:the_paragliding_app/data/models/paragliding_site.dart';
import 'package:the_paragliding_app/presentation/screens/site_details_screen.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';

/// Site details was a modal bottom sheet whose tabs lived in a fixed 450px
/// box. The box could not track the space available, so content ran past it
/// and was clipped mid-widget, while dragging the sheet taller only added
/// dead surface below. It is a page now, which removes the sheet's extents
/// from the problem entirely - but not the invariant underneath it:
///
///   the tab body is sized by what is left of the screen, and the header
///   that says whether the site is flyable does not move when a tab scrolls.
void main() {
  final site = ParaglidingSite(
    id: 9247,
    name: 'Manilla - Mt Borah - West launch',
    latitude: -30.6792,
    longitude: 150.6086,
    siteType: 'launch',
    windDirections: const ['W', 'NW'],
    source: 'pge:4632;ansg:136-20',
  );

  setUp(() async {
    // The page reads favourites out of the catalogue table on open.
    await PgeSitesDatabaseService.instance.initializeTables();
    // Tab names come from the registry the producer publishes, so without it
    // the tabs read `pge` and `ansg` rather than `PGE` and `ANSG`.
    await Guides.load();
  });

  /// Pump the page on a phone-shaped screen and let its loads fail.
  ///
  /// Every fetch it starts (wind, forecast, PGE detail) fails in a test
  /// binding, which is what we want: the layout is the subject, and the error
  /// states are the smallest content a tab can have. pumpAndSettle is no use
  /// here - a CircularProgressIndicator animates forever - so the frames are
  /// pumped by hand.
  Future<void> pumpPage(WidgetTester tester, {ParaglidingSite? which}) async {
    // A Pixel 9 in logical pixels: 1080x2424 at dpr 2.625. Layout bugs are
    // viewport-shaped, so the surface has to be a real one.
    tester.view.physicalSize = const Size(411, 923);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: SiteDetailsScreen(
        paraglidingSite: which ?? site,
        maxWindSpeed: 25,
        cautionWindSpeed: 15,
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('the tab body runs to the bottom of the screen', (tester) async {
    await pumpPage(tester);

    // No dead space below the tabs, and no viewport hanging off the bottom
    // with its last widget parked out of reach. On a page this is what
    // Expanded means - the assertion exists because the sheet version had a
    // 450px box here and satisfied neither half.
    final tabs = tester.getRect(find.byType(TabBarView));
    expect(tabs.bottom, closeTo(923, 1));
  });

  testWidgets('the header stays put while a tab scrolls', (tester) async {
    await pumpPage(tester);

    // The wind rose and the flyability row answer "is it on right now?".
    // Scrolling a guide must not take them off screen - the complaint that
    // sent the collapsing-header version back.
    final rowBefore = tester.getRect(find.text('Launch:'));

    await tester.drag(find.byType(TabBarView), const Offset(0, -300));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(tester.getRect(find.text('Launch:')), rowBefore);
  });

  testWidgets('no hardcoded height wraps the tab body', (tester) async {
    await pumpPage(tester);

    // The constant cannot come back: a SizedBox(height: 450) between the page
    // and the TabBarView is the whole original bug, in one widget.
    final boxed = find.ancestor(
      of: find.byType(TabBarView),
      matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.height != null && w.height! > 0),
    );
    expect(boxed, findsNothing);
  });

  testWidgets('the name is the page title, and is not repeated', (tester) async {
    await pumpPage(tester);

    // It used to be a headline inside the body competing with the wind rose
    // for one row. The AppBar owns it now - once.
    expect(find.text('Manilla - Mt Borah - West launch'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Manilla - Mt Borah - West launch'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a site with no guides still renders', (tester) async {
    // The no-tabs fallback is the branch nobody looks at.
    await pumpPage(
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
    await pumpPage(tester);

    expect(find.text('Forecast'), findsOneWidget);
    expect(find.text('PGE'), findsOneWidget);
    expect(find.text('ANSG'), findsOneWidget);
  });

  testWidgets('the launch altitude says which datum it is', (tester) async {
    // Above ground level at a launch is zero by definition, so an unlabelled
    // figure invites the one reading it cannot have - and the guides really do
    // publish both. Site Guide's height for Mt Bakewell is 255m above the
    // valley; PGE's is 436m AMSL. The unit is in the text rather than only in
    // the tooltip because this row must not depend on a hover.
    await pumpPage(
      tester,
      which: ParaglidingSite(
        id: 9247,
        name: 'Manilla - Mt Borah - West launch',
        latitude: -30.6792,
        longitude: 150.6086,
        altitude: 847,
        siteType: 'launch',
        windDirections: const ['W', 'NW'],
        source: 'pge:4632;ansg:136-20',
      ),
    );

    expect(find.text('847 m AMSL'), findsOneWidget);
    expect(find.byTooltip('Altitude above mean sea level'), findsOneWidget);
  });

  group('a landing', () {
    // A landing opens the same screen a launch does. The one thing it cannot
    // answer is whether you can fly today, and that is the only thing this
    // screen withholds from it.
    //
    // Its sibling test asserted the guide's prose in the header, and stays
    // deleted: `notes` is no longer shipped in the catalogue at all.
    final landing = ParaglidingSite(
      name: 'Rofan Feldererfeld Landeplatz',
      latitude: 47.423078,
      longitude: 11.74615,
      siteType: 'landing',
      altitude: 560,
      source: 'dhv:1234-rofan-feldererfeld-landeplatz',
    );

    testWidgets('offers no forecast, because it has no wind', (tester) async {
      // Shown anyway, a forecast built from no wind directions does not read
      // as "this question does not apply" - it reads as "we checked, and it
      // is unflyable".
      await pumpPage(tester, which: landing);

      expect(find.text('Forecast'), findsNothing);
    });

    testWidgets('keeps the guide tab it is described by', (tester) async {
      // The rest of the page is a site like any other: the guide that
      // published it, named, with a way out to its own write-up.
      await pumpPage(tester, which: landing);

      expect(find.text('DHV'), findsOneWidget);
      expect(find.text('560 m AMSL'), findsOneWidget);
    });
  });
}

