#!/usr/bin/env python3
"""Read-only compatibility evidence collector.

The default is entirely offline and uses embedded fixtures. Network access is
opt-in with --online and is restricted to the three public Bilibili resources
listed in compatibility/manifest.json. This tool never sends cookies, tokens,
credentials, live-control requests, or arbitrary URLs.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import sys
from typing import Any, BinaryIO, Mapping
from html.parser import HTMLParser
from urllib.parse import urlparse
import re
import urllib.error
import urllib.request

MAX_BODY_BYTES = 2 * 1024 * 1024
TIMEOUT_SECONDS = 8
FIXED_RESOURCES = {
    "liveVersion": ("api.live.bilibili.com", "/xlive/app-blink/v1/liveVersionInfo/getHomePageLiveVersion", "system_version=2"),
    "miniLogin": ("live.bilibili.com", "/p/html/live-pc-blink/mini-login-v2/", ""),
    "faceAuth": ("live.bilibili.com", "/p/html/bilili-page-face-auth/index.html", ""),
}
SCRIPT_DIR = Path(__file__).resolve().parent
LAB_ROOT = SCRIPT_DIR.parent
MANIFEST_PATH = LAB_ROOT / "compatibility" / "manifest.json"

# Synthetic fixtures deliberately have a visible marker. They are not claims
# about the current official response and are never used to declare support.
EMBEDDED_FIXTURES: dict[str, tuple[str, bytes]] = {
    "liveVersion": (
        "application/json",
        b'{"code":0,"data":{"curr_version":"0.0.0.1","build":11050}}',
    ),
    "miniLogin": ("text/html; charset=utf-8", b'<html><body><div id="app">fixture</div><script src="https://s1.hdslb.com/fixture.js"></script></body></html>'),
    "faceAuth": ("text/html; charset=utf-8", b'<html><body><div id="app">fixture</div><script src="https://s1.hdslb.com/fixture.js"></script></body></html>'),
}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_manifest(path: Path = MANIFEST_PATH) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        manifest = json.load(fh)
    if manifest.get("schemaVersion") != 1 or not isinstance(manifest.get("resources"), dict):
        raise ValueError("manifest_schema_invalid")
    if set(manifest["resources"]) != set(FIXED_RESOURCES):
        raise ValueError("manifest_resource_set_invalid")
    for resource_id, resource in manifest["resources"].items():
        if resource_id not in EMBEDDED_FIXTURES:
            raise ValueError("manifest_resource_unknown")
        if (resource.get("host"), resource.get("path"), resource.get("query", "")) != FIXED_RESOURCES[resource_id]:
            raise ValueError("manifest_resource_not_allowlisted")
    return manifest


def _safe_fixture_root(path: Path) -> Path:
    # Fixture files are inputs for local tests only. Refuse a file path and
    # symlinked files; output never includes their path or contents.
    root = path.expanduser().resolve()
    if not root.is_dir():
        raise ValueError("fixture_dir_invalid")
    return root


def read_fixture(resource_id: str, fixture_dir: Path | None) -> tuple[str, bytes, str]:
    if fixture_dir is None:
        content_type, body = EMBEDDED_FIXTURES[resource_id]
        return content_type, body, "embedded-fixture"
    root = _safe_fixture_root(fixture_dir)
    suffix = ".json" if resource_id == "liveVersion" else ".html"
    file_path = root / f"{resource_id}{suffix}"
    if file_path.is_symlink() or not file_path.is_file():
        raise ValueError("fixture_missing")
    size = file_path.stat().st_size
    if size > MAX_BODY_BYTES:
        raise ValueError("fixture_too_large")
    return "application/json" if suffix == ".json" else "text/html", file_path.read_bytes(), "fixture"


class SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Reject every redirect: never send a second request to an unexpected location."""
    def __init__(self, expected_path: str):
        super().__init__()
        self.block_reason: str | None = None

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        self.block_reason = "redirect_not_allowlisted"
        return None


def _read_limited(stream: BinaryIO) -> bytes:
    body = stream.read(MAX_BODY_BYTES + 1)
    if len(body) > MAX_BODY_BYTES:
        raise ValueError("response_too_large")
    return body


def fetch_online(resource_id: str, resource: Mapping[str, Any]) -> tuple[str, int, str, bytes, bool]:
    """Fetch one fixed resource; return content type/status/final path/body/redirected."""
    host, path, query = FIXED_RESOURCES[resource_id]
    url = f"https://{host}{path}" + (f"?{query}" if query else "")
    handler = SafeRedirectHandler(path)
    opener = urllib.request.build_opener(handler)
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json, text/html;q=0.9", "User-Agent": "LiveHimeCompatChecker/0.1"},
        method="GET",
    )
    # No Cookie header, Authorization header, or user-controlled URL is ever sent.
    try:
        with opener.open(request, timeout=TIMEOUT_SECONDS) as response:
            body = _read_limited(response)
            status = int(getattr(response, "status", response.getcode()))
            content_type = response.headers.get_content_type()
            final_path = urlparse(response.geturl()).path.rstrip("/") or "/"
            redirected = response.geturl() != url
            if handler.block_reason:
                raise ValueError(handler.block_reason)
            return content_type, status, final_path, body, redirected
    except urllib.error.HTTPError as exc:
        # HTTPError may carry a response body; do not read/log it.
        raise RuntimeError(handler.block_reason or f"http_status_{exc.code}") from None
    except urllib.error.URLError:
        raise RuntimeError("network_error") from None
    except (TimeoutError, OSError):
        raise RuntimeError("network_error") from None


class PageReferences(HTMLParser):
    def __init__(self):
        super().__init__()
        self.references = []
        self.has_root = False
        self.has_html = False
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        self.has_html |= tag == "html"
        self.has_root |= attrs.get("id") in {"app", "root"}
        if tag == "script" and attrs.get("src"):
            self.references.append(attrs["src"])
        if tag == "link" and attrs.get("rel") == "stylesheet" and attrs.get("href"):
            self.references.append(attrs["href"])


def page_fingerprint(body: bytes) -> dict[str, Any]:
    parser = PageReferences()
    try:
        parser.feed(body.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise ValueError("page_schema_mismatch") from None
    if not parser.has_html or not parser.references:
        raise ValueError("page_schema_mismatch")
    # The official mini-login-v2 page dynamically creates its root. A static
    # #app element is not a valid requirement for this entry point.
    # Only fingerprints are exported: no arbitrary strings copied from HTML.
    return {"resourceReferenceCount": len(parser.references),
            "resourceReferencesSha256": hashlib.sha256(json.dumps(sorted(set(parser.references))).encode()).hexdigest()}


def parse_version(body: bytes) -> tuple[str | None, int | None, str | None]:
    try:
        parsed = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None, None, "schema_mismatch"
    data = parsed.get("data") if isinstance(parsed, dict) else None
    if not isinstance(parsed, dict) or (type(parsed.get("code")) is not int or parsed.get("code") != 0) or not isinstance(data, dict):
        return None, None, "schema_mismatch"
    version = data.get("curr_version")
    build = data.get("build")
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]{1,6}(?:\.[0-9]{1,6}){1,4}", version) or type(build) is not int or build <= 0:
        return None, None, "schema_mismatch"
    return version[:80], build, None


def resource_record(resource_id: str, resource: Mapping[str, Any], mode: str, fixture_dir: Path | None) -> dict[str, Any]:
    record: dict[str, Any] = {
        "id": resource_id,
        "kind": resource.get("kind"),
        "location": f"https://{resource['host']}{resource['path']}",
        "mode": mode,
    }
    try:
        if mode == "offline":
            content_type, body, source = read_fixture(resource_id, fixture_dir)
            status, final_path, redirected = 200, str(resource["path"]), False
        else:
            content_type, status, final_path, body, redirected = fetch_online(resource_id, resource)
            source = "official-public"
        mime = content_type.split(";", 1)[0].strip().lower()
        record.update({
            "status": "ok" if status == 200 else "http_error",
            "httpStatus": status,
            "contentType": mime if mime in {"application/json", "text/html"} else "other",
            "bytes": len(body),
            "sha256": hashlib.sha256(body).hexdigest(),
            "source": source,
            "redirected": redirected,
        })
        if final_path.rstrip("/") != str(resource["path"]).rstrip("/"):
            record.update({"status": "error", "error": "redirect_not_allowlisted"})
        if resource_id != "liveVersion" and record["status"] == "ok":
            if mime != "text/html": raise ValueError("page_schema_mismatch")
            record.update(page_fingerprint(body))
        if resource_id == "liveVersion" and record["status"] == "ok":
            if mime != "application/json": raise ValueError("schema_mismatch")
            version, build, error = parse_version(body)
            if error:
                record.update({"status": "error", "error": error})
            else:
                record.update({"observedVersion": version, "observedBuild": build})
    except (ValueError, RuntimeError) as exc:
        record.update({"status": "error", "error": str(exc)[:80]})
    return record


def make_snapshot(manifest: Mapping[str, Any], mode: str, fixture_dir: Path | None = None) -> dict[str, Any]:
    resources = [resource_record(rid, resource, mode, fixture_dir) for rid, resource in manifest["resources"].items()]
    version = next((r for r in resources if r["id"] == "liveVersion" and r.get("status") == "ok"), None)
    return {
        "schemaVersion": 1,
        "projectVersion": manifest.get("projectVersion"),
        "generatedAt": utc_now(),
        "mode": mode,
        "observed": {
            "version": version.get("observedVersion") if version else None,
            "build": version.get("observedBuild") if version else None,
            "source": version.get("source") if version else None,
        },
        "resources": resources,
        "note": "Hashes are evidence only. changed/review_required does not mean incompatible.",
    }


def validate_snapshot(value: Mapping[str, Any]) -> None:
    if not isinstance(value, dict) or value.get("schemaVersion") != 1 or value.get("mode") not in {"online", "offline"}:
        raise ValueError("snapshot_schema_invalid")
    records = value.get("resources")
    if not isinstance(records, list) or len(records) != 3 or any(not isinstance(r, dict) for r in records) or {r.get("id") for r in records} != set(FIXED_RESOURCES):
        raise ValueError("snapshot_resource_set_invalid")
    for record in records:
        if record.get("status") == "ok" and not re.fullmatch(r"[0-9a-f]{64}", str(record.get("sha256", ""))):
            raise ValueError("snapshot_hash_invalid")
    observed = value.get("observed")
    if not isinstance(observed, dict): raise ValueError("snapshot_schema_invalid")
    version = observed.get("version")
    if version is not None and not re.fullmatch(r"[0-9]{1,6}(?:\.[0-9]{1,6}){1,4}", str(version)):
        raise ValueError("snapshot_version_invalid")


def compare_snapshots(previous: Mapping[str, Any], current: Mapping[str, Any]) -> dict[str, Any]:
    validate_snapshot(previous)
    validate_snapshot(current)
    if previous["mode"] != current["mode"]:
        raise ValueError("cannot_compare_fixture_and_official")
    old_by_id = {r.get("id"): r for r in previous.get("resources", []) if isinstance(r, dict)}
    changes: list[dict[str, Any]] = []
    for item in current.get("resources", []):
        rid = item.get("id")
        old = old_by_id.get(rid)
        if item.get("status") != "ok":
            result, reason = "error", "resource_error"
        elif old is None or old.get("status") != "ok" or old.get("sha256") is None:
            result, reason = "baseline_unknown", "no_prior_hash"
        elif item.get("sha256") != old.get("sha256"):
            result, reason = "changed", "hash_changed_review_required"
        else:
            result, reason = "unchanged", "hash_match"
        changes.append({"id": rid, "result": result, "reason": reason})
    old_version = previous.get("observed", {}).get("version")
    new_version = current.get("observed", {}).get("version")
    version_change = "unknown"
    if old_version and new_version:
        version_change = "changed_review_required" if (old_version, previous.get("observed", {}).get("build")) != (new_version, current.get("observed", {}).get("build")) else "unchanged"
    return {
        "schemaVersion": 1,
        "comparedAt": utc_now(),
        "previousMode": previous.get("mode"),
        "currentMode": current.get("mode"),
        "observedVersion": {"previous": old_version, "current": new_version, "result": version_change},
        "resources": changes,
        "decision": "review_required" if any(c["result"] in {"changed", "error", "baseline_unknown"} for c in changes) or version_change == "changed_review_required" else "no_change_observed",
        "note": "This comparison never declares compatibility or incompatibility and never changes a baseline.",
    }


def write_json(value: Mapping[str, Any], output: str | None) -> None:
    text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=False) + "\n"
    if not output or output == "-":
        sys.stdout.write(text)
    else:
        target = Path(output).expanduser()
        target.write_text(text, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    snap = sub.add_parser("snapshot", help="collect a read-only snapshot (offline by default)")
    snap.add_argument("--online", action="store_true", help="explicitly fetch fixed public resources")
    snap.add_argument("--fixture-dir", type=Path, help="test fixture directory with fixed filenames")
    snap.add_argument("--output", help="JSON output path, or - for stdout")
    comp = sub.add_parser("compare", help="compare two previously saved JSON snapshots")
    comp.add_argument("previous", type=Path)
    comp.add_argument("current", type=Path)
    comp.add_argument("--output", help="JSON output path, or - for stdout")
    args = parser.parse_args(argv)
    try:
        manifest = load_manifest()
        if args.command == "snapshot":
            if args.online and args.fixture_dir:
                parser.error("--online and --fixture-dir are mutually exclusive")
            snapshot = make_snapshot(manifest, "online" if args.online else "offline", args.fixture_dir)
            write_json(snapshot, args.output)
            return 1 if any(r["status"] != "ok" for r in snapshot["resources"]) else 0
        else:
            with args.previous.open("r", encoding="utf-8") as fh:
                previous = json.load(fh)
            with args.current.open("r", encoding="utf-8") as fh:
                current = json.load(fh)
            write_json(compare_snapshots(previous, current), args.output)
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print("compatibility-check: invalid input or unavailable output; no changes applied", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
