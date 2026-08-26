import 'package:flutter/material.dart';

import '../../../data/models/paragliding_site.dart';
import '../../../utils/site_marker_utils.dart';

/// One row of the site search dropdown.
///
/// The leading widget is the symbol the map draws for that site - an outlined
/// pin for a launch, a windsock for a landing - and it is load-bearing rather
/// than decoration: a landing usually carries its launch's name ("Hirschberg
/// Startplatz" and "Hirschberg Landeplatz 1"), and 423 of the catalogue's 5,882
/// landings say nothing about landing at all ("West paddock", "Godfrey's"). Two
/// rows that read the same have to be told apart before the tap, not after it.
///
/// The symbol comes from [SiteMarkerUtils.siteSymbol] so this cannot drift from
/// what the map and the legend show, for the same reason #362 gave the glyph one
/// definition.
///
/// It replaces a two-letter `CircleAvatar` that was wrong as well as redundant:
/// a catalogue row's `country` is the JOINed country *name*, so the circle read
/// "GE" above a subtitle reading "Germany".
class SiteSearchResultTile extends StatelessWidget {
  const SiteSearchResultTile({
    super.key,
    required this.site,
    required this.onTap,
  });

  final ParaglidingSite site;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      // A fixed box so names line up whichever symbol a row got.
      leading: SizedBox(
        width: SiteMarkerUtils.resultSymbolSize,
        height: SiteMarkerUtils.resultSymbolSize,
        child: Center(
          child: SiteMarkerUtils.siteSymbol(
            site.siteType,
            // Every search result is a catalogue row, so they are all "New
            // Sites"; a landing ignores this and carries the windsock's palette.
            color: SiteMarkerUtils.newSiteColor,
            size: SiteMarkerUtils.resultSymbolSize,
          ),
        ),
      ),
      title: Text(
        site.name,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        site.country ?? 'Unknown',
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
