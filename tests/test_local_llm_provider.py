import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class LucyLocalLLMProviderTests(unittest.TestCase):
    def test_model_provider_config_supports_auto_intel_fallback(self):
        config = json.loads((ROOT / "data" / "model_provider.json").read_text())
        self.assertEqual(config["provider"], "auto")
        self.assertEqual(config["apple_silicon_provider"], "mlx")
        self.assertIn(config["intel_provider"], {"llamacpp", "llama_cpp", "llama-cpp"})
        self.assertIn("llamacpp_chat_model_path", config)
        self.assertFalse(config.get("allow_cloud", True))

    def test_architecture_provider_routing(self):
        import sys

        sys.path.insert(0, str(ROOT / "tools" / "providers"))
        import local_llm  # type: ignore

        config = {
            "provider": "auto",
            "apple_silicon_provider": "mlx",
            "intel_provider": "llamacpp",
        }
        self.assertEqual(local_llm.resolve_provider(config, arch="arm64"), "mlx")
        self.assertEqual(local_llm.resolve_provider(config, arch="x86_64"), "llamacpp")

    def test_swift_local_llm_launchers_honor_python_override(self):
        chat = (ROOT / "swift_app" / "Sources" / "ChatWindowController.swift").read_text()
        router = (ROOT / "swift_app" / "Sources" / "LucyMLXIntentRouter.swift").read_text()
        self.assertIn('ProcessInfo.processInfo.environment["PYTHON"] ?? "python3"', chat)
        self.assertIn('ProcessInfo.processInfo.environment["PYTHON"] ?? "python3"', router)
        self.assertIn('"tools/providers/local_llm.py"', chat)
        self.assertIn('"tools/providers/local_llm.py"', router)

    def test_autonomous_dev_uses_auto_local_provider_not_mlx_model_argument(self):
        text = (ROOT / "tools" / "lucy_autonomous_dev.py").read_text()
        self.assertIn("def call_local_llm(", text)
        self.assertIn('"auto/local"', text)
        self.assertNotIn("def call_mlx_lm(", text)

    def test_active_code_uses_provider_abstraction_for_generation(self):
        allowed = {"tools/providers/local_llm.py"}
        offenders = []
        for base in [ROOT / "swift_app" / "Sources", ROOT / "tools", ROOT / "tools_created_by_lucy"]:
            for path in base.rglob("*"):
                if not path.is_file():
                    continue
                rel = str(path.relative_to(ROOT))
                if ".bak" in path.name or "before_" in path.name or rel in allowed:
                    continue
                if path.suffix not in {".py", ".sh", ".swift"}:
                    continue
                text = path.read_text(errors="ignore")
                direct_invocation = (
                    "-m mlx_lm" in text
                    or "mlx_lm generate" in text
                    or "mlx_lm.generate" in text
                )
                if direct_invocation:
                    offenders.append(rel)
        self.assertEqual(offenders, [], "Direct mlx_lm invocations should live only in tools/providers/local_llm.py")

    def test_intel_setup_docs_exist(self):
        self.assertTrue((ROOT / "tools" / "setup_local_llm_intel.sh").exists())
        self.assertTrue((ROOT / "docs" / "intel-mac-local-llm.md").exists())


if __name__ == "__main__":
    unittest.main()