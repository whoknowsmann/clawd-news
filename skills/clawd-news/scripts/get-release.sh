#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
state_file_default="$script_dir/../state/last-seen.json"

usage() {
  cat >&2 <<'USAGE'
Usage: get-release.sh --repo owner/name [--include-prereleases] [--state-file path] <latest|tag>
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

include_prereleases=false
state_file="$state_file_default"
repo=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || die "--repo requires a value"
      repo="$2"
      shift 2
      ;;
    --include-prereleases)
      include_prereleases=true
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
    --*)
      die "Unknown argument: $1"
      ;;
    *)
      break
      ;;
  esac
done

[ -n "$repo" ] || die "--repo is required"
[ "$#" -ge 1 ] || die "Release tag or 'latest' is required"

require_dep gh
require_dep jq
check_auth

requested_tag="$1"

if [ "$requested_tag" = "latest" ]; then
  releases_json=$(gh release list --repo "$repo" --json tagName,name,publishedAt,url,isPrerelease --limit 20)
  jq -e . <<<"$releases_json" >/dev/null || die "Invalid JSON from gh release list for $repo"
  if [ "$include_prereleases" = true ]; then
    requested_tag=$(jq -r '.[0].tagName // empty' <<<"$releases_json")
  else
    requested_tag=$(jq -r '[.[] | select(.isPrerelease == false)] | .[0].tagName // empty' <<<"$releases_json")
  fi
  [ -n "$requested_tag" ] || die "No release found for $repo"
fi

release_json=$(gh release view "$requested_tag" --repo "$repo" --json tagName,name,publishedAt,url,body,isPrerelease)
jq -e . <<<"$release_json" >/dev/null || die "Invalid JSON from gh release view for $repo"

output=$(jq --arg repo "$repo" '. + {repo:$repo}' <<<"$release_json")
jq -e . <<<"$output" >/dev/null || die "Output JSON validation failed"

printf '%s\n' "$output"
