#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
state_file_default="$script_dir/../state/last-seen.json"

usage() {
  cat >&2 <<'USAGE'
Usage: check-releases.sh [--repo owner/name] [--include-prereleases] [--state-file path]
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

to_json_array() {
  if [ "$#" -eq 0 ]; then
    echo '[]'
    return
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
}

include_prereleases=false
state_file="$state_file_default"
repos=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || die "--repo requires a value"
      repos+=("$2")
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
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [ "${#repos[@]}" -eq 0 ] && [ -n "${CLAWD_NEWS_REPOS:-}" ]; then
  IFS=',' read -r -a env_repos <<<"$CLAWD_NEWS_REPOS"
  for entry in "${env_repos[@]}"; do
    repo_trimmed=$(echo "$entry" | xargs)
    if [ -n "$repo_trimmed" ]; then
      repos+=("$repo_trimmed")
    fi
  done
fi

if [ "${#repos[@]}" -eq 0 ]; then
  repos=("clawdbot/clawdbot")
fi

require_dep gh
require_dep jq
check_auth

state_json='{"lastSeenByRepo":{},"lastCheck":null}'
if [ -f "$state_file" ]; then
  jq -e . "$state_file" >/dev/null || die "Invalid JSON in state file: $state_file"
  state_json=$(cat "$state_file")
fi
jq -e . <<<"$state_json" >/dev/null || die "Invalid state JSON"

new_releases=()
repos_checked=()

for repo in "${repos[@]}"; do
  repos_checked+=("$repo")
  releases_json=$(gh release list --repo "$repo" --json tagName,name,publishedAt,isPrerelease --limit 20)
  jq -e . <<<"$releases_json" >/dev/null || die "Invalid JSON from gh release list for $repo"

  if [ "$include_prereleases" = true ]; then
    latest_release=$(jq -c '.[0] // empty' <<<"$releases_json")
  else
    latest_release=$(jq -c '[.[] | select(.isPrerelease == false)] | .[0] // empty' <<<"$releases_json")
  fi

  if [ -z "$latest_release" ] || [ "$latest_release" = "null" ]; then
    continue
  fi

  tag=$(jq -r '.tagName' <<<"$latest_release")
  name=$(jq -r '.name' <<<"$latest_release")
  published_at=$(jq -r '.publishedAt' <<<"$latest_release")
  url="https://github.com/$repo/releases/tag/$tag"

  last_seen_published=$(jq -r --arg repo "$repo" '.lastSeenByRepo[$repo].lastReleasePublishedAt // empty' <<<"$state_json")

  if [ -z "$last_seen_published" ] || [[ "$published_at" > "$last_seen_published" ]]; then
    release_obj=$(jq -n \
      --arg repo "$repo" \
      --arg tag "$tag" \
      --arg name "$name" \
      --arg publishedAt "$published_at" \
      --arg url "$url" \
      '{repo:$repo,tag:$tag,name:$name,publishedAt:$publishedAt,url:$url}')
    new_releases+=("$release_obj")
  fi
done

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
updated_state=$(jq --arg lastCheck "$now" '.lastCheck = $lastCheck' <<<"$state_json")

mkdir -p "$(dirname "$state_file")"
state_tmp=$(mktemp)
printf '%s' "$updated_state" >"$state_tmp"
jq -e . "$state_tmp" >/dev/null || die "Invalid JSON when writing state"
mv "$state_tmp" "$state_file"

repos_checked_json=$(to_json_array "${repos_checked[@]}")
if [ "${#new_releases[@]}" -eq 0 ]; then
  new_releases_json='[]'
  status="up_to_date"
else
  new_releases_json=$(printf '%s\n' "${new_releases[@]}" | jq -s '.')
  status="new_release"
fi

output=$(jq -n \
  --arg status "$status" \
  --arg lastCheck "$now" \
  --argjson reposChecked "$repos_checked_json" \
  --argjson newReleases "$new_releases_json" \
  '{status:$status,reposChecked:$reposChecked,newReleases:$newReleases,lastCheck:$lastCheck}')

jq -e . <<<"$output" >/dev/null || die "Output JSON validation failed"
printf '%s\n' "$output"
