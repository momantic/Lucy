import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "build_lucy_app.sh"


class SingleLucyAppPolicyTests(unittest.TestCase):
    def test_build_script_installs_one_canonical_user_app(self):
        text = BUILD_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('CANONICAL_APP="${LUCY_APP_PATH:-$HOME/Applications/Lucy.app}"', text)
        self.assertIn('APP_PARENT_DIR="$(dirname "$CANONICAL_APP")"', text)
        self.assertIn('rm -rf "$CANONICAL_APP"', text)
        self.assertIn('swift_app/Sources/*.swift \\', text)
        self.assertIn('-o "$ARCH_OUTPUT"', text)
        self.assertIn('lipo -create "${ARCH_OUTPUTS[@]}" -output "$CANONICAL_APP/Contents/MacOS/Lucy"', text)
        self.assertIn('codesign --force --sign "${LUCY_CODESIGN_IDENTITY:--}" "$CANONICAL_APP"', text)
        self.assertNotIn("STAGING_APP=", text)
        self.assertIn("Built Lucy app", text)


if __name__ == "__main__":
    unittest.main()