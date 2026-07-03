import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SWIFT = ROOT / "swift_app" / "Sources" / "ChatWindowController.swift"
GOAL_ENGINE = ROOT / "tools" / "lucy_goal_engine.py"


class InAppLinkedInRouteTests(unittest.TestCase):
    def test_swift_has_dedicated_linkedin_route_before_self_loop(self):
        text = SWIFT.read_text(encoding="utf-8")
        route_call = text.index("if routeLinkedInPostDraft(userText)")
        self_loop = text.index('append("Lucy: I understand this as a task, so I am using my MLX self-loop.')
        self.assertLess(route_call, self_loop)
        self.assertIn("func looksLikeLinkedInPostDraftRequest", text)
        self.assertIn("lucy_linkedin_direct.py", text)

    def test_goal_engine_linkedin_route_no_name_error_in_test_mode(self):
        env = {
            "LUCY_TEST_SKIP_MLX": "1",
            "LUCY_TEST_BRIDGE_TEXT": "too short",
            "LUCY_TEST_APPLESCRIPT_TEXT": "LinkedIn post one about AI agents. LinkedIn post two about risk controls. LinkedIn post three about traders using copilots. LinkedIn post four about audit trails. LinkedIn post five about execution guardrails.",
        }
        result = subprocess.run(
            ["python3", str(GOAL_ENGINE), "write me a LinkedIn post about AI agents in stocks"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            env={**env, **__import__("os").environ},
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn('"mode": "lucy_linkedin_direct_v2"', result.stdout)
        self.assertIn("LINKEDIN DRAFT", result.stdout)


if __name__ == "__main__":
    unittest.main()