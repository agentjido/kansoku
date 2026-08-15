#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

mkdir -p "$workspace/scripts"
cp "$repo_root/mix.exs" "$workspace/mix.exs"
cp "$repo_root/.tool-versions" "$workspace/.tool-versions"
cp "$repo_root/README.md" "$workspace/README.md"
cp "$repo_root/CHANGELOG.md" "$workspace/CHANGELOG.md"
cp "$repo_root/scripts/kansoku_release_prep.exs" "$workspace/scripts/"

awk '
  { print }
  $0 == "## Unreleased" {
    print ""
    print "- Add release prep regression coverage."
  }
' "$workspace/CHANGELOG.md" > "$workspace/CHANGELOG.md.tmp"
mv "$workspace/CHANGELOG.md.tmp" "$workspace/CHANGELOG.md"

cd "$workspace"

elixir scripts/kansoku_release_prep.exs 9.8.7 \
  --date 2026-07-12 \
  --notes-file "$workspace/release-notes.md"

grep -Fq 'version: "9.8.7"' mix.exs
grep -Fq '{:kansoku, "~> 9.8.7"}' README.md
grep -Fq '## Unreleased' CHANGELOG.md
grep -Fq '## 9.8.7 - 2026-07-12' CHANGELOG.md
grep -Fq '## Changes' release-notes.md

elixir scripts/kansoku_release_prep.exs 9.8.7 \
  --notes-only \
  --notes-file "$workspace/recovered-release-notes.md"

cmp release-notes.md recovered-release-notes.md

if elixir scripts/kansoku_release_prep.exs v9.8.8 >/dev/null 2>&1; then
  echo "release prep unexpectedly accepted a leading-v version" >&2
  exit 1
fi

if elixir scripts/kansoku_release_prep.exs 9.8.7 >/dev/null 2>&1; then
  echo "release prep unexpectedly accepted the current version" >&2
  exit 1
fi
