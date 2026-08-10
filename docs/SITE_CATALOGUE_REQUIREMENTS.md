# Site catalogue: requirements for review

Brief for reviewing how the app absorbs a refreshed site catalogue and what it
does with it. Key code: `pge_sites_download_service.dart`,
`pge_sites_database_service.dart` (`importSitesData`), `catalog_ref.dart`,
`site_matching_service.dart`, `launch_rematch_service.dart`,
`app_initialization_service.dart`.

**How to use this.** Each requirement is stated as an invariant in the pilot's
terms, then — separately, and *not* normative — the mechanism the code happens
to use today. Judge the mechanism against the invariant. Where the two are
merely consistent with each other, the requirement has not been checked.

## Where merging happens

The app **does not merge guides**. An external pipeline
(`paragliding_site_federation`) reconciles ParaglidingEarth with national guides
and publishes one row per physical launch, carrying every contributing guide's
id in a `source` list (`pge:4632;ansg:106-28`). The app consumes that snapshot.

So the app's merge duties are only these: pick each row's key, absorb the event
where two rows it already holds arrive as one, and let go of rows that vanish.
Everything else — which guide wins on name, coordinates, wind — is the
pipeline's call and the app must not second-guess it.

## The user need

A pilot's flight log exists nowhere else. The catalogue under it is refreshed
roughly monthly from sources nobody here controls. **A refresh must be a
non-event**: nothing the pilot owns moves, and no logged flight changes hill.

---

## Tier 1 — breaking these destroys data the pilot cannot get back

**R1. A refresh never changes which launch a logged flight is on.**
Import a new snapshot; every flight shows the same launch, name and
coordinates as before.
*Mechanism:* catalogue rows are keyed on a guide's own id (`provider:id`);
flown sites point at it through `sites.catalog_ref`.
*Falsified by:* any flight whose launch name or position differs across an
import that did not move that launch upstream.

**R2. Identity survives the producer renumbering, reordering or re-emitting.**
A CSV whose row ids all shift by one must be inert.
*Mechanism:* the CSV's own `id` column is not imported at all.
*Falsified by:* a key derived from row position, coordinates, or name.
Coordinates disqualify themselves twice — guides refine a takeoff by 20m
routinely, and ~23 launches share a location with another within ~14m.

**R3. A row the database already holds keeps the key it is stored under.**
A launch gaining a second guide's id — routine as federation grows — must not
be re-keyed by precedence.
*Mechanism:* held-key-first, then the producer's emitted `ref`, then derived.
*Falsified by:* any re-key, because a re-key is a delete plus an insert: the
favourite goes with the deleted row and every `catalog_ref` to it dangles
permanently, since the old key is never emitted again.

**R4. Favourites survive structurally, not by being copied out and back.**
*Mechanism:* `is_favorite` lives on the catalogue row and is never deleted;
on a merge the survivor inherits it and the flown site's link moves with it.
*Falsified by:* any read-all/delete-all/write-back cycle, or a merge where the
count of favourites drops.

**R5. The catalogue never overwrites the pilot's own site data.**
A renamed, moved or hand-created site keeps its name and position.
*Mechanism:* an import writes only `pge_sites`, plus `sites.catalog_ref` on a
merge. `custom_name` marks a site the pilot edited.
*Falsified by:* any write to `sites.name`/`latitude`/`longitude` on the import
path, or a re-match that moves a `custom_name` site.

**R6. Repairing old flights is previewed and confirmed, never automatic.**
*Mechanism:* `LaunchRematchService.preview()` / `.apply()`, gated on a real
improvement (100m) and offered from Data Management.
*Falsified by:* any path that rewrites `flights.launch_site_id` in bulk without
the pilot seeing what will move.

## Tier 2 — breaking these shows wrong information, recoverably

**R7. A launch disappearing from the snapshot degrades, it does not delete.**
The flown site and its flights stay; only catalogue extras (wind, altitude)
go blank, and they return by themselves if the guide restores the entry.
*Mechanism:* `sites.catalog_ref` is deliberately never cleared; the LEFT JOIN
simply finds nothing.
*Falsified by:* clearing the link, or deleting the flown site.

**R8. Importing the same snapshot twice changes nothing.**
Second import: zero inserted, zero deleted, favourites and links identical.
*Falsified by:* any counter moving on the second run.

**R9. A bad download cannot damage the working catalogue.**
Truncated body, HTML error page, or a snapshot missing columns leaves the
existing sites untouched.
*Mechanism:* validate required columns by name and plausible size before
writing; temp file plus atomic rename; import in one transaction.
*Falsified by:* validation keyed to a literal header prefix (this has failed
once already, the day the producer added a column), or a partial import.

**R10. Matching picks the genuinely nearest launch.**
The catalogue now resolves individual launches 180m–1km apart, so a flown site
must not capture its neighbours' takeoffs, and GPS scatter must not rename the
pilot's own site.
*Mechanism:* both local tiers are consulted and compared; the flown site wins
unless a catalogue launch is materially closer (100m).
*Falsified by:* a short-circuit that returns a flown site without asking the
catalogue.

## Tier 3 — freshness and control

**R11. The bundled snapshot works forever with no network,** and a new app
release actually imports the snapshot it ships. A non-empty table is not
evidence the catalogue is current.

**R12. Update checks never cost the pilot anything at a launch site.**
Cheap (HEAD), off the startup path, throttled on *last check* rather than last
download, every failure swallowed. Note the cadence mismatch: the pipeline
publishes weekly, the throttle is 30 days.

**R13. The pilot can see and force the state.** Last checked, last downloaded,
whether the copy on disk is the published or the bundled one, and a manual
refresh. "Checked yesterday, unchanged" and "not checked in a month" must not
look identical.

**R14. Every import is auditable after the fact.** One structured line: rows
inserted / updated / deleted / merged / skipped, favourites held, links left
dangling. A silent rewrite of the pilot's data cannot be checked later.

**R15. The import stays within its budget.** ~11.7k rows, batched, off the
startup path; map reads are bounding-box queries against an index.

---

## Questions worth putting to the code

- What happens to a flown site whose `catalog_ref` is absent this month and
  present again next month?
- Can two rows in one snapshot resolve to the same key? What does the unique
  index do, and is the outcome logged honestly rather than as two inserts?
- `CatalogRef.providerPrecedence` must not drift from the producer's
  `KEY_PRECEDENCE` — the assertion that they agree lives in the *other* repo.
  What in this repo notices if it lapses?
- Can a failed download or a failed preferences write be reported to the pilot
  as success, or a successful one as failure?
- Do the tests drive `importSitesData` itself, or a reimplementation of its SQL
  that can drift from it?
- Which of R1–R15 has a test that has been *seen to fail* without the fix?
