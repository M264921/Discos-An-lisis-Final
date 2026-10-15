import os
from pathlib import Path
import subprocess
import sys
import unittest


class EntrypointTests(unittest.TestCase):
    def test_package_and_cli_module_offer_help_without_api_calls(self):
        root = Path(__file__).resolve().parents[1]
        env = {**os.environ, "PYTHONPATH": str(root / "src")}
        for module in ("discos_analisis", "discos_analisis.cli.enrich"):
            result = subprocess.run([sys.executable, "-m", module, "--help"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("usage:", result.stdout.lower())


    def test_invalid_arguments_return_nonzero_through_both_entrypoints(self):
        root = Path(__file__).resolve().parents[1]
        env = {**os.environ, "PYTHONPATH": str(root / "src")}
        for module in ("discos_analisis", "discos_analisis.cli.enrich"):
            result = subprocess.run([sys.executable, "-m", module, "--definitely-invalid"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
