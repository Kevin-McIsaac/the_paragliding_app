# Contributing

[AGENTS.md](AGENTS.md) is the source of truth for project rules. This page is the short
entry point for a human contributor.

## Setup

1. Use DSH for agent work. See [docs/DSH.md](docs/DSH.md).
2. Run `bin/setup_worktree.sh` in every new worktree.
3. Install dependencies: `cd the_paragliding_app && flutter pub get`.

## Checks

Run these from `the_paragliding_app/`:

```sh
flutter analyze
flutter test
```

Run the user manual sync check from the repository root:

```sh
bin/sync_user_manual.sh --check
```

Run `dart format` on the files you change. The repository is not fully formatted yet,
so a whole-tree format check is not part of CI.

## Pull requests

- Branch from `origin/main`. Use a worktree for agent work.
- Keep one feature or fix per pull request.
- Add the evidence: test output, a screenshot, or a log excerpt.
- Describe any database change and its `_onUpgrade` branch.

## Never commit

- `dev_data/` (real flight data and local app state)
- `env.json` (API keys)
- `upload-keystore*.jks` and `upload-cert*.pem`
- `.dsh/` (DSH local state)
