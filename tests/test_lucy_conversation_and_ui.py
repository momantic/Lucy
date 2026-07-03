import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = ROOT / "swift_app" / "Sources" / "ChatWindowController.swift"
BUILD_SCRIPT = ROOT / "build_lucy_app.sh"
APP_DELEGATE = ROOT / "swift_app" / "Sources" / "AppDelegate.swift"


class LucyConversationAndUITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.chat = CHAT.read_text(encoding="utf-8")
        cls.build_script = BUILD_SCRIPT.read_text(encoding="utf-8")
        cls.app_delegate = APP_DELEGATE.read_text(encoding="utf-8")

    def _function_body(self, name: str) -> str:
        match = re.search(rf"func {re.escape(name)}\([^)]*\).*?\{{", self.chat)
        self.assertIsNotNone(match, f"Missing function {name}")
        start = match.end()
        depth = 1
        i = start
        while i < len(self.chat) and depth:
            if self.chat[i] == "{":
                depth += 1
            elif self.chat[i] == "}":
                depth -= 1
            i += 1
        self.assertEqual(depth, 0, f"Could not parse function body for {name}")
        return self.chat[start : i - 1]

    def test_natural_command_router_is_typo_tolerant_without_slashes(self):
        body = self._function_body("routeNaturalCommand")

        # Commands should be normalized once, not handled only by exact strings or /commands.
        self.assertIn("normalizedForIntent", body)
        self.assertIn("correctCommonTypos", body)
        self.assertIn("levenshteinDistance", body)

        # Common typo examples users actually type should be understood.
        for typo in ["opne", "serach", "searfch", "yotube", "you tube", "googel", "chorme", "safair"]:
            self.assertIn(typo, body)

        # Natural phrases should route directly to actions, without requiring slash commands.
        for phrase in ["open google", "search youtube for", "use chrome", "use safari", "find me"]:
            self.assertIn(phrase, body)

    def test_general_action_router_understands_typoed_natural_prompts(self):
        body = self._function_body("shouldRouteToAgentLoop")
        self.assertIn("normalizedForIntent", body)
        for typo in ["opne", "serach", "wrtie", "emial", "mesage", "summrize", "anaylze"]:
            self.assertIn(typo, body)

    def test_all_natural_request_routers_share_typo_normalization(self):
        for function_name in [
            "registryToolBaseForNaturalRequest",
            "looksLikeNoteRequest",
            "looksLikeCalendarRequest",
            "looksLikeReminderRequest",
            "unsupportedCapabilityResponse",
            "shouldRouteToAgentLoop",
        ]:
            body = self._function_body(function_name)
            self.assertIn(
                "normalizedForIntent",
                body,
                f"{function_name} should interpret typoed everyday prompts through shared normalization",
            )

    def test_typo_corrector_covers_everyday_prompt_wording(self):
        body = self._function_body("correctCommonTypos")

        # These examples cover common prompt meaning words, not only browser/search commands.
        for typo in [
            "pleaze",
            "ntoe",
            "nots",
            "shcedule",
            "schedual",
            "remidn",
            "remeber",
            "mesage",
            "adress",
        ]:
            self.assertIn(typo, body)

        # Phrase-level corrections help Lucy interpret the message instead of a single token.
        for phrase in ["remind me", "set reminder", "thank you"]:
            self.assertIn(phrase, body)

    def test_chat_window_has_polished_layout_and_no_command_wall(self):
        self.assertIn("NSVisualEffectView", self.chat)
        self.assertIn("LucyHeaderView", self.chat)
        self.assertIn("Start typing naturally", self.chat)
        self.assertIn("I understand natural requests", self.chat)

        intro_match = re.search(r'output\.string = """(.*?)"""', self.chat, re.S)
        self.assertIsNotNone(intro_match)
        intro_text = intro_match.group(1)
        self.assertNotIn("Useful commands:", intro_text)
        self.assertNotIn("/memory", intro_text)
        self.assertNotIn("/autodev", intro_text)

    def test_app_bundle_copies_lucy_picture_icon_and_resources(self):
        self.assertIn("lucy-store-icon.png", self.build_script)
        self.assertIn("CFBundleIconFile", self.build_script)
        self.assertIn("LucyStoreIcon", self.build_script)
        self.assertIn("cp -R assets", self.build_script)
        self.assertIn("cp -R data", self.build_script)

    def test_app_startup_uses_visible_default_picture_mode(self):
        self.assertIn('UserDefaults.standard.register(defaults: ["lucy.use3DSprites": true', self.app_delegate)
        self.assertIn("petView.loadSpriteFrames()", self.app_delegate)


if __name__ == "__main__":
    unittest.main()