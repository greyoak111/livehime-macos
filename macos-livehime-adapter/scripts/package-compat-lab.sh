#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
package_dir=${script_dir:h}
cd "$package_dir"
swift build -c release --product LiveHimeCompatLab
lab_bin_dir=$(swift build -c release --show-bin-path)
python3 - "$package_dir" "$lab_bin_dir/LiveHimeCompatLab" <<'PY'
from pathlib import Path
import datetime
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

package = Path(sys.argv[1]).resolve()
binary = Path(sys.argv[2]).resolve()
dist = package / 'dist'
if dist.is_symlink(): raise SystemExit('Refusing a symlinked output directory')
dist.mkdir(exist_ok=True)
target = dist / 'LiveHimeCompatLab.app'
if target.is_symlink(): raise SystemExit('Refusing a symlinked app')
if subprocess.run(['pgrep', '-f', '^' + re.escape(str(target / 'Contents/MacOS/LiveHimeCompatLab')) + '$'], stdout=subprocess.DEVNULL).returncode == 0:
    raise SystemExit('Close Compatibility Lab before replacing its bundle')
with tempfile.TemporaryDirectory(prefix='.compat-stage-', dir=dist) as folder:
    app = Path(folder) / target.name
    contents = app / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    shutil.copy2(binary, contents / 'MacOS/LiveHimeCompatLab')
    info = {'CFBundleExecutable': 'LiveHimeCompatLab', 'CFBundleIdentifier': 'local.livehime.compat-lab',
            'CFBundleName': 'LiveHime Compatibility Lab', 'CFBundlePackageType': 'APPL',
            'CFBundleShortVersionString': '0.1.1', 'CFBundleVersion': '1',
            'LSMinimumSystemVersion': '13.0', 'NSHighResolutionCapable': True}
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    backup = None
    if target.exists():
        suffix = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
        backup = dist / f'LiveHimeCompatLab.previous-{suffix}.app'
        target.rename(backup)
    try: app.rename(target)
    except Exception:
        if backup: backup.rename(target)
        raise
print(target)
PY
