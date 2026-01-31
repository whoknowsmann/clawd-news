#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: format-summary.sh < release.json
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

extract_section_bullets() {
  local section_regex="$1"
  echo "$body" | awk -v section="$section_regex" '
    BEGIN { in_section = 0; IGNORECASE = 1 }
    /^#{1,6}[[:space:]]+/ {
      if (tolower($0) ~ section) {
        in_section = 1
        next
      } else if (in_section) {
        exit
      }
    }
    {
      if (in_section && $0 ~ /^[[:space:]]*([-*]|•)[[:space:]]+/) {
        sub(/^[[:space:]]*/, "")
        print
      }
    }
  '
}

extract_all_bullets() {
  echo "$body" | awk '
    /^[[:space:]]*([-*]|•)[[:space:]]+/ {
      sub(/^[[:space:]]*/, "")
      print
    }
  '
}

extract_breaking_bullets() {
  echo "$body" | awk '
    /^[[:space:]]*([-*]|•)[[:space:]]+/ {
      line=$0
      sub(/^[[:space:]]*/, "", line)
      lower=tolower(line)
      if (lower ~ /breaking/) {
        print line
      }
    }
  '
}

print_section() {
  local title="$1"
  local content="$2"
  if [ -n "$content" ]; then
    echo "### $title"
    echo "$content" | head -n 10
    echo
  fi
}

require_dep gh
require_dep jq
check_auth

input=$(cat)
[ -n "$input" ] || usage
jq -e . <<<"$input" >/dev/null || die "Invalid JSON input"

repo=$(jq -r '.repo // empty' <<<"$input")
tag=$(jq -r '.tagName // .tag // empty' <<<"$input")
name=$(jq -r '.name // empty' <<<"$input")
published_at=$(jq -r '.publishedAt // empty' <<<"$input")
url=$(jq -r '.url // empty' <<<"$input")
body=$(jq -r '.body // ""' <<<"$input")

[ -n "$repo" ] || die "Missing repo in input JSON"
[ -n "$tag" ] || die "Missing tagName in input JSON"
[ -n "$name" ] || die "Missing name in input JSON"
[ -n "$published_at" ] || die "Missing publishedAt in input JSON"
[ -n "$url" ] || die "Missing url in input JSON"

formatted_date=$(date -u -d "$published_at" +"%b %d, %Y" 2>/dev/null || echo "$published_at")

breaking_bullets=$(extract_breaking_bullets)

highlight_bullets=$(extract_section_bullets "highlights|changes")
if [ -z "$highlight_bullets" ]; then
  highlight_bullets=$(extract_all_bullets)
fi

fixes_bullets=$(extract_section_bullets "fixes")
fix_related_count=0
if [ -z "$fixes_bullets" ]; then
  fix_related_count=$(extract_all_bullets | awk '
    {
      lower=tolower($0)
      if (lower ~ /(fix|bug|crash|resolve)/) { count++ }
    }
    END { print count + 0 }
  ')
fi

echo "## 📰 $repo — $tag ($formatted_date)"
echo "**$name**"
echo

print_section "⚠️ Breaking Changes" "$breaking_bullets"
print_section "✨ Highlights" "$highlight_bullets"

if [ -n "$fixes_bullets" ]; then
  print_section "🐛 Fixes" "$fixes_bullets"
elif [ "$fix_related_count" -gt 0 ]; then
  echo "### 🐛 Fixes"
  echo "Fix-related items: $fix_related_count (approx)"
  echo
fi

echo "[Full changelog]($url)"
echo
printf '%s\n' "---"
