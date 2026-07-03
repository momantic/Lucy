import os
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "lucy_linkedin_direct.sh"


class LinkedInDirectScriptTests(unittest.TestCase):
    def test_script_contains_non_extension_research_fallbacks(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("linkedin_research_to_file_auto.sh", text)
        self.assertIn("read_linkedin_chrome_window_text.sh", text)

    def test_script_prefers_structured_browser_bridge_linkedin_posts(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("linkedin_posts_text", text)
        self.assertIn("Using structured LinkedIn post capture", text)
        self.assertIn("Do not invent names, companies, dates, sources, metrics", text)

    def test_mocked_run_uses_non_extension_fallback_when_bridge_is_weak(self):
        env = os.environ.copy()
        env["LUCY_TEST_SKIP_MLX"] = "1"
        env["LUCY_TEST_BRIDGE_TEXT"] = "too short"
        env["LUCY_TEST_APPLESCRIPT_TEXT"] = "LinkedIn post one about AI agents. LinkedIn post two about risk controls. LinkedIn post three about traders using copilots. LinkedIn post four about audit trails. LinkedIn post five about execution guardrails."
        result = subprocess.run(
            [str(SCRIPT), "write me a linkedin post about AI agents in stocks"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            env=env,
            timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("Browser Bridge research was weak", result.stdout)
        self.assertIn("non-extension", result.stdout.lower())
        post = Path("/tmp/lucy_linkedin_post.txt").read_text(encoding="utf-8")
        self.assertIn("AI agents", post)


if __name__ == "__main__":
    unittest.main()