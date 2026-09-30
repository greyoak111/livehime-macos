#!/bin/zsh
# Checks a version's release notes before its release build: they exist, have
# something for the "What's new" dialog (a "## 新功能" or "## 修复" section),
# and the app bundles the same file (the fork's plugins/livehime/data/release-notes,
# which the dialog reads).
# Usage: check-release-notes.sh <version>
set -uo pipefail

version=${1#v}
root=${0:A:h:h}
notes="$root/docs/RELEASE_NOTES_v$version.md"
bundled="$root/obs-studio-clean/plugins/livehime/data/release-notes/RELEASE_NOTES_v$version.md"
fails=0

expect() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then print -- "PASS  $name"; else print -- "FAIL  $name"; fails=$((fails + 1)); fi
}

expect "docs/RELEASE_NOTES_v$version.md exists" test -f "$notes"
expect "has a 新功能 or 修复 section for the dialog" grep -qE '^## (新功能|修复)' "$notes"
expect "bundled in the app (plugins/livehime/data/release-notes)" test -f "$bundled"
expect "the bundled copy is the same file" cmp -s "$notes" "$bundled"

(( fails == 0 )) && print -- "release notes OK" || print -- "$fails check(s) failed"
exit $(( fails > 0 ))
