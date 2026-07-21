import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RELEASE_VERSION = os.environ.get("LUCY_RELEASE_VERSION", "v0.1-beta")
RELEASE_NAME = f"Lucy-{RELEASE_VERSION}"
RELEASE_ZIP = ROOT / "release" / f"{RELEASE_NAME}.zip"
RELEASE_SCRIPT = ROOT / "release_lucy_zip.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "release-macos.yml"


class LucyReleaseZipTests(unittest.TestCase):
    def test_public_release_script_requires_developer_id_and_notarization(self):
        script = RELEASE_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("LUCY_CODESIGN_IDENTITY", script)
        self.assertIn("LUCY_NOTARY_PROFILE", script)
        self.assertIn("Refusing to build a public Lucy ZIP", script)
        self.assertIn("xcrun notarytool submit", script)
        self.assertIn("xcrun stapler staple", script)
        self.assertIn("spctl --assess", script)
        self.assertIn("Authority=Developer ID Application", script)

    def test_github_workflow_builds_notarized_release_before_upload(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("Import Developer ID certificate", workflow)
        self.assertIn("xcrun notarytool store-credentials lucy-notary", workflow)
        self.assertIn("LUCY_NOTARY_PROFILE: lucy-notary", workflow)
        self.assertIn("LUCY_CODESIGN_IDENTITY", workflow)
        self.assertIn("test_release_zip_contains_gatekeeper_acceptable_downloaded_app", workflow)
        self.assertIn("gh release upload", workflow)

    @unittest.skipUnless(RELEASE_ZIP.exists(), "release ZIP is not built")
    @unittest.skipUnless(shutil.which("ditto") and shutil.which("codesign") and shutil.which("spctl"), "macOS release tools required")
    @unittest.skipUnless(os.environ.get("LUCY_EXPECT_PUBLIC_RELEASE_ZIP") == "1", "set LUCY_EXPECT_PUBLIC_RELEASE_ZIP=1 to validate a public notarized ZIP artifact")
    def test_release_zip_contains_gatekeeper_acceptable_downloaded_app(self):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["ditto", "-x", "-k", str(RELEASE_ZIP), tmp], check=True)
            app = Path(tmp) / RELEASE_NAME / "Lucy.app"
            self.assertTrue(app.is_dir(), f"release ZIP must contain {RELEASE_NAME}/Lucy.app")

            verify = subprocess.run(
                ["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
            )
            self.assertEqual(verify.returncode, 0, verify.stdout)

            details = subprocess.run(
                ["codesign", "-dv", "--verbose=4", str(app)],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
            )
            self.assertEqual(details.returncode, 0, details.stdout)
            self.assertIn("Authority=Developer ID Application", details.stdout)
            self.assertIn("TeamIdentifier=", details.stdout)
            self.assertNotIn("Signature=adhoc", details.stdout)

            os.setxattr(app, "com.apple.quarantine", b"0081;00000000;Chrome;00000000-0000-0000-0000-000000000000")
            assess = subprocess.run(
                ["spctl", "--assess", "--type", "execute", "--verbose=4", str(app)],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
            )
            self.assertEqual(assess.returncode, 0, assess.stdout)
            self.assertIn("accepted", assess.stdout.lower())


if __name__ == "__main__":
    unittest.main()
