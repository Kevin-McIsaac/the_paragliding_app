import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:the_paragliding_app/data/models/paragliding_site.dart';
import 'package:the_paragliding_app/presentation/screens/site_details_screen.dart';
import 'package:the_paragliding_app/services/paragliding_earth_api.dart';
import 'package:the_paragliding_app/services/pge_sites_database_service.dart';

/// The site details header states a launch altitude, a landing altitude and the
/// drop between them. All three come out of one ParaglidingEarth response, and
/// all three were wrong in a way a live single-result query cannot show:
///
///  * the landing was `findAllElements('landing').first` over the whole
///    document while the takeoff beside it was matched by id. One launch's
///    altitude and map pin under another's name.
///  * PGE writes a negative altitude where it has none, and "-1m" was rendered
///    as if it were one.
///
/// Driven through the parser directly rather than over the network: the only
/// other test of this path is `pge_api_site_lookup_test.dart`, which is
/// network-tagged, and a real 0.5km query usually returns a single site - the
/// one case where picking the wrong landing looks identical to picking the
/// right one.

/// Two launches around Annecy, each with its own landing, in the flat
/// takeoff/landing sibling layout the API actually returns. Trimmed from a live
/// `getAroundLatLngSites.php?lat=45.90&lng=6.20&distance=12` response.
const _twoLaunchesEachWithALanding = '''
<?xml version="1.0"?>
<search>
  <results>2</results>
  <takeoff>
    <name>Annecy - Planfait</name>
    <pge_site_id>21842</pge_site_id>
    <takeoff_altitude>956</takeoff_altitude>
    <lat>45.8271</lat>
    <lng>6.20166</lng>
    <orientations><N>0</N><NE>0</NE><E>0</E><SE>0</SE><S>0</S><SW>1</SW><W>2</W><NW>1</NW></orientations>
  </takeoff>
  <landing>
    <site>Annecy - Planfait</site>
    <landing_name>Talloires</landing_name>
    <landing_lat>45.8486</landing_lat>
    <landing_lng>6.21407</landing_lng>
    <landing_altitude>555</landing_altitude>
    <landing_pge_site_id>21842</landing_pge_site_id>
  </landing>
  <takeoff>
    <name>Montmin (Col de la Forclaz)</name>
    <pge_site_id>3046</pge_site_id>
    <takeoff_altitude>1265</takeoff_altitude>
    <lat>45.8161</lat>
    <lng>6.24222</lng>
  </takeoff>
  <landing>
    <site>Montmin (Col de la Forclaz)</site>
    <landing_name>Doussard</landing_name>
    <landing_lat>45.7889</landing_lat>
    <landing_lng>6.21639</landing_lng>
    <landing_altitude>467</landing_altitude>
    <landing_pge_site_id>3046</landing_pge_site_id>
  </landing>
</search>
''';

/// Two launches on one hill where only the second has a landing - the shape
/// that made a landing appear under a site that has none. Mt Bakewell is the
/// real case: PGE records no landing for it, and the Australian Site Guide
/// publishes landings as prose with no coordinates or altitude at all.
const _onlyTheSecondLaunchHasALanding = '''
<?xml version="1.0"?>
<search>
  <results>2</results>
  <takeoff>
    <name>Mt Bakewell (top launches)</name>
    <pge_site_id>6724</pge_site_id>
    <takeoff_altitude>436</takeoff_altitude>
  </takeoff>
  <takeoff>
    <name>Somewhere else entirely</name>
    <pge_site_id>9999</pge_site_id>
    <takeoff_altitude>800</takeoff_altitude>
  </takeoff>
  <landing>
    <site>Somewhere else entirely</site>
    <landing_lat>1.0</landing_lat>
    <landing_lng>2.0</landing_lng>
    <landing_altitude>300</landing_altitude>
    <landing_pge_site_id>9999</landing_pge_site_id>
  </landing>
</search>
''';

void main() {
  group('landing belongs to the takeoff it was asked for', () {
    test('takes the matching landing, not the document\'s first', () {
      final details = ParaglidingEarthApi.parseSiteDetails(
        _twoLaunchesEachWithALanding,
        siteId: 3046,
      );

      expect(details, isNotNull);
      // 555 is Planfait's, and is what the first-in-document lookup returned.
      expect(details!['landing_altitude'], '467');
      expect(details['landing_lat'], '45.7889');
      expect(details['landing_lng'], '6.21639');
    });

    test('a launch with no landing of its own gets none', () {
      final details = ParaglidingEarthApi.parseSiteDetails(
        _onlyTheSecondLaunchHasALanding,
        siteId: 6724,
      );

      expect(details, isNotNull);
      expect(details!['takeoff_altitude'], '436');
      expect(details.containsKey('landing_altitude'), isFalse,
          reason: 'the only landing here belongs to another site');
      expect(details.containsKey('landing_lat'), isFalse);
      expect(details.containsKey('landing'), isFalse);
    });

    test('still matches the takeoff itself by id', () {
      final details = ParaglidingEarthApi.parseSiteDetails(
        _twoLaunchesEachWithALanding,
        siteId: 3046,
      );

      expect(details!['name'], 'Montmin (Col de la Forclaz)');
      expect(details['takeoff_altitude'], '1265');
    });
  });

  group('altitudes PGE does not actually have', () {
    String withTakeoffAltitude(String value) => '''
<?xml version="1.0"?>
<search>
  <results>1</results>
  <takeoff>
    <name>Lancrenaz</name>
    <pge_site_id>21827</pge_site_id>
    <takeoff_altitude>$value</takeoff_altitude>
  </takeoff>
</search>
''';

    test('a negative altitude is dropped rather than shown', () {
      // France alone carries 8 of these in 1081 sites; the header rendered
      // them as "-1m".
      for (final sentinel in ['-1', '-2']) {
        final details = ParaglidingEarthApi.parseSiteDetails(
          withTakeoffAltitude(sentinel),
          siteId: 21827,
        );

        expect(details, isNotNull);
        expect(details!.containsKey('takeoff_altitude'), isFalse,
            reason: '$sentinel means "not recorded", not an altitude');
        expect(details['name'], 'Lancrenaz',
            reason: 'the rest of the site must survive');
      }
    });

    test('zero is kept - a sea-level launch is a real thing', () {
      final details = ParaglidingEarthApi.parseSiteDetails(
        withTakeoffAltitude('0'),
        siteId: 21827,
      );

      expect(details!['takeoff_altitude'], '0');
    });

    test('a negative landing altitude is dropped too', () {
      const xml = '''
<?xml version="1.0"?>
<search>
  <results>1</results>
  <takeoff>
    <name>Somewhere</name>
    <pge_site_id>1</pge_site_id>
    <takeoff_altitude>900</takeoff_altitude>
  </takeoff>
  <landing>
    <landing_altitude>-1</landing_altitude>
    <landing_lat>45.0</landing_lat>
    <landing_pge_site_id>1</landing_pge_site_id>
  </landing>
</search>
''';

      final details = ParaglidingEarthApi.parseSiteDetails(xml, siteId: 1);

      expect(details!.containsKey('landing_altitude'), isFalse);
      expect(details['landing_lat'], '45.0',
          reason: 'the landing still exists, only its altitude is unknown');
    });
  });

  group('heightAboveLanding', () {
    test('is the drop between the two altitudes', () {
      expect(heightAboveLanding('956', '555'), 401);
      expect(heightAboveLanding(1265, 467), 798);
    });

    test('needs both figures', () {
      expect(heightAboveLanding('956', null), isNull);
      expect(heightAboveLanding(null, '555'), isNull);
      expect(heightAboveLanding(null, null), isNull);
      expect(heightAboveLanding('', ''), isNull);
    });

    test('gives nothing when the landing is not below the launch', () {
      // A winch or flatland site, or an altitude nobody filled in. "-401 m"
      // beside a launch reads as a bug rather than as the gap it is.
      expect(heightAboveLanding('555', '956'), isNull);
      expect(heightAboveLanding('600', '600'), isNull);
    });

    test('rounds to whole metres', () {
      expect(heightAboveLanding('956.4', '555.1'), 401);
    });
  });

  group('the header as a pilot reads it', () {
    setUp(() async {
      // The page reads favourites out of the catalogue table on open.
      await PgeSitesDatabaseService.instance.initializeTables();
      ParaglidingEarthApi.debugSetOfflineMode(offline: false);
      ParaglidingEarthApi.debugHttpClient = MockClient(
        (request) async => http.Response(_brauneckWithItsLanding, 200,
            headers: {'content-type': 'application/xml; charset=utf-8'}),
      );
    });

    tearDown(() {
      ParaglidingEarthApi.debugHttpClient = null;
    });

    testWidgets('launch and landing state the datum, with the drop between',
        (tester) async {
      // A Pixel 9 in logical pixels, as in site_details_layout_test.
      tester.view.physicalSize = const Size(411, 923);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: SiteDetailsScreen(
          paraglidingSite: ParaglidingSite(
            id: 10727,
            name: 'Brauneck',
            latitude: 47.6634,
            longitude: 11.5233,
            altitude: 1541,
            siteType: 'launch',
            windDirections: const ['N', 'NE'],
            source: 'pge:8612',
          ),
          maxWindSpeed: 25,
          cautionWindSpeed: 15,
        ),
      ));

      // The weather fetches fail in a test binding and spin forever, so
      // pumpAndSettle is no use - the frames are pumped by hand.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('1541 m AMSL'), findsOneWidget);
      expect(find.text('718 m AMSL'), findsOneWidget);
      expect(find.text('823 m'), findsOneWidget,
          reason: 'the drop belongs on the launch line');
      expect(find.text('Landing:'), findsOneWidget);
      expect(find.byTooltip('Height above the landing area'), findsOneWidget);
      expect(find.byTooltip('Altitude above mean sea level'), findsNWidgets(2));
    });
  });
}

/// Brauneck, above Lenggries - launch 1541m, landing 718m, so an 823m drop.
/// Trimmed from the live response for `lat=47.6634&lng=11.5233&distance=0.5`.
const _brauneckWithItsLanding = '''
<?xml version="1.0"?>
<search>
  <results>1</results>
  <takeoff>
    <name>Brauneck</name>
    <pge_site_id>8612</pge_site_id>
    <takeoff_altitude>1541</takeoff_altitude>
    <lat>47.6634</lat>
    <lng>11.5233</lng>
    <countryCode>de</countryCode>
    <orientations><N>1</N><NE>1</NE><E>0</E><SE>0</SE><S>0</S><SW>0</SW><W>0</W><NW>1</NW></orientations>
  </takeoff>
  <landing>
    <site>Brauneck</site>
    <landing_name>Hangglider Landing</landing_name>
    <landing_lat>47.6798</landing_lat>
    <landing_lng>11.5641</landing_lng>
    <landing_altitude>718</landing_altitude>
    <landing_pge_site_id>8612</landing_pge_site_id>
  </landing>
</search>
''';
