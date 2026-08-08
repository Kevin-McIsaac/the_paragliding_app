# Site details: is the bottom sheet still right, and why is the tab body clipped?

An options paper. Nothing here is implemented.

All line numbers are against `origin/worktree-federated-sites` at **`03ca14d`** ("Rename
pge_site_id to catalog_site_id…", PR #323), not `main`. The dialog is 1938 lines there;
`main`'s copy is 274 insertions behind.

---

## 1. What is actually there

### 1.1 The container

`the_paragliding_app/lib/presentation/widgets/site_details_dialog.dart`

| Line | What |
|---|---|
| 579–583 | `DraggableScrollableSheet(initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.95, expand: false)` |
| 600 | outer `Column(mainAxisSize: MainAxisSize.min)` |
| 604–616 | drag handle (outside the scroll view, so it always drags the sheet) |
| 618–620 | `Expanded(SingleChildScrollView(controller: scrollController, padding: fromLTRB(20,0,20,20)))` — the sheet's own controller lives here |
| 622 | inner `Column(mainAxisSize: MainAxisSize.min)` — header, overview, then… |
| **736** | **`SizedBox(height: 450, // Fixed height for tab content`** |
| 738–741 | `SizedBox(height: 40, child: TabBar(...))` |
| 780–781 | `Expanded(child: TabBarView(...))` → so the tab body is exactly **410 dp**, always |
| 794 | `else ..._buildSimpleContent(...)` — the no-tabs fallback, a plain list of widgets |

So the brief's sketch of the tree is correct in every particular.

### 1.2 The tabs

| Line | Tab | Shape |
|---|---|---|
| 1304 | `_buildWeatherTab` — **Forecast** | `RefreshIndicator` → `SingleChildScrollView` (1319) → `ConstrainedBox(maxHeight: 390)` (1327) → attribution bar + `SiteForecastTable` |
| 1023 | `_buildTakeoffTab` — **PGE** | `Scrollbar` (1025) → `SingleChildScrollView` (1027, own controller) → ~12 optional prose sections, ending at the `Open in PGE` button (1294) |
| 946 | `_buildSourceTab` — **every non-PGE guide** | `Scrollbar` (955) → `SingleChildScrollView` (957, own controller) → 4 detail rows + an `Open in <label>` button |

Each tab gets its own `ScrollController` via `_scrollControllerFor` (325–326), disposed at
321–326. That was added on this branch because offscreen tabs asserted without one.

Supporting widgets: `site_forecast_table.dart:21`, `fixed_column_table.dart:43–49`
(a `Stack` over a horizontal `SingleChildScrollView`, with the day column pinned),
`flyability_constants.dart:6` (`cellSize = 36.0`), and `_dayColumnWidth = 80.0`
(site_details_dialog.dart:140).

### 1.3 Where it is opened from — one place, not several

The brief says "and from a few other places". That is **wrong**; there is exactly one
entry point:

```
nearby_sites_map.dart:219  _onSiteMarkerTap
  → widget.onSiteSelected  (nearby_sites_map.dart:222)
  → nearby_sites_screen.dart:1813  onSiteSelected: _onSiteSelected
  → nearby_sites_screen.dart:1196  _onSiteSelected
  → nearby_sites_screen.dart:1207  _showSiteDetailsDialog(...)
  → nearby_sites_screen.dart:1347  showModalBottomSheet(isScrollControlled: true,
                                     backgroundColor: Colors.transparent)  [1352]
```

`multi_site_flyability_screen.dart:526` also defines `_onSiteSelected`, but it is a name
collision — it sets `_selectedReferenceSite` and reloads data. It never opens this dialog.

**This matters for the options below**: changing the presentation is a five-line change at
one call site, not a migration.

Two further facts about the presentation, both load-bearing:

- `showModalBottomSheet` is called **without `useSafeArea`**, and the dialog contains no
  `SafeArea` and no `MediaQuery` reference anywhere. Nothing accounts for the Android
  gesture inset at the bottom (~24 dp) or the status bar at the top when expanded to 0.95.
- It is **modal**. There is a `barrierColor` scrim (Material's default `black54`) over the
  map, and the map cannot be panned while the sheet is up. The usual argument for a bottom
  sheet — "keep map context" — is therefore *already not being delivered*. The user sees a
  dimmed, frozen map behind a 60%-height panel.

---

## 2. Diagnosis

### 2.1 The arithmetic

Pixel 9: 1080×2424 px at dpr 2.625 → **411 × 923 dp**.

Estimated natural height of the sheet's content (heights from the widget tree; text-metric
dependent, so treat as ±10%):

| Block | dp |
|---|---|
| drag handle + its 8 dp vertical margins | 20 |
| header row (wind rose is `size: 60.0`, the tallest thing in it) | 60 |
| `SizedBox(height: 8)` | 8 |
| overview rows (1–3 rows of 16 dp icons + 6 dp gaps) | ~46 |
| `SizedBox(height: 8)` | 8 |
| **the fixed box** | **450** |
| scroll view bottom padding | 20 |
| **total** | **~612** |

Sheet extents: `0.30 → 277 dp`, `0.60 → 554 dp`, `0.95 → 877 dp`.

### 2.2 Why the "Open in PGE" button is cut in half

At the initial 0.6 extent the sheet is 554 dp and the content is ~612 dp, so the outer
`SingleChildScrollView` (619) has ~58 dp of overflow. Chrome above the fixed box occupies
~142 dp, leaving **412 dp of the 450 dp box visible** — TabBar 40, so about **372 dp of the
410 dp `TabBarView` is on screen**. The last ~38 dp of the PGE tab's *own scroll viewport*
sits below the sheet's bottom edge, and the ~24 dp gesture inset (nothing accounts for it,
§1.3) hides more.

The `Open in PGE` button (1294) is the **last widget in that tab**. So when the user scrolls
the inner view to its end, the button comes to rest at the bottom of the inner viewport —
which is precisely the part that is off screen. A 40 dp `OutlinedButton` against ~40–60 dp of
hidden viewport is exactly the reported "cut in half".

The nasty part: **inner scrolling can never reveal it.** The inner view is already at its
end. The fix would be to scroll the *outer* view up by ~58 dp, but a vertical drag started
over the `TabBarView` is consumed by the tab's own scrollable and never reaches the outer
one — Flutter does not chain nested scrollables. The only place the user can grab the outer
scroll view is the ~142 dp of header. Nothing signals that.

So the content is not clipped by a `ClipRect`. It is parked in a viewport whose bottom is
rendered outside the sheet, and the gesture that would bring it into view is swallowed.

### 2.3 Why dragging taller only adds dead space

At 0.95 the sheet is 877 dp and the content is still ~612 dp — the `Column` at 622 is
`mainAxisSize: min` and the `SizedBox` at 736 is a constant, so neither grows. Result:
**~265 dp of empty surface** below the box. Confirmed by the report; the arithmetic agrees.

The two symptoms are one bug seen from both sides: **the tab body's height is unrelated to
the space available for it.**

### 2.4 Where 450 came from, and why it is wrong for every tab

`40 (TabBar) + 8 (padding) + 390 (the Forecast tab's own `maxHeight`, line 1327) = 438`.
450 is a rounding-up of the **Forecast** tab's needs. It is wrong for all three tabs:

- **Forecast** naturally needs ~330 dp (8 rows × 36 dp `cellSize`, plus the attribution
  bar), is capped at 390, and is handed 410. It has spare room *before* the sheet is even
  expanded, and gains nothing from expanding.
- **PGE** wants several thousand dp and gets 410.
- **Guide tabs** (ANSG today) need ~250 dp and get 410.

One constant cannot serve all three, and each new guide tab makes that more obviously true.

### 2.5 Two corrections to the brief

- **"no scrollbar or affordance".** The observation is right, the cause is not: both guide
  tabs *do* wrap their scroll view in a `Scrollbar` (955, 1025). But neither passes
  `thumbVisibility: true`, so on Android the Material scrollbar fades out at rest and shows
  nothing until you are already dragging. The **Forecast** tab (1304) has no `Scrollbar` at
  all. Worth knowing, because "add a scrollbar" is not the fix — "make the existing ones
  persistent" is, and it is one line each.
- **"ANSG (a short summary plus an Open in Site Guide button)"** is not ANSG-specific.
  `_buildSourceTab` (946) is the generic branch for *any* non-PGE guide; ANSG is simply the
  only one that exists today. Every future guide gets this shape for free — which is
  relevant to how much the tab count really costs.

### 2.6 A latent bug in the same family

`ConstrainedBox(maxHeight: 390)` at 1327 wraps a `Column(mainAxisSize: min)` (1330).
A `ConstrainedBox` neither scrolls nor clips: if the attribution bar wraps to an extra line,
or a future model adds a row, the column overflows its 390 and paints the yellow-and-black
stripes. It is the same mistake as the 450, one level down, and any fix should take it out
too.

---

## 3. Question 1 — is a bottom sheet the right container?

### Option 1A — Keep the draggable modal sheet, fix only the layout

Presentation unchanged; §4 does the work.

- **Pros.** Marker-tap → bottom sheet is *the* mobile-map idiom (Google Maps, Windy, XCTrack
  all do it). No new screen, no navigation change, no call-site change. Drag-to-expand starts
  doing something useful instead of adding dead space. Smallest possible diff.
- **Cons.** Even fully expanded (0.95) the tab body tops out at ~695 dp — a cramped reading
  area for the PGE prose. Tabs inside a sheet keep a permanent gesture ambiguity: a vertical
  drag over the body scrolls the tab, never the sheet. The forecast table stays 411 dp wide.
- **Effort** S. **Risk** Low.

### Option 1B — Full-screen route

`Navigator.push` → `Scaffold(appBar: AppBar(title, actions: [favourite]), bottom: TabBar,
body: TabBarView)`.

- **Pros.** Dissolves Question 2 completely: `Scaffold` gives a bounded body, `Expanded`
  works, every tab scrolls naturally, no fixed height anywhere, no nested-controller
  problem. ~830 dp of body — 2.2× today's reading area, and the whole 7-day table fits with
  no `maxHeight` cap. `AppBar.bottom: TabBar` is the standard M3 home for a growing tab set.
  System back / predictive back returns to the map with camera and state intact, because
  `NearbySitesScreen` stays alive underneath.
- **Cons.** Abandons the map-anchored idiom for the common case, which is a *glance*: wind
  now, flyability now, is it on. That becomes push-a-route-and-come-back. Loses drag-to-peek.
  Does **not** help the table's width — 411 dp either way.
- **Effort** S–M (rewrite the outer 40 lines of `build`, swap 1352 for a push). **Risk** Low.

### Option 1C — Peek sheet + full-screen details (the Google Maps pattern)

Sheet shrinks to a compact card — wind rose, name, altitude/wind, favourite, flyability now,
plus a **Details** button that pushes 1B.

- **Pros.** Correct for both use cases: glance stays one tap on the map, deep reading gets a
  real page. Scales indefinitely as guides are added. Arguably *less* total code than today,
  because the sheet stops being a scroll container at all.
- **Cons.** Two containers to build and keep visually consistent, plus a second route.
  Speculative: nobody has yet complained about the extra tap, because the extra tap does not
  exist yet.
- **Effort** M–L. **Risk** Low–Medium. **This is over-engineering to do now.** It is the
  right destination if the tab count keeps climbing; 1A/4B is a stepping stone to it, not a
  detour.

### Option 1D — Non-modal persistent sheet (`showBottomSheet` / `Scaffold.bottomSheet`)

- **Pros.** Actually delivers the map context the current design only claims: no scrim, map
  stays pannable behind it.
- **Cons.** **Does not fix Question 2 at all** — same fixed box, same clipping. Adds manual
  back-button handling, dismissal, and a piece of `NearbySitesScreen` state to own. Solves a
  problem nobody reported while leaving the reported one intact.
- **Effort** M. **Risk** Medium. Not recommended.

---

## 4. Question 2 — the fixed-height box

### Option 4A — Make the height responsive

`SizedBox(height: MediaQuery.sizeOf(context).height * 0.5)`, or a `LayoutBuilder`.

- **Pros.** One line. Helps small and large phones alike.
- **Cons.** Still a magic fraction, just a portable one. **Neither symptom goes away**: at
  0.95 there is still dead space (the box does not track the sheet's extent, only the
  screen's), and the inner viewport can still extend below the sheet's edge. It is a
  band-aid over §2.2.
- **Effort** XS. **Risk** Low. Reasonable only as a stopgap, paired with
  `thumbVisibility: true` on the two `Scrollbar`s and a `Scrollbar` on the Forecast tab.

### Option 4B — Restructure: header scrolls, tab body fills the remainder ✅

Replace the single `Expanded(SingleChildScrollView(...))` at 618 with siblings:

```
Column(mainAxisSize: min)            // 600, unchanged
  ├── drag handle                    // 604, unchanged
  ├── Flexible(SingleChildScrollView(controller: scrollController,
  │     child: Column([header, overview])))
  ├── TabBar                         // no longer inside the scroll view
  └── Expanded(TabBarView(...))      // no SizedBox, no 450
```

The brief warns that `Expanded` inside a `SingleChildScrollView` cannot work. True — but
this moves the tab body *out* of the scroll view, so it never sees an unbounded constraint.
`DraggableScrollableSheet` hands its builder a bounded height, so `Flexible` + `Expanded`
are legal. The existing `Expanded` at 618 already proves it inside this same
`MainAxisSize.min` column.

The controller question resolves cleanly rather than fiddlily. The sheet's `scrollController`
stays on the header scroll view. That view normally has **zero scroll extent**, so any drag
on it is over-scroll, which `DraggableScrollableSheet` translates into an extent change —
i.e. **dragging the header resizes the sheet, dragging the body scrolls the tab.** That is a
sharper, more predictable model than today's, where dragging the header does something
different depending on how much slack the outer view happens to have. Each tab keeps its own
controller (325), unchanged.

- **Pros.** Kills both symptoms at the root. Tab body is *always* exactly the space available
  — no dead space at 0.95 (body grows to ~695 dp), no viewport hanging below the sheet edge
  at 0.6 (body is ~372 dp and entirely on screen). Drag-to-expand becomes meaningful for the
  first time. Deletes both magic numbers (450, and the 390 at 1327 can go with it). Tab count
  becomes free. One file, no call-site change.
- **Cons.** The `else` branch at 794 (`_buildSimpleContent`, the no-tabs fallback) has a
  different shape and needs a small conditional — two layouts in one `build`. Needs
  `useSafeArea: true` at 1352 or a `SafeArea` at the bottom, or the gesture inset still eats
  the last rows. Drag-to-expand from the header must be verified on a device.
- **Effort** S (~40 lines moved, one file). **Risk** Low–Medium.

### Option 4C — `NestedScrollView`

`NestedScrollView(controller: sheetScrollController, headerSliverBuilder: [
SliverToBoxAdapter(header), SliverPersistentHeader(pinned: true, TabBar)], body: TabBarView)`.

- **Pros.** The widget purpose-built for header + pinned tabs + per-tab scroll. Would give a
  collapsing header for free.
- **Cons.** Substantially more machinery than the problem needs:
  `SliverOverlapAbsorber`/`Injector` to avoid a gap under the pinned header, a
  `SliverPersistentHeaderDelegate` class for the TabBar, and `NestedScrollView` has a long
  history of rough edges with `TabBarView` scroll-position retention. Combining it with
  `DraggableScrollableSheet`'s controller is a supported-but-lightly-trodden path.
- **Effort** M. **Risk** Medium. **Over-engineering for three tabs of modest content in a
  sub-10-screen app** — 4B reaches the same place with a `Flexible` and an `Expanded`.

### Option 4D — Full-screen route (= Option 1B)

Same change, described from the other side. `Scaffold` body is bounded, so
`Column([TabBar, Expanded(TabBarView)])` just works. No fixed height, no nesting, no
controller juggling, and §2.6 goes away with the `maxHeight` cap.

- **Effort** S–M. **Risk** Low. **Fixes both questions at once** — see §5.

---

## 5. Do the two questions have the same answer?

**They share one root cause, but not the answer the brief expects.**

The root cause of Question 2 is that `SizedBox(height: 450)` at line 736 has no relationship
to the space available. Every reported symptom — the half-cut button, the dead black space,
the fact that dragging makes it worse — follows from that single constant, and §2.2/§2.3
show the arithmetic both ways.

That constant is **not** a consequence of choosing a bottom sheet. It is a consequence of
putting a fixed-height box inside a scroll view. The identical mistake in a full-screen
`Scaffold` would produce the identical dead space. Conversely, the sheet is perfectly capable
of hosting this content once the tab body is allowed to fill its slot.

So: **Question 1's answer is "yes, keep the sheet"; Question 2's answer is "delete the 450".**
Option 4D would fix both, but it fixes Question 2 as a side effect of answering Question 1
in a way Question 1 does not require.

---

## 6. Recommendation

**Do Option 4B, keep Option 1A. Roughly 40 lines in one file.**

1. **Move the `TabBar` and `TabBarView` out of the outer `SingleChildScrollView`** and make
   them siblings of a `Flexible` header (§4B). Delete `SizedBox(height: 450)` (736) and the
   `ConstrainedBox(maxHeight: 390)` (1327) with it.
2. **Pass `useSafeArea: true`** to `showModalBottomSheet` (nearby_sites_screen.dart:1352), or
   wrap the sheet body bottom in a `SafeArea`. Without it the gesture inset keeps eating the
   last ~24 dp regardless of everything above.
3. **Add `thumbVisibility: true`** to the two `Scrollbar`s (955, 1025) and wrap the Forecast
   tab (1319) in one. This is the actual fix for "no affordance that more content exists"
   (§2.5) — the scrollbars are already there, they are just invisible at rest.
4. Consider raising `initialChildSize` from 0.6 to ~0.7 once the body scales, so the first
   thing the pilot sees is more forecast and less empty header. Cheap, reversible, worth
   eyeballing on a device.

**Why not full screen (1B/4D),** despite it being the cleaner engineering answer: the sheet
is not what is broken. A marker tap on a map opening a sheet is the idiom every comparable
app uses, and once 4B lands, drag-to-expand does the job it was always meant to — 0.6 for a
glance at the forecast, 0.95 for reading a guide. Moving to a page trades that for reading
room the app can get more cheaply, and it is a one-way door on the interaction model.

**Explicitly over-engineered for this app, now:** Option 4C (`NestedScrollView`) and Option
1C (peek + details page). 4C is more machinery than three tabs justify. 1C is the right
long-term shape but is a bet on a complaint nobody has made.

**When to revisit.** Two triggers, both concrete:

- **A fourth or fifth guide tab.** Four fixed-width tabs at `TabAlignment.fill` on a 411 dp
  screen is ~100 dp each; `_sourceLabel` (PGE, ANSG) survives that, longer labels will not.
  At that point switch the `TabBar` to `isScrollable: true`, and reconsider Option 1C.
- **Prose tabs that need real reading time.** If pilots start reading the PGE access notes
  at launch rather than skimming them, ~695 dp at full expansion is the wrong reading
  surface and 1C earns its keep.

## 7. Verification, whichever option is taken

The failure mode here is layout, so a passing widget test proves little unless it is pinned
to a real viewport. If this is implemented:

- Set a **fixed test surface of 411 × 923** and assert the `Open in PGE` button's bottom edge
  is inside the sheet's paint bounds after scrolling the PGE tab to its end. Run it against
  the **unfixed** code first and watch it fail — per CLAUDE.md, a test that passes either way
  reads as coverage and is worse than none.
- Assert there is **no `SizedBox` with a hard-coded height** wrapping the `TabBarView`, so
  the constant cannot come back.
- Check the **no-tabs fallback** (`_buildSimpleContent`, 794) still renders — it is the
  branch nobody looks at.
- `flutter analyze` clean, and `flutter test`.
