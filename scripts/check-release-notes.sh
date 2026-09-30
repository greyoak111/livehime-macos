#!/bin/zsh
# Checks a version's release notes before its release build: they exist, have
# something for the "What's new" dialog (a "## 新功能" or "## 修复" section),
# and the app bundles them (the fork's plugins/livehime/data/release-notes,
# which the dialog reads) with the same sections the dialog shows (新功能, 修复,
# 升级). Validation and source may be filled in after the build.
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
# The sections the dialog shows, as ReleaseNotes.swift picks them.
shown() {
  python3 - "$1" <<'PY'
import sys
keep, out = False, []
for line in open(sys.argv[1], encoding="utf-8").read().split("\n"):
    if line.startswith("## "):
        keep = any(line[3:].strip().startswith(t) for t in ("新功能", "修复", "升级"))
    elif line.startswith("# "):
        keep = False
    if keep:
        out.append(line)
print("\n".join(out).strip())
PY
}

expect "docs/RELEASE_NOTES_v$version.md exists" test -f "$notes"
expect "has a 新功能 or 修复 section for the dialog" grep -qE '^## (新功能|修复)' "$notes"
expect "bundled in the app (plugins/livehime/data/release-notes)" test -f "$bundled"
expect "the bundled copy shows the same sections" test "$(shown "$notes" 2>/dev/null)" = "$(shown "$bundled" 2>/dev/null)"

(( fails == 0 )) && print -- "release notes OK" || print -- "$fails check(s) failed"
exit $(( fails > 0 ))
