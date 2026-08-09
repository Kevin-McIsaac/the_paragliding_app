/// The catalogue's key: one contributing guide's own identifier for a launch,
/// as `provider:id` - `pge:4632`, `siteguide_au:106-28`.
///
/// Why not the catalogue's own row id: it is a dense row number that tracks the
/// producer's file order, so a single upstream insertion shifts every id after
/// it. Nothing persistent may reference it. A guide's id is assigned and
/// maintained upstream and does not move, which is what lets a flown site keep
/// its link across a catalogue rebuild.
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
  static const List<String> providerPrecedence = ['pge', 'siteguide_au'];

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

  /// Every `provider:id` token in a `source` value, in the order given.
  static List<String> tokensOf(String? source) {
    if (source == null || source.isEmpty) return const [];
    return source
        .split(';')
        .map((token) => token.trim())
        .where((token) => token.contains(':') && !token.startsWith(':'))
        .toList();
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
