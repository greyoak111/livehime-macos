#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
package_dir=${script_dir:h}
cd "$package_dir"
swift build -c release --product LiveHimeMacApp
app="$package_dir/dist/LiveHimeMacApp.app"
# Do not rewrite a mapped executable or its signature while macOS is using
# that bundle for privacy decisions. Build may finish, packaging must wait.
if pgrep -f "^$app/Contents/MacOS/LiveHimeMacApp" >/dev/null; then
  print -u2 -- 'Quit LiveHime before updating its bundle.'
  exit 1
fi
if [[ "${LIVEHIME_UPDATE_HOST_ONLY:-0}" != "1" ]] && pgrep -f "^$app/Contents/Resources/OBS.app/Contents/MacOS/OBS" >/dev/null; then
  print -u2 -- 'Quit the bundled OBS before replacing its runtime.'
  exit 1
fi
set_privacy_strings() {
  local info="$1"
  /usr/libexec/PlistBuddy -c 'Set :NSCameraUsageDescription LiveHime uses the camera as an OBS capture source.' "$info" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :NSCameraUsageDescription string LiveHime uses the camera as an OBS capture source.' "$info"
  /usr/libexec/PlistBuddy -c 'Set :NSMicrophoneUsageDescription LiveHime uses the microphone as an OBS audio source.' "$info" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :NSMicrophoneUsageDescription string LiveHime uses the microphone as an OBS audio source.' "$info"
  /usr/libexec/PlistBuddy -c 'Set :NSScreenCaptureUsageDescription LiveHime uses screen capture as an OBS video source.' "$info" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :NSScreenCaptureUsageDescription string LiveHime uses screen capture as an OBS video source.' "$info"
  /usr/libexec/PlistBuddy -c 'Set :NSAudioCaptureUsageDescription LiveHime uses system audio as an OBS source.' "$info" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :NSAudioCaptureUsageDescription string LiveHime uses system audio as an OBS source.' "$info"
}
if [[ "${LIVEHIME_UPDATE_HOST_ONLY:-0}" == "1" ]]; then
  # Keep the running OBS runtime and its signature unchanged when only the
  # native host changed. Quit LiveHime before using this mode.
  [[ -f "$app/Contents/Info.plist" && -d "$app/Contents/Resources/OBS.app" ]]
  cp ".build/arm64-apple-macosx/release/LiveHimeMacApp" "$app/Contents/MacOS/LiveHimeMacApp"
  set_privacy_strings "$app/Contents/Info.plist"
  python3 "$script_dir/local-signing.py" --sign "$app"
  printf '%s\n' "$app"
  exit 0
fi
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp ".build/arm64-apple-macosx/release/LiveHimeMacApp" "$app/Contents/MacOS/LiveHimeMacApp"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>LiveHimeMacApp</string>
  <key>CFBundleIdentifier</key><string>local.livehime.macos</string>
  <key>CFBundleName</key><string>LiveHime macOS</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key><string>LiveHime uses the camera as an OBS capture source.</string>
  <key>NSMicrophoneUsageDescription</key><string>LiveHime uses the microphone as an OBS audio source.</string>
  <key>NSScreenCaptureUsageDescription</key><string>LiveHime uses screen capture as an OBS video source.</string>
  <key>NSAudioCaptureUsageDescription</key><string>LiveHime uses system audio as an OBS source.</string>
</dict></plist>
PLIST

# Stage the upstream OBS runtime into the host bundle when it is available.
# Keeping the complete OBS.app under Resources preserves its Frameworks,
# PlugIns, Qt platform plugins and rpath layout.  The host can launch this
# nested app later without requiring a separately installed OBS copy.
include_obs="${LIVEHIME_INCLUDE_OBS:-1}"
obs_source="${OBS_APP_SOURCE:-$package_dir/../obs-studio/build_macos/frontend/RelWithDebInfo/OBS.app}"
if [[ "$include_obs" == "1" && -x "$obs_source/Contents/MacOS/OBS" ]]; then
  mkdir -p "$app/Contents/Resources"
  ditto "$obs_source" "$app/Contents/Resources/OBS.app"
  # The upstream development build does not carry the privacy strings that
  # macOS requires before CoreAudio/AVCapture initialization. Without these
  # keys TCC terminates OBS as soon as the user grants microphone/camera
  # access, which looks like an OBS integration failure from LiveHime.
  obs_info="$app/Contents/Resources/OBS.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :NSCameraUsageDescription LiveHime uses the camera as an OBS capture source.' "$obs_info" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :NSCameraUsageDescription string LiveHime uses the camera as an OBS capture source.' "$obs_info"
  /usr/libexec/PlistBuddy -c 'Set :NSMicrophoneUsageDescription LiveHime uses the microphone as an OBS audio source.' "$obs_info" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :NSMicrophoneUsageDescription string LiveHime uses the microphone as an OBS audio source.' "$obs_info"
  /usr/libexec/PlistBuddy -c 'Set :NSScreenCaptureUsageDescription LiveHime uses screen capture as an OBS video source.' "$obs_info" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :NSScreenCaptureUsageDescription string LiveHime uses screen capture as an OBS video source.' "$obs_info"
  /usr/libexec/PlistBuddy -c 'Set :NSAudioCaptureUsageDescription LiveHime uses system audio as an OBS source.' "$obs_info" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :NSAudioCaptureUsageDescription string LiveHime uses system audio as an OBS source.' "$obs_info"
  # OBS is an implementation detail of the single LiveHime app. Keep its
  # process out of the Dock and menu bar while retaining its capture backend.
  /usr/libexec/PlistBuddy -c 'Set :LSUIElement true' "$obs_info" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$obs_info"
  # The build tree may carry a stale development signature. Re-sign the
  # nested bundle before signing the outer app so strict verification works.
  python3 "$script_dir/local-signing.py" --deep --sign "$app/Contents/Resources/OBS.app"
  printf 'internal OBS backend: bundled\n' > "$app/Contents/Resources/OBS_BUNDLE_INFO.txt"
else
  if [[ "$include_obs" == "1" ]]; then
    printf 'warning: OBS.app not found at %s; building host-only bundle\n' "$obs_source" >&2
  fi
fi

# Reuse the same local certificate on every rebuild so TCC's saved code
# requirement remains valid. Nested code was signed first, with its own IDs.
python3 "$script_dir/local-signing.py" --sign "$app"
printf '%s\n' "$app"
