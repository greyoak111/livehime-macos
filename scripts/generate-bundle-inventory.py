#!/usr/bin/env python3
"""Write a path-safe Mach-O and bundled-resource inventory for a candidate app."""

from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path


def is_macho(path: Path) -> bool:
    result = subprocess.run(["/usr/bin/file", str(path)], capture_output=True, text=True)
    return "Mach-O" in result.stdout


def dependencies(path: Path, bundle: Path) -> list[str]:
    result = subprocess.run(["/usr/bin/otool", "-arch", "arm64", "-L", str(path)], capture_output=True, text=True)
    lines = result.stdout.splitlines()[1:]
    prefix = str(bundle) + os.sep
    values = []
    for line in lines:
        value = line.strip().split(" (compatibility")[0]
        if not value:
            continue
        if value.startswith(prefix):
            value = "@bundle/" + value[len(prefix):]
        values.append(value)
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("bundle", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    if not (bundle / "Contents").is_dir():
        raise SystemExit(f"not an app bundle: {bundle}")

    machos: list[tuple[str, list[str]]] = []
    for path in sorted(bundle.rglob("*")):
        if path.is_file() and is_macho(path):
            machos.append((str(path.relative_to(bundle)), dependencies(path, bundle)))
    resources = sorted(
        str(path.relative_to(bundle))
        for path in bundle.rglob("*")
        if path.is_file() and ("PlugIns" in path.parts or path.suffix in {".framework", ".dylib"})
    )

    lines = [
        "# LiveHime macOS v0.1.1 candidate bundle inventory",
        "",
        "Generated from the local candidate app with scripts/generate-bundle-inventory.py.",
        "Paths are relative to the app bundle; no account data, cookies, stream keys or",
        "host-specific absolute paths are included.",
        "",
        "## Bundled resource files",
        "",
    ]
    lines.extend(f"- `{item}`" for item in resources)
    lines += ["", "## Mach-O files and direct dependencies", ""]
    for relative, deps in machos:
        lines.append(f"### `{relative}`")
        lines.extend(f"- `{dep}`" for dep in deps)
        lines.append("")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
