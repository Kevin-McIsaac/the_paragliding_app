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

  /// The ref for a row stored before the producer emitted one, from its
  /// `source` column.
  ///
  /// **This does not choose between guides, and must not start to.** Which
  /// guide's id keys a launch is the producer's decision, published in the
  /// `ref` column; an import without that column is now rejected outright
  /// rather than keyed by guesswork, because guessing differently from the
  /// producer re-keys a launch, and a re-key is a delete plus an insert - the
  /// pilot's favourite goes with the deleted row and every `catalog_ref` to it
  /// dangles permanently, since the old key is never emitted again.
  ///
  /// This used to hold a `providerPrecedence` list hand-copied from the
  /// producer's `KEY_PRECEDENCE`, with a comment on each side saying the two
  /// "must not drift" - which is a hope with a test either side of it, not a
  /// guarantee. Requiring the emitted key removes the second opinion entirely.
  ///
  /// What is left are the two backfills for rows already on disk: `_backfillRefs`
  /// and the v4 -> v5 migration. Those rows predate federation, so their `source`
  /// holds a single token and there is nothing to rank - first valid token is
  /// the whole rule. Callers that could see a federated multi-token `source`
  /// should use the producer's `ref` instead.
  ///
  /// Returns null when there is nothing to key on, so a caller can decide
  /// whether that is a skip rather than inventing a ref.
  static String? fromSource(String? source) {
    final tokens = tokensOf(source);
    return tokens.isEmpty ? null : tokens.first;
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
