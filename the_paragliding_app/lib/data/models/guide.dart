import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../services/logging_service.dart';
import '../../utils/catalog_ref.dart';

/// Who a `source` prefix is, as the guide describes itself.
///
/// A catalogue row names its guides by key - `dhv:1443-...;pge:10043` - and a
/// key is not a name. Nothing in the catalogue says `dhv` is the DHV
/// Geländedatenbank, that a pilot should read "DHV" on a tab, or where DHV's
/// page for that site is. The app used to answer all three from four hand-written
/// `switch` expressions on the site page, plus a second, divergent copy on the
/// About screen - so a guide the producer added stayed nameless here until
/// someone shipped a release for it, and the two copies could disagree about
/// the same guide (they did: two different DHV URLs).
///
/// It is the producer's now, published as `app/guides.json` beside the rows and
/// bundled at `assets/data/guides.json`. Small and slow-moving - one entry per
/// guide, three today - which is why it is a file rather than columns repeated
/// on every one of 18,761 rows.
class Guide {
  const Guide({
    required this.key,
    required this.label,
    required this.fullName,
    required this.homepage,
    required this.siteUrlTemplate,
    required this.licence,
    required this.licenceUrl,
  });

  /// The provider prefix carried in every `source` token, e.g. `dhv`.
  final String key;

  /// What a pilot sees on a tab.
  final String label;

  /// The guide spelled out, for tooltips and attribution. A label alone is
  /// ambiguous - "PGE" means nothing until you have seen it once.
  final String fullName;

  /// The guide's front door, for an attribution link. Not the same address as
  /// a site page: DHV's index is `db3/gelaende`, its detail page `db2/details.php`.
  final String homepage;

  /// One site's page, with `{id}` to be filled in. See [siteUrl].
  final String siteUrlTemplate;

  /// Empty where the guide publishes no terms, which is the honest answer for
  /// DHV's KML export and Site Guide's bulk export - implying a licence nobody
  /// granted would be worse than showing none.
  final String licence;
  final String licenceUrl;

  bool get hasLicence => licence.isNotEmpty && licenceUrl.isNotEmpty;

  /// This guide's page for a launch, given the row's `site_group`.
  ///
  /// **The id comes from `site_group`, not from `source`,** and that is the
  /// whole reason the template is published rather than derived here. A
  /// `source` id names the *launch*; these guides publish a page per *site*,
  /// and two of the three append a suffix to reach the launch - `pge:6824-lz`,
  /// `ansg:lz-1`. `site_group` carries the site id for every provider on every
  /// row (checked over the whole catalogue, 19,759 of 19,759).
  ///
  /// This used to chop the source id at the first hyphen instead, which sent
  /// every PGE landing to `?site=6824-lz` and every Australian one to
  /// `/sites/details/lz`: 4,828 of 19,759 links.
  ///
  /// Null when the row's `site_group` does not name this guide, rather than a
  /// half-built URL - a link that 404s is worse than no link.
  String? siteUrl(String? siteGroup) {
    for (final token in CatalogRef.tokensOf(siteGroup)) {
      if (CatalogRef.providerOf(token) == key) {
        return siteUrlTemplate.replaceAll(
          '{id}',
          token.substring(token.indexOf(':') + 1),
        );
      }
    }
    return null;
  }
}

/// The guides the bundled catalogue knows about, keyed by provider prefix.
///
/// Loaded once at startup. Reads are synchronous because they happen in
/// `build()`, and a guide list that arrives a frame late would flash raw keys
/// on the tabs.
class Guides {
  const Guides._();

  static const String assetPath = 'assets/data/guides.json';

  static Map<String, Guide> _guides = const {};

  /// Load the bundled registry. Safe to call more than once.
  ///
  /// A failure here is not fatal and must not be: every caller degrades to the
  /// raw provider key, which is what the app showed for an unranked guide
  /// before this existed. A crash on startup because a guide could not be
  /// *named* would be a far worse trade than a tab reading `ffvl`.
  static Future<void> load() async {
    try {
      final decoded = jsonDecode(await rootBundle.loadString(assetPath));
      _guides = {
        for (final entry in (decoded as Map<String, dynamic>).entries)
          entry.key: Guide(
            key: entry.key,
            label: (entry.value['label'] ?? entry.key) as String,
            fullName: (entry.value['full_name'] ?? entry.key) as String,
            homepage: (entry.value['homepage'] ?? '') as String,
            siteUrlTemplate: (entry.value['site_url_template'] ?? '') as String,
            licence: (entry.value['licence'] ?? '') as String,
            licenceUrl: (entry.value['licence_url'] ?? '') as String,
          ),
      };
      LoggingService.structured('GUIDES_LOADED', {
        'count': _guides.length,
        'keys': _guides.keys.join(','),
      });
    } catch (error, stackTrace) {
      LoggingService.error('[GUIDES] Failed to load $assetPath', error, stackTrace);
    }
  }

  /// Every guide, in the order the producer published them.
  static Iterable<Guide> get all => _guides.values;

  // pageUrlFor is gone. It picked a single guide for a row - primary, then the
  // key - so a landing could be linked out to from a map pin and a launch's
  // header row. Both now open the landing's own page, which renders one tab per
  // contributing guide with its own "Open in X", so a landing described by two
  // guides gets both rather than whichever this chose.
  //
  // Guide.siteUrl is what those tabs use, and stays.

  /// The guide behind a `source` prefix, or null if the catalogue names one
  /// this release has never heard of.
  static Guide? of(String provider) => _guides[provider];

  /// What to call a guide on a tab. Falls back to the raw prefix, which is what
  /// the old `switch` did for anything it did not list.
  static String labelOf(String provider) => _guides[provider]?.label ?? provider;

  /// The guide spelled out, same fallback.
  static String fullNameOf(String provider) =>
      _guides[provider]?.fullName ?? provider;

  @Deprecated('Test seam: use load(). Only for tests that cannot read assets.')
  static void debugSet(Map<String, Guide> guides) => _guides = guides;
}
