import importlib.util
import os
from pathlib import Path
from unittest import mock
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
TRACKER = ROOT / "backend" / "download_tracker.py"


def load_tracker(db_path):
    os.environ["LUCY_TRACKER_DB"] = str(db_path)
    os.environ["LUCY_TRACKER_TOKEN"] = "test-secret"
    spec = importlib.util.spec_from_file_location("download_tracker", TRACKER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.init_db()
    return module


class FakeHandler:
    headers = {
        "User-Agent": "UnitTest Browser",
        "Referer": "https://lucy.local/test",
        "X-Forwarded-For": "203.0.113.10",
    }
    client_address = ("127.0.0.1", 12345)


class DownloadTrackerTests(unittest.TestCase):
    def test_records_download_and_returns_stats(self):
        with tempfile.TemporaryDirectory() as tmp:
            tracker = load_tracker(Path(tmp) / "downloads.sqlite3")
            event_id = tracker.record_download(FakeHandler(), "home-hero")
            stats = tracker.fetch_stats()

            self.assertEqual(event_id, 1)
            self.assertEqual(stats["total"], 1)
            self.assertEqual(stats["today"], 1)
            self.assertEqual(stats["last_hour"], 1)
            self.assertEqual(stats["unique_total"], 1)
            self.assertEqual(stats["by_source"], [{"source": "home-hero", "count": 1}])
            self.assertEqual(stats["recent"][0]["source"], "home-hero")

    def test_private_stats_requires_token(self):
        with tempfile.TemporaryDirectory() as tmp:
            tracker = load_tracker(Path(tmp) / "downloads.sqlite3")
            self.assertTrue(tracker.authorized({"token": ["test-secret"]}, {}))
            self.assertFalse(tracker.authorized({"token": ["wrong"]}, {}))
            self.assertTrue(tracker.authorized({}, {"Authorization": "Bearer test-secret"}))

    def test_download_redirect_records_before_redirecting(self):
        with tempfile.TemporaryDirectory() as tmp:
            tracker = load_tracker(Path(tmp) / "downloads.sqlite3")
            handler = tracker.DownloadTrackerHandler.__new__(tracker.DownloadTrackerHandler)
            handler.path = "/d/lucy?source=install-page"
            handler.headers = FakeHandler.headers
            handler.client_address = FakeHandler.client_address
            responses = []
            headers = []

            handler.send_response = responses.append
            handler.send_header = lambda key, value: headers.append((key, value))
            handler.end_headers = mock.Mock()

            handler.do_GET()

            self.assertEqual(responses, [302])
            self.assertTrue(any(key == "Location" and "Lucy-v0.1-beta.zip" in value for key, value in headers))
            self.assertEqual(tracker.fetch_stats()["total"], 1)


if __name__ == "__main__":
    unittest.main()