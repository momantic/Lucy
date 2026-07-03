import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "browser_bridge" / "extension" / "content.js"
BACKGROUND = ROOT / "browser_bridge" / "extension" / "background.js"
PACKAGED_EXTENSION = ROOT / "bridge-extension"


class BrowserBridgeExtensionTests(unittest.TestCase):
    def test_content_script_routes_localhost_requests_through_background_worker(self):
        content = CONTENT.read_text(encoding="utf-8")
        self.assertIn("chrome.runtime.sendMessage", content)
        self.assertNotIn('fetch("http://127.0.0.1:8765/page"', content)
        self.assertNotIn('fetch("http://127.0.0.1:8765/next_command"', content)
        self.assertIn("/next_command?url=", content)

    def test_content_script_extracts_structured_linkedin_posts(self):
        content = CONTENT.read_text(encoding="utf-8")
        self.assertIn("function extractLinkedInPosts", content)
        self.assertIn("feed-shared-update-v2", content)
        self.assertIn("reusable-search__result-container", content)
        self.assertIn("linkedinPosts", content)
        self.assertIn("LinkedIn top visible posts captured", content)

    def test_background_worker_handles_bridge_fetch_messages(self):
        background = BACKGROUND.read_text(encoding="utf-8")
        self.assertIn("chrome.runtime.onMessage.addListener", background)
        self.assertIn("bridge_fetch", background)
        self.assertIn("http://127.0.0.1:8765", background)

    def test_bridge_server_persists_linkedin_posts(self):
        server = (ROOT / "browser_bridge" / "server.py").read_text(encoding="utf-8")
        self.assertIn("linkedin_posts", server)
        self.assertIn("lucy_browser_linkedin_posts.json", server)
        self.assertIn("target_url_contains", server)
        self.assertIn("BRIDGE_VERSION", server)

    def test_packaged_bridge_extension_matches_active_capture_path(self):
        packaged_manifest = (PACKAGED_EXTENSION / "manifest.json").read_text(encoding="utf-8")
        packaged_content = (PACKAGED_EXTENSION / "content.js").read_text(encoding="utf-8")
        packaged_background = (PACKAGED_EXTENSION / "background.js").read_text(encoding="utf-8")

        self.assertIn("content.js", packaged_manifest)
        self.assertIn("host_permissions", packaged_manifest)
        self.assertIn("function extractLinkedInPosts", packaged_content)
        self.assertIn("linkedinPosts", packaged_content)
        self.assertIn("bridge_fetch", packaged_background)


if __name__ == "__main__":
    unittest.main()