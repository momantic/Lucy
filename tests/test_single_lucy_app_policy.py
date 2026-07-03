import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "build_lucy_app.sh"


class SingleLucyAppPolicyTests(unittest.TestCase):
    def test_build_script_installs_one_canonical_user_app(self):
        text = BUILD_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('CANONICAL_APP="$HOME/Applications/Lucy.app"', text)
        self.assertIn('rm -rf "$CANONICAL_APP"', text)
        self.assertIn('swiftc swift_app/Sources/*.swift -o "$CANONICAL_APP/Contents/MacOS/Lucy"', text)
        self.assertIn('rm -rf "$ROOT/dist/Lucy.app" "$ROOT/release/Lucy-v0.1-beta/Lucy.app"', text)
        self.assertNotIn("STAGING_APP=", text)
        self.assertIn("Built canonical Lucy app", text)


if __name__ == "__main__":
    unittest.main()