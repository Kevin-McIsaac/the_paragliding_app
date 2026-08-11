---
name: release
description: Cut and publish a release of this app to the Google Play internal track. Use when asked to create, cut or make a release, to ship or publish the app, to bump the version or versionCode, to write the release notes users see, or to push a release tag - and when asked whether a release actually shipped. Covers choosing the version numbers, writing distribution/whatsnew/whatsnew-en-GB, tagging, and checking the run really published.
---

# Releasing this app

`GOOGLE_PLAY_DEPLOYMENT.md` (repo root) is the **reference**: CI job structure, secrets,
signing, the troubleshooting table. This skill is the **sequence and the decisions**. When
something fails, go to the troubleshooting table there rather than guessing.

Pushing a `v*` tag builds a signed APK and AAB, verifies both, publishes the AAB to the Play
**internal** track, and attaches the APK to a GitHub Release.

## Mind the two working directories

`pubspec.yaml` is under `the_paragliding_app/`; the release notes are repo-root-relative.
All commands below are from the **repo root**.

| | path |
|---|---|
| version | `the_paragliding_app/pubspec.yaml` |
| release notes | `distribution/whatsnew/whatsnew-en-GB` |

## 1. Read the range first

```bash
git fetch --tags
LAST=$(git tag -l 'v*' | sort -V | tail -1)   # e.g. v1.0.7+19
git log --oneline "$LAST"..origin/main
```

Classify every commit **user-visible** or **dev-only** before touching a number. Dev-only
means tooling, CI, docs, test infrastructure, worktree lore - anything a pilot using the app
cannot observe. That split drives both the version name and the notes.

## 2. Choose the numbers

`pubspec.yaml` holds both, as `version: <name>+<code>`.

- **`versionCode`** (the `+N`) - always the previous one plus 1. Play never allows a reuse,
  and CI refuses a tag whose code is not strictly greater than every existing `v*` tag.
- **`versionName`** - bump the patch digit whenever the range contains user-visible change,
  which it nearly always does. Builds 5 through 11 all shipped as `1.0.2`, and users could
  not tell a months-old build from a current one. A dev-only range may keep the name and
  bump only the code.

## 3. Write the notes users see

Rewrite `distribution/whatsnew/whatsnew-en-GB` wholesale - it holds the *previous* release's
notes, and a stale file passes every CI check.

- Group by **what a pilot notices**, not by PR. Several PRs usually collapse into one bullet.
- Dev-only commits never appear.
- Say what changed *for them*. 1.0.4 lowered every user's total hours by ~11% by measuring
  takeoff-to-landing; shipped without explanation that reads as data loss, not a correction.
- Bullets are `•` (U+2022), wrapped by hand, matching the existing file.

**Hard limit 500 characters**, counted the way CI counts it:

```bash
LC_ALL=C.UTF-8 wc -m distribution/whatsnew/whatsnew-en-GB   # must be <= 500
```

`-m`, not `-c`: the bullets are multi-byte and `-c` overcounts.

## 4. Get it onto main

Both files go through a normal PR - branch, `flutter analyze`, `flutter test`, review, squash
merge. Past release commits are titled `Release 1.0.7+19 (#326)` and say in the body **why**
that version name was chosen. CI refuses to release from a commit that is not an ancestor of
`main`, so there is no tag-a-branch shortcut.

## 5. Tag - this is the moment of no return

**Ask the user before pushing the tag.** The `play-internal` environment has no protection
rules: the push publishes to the internal track with no human checkpoint, and a `versionCode`
that reaches Play is burned whether or not the release was any good.

```bash
git switch main && git pull
git tag -a v1.0.8+20 -m "Release 1.0.8+20" && git push origin v1.0.8+20
```

Four checks run in seconds before the ~15 minute build: tag matches pubspec, versionCode
exceeds every existing tag, notes exist and fit, tagged commit is an ancestor of `main`.
`flutter analyze` and the full suite run alongside them.

## 6. Verify it shipped - check the step, not the run

```bash
gh run watch   # pick the run for the tag; do not hand-roll a poll loop
```

Then, in this order:

- **A `cancelled` or `failed` run may still have published.** Check the *Publish to Play
  internal track* step's own conclusion, not the run's. A cancel landing after the upload
  stops later jobs while the publish already went through - that is how versionCode 13 was
  burned, and re-tagging on the assumption it failed burns another.

  ```bash
  gh run view <run-id> --json jobs \
    -q '.jobs[].steps[] | select(.name|test("Play")) | "\(.name): \(.conclusion)"'
  ```

- Confirm the GitHub Release exists with the APK attached: `gh release view v1.0.8+20`.
- Optionally check provenance on the downloaded APK:
  `gh attestation verify app-release.apk --repo Kevin-McIsaac/the_paragliding_app`.
- Internal testers see it within minutes; there is no review delay.

**Promotion to production is manual** in Play Console, deliberately outside CI. Do not
promote without being asked.

## Testing pipeline changes without publishing

```bash
gh workflow run build.yml --ref my-branch
```

Same tests, build, verification and attestation; no publish. It does **not** exercise the
four tag-only checks, the Play upload or the GitHub release - those first run for real on the
next tag.
