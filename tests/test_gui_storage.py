import gzip
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class GuiStorageTests(unittest.TestCase):
    def load_module(self):
        spec = importlib.util.spec_from_file_location('gui', ROOT / 'tools/MingoMedia_inventory_gui.py')
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {'PySimpleGUI': SimpleNamespace(Window=object)}):
            spec.loader.exec_module(module)
        return module

    def test_gui_uses_repo_root_and_separate_schema_directory(self):
        module = self.load_module()
        self.assertEqual(module.ROOT, ROOT)
        self.assertEqual(module.INVENTORY_GZ, ROOT / 'data/gui/inventory.json.gz')

    def test_corrupt_inventory_refuses_silent_replacement_and_atomic_save(self):
        module = self.load_module()
        with tempfile.TemporaryDirectory(prefix='mingo-gui-test-') as temp:
            module.DATA_DIR = Path(temp)
            module.INVENTORY_GZ = Path(temp) / 'inventory.json.gz'
            module.INVENTORY_GZ.write_bytes(b'corrupt')
            with self.assertRaises(ValueError):
                module.load_inventory()
            self.assertEqual(module.INVENTORY_GZ.read_bytes(), b'corrupt')
            module.save_inventory({'items': [{'path': 'fixture'}]})
            self.assertEqual(module.load_inventory()['items'][0]['path'], 'fixture')
            self.assertEqual(list(Path(temp).glob('*.tmp')), [])


if __name__ == '__main__':
    unittest.main()
