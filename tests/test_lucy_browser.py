import importlib.util
import sys
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
LUCY_BROWSER = ROOT / "tools_created_by_lucy" / "lucy_browser.py"


def load_lucy_browser():
    spec = importlib.util.spec_from_file_location("lucy_browser", LUCY_BROWSER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class LucyBrowserTests(unittest.TestCase):
    def test_read_queues_fresh_page_read_before_returning_state(self):
        browser = load_lucy_browser()
        calls = []

        def fake_post(path, obj):
            calls.append(("post", path, obj))
            return {"ok": True, "queued": obj}

        def fake_get(path, timeout=5):
            calls.append(("get", path))
            return {"ok": True, "last_page": "fresh linkedin text", "last_url": "https://www.linkedin.com/feed/"}

        with mock.patch.object(browser, "ensure_bridge_server", return_value=None), \
             mock.patch.object(browser, "post", side_effect=fake_post), \
             mock.patch.object(browser, "get", side_effect=fake_get):
            state = browser.read_page(wait_seconds=0)

        self.assertEqual(state["last_page"], "fresh linkedin text")
        self.assertIn(("post", "/command", {"type": "read_page"}), calls)
        self.assertEqual(calls[-1], ("get", "/state"))

    def test_read_can_target_linkedin_tabs_so_other_tabs_do_not_consume_command(self):
        browser = load_lucy_browser()
        commands = []

        with mock.patch.object(browser, "ensure_bridge_server", return_value=None), \
             mock.patch.object(browser, "get", return_value={"ok": True, "last_page": "fresh linkedin text"}), \
             mock.patch.object(browser, "post", side_effect=lambda path, obj: commands.append((path, obj)) or {"ok": True}):
            browser.read_page(wait_seconds=0, target_url_contains="linkedin.com")

        self.assertEqual(commands, [("/command", {"type": "read_page", "target_url_contains": "linkedin.com"})])

    def test_bridge_available_requires_expected_bridge_version(self):
        browser = load_lucy_browser()
        with mock.patch.object(browser, "bridge_status", return_value={"ok": True, "service": "Lucy Browser Bridge"}):
            self.assertFalse(browser.bridge_available())
        with mock.patch.object(browser, "bridge_status", return_value={"ok": True, "service": "Lucy Browser Bridge", "version": browser.EXPECTED_BRIDGE_VERSION}):
            self.assertTrue(browser.bridge_available())

    def test_linkedin_search_targets_linkedin_read_command(self):
        browser = load_lucy_browser()
        read_calls = []

        with mock.patch.object(browser, "ensure_bridge_server", return_value=None), \
             mock.patch.object(browser, "open_url", return_value="https://www.linkedin.com/search/results/content/?keywords=ai"), \
             mock.patch.object(browser.time, "sleep", return_value=None), \
             mock.patch.object(browser, "read_page", side_effect=lambda **kwargs: read_calls.append(kwargs) or {"ok": True}):
            browser.linkedin_search("ai agents")

        self.assertEqual(read_calls, [{"wait_seconds": 1.5, "target_url_contains": "linkedin.com"}])

    def test_page_text_falls_back_to_tmp_cache_when_bridge_state_is_empty(self):
        browser = load_lucy_browser()
        cache = Path("/tmp/lucy_browser_page.txt")
        old = cache.read_text(encoding="utf-8") if cache.exists() else None
        try:
            cache.write_text("cached linkedin bridge text", encoding="utf-8")
            with mock.patch.object(browser, "ensure_bridge_server", return_value=None), \
                 mock.patch.object(browser, "get", return_value={"ok": True, "last_page": ""}):
                self.assertEqual(browser.page_text(), "cached linkedin bridge text")
        finally:
            if old is None:
                cache.unlink(missing_ok=True)
            else:
                cache.write_text(old, encoding="utf-8")

    def test_linkedin_posts_text_formats_structured_bridge_posts(self):
        browser = load_lucy_browser()
        posts = [
            {
                "author": "Alex Chen",
                "headline": "AI platform founder",
                "text": "Agent builders are moving toward local-first workflows for privacy and latency.",
                "url": "https://www.linkedin.com/feed/update/urn:li:activity:1",
                "engagement": "42 reactions",
            },
            {
                "author": "Priya Rao",
                "text": "The hard part is not demos. The hard part is governance, evals, and audit trails.",
            },
        ]

        with mock.patch.object(browser, "ensure_bridge_server", return_value=None), \
             mock.patch.object(browser, "get", return_value={"ok": True, "linkedin_posts": posts}):
            text = browser.linkedin_posts_text()

        self.assertIn("LinkedIn top visible posts captured", text)
        self.assertIn("Post 1", text)
        self.assertIn("Author: Alex Chen", text)
        self.assertIn("Agent builders are moving", text)
        self.assertIn("Post 2", text)
        self.assertIn("audit trails", text)


if __name__ == "__main__":
    unittest.main()