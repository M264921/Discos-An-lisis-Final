"""Regression fixtures never reference real media or mounted-drive inventories."""
import csv
import hashlib
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('cleanup', ROOT / 'tools/remove_nonmedia_duplicates.py')
cleanup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cleanup)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='mingo-cleaner-test-')).resolve()
        self.csv = self.root / 'duplicates.csv'
        self.log = self.root / 'logs/result.csv'

    def tearDown(self):
        assert self.root.parent == Path(tempfile.gettempdir()).resolve()
        assert self.root.name.startswith('mingo-cleaner-test-')
        shutil.rmtree(self.root)

    def fixtures(self, names=('a.db', 'b.db'), data=b'same'):
        files = [self.root / name for name in names]
        for file in files:
            file.write_bytes(data)
        with self.csv.open('w', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=['Path', 'Hash'])
            writer.writeheader()
            writer.writerows({'Path': str(file), 'Hash': hashlib.sha256(data).hexdigest()} for file in files)
        return files

    def test_preview_never_deletes_and_apply_keeps_one(self):
        files = self.fixtures()
        self.assertEqual(cleanup.remove_paths(self.csv, self.log), 1)
        self.assertTrue(all(p.exists() for p in files))
        self.assertEqual(cleanup.remove_paths(self.csv, self.log, apply=True), 1)
        self.assertEqual(sum(p.exists() for p in files), 1)
        self.assertEqual(cleanup.remove_paths(self.csv, self.log, apply=True), 0)

    def test_stale_hash_and_missing_keeper_cannot_delete_last_copy(self):
        files = self.fixtures()
        files[0].write_bytes(b'changed')
        self.assertEqual(cleanup.remove_paths(self.csv, self.log, apply=True), 0)
        self.assertTrue(files[1].exists())
        files[0].unlink()
        self.assertEqual(cleanup.remove_paths(self.csv, self.log, apply=True), 0)

    def test_media_keeper_preserved(self):
        files = self.fixtures(('movie.mp4', 'cache.db'))
        self.assertEqual(cleanup.remove_paths(self.csv, self.log, apply=True), 1)
        self.assertTrue(files[0].exists())
        self.assertFalse(files[1].exists())

    def test_cleaner_none_and_dryrun_do_not_call_legacy_mover(self):
        files = self.fixtures()
        tools = self.root / 'tools'
        (tools / 'agents').mkdir(parents=True)
        shutil.copy2(ROOT / 'tools/remove_nonmedia_duplicates.py', tools)
        shutil.copy2(ROOT / 'tools/agents/inventory-cleaner.ps1', tools / 'agents')
        (tools / 'Move-I-Duplicates.ps1').write_text("throw 'Legacy mover invoked'", encoding='ascii')
        for mode in ('None', 'DryRun'):
            result = subprocess.run(['pwsh', '-NoProfile', '-File', str(tools / 'agents/inventory-cleaner.ps1'),
                                     '-RepoRoot', str(self.root), '-DupesCsv', self.csv.name, '-SweepMode', mode],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(all(p.exists() for p in files))
        result = subprocess.run(['pwsh', '-NoProfile', '-File', str(tools / 'agents/inventory-cleaner.ps1'),
                                 '-RepoRoot', str(self.root), '-DupesCsv', self.csv.name, '-SweepMode', 'Apply'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(sum(p.exists() for p in files), 1)


if __name__ == '__main__':
    unittest.main()
