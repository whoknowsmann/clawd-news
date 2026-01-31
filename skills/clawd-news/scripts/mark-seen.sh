#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
state_file_default="$script_dir/../state/last-seen.json"

usage() {
  cat >&2 <<'USAGE'
Usage:
  mark-seen.sh --repo owner/name --tag vX.Y.Z --published-at 2026-01-30T05:26:50Z
  mark-seen.sh --from-json
USAGE
}

die() {
  echo "$1" >&2
  exit 1
}

require_dep() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

check_auth() {
  gh auth status >/dev/null 2>&1 || die "gh auth status failed; run 'gh auth login'"
}

state_file="$state_file_default"
from_json=false
repo=""
tag=""
published_at=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || die "--repo requires a value"
      repo="$2"
      shift 2
      ;;
    --tag)
      [ "$#" -ge 2 ] || die "--tag requires a value"
      tag="$2"
      shift 2
      ;;
    --published-at)
      [ "$#" -ge 2 ] || die "--published-at requires a value"
      published_at="$2"
      shift 2
      ;;
    --from-json)
      from_json=true
      shift
      ;;
    --state-file)
      [ "$#" -ge 2 ] || die "--state-file requires a value"
      state_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

require_dep gh
require_dep jq
check_auth

if [ "$from_json" = true ]; then
  input=$(cat)
  [ -n "$input" ] || die "Expected JSON on stdin"
  jq -e . <<<"$input" >/dev/null || die "Invalid JSON input"
  repo=$(jq -r '.repo // empty' <<<"$input")
  tag=$(jq -r '.tagName // .tag // empty' <<<"$input")
  published_at=$(jq -r '.publishedAt // empty' <<<"$input")
fi

[ -n "$repo" ] || die "Missing repo"
[ -n "$tag" ] || die "Missing tag"
[ -n "$published_at" ] || die "Missing publishedAt"

state_json='{"lastSeenByRepo":{},"lastCheck":null}'
if [ -f "$state_file" ]; then
  jq -e . "$state_file" >/dev/null || die "Invalid JSON in state file: $state_file"
  state_json=$(cat "$state_file")
fi
jq -e . <<<"$state_json" >/dev/null || die "Invalid state JSON"

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
updated_state=$(jq \
  --arg repo "$repo" \
  --arg tag "$tag" \
  --arg publishedAt "$published_at" \
  --arg lastCheck "$now" \
  '.lastSeenByRepo[$repo] = {lastReleaseTag:$tag,lastReleasePublishedAt:$publishedAt} | .lastCheck = $lastCheck' \
  <<<"$state_json")

mkdir -p "$(dirname "$state_file")"
state_tmp=$(mktemp)
printf '%s' "$updated_state" >"$state_tmp"
jq -e . "$state_tmp" >/dev/null || die "Invalid JSON when writing state"
mv "$state_tmp" "$state_file"

output=$(jq -n \
  --arg repo "$repo" \
  --arg tag "$tag" \
  --arg publishedAt "$published_at" \
  '{status:"ok",repo:$repo,markedTag:$tag,markedPublishedAt:$publishedAt}')

jq -e . <<<"$output" >/dev/null || die "Output JSON validation failed"

printf '%s\n' "$output"
