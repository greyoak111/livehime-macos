#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
root_dir=${script_dir:h}
cd "$root_dir"
python3 -m unittest discover -s scripts/tests -v
cd "$root_dir/macos-livehime-adapter"
swift test
