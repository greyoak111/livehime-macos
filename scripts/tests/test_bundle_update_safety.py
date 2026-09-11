import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "bundle-update-safety.py"
spec = importlib.util.spec_from_file_location("bundle_update_safety", SCRIPT)
check = importlib.util.module_from_spec(spec); spec.loader.exec_module(check)


class BundleSafetyTests(unittest.TestCase):
    def make_bundle(self, root, name="App", identifier="local.livehime.compat-lab", version="0.1.1", nested=False):
        app = root / f"{name}.app"; (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/MacOS" / name).write_bytes(f"binary-{version}".encode()); (app / "Contents/MacOS" / name).chmod(0o755)
        info = {"CFBundleExecutable": name, "CFBundleIdentifier": identifier, "CFBundleShortVersionString": version}
        (app / "Contents/Info.plist").write_bytes(__import__("plistlib").dumps(info))
        if nested:
            obs = app / "Contents/Resources/OBS.app"; (obs / "Contents/MacOS").mkdir(parents=True)
            (obs / "Contents/MacOS/OBS").write_bytes(b"obs"); (obs / "Contents/MacOS/OBS").chmod(0o755)
            oi = {"CFBundleExecutable":"OBS", "CFBundleIdentifier":"org.obsproject.obs-studio", "CFBundleShortVersionString":"32"}
            (obs / "Contents/Info.plist").write_bytes(__import__("plistlib").dumps(oi))
        return app

    def test_fixture_is_ready_without_codesign_and_nested_obs_is_reported(self):
        with tempfile.TemporaryDirectory() as t:
            result = check.inspect(str(self.make_bundle(Path(t), nested=True)), skip_signature=True, processes=set())
        self.assertEqual(result["status"], "ready"); self.assertFalse(result["nestedOBS"]["running"])

    def test_running_host_or_nested_obs_blocks(self):
        with tempfile.TemporaryDirectory() as t:
            app = self.make_bundle(Path(t), nested=True)
            main = (app / "Contents/MacOS/App").resolve(); obs = (app / "Contents/Resources/OBS.app/Contents/MacOS/OBS").resolve()
            self.assertEqual(check.inspect(str(app), skip_signature=True, processes={main})["status"], "blocked")
            self.assertEqual(check.inspect(str(app), skip_signature=True, processes={obs})["status"], "blocked")

    def test_private_and_credential_paths_block(self):
        with tempfile.TemporaryDirectory() as t:
            app = self.make_bundle(Path(t)); secret = app / "Contents/Resources/private"; secret.mkdir(parents=True); (secret / "x.token").write_text("fixture")
            with self.assertRaises(check.SafetyError): check.inspect(str(app), skip_signature=True, processes=set())

    def test_symlinked_bundle_or_executable_blocks(self):
        with tempfile.TemporaryDirectory() as t:
            app = self.make_bundle(Path(t)); (app / "Contents/MacOS/App").unlink(); (app / "Contents/MacOS/App").symlink_to("/bin/echo")
            with self.assertRaises(check.SafetyError): check.inspect(str(app), skip_signature=True, processes=set())

    def test_internal_framework_symlink_is_allowed(self):
        with tempfile.TemporaryDirectory() as t:
            app = self.make_bundle(Path(t)); framework = app / "Contents/Frameworks/Example.framework"
            (framework / "Versions/A").mkdir(parents=True)
            (framework / "Versions/Current").symlink_to("A")
            result = check.inspect(str(app), skip_signature=True, processes=set())
            self.assertEqual(result["status"], "ready")

    def test_identifier_mismatch_blocks_compare(self):
        with tempfile.TemporaryDirectory() as t:
            old = self.make_bundle(Path(t), name="Old", identifier="local.livehime.compat-lab")
            new = self.make_bundle(Path(t), name="New", identifier="evil.example")
            with self.assertRaises(check.SafetyError): check.compare(str(old), str(new), True)

    def test_version_and_binary_change_requires_review_but_does_not_install(self):
        with tempfile.TemporaryDirectory() as t:
            old = self.make_bundle(Path(t), name="Old", version="0.1.0")
            new = self.make_bundle(Path(t), name="New", version="0.1.1")
            # Same identity is required for a replacement; use matching Info.plist after creation.
            import plistlib
            info = plistlib.loads((new / "Contents/Info.plist").read_bytes()); info["CFBundleIdentifier"] = "local.livehime.compat-lab"; (new / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            result = check.compare(str(old), str(new), True)
            self.assertEqual(result["decision"], "review_required"); self.assertTrue(result["executableChanged"])
            self.assertTrue(old.exists()); self.assertTrue(new.exists())

    def test_invalid_plist_returns_stable_cli_error(self):
        with tempfile.TemporaryDirectory() as t:
            app = self.make_bundle(Path(t)); (app / "Contents/Info.plist").write_bytes(b"not-plist")
            # The public CLI must not expose the local path or parser details.
            import subprocess, sys
            result = subprocess.run([sys.executable, str(SCRIPT), "--skip-signature", "inspect", str(app)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1); self.assertEqual(json.loads(result.stdout)["reason"], "preflight_failed")


if __name__ == "__main__": unittest.main()
