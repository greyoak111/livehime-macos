#!/usr/bin/env python3
"""Read-only preflight for a LiveHime app replacement.

This command never copies, renames, deletes, launches, terminates, signs, or
installs an app. It turns an update into evidence that can be reviewed before a
future installer is allowed to act.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
from typing import Any, Iterable

EXPECTED_HOST_ID = "local.livehime.macos"
EXPECTED_LAB_ID = "local.livehime.compat-lab"
FORBIDDEN_PARTS = {"private", "captures", "credentials"}
FORBIDDEN_SUFFIXES = (".cookie", ".cookies", ".token", ".session", ".pem", ".p12", ".key")
ALLOWED_PUBLIC_FILES = {
    # OBS ships this public Sparkle verification key in its normal bundle.
    # It is not a credential or signing secret; keep the broader suffix
    # block for all other PEM/key material.
    "Contents/Resources/OBS.app/Contents/Resources/OBSPublicRSAKey.pem",
}


class SafetyError(Exception):
    pass


def clean_path(value: str) -> Path:
    path = Path(value).expanduser()
    if not path.exists() or path.is_symlink() or not path.is_dir():
        raise SafetyError("bundle_path_invalid")
    return path.resolve()


def read_plist(path: Path) -> dict[str, Any]:
    info_path = path / "Contents" / "Info.plist"
    try:
        with info_path.open("rb") as fh:
            value = plistlib.load(fh)
    except (OSError, plistlib.InvalidFileException):
        raise SafetyError("bundle_plist_invalid") from None
    if not isinstance(value, dict):
        raise SafetyError("bundle_plist_invalid")
    return value


def executable_path(bundle: Path, info: dict[str, Any]) -> Path:
    name = info.get("CFBundleExecutable")
    if not isinstance(name, str) or not name or "/" in name or "\\" in name:
        raise SafetyError("bundle_executable_invalid")
    path = bundle / "Contents" / "MacOS" / name
    if path.is_symlink() or not path.is_file() or not os.access(path, os.X_OK):
        raise SafetyError("bundle_executable_missing")
    return path.resolve()


def scan_forbidden_files(bundle: Path) -> None:
    for item in bundle.rglob("*"):
        if item.is_symlink():
            # macOS Frameworks commonly contain internal Version symlinks.
            # They are safe to preserve when they resolve inside the bundle;
            # an external link would let a candidate pull code from outside
            # the signed package.
            try:
                resolved = item.resolve(strict=False)
                resolved.relative_to(bundle)
            except (OSError, ValueError):
                raise SafetyError("bundle_external_symlink_found") from None
            continue
        relative_parts = {part.lower() for part in item.relative_to(bundle).parts}
        if relative_parts & FORBIDDEN_PARTS:
            raise SafetyError("bundle_private_path_found")
        relative = str(item.relative_to(bundle))
        if relative in ALLOWED_PUBLIC_FILES:
            continue
        if item.is_file() and item.name.lower().endswith(FORBIDDEN_SUFFIXES):
            raise SafetyError("bundle_credential_file_found")


def process_paths(lines: Iterable[str]) -> set[Path]:
    paths: set[Path] = set()
    for line in lines:
        fields = line.strip().split(None, 1)
        if len(fields) != 2:
            continue
        command = fields[1].split(None, 1)[0]
        if command.startswith("/"):
            try: paths.add(Path(command).resolve())
            except OSError: pass
    return paths


def running_paths() -> set[Path]:
    result = subprocess.run(["ps", "-axo", "pid=,command="], check=True, capture_output=True, text=True)
    return process_paths(result.stdout.splitlines())


def verify_signature(bundle: Path) -> None:
    result = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise SafetyError("bundle_signature_invalid")


def inspect(bundle_value: str, *, skip_signature: bool = False,
            processes: set[Path] | None = None) -> dict[str, Any]:
    bundle = clean_path(bundle_value)
    info = read_plist(bundle)
    identifier = info.get("CFBundleIdentifier")
    version = info.get("CFBundleShortVersionString")
    if not isinstance(identifier, str) or not identifier:
        raise SafetyError("bundle_identifier_missing")
    if not isinstance(version, str) or not version:
        raise SafetyError("bundle_version_missing")
    executable = executable_path(bundle, info)
    scan_forbidden_files(bundle)
    if not skip_signature: verify_signature(bundle)
    live = processes if processes is not None else running_paths()
    main_running = executable in live
    nested = bundle / "Contents" / "Resources" / "OBS.app"
    obs_record: dict[str, Any] | None = None
    if nested.exists():
        if nested.is_symlink(): raise SafetyError("nested_obs_symlink_found")
        obs_info = read_plist(nested)
        obs_executable = executable_path(nested, obs_info)
        if obs_info.get("CFBundleIdentifier") == identifier:
            raise SafetyError("nested_obs_identifier_collides")
        obs_running = obs_executable in live
        if not skip_signature: verify_signature(nested)
        obs_record = {"present": True, "identifier": obs_info.get("CFBundleIdentifier"),
                      "version": obs_info.get("CFBundleShortVersionString"), "running": obs_running}
    return {"status": "blocked" if main_running or (obs_record and obs_record["running"]) else "ready",
            "identifier": identifier, "version": version, "running": main_running,
            "nestedOBS": obs_record, "signatureChecked": not skip_signature}


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""): h.update(chunk)
    return h.hexdigest()


def binary_digest(bundle_value: str) -> str:
    bundle = clean_path(bundle_value)
    return digest(executable_path(bundle, read_plist(bundle)))


def compare(old_value: str, new_value: str, skip_signature: bool) -> dict[str, Any]:
    old = inspect(old_value, skip_signature=skip_signature)
    new = inspect(new_value, skip_signature=skip_signature)
    if old["identifier"] != new["identifier"]:
        raise SafetyError("bundle_identifier_changed")
    return {"status": "blocked" if old["status"] == "blocked" or new["status"] == "blocked" else "ready",
            "identifier": new["identifier"], "oldVersion": old["version"], "newVersion": new["version"],
            "executableChanged": binary_digest(old_value) != binary_digest(new_value),
            "oldRunning": old["running"], "newRunning": new["running"],
            "oldNestedOBS": old["nestedOBS"], "newNestedOBS": new["nestedOBS"],
            "decision": "review_required" if old["version"] != new["version"] else "same_version_preflight"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-signature", action="store_true", help="test fixtures only")
    sub = parser.add_subparsers(dest="command", required=True)
    one = sub.add_parser("inspect"); one.add_argument("bundle")
    two = sub.add_parser("compare"); two.add_argument("old"); two.add_argument("new")
    args = parser.parse_args(argv)
    try:
        result = inspect(args.bundle, skip_signature=args.skip_signature) if args.command == "inspect" else compare(args.old, args.new, args.skip_signature)
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0 if result["status"] == "ready" else 1
    except (OSError, subprocess.SubprocessError, SafetyError):
        print(json.dumps({"status": "blocked", "reason": "preflight_failed"}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
