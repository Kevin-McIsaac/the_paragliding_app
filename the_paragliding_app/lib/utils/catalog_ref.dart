/// The catalogue's key: one contributing guide's own identifier for a launch,
/// as `provider:id` - `pge:4632`, `ansg:106-28`.
///
/// Why not the catalogue's own `id`: it is assigned by a registry that lives in
/// the producer's repository, not here. That registry is committed and its tests
/// assert stability across runs, so the ids are *intended* to hold - but the
/// guarantee is a file in another project, invisible from this side, and the app
/// had no defence if it ever lapsed. Driven with the ids shifted by one, a flown
/// Mt Borah site rendered a launch 800km away: 380m for 800m, wind N for W, and
/// the pilot's favourite moved with it.
///
/// A guide's own id needs no such guarantee - upstream assigns and maintains it,
/// and it is already in the row. Keying on it means a renumbered catalogue is
/// inert rather than dangerous, and the producer needs no promise from us.
///
/// Why not coordinates or a plus code: measured against the shipped catalogue,
/// 23 cells of ~14m hold more than one launch (the paraglider and hang-glider
/// takeoffs on one hill), and 50 rows share coordinates exactly - so location is
/// not unique. It is not stable either: a guide refining a takeoff by 20m would
/// change the key, and coordinate corrections are one of the routine updates
/// this has to survive.
class CatalogRef {
  const CatalogRef._();

  /// Guides in the order they are preferred when a launch is described by more
  /// than one, most authoritative first.
  ///
  /// A merged row's ref is its highest-precedence token, so the choice has to
  /// be a fixed rule rather than a property of column order - otherwise the key
  /// moves when the producer's output does. `pge` leads because it supplies
  /// 11,508 of the catalogue's 11,792 tokens; only 89 rows carry two at all.
  ///
  /// Providers are three-letter abbreviations of the guide: `pge` is
  /// ParaglidingEarth, `ansg` the Australian National Site Guide. Keep new ones
  /// to three letters - the prefix appears in every stored ref, so a verbose one
  /// is a cost paid on every row forever.
  static const List<String> providerPrecedence = ['pge', 'ansg'];

  /// Prefixes an older producer emitted, mapped to the current name.
  ///
  /// Normalised on read so the app works against a catalogue emitting either,
  /// and stores only the current form. Nothing in the wild needs migrating:
  /// `sites.catalog_ref` has never shipped - released installs still hold the
  /// integer `catalog_site_id` - so no device holds a legacy ref.
  static const Map<String, String> _renamedProviders = {
    'siteguide_au': 'ansg',
  };

  /// The ref for a catalogue row, from its `source` column.
  ///
  /// Returns null when there is nothing to key on, so a caller can decide
  /// whether that is a skip or a fallback rather than inventing a ref.
  static String? fromSource(String? source) {
    final tokens = tokensOf(source);
    if (tokens.isEmpty) return null;

    for (final provider in providerPrecedence) {
      for (final token in tokens) {
        if (providerOf(token) == provider) return token;
      }
    }

    // A guide nobody has assigned a precedence to yet. Keying on it is better
    // than dropping the row; the producer is where an unknown provider should
    // be a hard failure, because that is where the decision can be made.
    return tokens.first;
  }

  /// Every `provider:id` token in a `source` value, in the order given, with any
  /// renamed provider normalised to its current prefix.
  static List<String> tokensOf(String? source) {
    if (source == null || source.isEmpty) return const [];
    return source
        .split(';')
        .map((token) => token.trim())
        .where((token) => token.contains(':') && !token.startsWith(':'))
        .map(_normalise)
        .toList();
  }

  static String _normalise(String token) {
    final provider = providerOf(token);
    final current = _renamedProviders[provider];
    return current == null
        ? token
        : '$current${token.substring(provider!.length)}';
  }

  /// The provider half of a ref, or null if it is not a ref at all.
  static String? providerOf(String? ref) {
    if (ref == null) return null;
    final separator = ref.indexOf(':');
    return separator <= 0 ? null : ref.substring(0, separator);
  }

  /// The ref for a launch known only by a ParaglidingEarth id.
  ///
  /// Used by the v4 -> v5 migration for a database that predates federation,
  /// where the stored link genuinely is a PGE id. It must not be used to guess
  /// a ref for a federated id: those are positional, they overlap PGE's id
  /// space, and inventing `pge:<n>` from one would point the site at an
  /// unrelated launch - the exact failure this key exists to end.
  static String forPgeId(Object pgeId) => 'pge:$pgeId';
}
