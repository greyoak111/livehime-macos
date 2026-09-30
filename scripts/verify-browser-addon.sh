#!/bin/zsh
# Checks a browser add-on zip before it is published: it unpacks to one
# obs-browser.plugin with CEF and the four helper apps inside, its manifest
# matches the file name and the OBS base of the app it is for, every binary is
# built for the right architecture, the plugin loads CEF from its own bundle and
# the app's libobs, nothing points into a build folder, only the kept CEF
# locales are there, CEF's license is included, and it is signed by the same
# certificate as the app.
# Usage: verify-browser-addon.sh <LiveHime-BrowserAddon-v<version>-<arch>.zip> <LiveHime.app of that arch>
set -uo pipefail

zip=${1:A} app=${2:A}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

expect() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then print -- "PASS  $name"; else print -- "FAIL  $name"; fails=$((fails + 1)); fi
}
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$manifest" "$1"; }
archs_are() { [[ $(lipo -archs "$1") == "$2" ]]; }
leaf() { (cd "$work" && rm -f codesign0 && codesign -d --extract-certificates "$1" 2>/dev/null && shasum -a 256 codesign0 | cut -d' ' -f1); }

name=${zip:t}
[[ $name =~ '^LiveHime-BrowserAddon-v([0-9]+\.[0-9]+\.[0-9]+)-(arm64|x86_64)\.zip$' ]] || {
  print -- "FAIL  file name is not LiveHime-BrowserAddon-v<version>-<arch>.zip"; exit 1; }
version=$match[1] arch=$match[2]

ditto -x -k "$zip" "$work/x" || { print -- "FAIL  cannot unpack $zip"; exit 1; }
expect "unpacks to exactly obs-browser.plugin" test "$(ls "$work/x")" = "obs-browser.plugin"
plugin="$work/x/obs-browser.plugin"
frameworks="$plugin/Contents/Frameworks"
cef="$frameworks/Chromium Embedded Framework.framework"
manifest="$plugin/Contents/Resources/addon.json"
binary="$plugin/Contents/MacOS/obs-browser"

expect "has a manifest" test -f "$manifest"
expect "manifest id is browser-source" test "$(field id)" = "browser-source"
expect "manifest version matches the file name ($version)" test "$(field version)" = "$version"
expect "manifest architecture matches the file name ($arch)" test "$(field arch)" = "$arch"
app_obs=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Frameworks/libobs.framework/Resources/Info.plist" 2>/dev/null)
expect "built for the app's OBS base (${app_obs%.*})" test "$(field obs)" = "${app_obs%.*}"

expect "carries CEF" test -f "$cef/Chromium Embedded Framework"
for helper in "OBS Helper" "OBS Helper (GPU)" "OBS Helper (Plugin)" "OBS Helper (Renderer)"; do
  expect "carries $helper" test -x "$frameworks/$helper.app/Contents/MacOS/$helper"
  expect "$helper is $arch" archs_are "$frameworks/$helper.app/Contents/MacOS/$helper" "$arch"
done
expect "plugin is $arch" archs_are "$binary" "$arch"
expect "CEF is $arch" archs_are "$cef/Chromium Embedded Framework" "$arch"
expect "app is $arch" archs_are "$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")" "$arch"

expect "plugin loads CEF from its own bundle" grep -q "Loading CEF from the plugin bundle" "$binary"
expect "plugin uses the app's libobs" sh -c "otool -L '$binary' | grep -q '@rpath/libobs.framework'"
expect "plugin looks in the app's Frameworks" sh -c "otool -l '$binary' | grep -A2 LC_RPATH | grep -q '@executable_path/../Frameworks'"
expect "no path into a build folder" sh -c "! otool -l '$binary' '$frameworks'/OBS\\ Helper*.app/Contents/MacOS/* | grep -A2 LC_RPATH | grep -q ' /'"
locales=("$cef"/Resources/*.lproj(N:t))
expect "only en, zh_CN, zh_TW locales" test "${(o)locales}" = "en.lproj zh_CN.lproj zh_TW.lproj"

expect "carries CEF's license" test -s "$plugin/Contents/Resources/LICENSE-CEF.txt"
expect "signature valid" codesign --verify --deep --strict "$plugin"
expect "signed by the app's certificate" test "$(leaf "$plugin")" = "$(leaf "$app")"

print -- "size $(( $(stat -f %z "$zip") / 1048576 )) MB, unpacked $(du -sh "$plugin" | cut -f1)"
(( fails == 0 )) && print -- "browser add-on OK" || print -- "$fails check(s) failed"
exit $(( fails > 0 ))
