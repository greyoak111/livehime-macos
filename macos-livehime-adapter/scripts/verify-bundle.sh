#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
package_dir=${script_dir:h}
app="${1:-$package_dir/dist/LiveHimeMacApp.app}"

fail() { print -u2 -- "verify-bundle: $*"; exit 1; }
[[ -d "$app" ]] || fail "bundle not found: $app"
host="$app/Contents/MacOS/LiveHimeMacApp"
obs="$app/Contents/Resources/OBS.app"
[[ -x "$host" ]] || fail "host executable missing: $host"
[[ -d "$obs" ]] || fail "bundled OBS.app missing: $obs"
[[ -x "$obs/Contents/MacOS/OBS" ]] || fail "bundled OBS executable missing"
[[ -f "$obs/Contents/PlugIns/obs-websocket.plugin/Contents/MacOS/obs-websocket" ]] \
  || fail "obs-websocket plugin missing"

arch_host=$(file -b "$host")
arch_obs=$(file -b "$obs/Contents/MacOS/OBS")
[[ "$arch_host" == *"Mach-O"* ]] || fail "host is not Mach-O: $arch_host"
[[ "$arch_obs" == *"Mach-O"* ]] || fail "OBS is not Mach-O: $arch_obs"
codesign --verify --deep --strict "$app" \
  || fail "codesign verification failed"
python3 - "$app" <<'PY'
from pathlib import Path
import plistlib
import subprocess
import sys
app = Path(sys.argv[1])
for bundle in [app, app / 'Contents/Resources/OBS.app']:
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    for key in ['NSCameraUsageDescription', 'NSMicrophoneUsageDescription', 'NSScreenCaptureUsageDescription', 'NSAudioCaptureUsageDescription']:
        assert info.get(key), f'{bundle.name}: missing {key}'
    if bundle.name == 'OBS.app':
        assert info.get('LSUIElement') is True, 'OBS backend must remain hidden from Dock/menu bar'
    result = subprocess.run(['/usr/bin/codesign', '-d', '-r-', str(bundle)], capture_output=True, text=True, check=True)
    assert 'certificate' in result.stdout and 'cdhash H' not in result.stdout, f'{bundle.name}: unstable signing identity'
print('privacy: host and OBS usage descriptions present')
print('identity: host and OBS use certificate-based requirements')
PY

print "bundle: $app"
print "host: $arch_host"
print "obs: $arch_obs"
print "obs-websocket: present"
print "codesign: verified"
