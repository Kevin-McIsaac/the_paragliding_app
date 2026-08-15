import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/models/guide.dart';
import 'package:the_paragliding_app/presentation/screens/about_screen.dart';

/// Who each `source` prefix is, and where its pages are.
///
/// The app used to answer this from four `switch` expressions on the site page
/// and a second, divergent copy on the About screen - so a guide the producer
/// added stayed nameless until someone shipped a release, and the two copies
/// could disagree about the same guide. They did: the About screen linked DHV's
/// `db3/gelaende` while the site page used `db2/details.php`.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Guides.load();
  });

  group('the bundled registry', () {
    test('describes the guides the catalogue federates from', () {
      expect(Guides.all.map((g) => g.key), containsAll(['pge', 'ansg', 'dhv']));
      expect(Guides.labelOf('pge'), 'PGE');
      expect(Guides.fullNameOf('dhv'), 'DHV Geländedatenbank');
      expect(Guides.fullNameOf('ansg'), 'Australian National Site Guide');
    });

    test('degrades to the bare key for a guide it has never heard of', () {
      // The behaviour the old `_ => provider` switch arm had, and the reason a
      // guide added upstream is a plain-looking tab rather than a crash.
      expect(Guides.of('ffvl'), isNull);
      expect(Guides.labelOf('ffvl'), 'ffvl');
      expect(Guides.fullNameOf('ffvl'), 'ffvl');
    });

    test('states a licence or states none, never half of one', () {
      for (final guide in Guides.all) {
        expect(guide.licence.isNotEmpty, guide.licenceUrl.isNotEmpty,
            reason: '${guide.key}: a licence url with no licence naming it '
                'reads as a grant nobody made');
      }
      expect(Guides.of('pge')!.licence, 'CC BY-SA 3.0');
      expect(Guides.of('dhv')!.hasLicence, isFalse,
          reason: 'DHV publishes no terms with its KML export');
    });
  });

  group('a guide page is addressed by site', () {
    // The bug the template replaced. `site_group` holds the id a guide's own
    // website answers on; `source` holds the launch, which two of the three
    // guides reach by appending a suffix.
    test('a launch resolves through its own group token', () {
      expect(Guides.of('pge')!.siteUrl('pge:10001'),
          'https://www.paraglidingearth.com/?site=10001');
      expect(Guides.of('dhv')!.siteUrl('dhv:1443;pge:9010'),
          'https://service.dhv.de/db2/details.php?qi=glp_details&item=1443');
    });

    test('a landing resolves to its site, not to the synthesised launch id', () {
      // pge:6824-lz used to produce `?site=6824-lz`, and ansg:lz-1 produced
      // `/sites/details/lz`. Both 404. The group token is the takeoff's site.
      expect(Guides.of('pge')!.siteUrl('pge:6824'),
          'https://www.paraglidingearth.com/?site=6824');
      expect(Guides.of('ansg')!.siteUrl('ansg:136'),
          'https://siteguide.org.au/sites/details/136');
    });

    test('a guide absent from the group gets no link rather than a broken one', () {
      expect(Guides.of('ansg')!.siteUrl('dhv:1443'), isNull);
      expect(Guides.of('pge')!.siteUrl(null), isNull);
      expect(Guides.of('pge')!.siteUrl(''), isNull);
    });
  });

  testWidgets('the About screen credits every guide from the registry',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pump();

    for (final guide in Guides.all) {
      expect(find.text(guide.fullName), findsOneWidget,
          reason: 'a guide the app ships data from must be credited');
    }
    expect(find.text('Database licensed CC BY-SA 3.0'), findsOneWidget);
    expect(find.textContaining('Database licensed'), findsOneWidget,
        reason: 'only ParaglidingEarth states one - the others must not '
            'borrow it');
  });
}
