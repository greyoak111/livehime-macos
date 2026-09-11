#!/bin/zsh
set -euo pipefail

# Replace an installed LiveHime bundle without touching its user data.  The
# Keychain item and WebKit data are keyed by the stable bundle identity, so a
# bundle replacement is sufficient for 0.1.0 -> 0.1.1 and later upgrades.
candidate_arg="${1:-}"
target_arg="${2:-/Applications/LiveHimeMacApp.app}"
if [[ -z "$candidate_arg" ]]; then
  print -u2 -- "usage: $0 /path/to/LiveHimeMacApp.app [target.app]"
  exit 64
fi

if [[ ! -d "$candidate_arg/Contents" || ! -f "$candidate_arg/Contents/Info.plist" ]]; then
  print -u2 -- "candidate is not a macOS app bundle: $candidate_arg"
  exit 65
fi

candidate="${candidate_arg:A}"
target="${target_arg:A}"
candidate_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist" 2>/dev/null || true)
candidate_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$candidate/Contents/Info.plist" 2>/dev/null || true)
if [[ "$candidate_id" != "local.livehime.macos" ]]; then
  print -u2 -- "refusing bundle identity $candidate_id; expected local.livehime.macos"
  exit 66
fi
if [[ -z "$candidate_version" ]]; then
  print -u2 -- "candidate has no CFBundleShortVersionString"
  exit 66
fi

if [[ -d "$target" ]]; then
  target_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$target_id" != "local.livehime.macos" ]]; then
    print -u2 -- "refusing to replace a different app at $target (bundle id: ${target_id:-unknown})"
    exit 67
  fi
  # Replacing a mapped bundle while it or its nested OBS backend is alive can
  # invalidate TCC decisions and leave a half-updated process. Ask the user to
  # stop cleanly instead of killing unrelated processes.
  if pgrep -f "^$target/Contents/MacOS/LiveHimeMacApp$" >/dev/null 2>&1 || \
     pgrep -f "^$target/Contents/Resources/OBS.app/Contents/MacOS/OBS$" >/dev/null 2>&1; then
    print -u2 -- "quit LiveHime and its bundled OBS before installing $candidate_version"
    exit 68
  fi
fi

parent=${target:h}
mkdir -p "$parent"
stage=$(mktemp -d "$parent/.livehime-install.XXXXXX")
backup="$stage/previous.app"
cleanup() {
  # The temporary directory is created by this invocation and contains only
  # the staged candidate/rollback copy.
  [[ -d "$stage" ]] && rm -rf "$stage"
}
trap cleanup EXIT INT TERM

ditto "$candidate" "$stage/LiveHimeMacApp.app"
if command -v codesign >/dev/null 2>&1; then
  codesign --verify --deep --strict "$stage/LiveHimeMacApp.app"
fi

if [[ -d "$target" ]]; then
  mv "$target" "$backup"
fi
if ! mv "$stage/LiveHimeMacApp.app" "$target"; then
  if [[ -d "$backup" && ! -e "$target" ]]; then
    mv "$backup" "$target"
  fi
  print -u2 -- "installation failed; the previous bundle was restored when possible"
  exit 69
fi

print -- "installed LiveHime macOS $candidate_version at $target"
print -- "Keychain and WebKit data were preserved because the bundle identity remains local.livehime.macos"
