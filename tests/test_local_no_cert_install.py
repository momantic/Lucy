import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INSTALL_SCRIPT = ROOT / "install_lucy_local_no_cert.sh"
INSTALL_DOC = ROOT / "docs" / "install" / "index.html"
README = ROOT / "README.md"
RELEASE_SCRIPT = ROOT / "release_lucy_zip.sh"
PUBLISH_SCRIPT = ROOT / "publish_lucy_release_asset.sh"
PRIVATE_RELEASE_WORKFLOW = ROOT / ".github" / "workflows" / "release-macos-private-nocert.yml"


class LocalNoCertInstallTests(unittest.TestCase):
    def test_no_cert_installer_repairs_download_metadata_and_resigns_locally(self):
        text = INSTALL_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("com.apple.quarantine", text)
        self.assertIn("com.apple.provenance", text)
        self.assertIn("codesign --force --deep --sign -", text)
        self.assertIn("codesign --verify --deep --strict", text)
        self.assertIn("build_lucy_app.sh", text)
        self.assertIn("--zip", text)
        self.assertIn("--direct-launch", text)
        self.assertIn("/tmp/lucy-local-no-cert.log", text)
        self.assertIn('rm -rf "$tmp"', text)
        self.assertIn("repair_extracted_release", text)
        self.assertIn('DIRECT_LAUNCH="${LUCY_DIRECT_LAUNCH:-0}"', text)

    def test_install_docs_explain_public_notarization_vs_private_no_cert(self):
        html = INSTALL_DOC.read_text(encoding="utf-8")
        readme = README.read_text(encoding="utf-8")

        self.assertIn("Private no-cert install", html)
        self.assertIn("install_lucy_local_no_cert.sh", html)
        self.assertIn("Public downloads still need Developer ID signing and notarization", html)
        self.assertIn("nocert-extracted-command", html)
        self.assertIn("apple-verify-command", html)
        self.assertIn("Apple could not verify Lucy is free of malware", html)
        self.assertIn("nocert-direct-command", html)
        self.assertIn("Private/local install without Apple Developer ID", readme)
        self.assertIn("--zip ~/Downloads/Lucy-v0.1-beta.zip", readme)
        self.assertIn("--direct-launch", readme)
        self.assertIn("publish_lucy_release_asset.sh", readme)
        self.assertIn("install_lucy_local_no_cert.sh --direct-launch", html)

    def test_release_zip_scrubs_metadata_from_final_zip_file(self):
        text = RELEASE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('xattr -cr "$ZIP_PATH"', text)
        self.assertIn("install_lucy_local_no_cert.sh", text)

    def test_publish_script_replaces_live_github_release_asset(self):
        text = PUBLISH_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("GITHUB_TOKEN", text)
        self.assertIn("releases/tags/$TAG", text)
        self.assertIn("releases/assets/$existing_asset_id", text)
        self.assertIn("uploads.github.com/repos/$OWNER/$REPO/releases/$release_id/assets", text)
        self.assertIn("browser_download_url", text)

    def test_private_no_cert_workflow_publishes_release_asset_on_push(self):
        text = PRIVATE_RELEASE_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("LUCY_ALLOW_UNNOTARIZED_RELEASE: '1'", text)
        self.assertIn("install_lucy_local_no_cert.sh --no-open", text)
        self.assertIn("gh release upload", text)
        self.assertIn("--clobber", text)
        self.assertIn("contents: write", text)
        self.assertIn("branches:", text)
        self.assertIn("main", text)


if __name__ == "__main__":
    unittest.main()