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
  /// **The producer decides this now** - it emits a `ref` column, and the import
  /// keys on that. This list survives as the fallback for a catalogue published
  /// before the column, which is the bundled asset of an older release, and it is
  /// still what the v4 -> v5 migration and the backfill use, since those read a
  /// local row's `source` where no emitted ref exists.
  ///
  /// It must not drift from the producer's `KEY_PRECEDENCE`: a launch keyed
  /// `pge:` there and `ansg:` here would leave a fresh install and an upgraded
  /// one disagreeing about the same site. The producer asserts the two agree over
  /// its whole catalogue, in tests/test_ref_matches_the_app.py.
  ///
  /// `pge` leads because it supplies almost all of the catalogue's tokens; only
  /// 89 rows carry two at all.
  ///
  /// A provider is the guide's own abbreviation, lowercased - `pge` for
  /// ParaglidingEarth, `ansg` for the Australian National Site Guide, `ffvl` for
  /// the Fédération Française de Vol Libre when it arrives. Whatever the guide
  /// is actually called, rather than a fixed width: the prefix is carried in
  /// every stored ref, so it wants to be short, but a recognisable acronym beats
  /// a letter saved.
  ///
  /// The only hard rule is that it cannot contain `:` or `;` - those separate the
  /// id and the tokens, so a prefix holding either would not survive a round
  /// trip through `source`.
  static const List<String> providerPrecedence = ['pge', 'ansg'];

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
        // Both halves have to be present. `pge:` names no launch, and keying a
        // row on it would collide with every other id-less token from that
        // guide - so it is dropped rather than trusted. Not reachable against
        // today's catalogue; this whole change is about not assuming that holds.
        .where((token) {
          final separator = token.indexOf(':');
          return separator > 0 && separator < token.length - 1;
        })
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
  /// where the stored link genuinely is a PGE id. It must not be used to guess a
  /// ref for a *federated* id: those come from the catalogue's own registry and
  /// overlap PGE's id space, so inventing `pge:<n>` from one would point the site
  /// at an unrelated launch - the exact failure this key exists to end.
  static String forPgeId(Object pgeId) => 'pge:$pgeId';
}
