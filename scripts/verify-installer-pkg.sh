#!/bin/zsh
# Checks a LiveHime installer package before it is published: each build
# inside is the release app byte for byte with a valid signature, Installer
# picks the build by chip, installs into /Applications without relocating to
# another copy, asks to quit LiveHime first, removes only an earlier LiveHime
# and hands the installed app to the user (the in-app updater needs that).
# Usage: verify-installer-pkg.sh <pkg> <arm64 app> <x86_64 app>
set -uo pipefail

pkg=${1:A} arm=${2:A} intel=${3:A}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

expect() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then print -- "PASS  $name"; else print -- "FAIL  $name"; fails=$((fails + 1)); fi
}
archs_are() { [[ $(lipo -archs "$1/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$1/Contents/Info.plist")") == "$2" ]]; }

if ! pkgutil --expand "$pkg" "$work/x"; then print -- "FAIL  cannot expand $pkg"; exit 1; fi
dist="$work/x/Distribution"
expect "picks the build by chip" grep -q "hw.optional.arm64" "$dist"
expect "asks to quit LiveHime first" grep -q "<must-close>" "$dist"
expect "installs on the startup disk only" grep -q 'rootVolumeOnly="true"' "$dist"

for app arch in "$arm" arm64 "$intel" x86_64; do
  comp="$work/x/$arch.pkg"
  expect "$arch: installs into /Applications" grep -q 'install-location="/Applications"' "$comp/PackageInfo"
  expect "$arch: never relocated to another copy" grep -q 'relocatable="false"' "$comp/PackageInfo"
  expect "$arch: preinstall removes only LiveHime" grep -q 'CFBundleIdentifier' "$comp/Scripts/preinstall"
  expect "$arch: postinstall gives the app to the user" grep -q 'chown' "$comp/Scripts/postinstall"
  mkdir -p "$work/p-$arch"
  (cd "$work/p-$arch" && gunzip -c "$comp/Payload" | cpio -i --quiet) 2>/dev/null
  installed="$work/p-$arch/LiveHimeMacApp.app"
  expect "$arch: the release app byte for byte" diff -rq --no-dereference "$app" "$installed"
  expect "$arch: signature valid" codesign --verify --strict --deep "$installed"
  expect "$arch: built for $arch" archs_are "$installed" "$arch"
done

(( fails == 0 )) && print -- "installer package OK" || print -- "$fails check(s) failed"
exit $(( fails > 0 ))
