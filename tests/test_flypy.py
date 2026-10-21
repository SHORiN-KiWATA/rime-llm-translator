import contextlib
import http.server
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


def load_config_tool():
    loader = importlib.machinery.SourceFileLoader("rime_llm_config_test", str(ROOT / "src/rime-llm-config"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class FlypyTranslationTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("lua") and shutil.which("curl"), "requires Lua and curl")
    def test_lua_conversion_and_backends(self):
        requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                requests.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
                response = json.dumps({"choices": [{"message": {"content": "你好"}}]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(response)))
                self.end_headers()
                self.wfile.write(response)

            def log_message(self, *args):
                pass

        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with tempfile.TemporaryDirectory() as temp:
                    config = Path(temp) / "config.lua"
                    config.write_text("""
flypy_test_config = {
    active_profile = "http", ai_trigger = "vv", miyu_prefix = "miyu:",
    prompt_core = "Convert pinyin to Chinese.", reply_cache_disk = false,
    tmp_dirs = { %s },
    profiles = {
        http = { name = "Offline HTTP", protocol = "openai-chat", model = "test",
            api_key = "offline", api_url = "http://127.0.0.1:%d/v1" },
        cli = { name = "Offline CLI", protocol = "codex", model = "test" },
    },
}
return flypy_test_config
""" % (json.dumps(temp), server.server_port), encoding="utf-8")
                    env = {**os.environ, "RIME_LLM_CONFIG_DIR": temp}
                    env.pop("RIME_LLM_TRACE", None)
                    result = subprocess.run(
                        ["lua", "tests/test_flypy.lua"], cwd=ROOT, env=env,
                        text=True, capture_output=True, timeout=30,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            finally:
                server.shutdown()
                thread.join(timeout=5)
        self.assertEqual(len(requests), 2, requests)
        self.assertEqual(requests[0]["messages"][-1]["content"], "ni hao")
        self.assertEqual(requests[1]["messages"][-1]["content"], "nihao")


class FlypyInitializationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tool = load_config_tool()

    def test_detect_user_build_and_system_schemas(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            user, system = root / "rime", root / "system"
            user.mkdir()
            system.mkdir()
            schema = "double_pinyin_flypy"
            self.assertFalse(self.tool.schema_installed(str(user), schema, system_dirs=[]))
            for parent in (user, user / "build", system):
                parent.mkdir(exist_ok=True)
                path = parent / (schema + ".schema.yaml")
                path.write_text("schema: {}\n", encoding="utf-8")
                self.assertTrue(self.tool.schema_installed(str(user), schema, system_dirs=[str(system)]))
                path.unlink()

    def test_patch_preserves_settings_and_is_idempotent(self):
        for schema in self.tool.SUPPORTED_SCHEMAS:
            with self.subTest(schema=schema):
                original = '# user configuration\npatch:\n  "menu/page_size": 9\n'
                content, status = self.tool.merge_schema_patch(original, schema)
                self.assertEqual(status, "appended")
                self.assertIn('"menu/page_size": 9', content)
                for _, key, _ in self.tool.schema_patch_entries(schema):
                    self.assertEqual(content.count('"' + key + '":'), 1, content)
                again, status = self.tool.merge_schema_patch(content, schema)
                self.assertEqual(again, content)
                self.assertEqual(status, "skipped")

    def test_old_patch_is_upgraded_for_flypy(self):
        content = 'patch:\n  "menu/page_size": 9\n' + self.tool.PATCH_CONTENT
        merged, status = self.tool.merge_schema_patch(content, "double_pinyin_flypy")
        self.assertEqual(status, "upgraded")
        self.assertIn('"menu/page_size": 9', merged)
        self.assertIn('"llm_translator/input_scheme": "flypy"', merged)
        self.assertIn('"llm_translator/trigger": ";;"', merged)
        alphabet = next(line for line in merged.splitlines() if '"speller/alphabet"' in line)
        pattern = next(line for line in merged.splitlines() if '"recognizer/patterns/llm_pinyin"' in line)
        self.assertIn(";", alphabet)
        self.assertIn(";", pattern)
        self.assertEqual(self.tool.merge_schema_patch(merged, "double_pinyin_flypy"), (merged, "skipped"))

    def test_flypy_disables_mint_input_limit_on_install_and_upgrade(self):
        schema = "double_pinyin_flypy"
        unlimited = '  "codeLengthLimit_processor": null\n'
        generated = self.tool.render_schema_patch_file(schema)
        self.assertIn(unlimited, generated)
        self.assertNotIn("codeLengthLimit_processor", self.tool.render_schema_patch_file("rime_ice"))
        for existing in (
            'patch:\n  "llm_translator/input_scheme": "flypy"\n  "menu/page_size": 9\n',
            'patch:\n  "llm_translator/input_scheme": "flypy"\n  "menu/page_size": 9\n  "codeLengthLimit_processor": 25\n',
        ):
            with self.subTest(existing=existing):
                merged, status = self.tool.merge_schema_patch(existing, schema)
                self.assertEqual(status, "upgraded")
                self.assertIn(unlimited, merged)
                self.assertEqual(merged.count('"codeLengthLimit_processor":'), 1)
                self.assertIn('"menu/page_size": 9', merged)
                self.assertEqual(self.tool.merge_schema_patch(merged, schema), (merged, "skipped"))

    def test_patch_handles_scalar_quotes_and_comments(self):
        for key, value, expected in (
            ('"speller/alphabet"', '"abc"', '"abc;"'),
            ("'speller/alphabet'", "'abc'", "'abc;'"),
            ('"speller/alphabet"', 'abc', 'abc;'),
        ):
            with self.subTest(key=key, value=value):
                original = f'patch:\n    {key}: {value} # trigger ; belongs in the value\n'
                merged, _ = self.tool.merge_schema_patch(original, "double_pinyin_flypy")
                self.assertIn(f'{key}: {expected} # trigger ; belongs in the value', merged)
                self.assertIn('    "llm_translator/trigger": ";;"', merged)
                self.assertEqual(self.tool.merge_schema_patch(merged, "double_pinyin_flypy"), (merged, "skipped"))

    def test_patch_stays_in_its_own_top_level_block(self):
        original = 'patch:\n    "menu/page_size": 9\nother:\n  "llm_translator/trigger": "unrelated"\n'
        merged, _ = self.tool.merge_schema_patch(original, "double_pinyin_flypy")
        self.assertIn('    "llm_translator/trigger": ";;"\n', merged)
        self.assertTrue(merged.endswith('other:\n  "llm_translator/trigger": "unrelated"\n'))
        self.assertEqual(self.tool.merge_schema_patch(merged, "double_pinyin_flypy"), (merged, "skipped"))
        for empty in ('# llm_translator configuration\n', 'patch: {}\n'):
            merged, _ = self.tool.merge_schema_patch(empty, "double_pinyin_flypy")
            self.assertEqual(merged.count("patch:"), 1)
            self.assertIn('"llm_translator/input_scheme": "flypy"', merged)

    def test_explicit_scheme_and_trigger_survive_reinitialization(self):
        original = self.tool.render_schema_patch_file("double_pinyin_flypy")
        original = original.replace('"llm_translator/trigger": ";;"', '"llm_translator/trigger": "!!"')
        original = original.replace('"llm_translator/input_scheme": "flypy"', '"llm_translator/input_scheme": "pinyin"')
        self.assertEqual(self.tool.merge_schema_patch(original, "double_pinyin_flypy"), (original, "skipped"))

    def test_init_configures_flypy_without_full_pinyin(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "double_pinyin_flypy.schema.yaml").write_text("schema: {}\n", encoding="utf-8")
            detect = self.tool.schema_installed
            with contextlib.ExitStack() as stack:
                stack.enter_context(mock.patch.object(self.tool, "schema_installed", side_effect=lambda directory, schema: detect(directory, schema, system_dirs=[])))
                stack.enter_context(mock.patch.object(self.tool, "load_state", return_value={"settings": {"ai_trigger": "vv"}}))
                stack.enter_context(mock.patch.object(self.tool, "save_state"))
                restart = stack.enter_context(mock.patch.object(self.tool, "restart_fcitx5"))
                backup = stack.enter_context(mock.patch.object(self.tool, "backup_file"))
                output = stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
                self.tool.init_rime_config(str(root))
                patch = root / "double_pinyin_flypy.custom.yaml"
                first = patch.read_text(encoding="utf-8")
                self.assertFalse((root / "rime_ice.custom.yaml").exists())
                self.assertIn("test;;", output.getvalue())
                self.assertIn("nihcuijp;;", output.getvalue())
                self.tool.init_rime_config(str(root))
                self.assertEqual(patch.read_text(encoding="utf-8"), first)
                self.assertEqual((root / "rime.lua").read_text().count("llm_processor ="), 1)
                backup.assert_not_called()
                self.assertEqual(restart.call_count, 2)


if __name__ == "__main__":
    unittest.main()
