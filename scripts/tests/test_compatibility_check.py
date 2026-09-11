import copy
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch
import urllib.request
import urllib.error

SCRIPT = Path(__file__).resolve().parents[1] / "compatibility-check.py"
spec = importlib.util.spec_from_file_location("compatibility_check", SCRIPT)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class CheckerTests(unittest.TestCase):
    def setUp(self):
        self.manifest = checker.load_manifest()

    def test_default_snapshot_never_fetches_network(self):
        with patch.object(checker, "fetch_online", side_effect=AssertionError("network forbidden")):
            snapshot = checker.make_snapshot(self.manifest, "offline")
        self.assertEqual(snapshot["observed"]["source"], "embedded-fixture")
        self.assertTrue(all(r["status"] == "ok" for r in snapshot["resources"]))
        self.assertEqual(checker.compare_snapshots(snapshot, snapshot)["decision"], "no_change_observed")

    def test_build_only_change_requires_review(self):
        old = checker.make_snapshot(self.manifest, "offline")
        new = copy.deepcopy(old)
        new["observed"]["build"] += 1
        self.assertEqual(checker.compare_snapshots(old, new)["decision"], "review_required")

    def test_page_reference_change_detected_without_disclosing_reference(self):
        old = b'<html><div id="app"></div><script src="first.js?secret=fixture"></script></html>'
        new = old.replace(b"first.js", b"second.js")
        self.assertNotEqual(checker.page_fingerprint(old), checker.page_fingerprint(new))
        self.assertNotIn("secret", json.dumps(checker.page_fingerprint(old)))

    def test_changed_resource_is_not_declared_incompatible(self):
        old = checker.make_snapshot(self.manifest, "offline")
        new = copy.deepcopy(old)
        new["resources"][1]["sha256"] = "a" * 64
        report = checker.compare_snapshots(old, new)
        self.assertEqual(report["resources"][1]["result"], "changed")
        self.assertEqual(report["decision"], "review_required")

    def test_missing_resource_is_not_silent_no_change(self):
        old = checker.make_snapshot(self.manifest, "offline")
        new = copy.deepcopy(old)
        new["resources"].pop()
        with self.assertRaises(ValueError): checker.compare_snapshots(old, new)

    def test_failed_prior_snapshot_cannot_be_trusted_baseline(self):
        old = checker.make_snapshot(self.manifest, "offline")
        new = copy.deepcopy(old)
        old["resources"][0]["status"] = "error"
        report = checker.compare_snapshots(old, new)
        self.assertEqual(report["decision"], "review_required")
        self.assertEqual(report["resources"][0]["result"], "baseline_unknown")

    def test_fixtures_and_online_snapshots_cannot_be_compared(self):
        old = checker.make_snapshot(self.manifest, "offline")
        new = copy.deepcopy(old)
        new["mode"] = "online"
        with self.assertRaises(ValueError): checker.compare_snapshots(old, new)

    def test_all_redirects_are_blocked_even_to_same_host(self):
        handler = checker.SafeRedirectHandler("/public")
        request = urllib.request.Request("https://live.bilibili.com/public")
        for url in ["https://attacker.invalid/private", "http://live.bilibili.com/public",
                    "https://live.bilibili.com:8443/public", "https://live.bilibili.com/public?token=secret"]:
            self.assertIsNone(handler.redirect_request(request, None, 302, "redirect", {}, url))
        self.assertEqual(handler.block_reason, "redirect_not_allowlisted")

    def test_size_limit(self):
        with self.assertRaisesRegex(ValueError, "too_large"):
            checker._read_limited(io.BytesIO(b"a" * (checker.MAX_BODY_BYTES + 1)))

    def test_error_html_and_invalid_version_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "schema"):
            checker.page_fingerprint(b"<html><body>Access denied</body></html>")
        for body in [b"<html>Oops</html>", b'{"code":false,"data":{}}',
                     b'{"code":0,"data":{"curr_version":"8.6.0","build":true}}',
                     b'{"code":0,"data":{"curr_version":"private-response","build":1}}']:
            self.assertEqual(checker.parse_version(body)[2], "schema_mismatch")

    def test_online_reads_fixed_public_resource_without_cookies(self):
        class Response(io.BytesIO):
            status = 200
            headers = type("Headers", (), {"get_content_type": lambda _: "application/json"})()
            def getcode(self): return 200
            def geturl(self): return "https://api.live.bilibili.com/xlive/app-blink/v1/liveVersionInfo/getHomePageLiveVersion?system_version=2"
        response = Response(checker.EMBEDDED_FIXTURES["liveVersion"][1])
        with patch.object(checker.urllib.request, "build_opener") as factory:
            factory.return_value.open.return_value = response
            checker.fetch_online("liveVersion", self.manifest["resources"]["liveVersion"])
            args, kwargs = factory.return_value.open.call_args
            request = args[0]
            self.assertEqual(request.get_method(), "GET")
            self.assertEqual(request.host, "api.live.bilibili.com")
            self.assertIsNone(request.get_header("Cookie"))
            self.assertIsNone(request.get_header("Authorization"))
            self.assertEqual(kwargs["timeout"], 8)

    def test_network_error_details_are_not_exported(self):
        with patch.object(checker.urllib.request, "build_opener") as factory:
            factory.return_value.open.side_effect = urllib.error.URLError("private-network-location")
            record = checker.resource_record("miniLogin", self.manifest["resources"]["miniLogin"], "online", None)
        self.assertEqual(record["error"], "network_error")
        self.assertNotIn("private-network-location", json.dumps(record))


if __name__ == "__main__": unittest.main()
