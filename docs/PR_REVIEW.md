# Pull request review

The `PR Review` workflow posts one advisory review comment on a pull request. It does
not use Claude Code. It sends the PR title, body, and diff to an OpenAI-compatible chat
completions endpoint, then writes the answer as a comment.

The workflow is `.github/workflows/pr-review.yml`. The script is
`scripts/pr_review.mjs`.

## Setup

Set two repository variables and one secret under Settings -> Secrets and variables ->
Actions.

| Name | Kind | Meaning |
|---|---|---|
| `REVIEW_API_URL` | Variable | Full chat completions URL |
| `REVIEW_MODEL` | Variable | Provider model id |
| `REVIEW_API_KEY` | Secret | Provider API key |
| `REVIEW_MAX_DIFF` | Variable, optional | Diff character cap. Default 60000, range 10000-200000 |

This repository uses DeepSeek. The active variables are
`https://api.deepseek.com/chat/completions` and `deepseek-chat`.

Examples:

| Provider | `REVIEW_API_URL` | `REVIEW_MODEL` |
|---|---|---|
| DeepSeek | `https://api.deepseek.com/chat/completions` | `deepseek-chat` |
| OpenRouter | `https://openrouter.ai/api/v1/chat/completions` | `deepseek/deepseek-v4.1-flash` |

The URL must be the full chat completions endpoint. The script does not append a path.

If `REVIEW_API_URL` or `REVIEW_MODEL` is absent, the job prints a notice and exits 0. No
review runs.

## When it runs

- A PR is opened.
- A draft PR is marked ready for review.
- A PR is reopened.
- The `ai-review` label is added.

It does not run on every push. To re-run after a change, remove the `ai-review` label
and add it again.

Draft PRs and fork PRs are skipped. A fork PR has no access to repository secrets.

## What it does

1. Reads the PR title, body, and diff with `gh`.
2. Removes lockfiles, generated files, builds, images, local data, and secret files
   (`env.json`, `key.properties`).
3. Caps the diff and says when it truncated.
4. Reads `AGENTS.md` for project rules.
5. Calls the endpoint with a fixed review prompt.
6. Posts one comment with the marker `<!-- generic-ai-review -->`. A later run updates
   that comment instead of adding another.
7. Prints the prompt and completion token counts.

The prompt treats the diff as untrusted data. The model has no tools and cannot run
commands.

## Safety

- The check is advisory. Do not add it to the required checks. A provider outage must
  not block a merge.
- The diff leaves GitHub and goes to the provider. Use a provider and data policy that
  fit the repository.
- The script sends no secrets. It reads `AGENTS.md` and the PR diff only.
- The script requires an `https://` URL. It refuses a plaintext endpoint.
- The API key is a repository secret and is masked in logs.
- The review comment is public to everyone who can read the PR.

## Cost

The largest cost is the diff. A 60,000 character cap is about 15,000 tokens on input.
The output cap is 1,800 tokens. A label trigger, not a push trigger, keeps the number of
runs low.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `PR review is not configured` | A variable or secret is missing | Set all three values |
| `review API returned 401` | Bad key | Replace `REVIEW_API_KEY` |
| `review API returned 404` | Wrong URL | Use the full chat completions URL |
| `review API returned no review text` | The provider returned an empty choice | Check the model id and the provider status |
| No comment appears | `pull-requests: write` or `issues: write` is missing | Restore both permissions in the workflow |
| The review is stale | The workflow does not run on push | Remove and re-add the `ai-review` label |
