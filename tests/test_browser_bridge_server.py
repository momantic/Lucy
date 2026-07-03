import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "browser_bridge" / "server.py"


def load_server():
    spec = importlib.util.spec_from_file_location("browser_bridge_server", SERVER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BrowserBridgeServerTests(unittest.TestCase):
    def test_targeted_linkedin_command_is_not_consumed_by_non_linkedin_tab(self):
        server = load_server()
        old_commands = list(server.STATE["commands"])
        try:
            server.STATE["commands"] = [{"type": "read_page", "target_url_contains": "linkedin.com"}]
            self.assertIsNone(server.pop_next_command("https://example.com"))
            self.assertEqual(len(server.STATE["commands"]), 1)

            cmd = server.pop_next_command("https://www.linkedin.com/search/results/content/?keywords=ai")
            self.assertEqual(cmd, {"type": "read_page", "target_url_contains": "linkedin.com"})
            self.assertEqual(server.STATE["commands"], [])
        finally:
            server.STATE["commands"] = old_commands

    def test_untargeted_commands_remain_backward_compatible(self):
        server = load_server()
        old_commands = list(server.STATE["commands"])
        try:
            server.STATE["commands"] = [{"type": "read_page"}]
            self.assertEqual(server.pop_next_command("https://example.com"), {"type": "read_page"})
            self.assertEqual(server.STATE["commands"], [])
        finally:
            server.STATE["commands"] = old_commands


if __name__ == "__main__":
    unittest.main()