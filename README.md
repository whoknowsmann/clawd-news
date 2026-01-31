# clawd-news

Track GitHub release news for Clawdbot/OpenClaw-related repos and output clean summaries. Use this repository to monitor one or more GitHub repositories for new releases, fetch release details, format markdown summaries, and mark releases as seen.

## Overview

Monitor GitHub releases across multiple repos, summarize new releases, and persist last-seen state with safe, atomic JSON writes.

## Configuration

- Pass one or more `--repo owner/name` flags.
- If no `--repo` flags are provided, read `CLAWD_NEWS_REPOS` (comma-separated).
- If neither is set, default to `clawdbot/clawdbot`.
- Include prereleases by passing `--include-prereleases`.
- Override the state file path with `--state-file <path>` (defaults to `state/last-seen.json`).

## Script usage

- `skills/clawd-news/scripts/check-releases.sh` → check configured repos for new releases.
- `skills/clawd-news/scripts/get-release.sh` → fetch full release details for a tag or `latest`.
- `skills/clawd-news/scripts/format-summary.sh` → read release JSON from stdin and output markdown.
- `skills/clawd-news/scripts/mark-seen.sh` → mark a release as seen.

### Manual usage examples

```bash
skills/clawd-news/scripts/check-releases.sh | jq
skills/clawd-news/scripts/check-releases.sh --repo clawdbot/clawdbot --repo openclaw/openclaw | jq
skills/clawd-news/scripts/get-release.sh --repo clawdbot/clawdbot latest | skills/clawd-news/scripts/format-summary.sh
skills/clawd-news/scripts/get-release.sh --repo clawdbot/clawdbot latest | skills/clawd-news/scripts/mark-seen.sh --from-json | jq
```

## State management

- State lives at `skills/clawd-news/state/last-seen.json` unless overridden with `--state-file`.
- Validate JSON before reading or writing with `jq -e .`.
- Write state atomically (write temp file, validate JSON, then `mv`).
- `check-releases.sh` updates only `lastCheck`.
- `mark-seen.sh` updates the per-repo `lastReleaseTag`, `lastReleasePublishedAt`, and `lastCheck`.
- Treat missing state files as empty defaults.

## Example agent workflow

1. Run `skills/clawd-news/scripts/check-releases.sh` to detect new releases.
2. For each new release, call `skills/clawd-news/scripts/get-release.sh --repo <owner/name> <tag>`.
3. Pipe the result to `skills/clawd-news/scripts/format-summary.sh` for a markdown summary.
4. After posting the summary, call `skills/clawd-news/scripts/mark-seen.sh --from-json` to update state.
