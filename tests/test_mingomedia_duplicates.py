"""Synthetic duplicate groups only. Native Recycle Bin fixture is opt-in on CI."""
from dataclasses import replace
import gzip
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest import mock

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import mingomedia_duplicates as duplicates
from mingomedia_core import Cancelled, Drive, inventory_authorizer, scan
from mingomedia_duplicates import (apply_plans, find_duplicates, make_plan, recommend, summary)
from mingomedia_recycle import protected_read, recycle_file


@unittest.skipUnless(os.name=='nt','Windows protected file handles')
class DuplicateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='MingoMedia-fixture-')
        self.base = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        # Fixtures live in the test runner's Temp/.codex, not user scan roots.
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(duplicates,'SECRET_DIRS',duplicates.SECRET_DIRS- {'.codex'}).start()
        mock.patch.object(duplicates,'SYSTEM_DIRS',duplicates.SYSTEM_DIRS- {'appdata','temp'}).start()
        self.drives = []
        for letter,kind in [('C','Disco fijo'),('D','Externo / USB'),('E','Disco fijo')]:
            root = self.base/letter
            root.mkdir()
            self.drives.append(Drive(letter,root,kind=kind))
        self.bin = self.base/'synthetic-bin'
        self.bin.mkdir()

    def file(self, letter, name, content=b'identical content'):
        path = self.base/letter/name
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(content)
        return path

    def review(self):
        result = scan(self.drives,{'todos'},self.base/'scan',lambda value:None,threading.Event())
        groups,ignored = find_duplicates(result)
        return result,groups,ignored

    def fake_recycle(self,path):
        target = self.bin/(str(len(list(self.bin.iterdir())))+'-'+path.name)
        path.rename(target)
        return target

    def plan(self, group, letter='C'):
        return make_plan(group,next(copy.key for copy in group.copies if copy.drive==letter))

    def test_three_copies_keep_one_updates_private_inventory(self):
        paths = [self.file(letter,'Foto ñ.txt') for letter in 'CDE']
        result,groups,ignored = self.review()
        self.assertEqual((len(groups),ignored),(1,0))
        plan = self.plan(groups[0])
        self.assertEqual(len(plan.retire),2)
        calls = []
        def recycler(path):
            # Keeper cannot be modified or deleted even by another local process.
            with self.assertRaises(OSError):
                paths[0].unlink()
            with self.assertRaises(OSError):
                paths[0].write_bytes(b'damaged')
            calls.append(path)
            return self.fake_recycle(path)
        outcome = apply_plans(result,[plan],recycler=recycler)
        self.assertEqual((outcome.recycled,outcome.skipped,outcome.result.count),(2,0,1))
        self.assertEqual(paths[0].read_bytes(),b'identical content')
        self.assertTrue(all(not path.exists() for path in paths[1:]))
        self.assertEqual(len(calls),2)
        with gzip.open(result.folder/'data/inventory.json.gz','rt',encoding='utf-8') as stream:
            self.assertEqual([item['unidad'] for item in json.load(stream)],['C:'])
        allowed = inventory_authorizer(result.catalog)
        self.assertTrue(allowed(paths[0]))
        self.assertFalse(allowed(paths[1]))
        events = [json.loads(line)['event'] for line in outcome.journal.read_text(encoding='utf-8').splitlines()]
        self.assertEqual(events.count('recycled'),2)

    def test_same_name_different_content_and_empty_excluded(self):
        self.file('C','same.txt',b'abcd')
        self.file('D','same.txt',b'efgh')
        self.file('C','empty.txt',b'')
        self.file('D','empty.txt',b'')
        self.assertEqual(self.review()[1],())

    def test_recommend_fixed_then_preference_and_manual(self):
        self.file('C','Descargas/file (1).txt')
        self.file('D','file.txt')
        self.file('E','Documentos/file.txt')
        result,groups,_ = self.review()
        group = groups[0]
        self.assertEqual(recommend(group,self.drives)[0].drive,'E')
        self.assertEqual(recommend(group,self.drives,'D')[0].drive,'D')
        manual = self.plan(group,'C')
        self.assertEqual(manual.keep.drive,'C')
        text = summary([manual])
        self.assertIn('CONSERVAR [C:]',text)
        for letter in 'DE':
            self.assertIn(f'PAPELERA  [{letter}:]',text)

    def test_changed_keeper_blocks_entire_group(self):
        keep = self.file('C','keep.txt')
        other = self.file('D','other.txt')
        result,groups,_ = self.review()
        old = keep.stat()
        keep.write_bytes(b'X'*old.st_size)
        os.utime(keep,ns=(old.st_atime_ns,old.st_mtime_ns))
        recycler = mock.Mock()
        outcome = apply_plans(result,[self.plan(groups[0])],recycler=recycler)
        self.assertEqual((outcome.recycled,outcome.skipped),(0,1))
        recycler.assert_not_called()
        self.assertTrue(other.exists())

    def test_missing_keeper_blocks_group(self):
        keep = self.file('C','keep.txt')
        other = self.file('D','other.txt')
        result,groups,_ = self.review()
        keep.unlink()
        outcome = apply_plans(result,[self.plan(groups[0])],recycler=self.fake_recycle)
        self.assertEqual((outcome.recycled,outcome.skipped),(0,1))
        self.assertTrue(other.exists())

    def test_changed_candidate_kept_while_other_duplicate_recycled(self):
        self.file('C','keep.txt')
        changed = self.file('D','changed.txt')
        normal = self.file('E','normal.txt')
        result,groups,_ = self.review()
        changed.write_bytes(b'new content')
        outcome = apply_plans(result,[self.plan(groups[0])],recycler=self.fake_recycle)
        self.assertEqual((outcome.recycled,outcome.skipped),(1,1))
        self.assertTrue(changed.exists())
        self.assertFalse(normal.exists())

    def test_recycle_failure_has_no_delete_fallback(self):
        self.file('C','keep.txt')
        other = self.file('D','other.txt')
        result,groups,_ = self.review()
        outcome = apply_plans(result,[self.plan(groups[0])],recycler=mock.Mock(side_effect=OSError('Unsupported volume')))
        self.assertEqual((outcome.recycled,outcome.skipped),(0,1))
        self.assertTrue(other.exists())

    def test_cancellation_between_copies_preserves_keeper(self):
        keep = self.file('C','keep.txt')
        self.file('D','other.txt')
        self.file('E','third.txt')
        result,groups,_ = self.review()
        cancel = threading.Event()
        def recycler(path):
            target = self.fake_recycle(path)
            cancel.set()
            return target
        outcome = apply_plans(result,[self.plan(groups[0])],cancel=cancel,recycler=recycler)
        self.assertEqual(outcome.recycled,1)
        self.assertTrue(outcome.cancelled)
        self.assertTrue(keep.exists())
        self.assertEqual(outcome.result.count,2)

    def test_hardlinks_count_as_one_physical_copy(self):
        original = self.file('C','one.txt')
        os.link(original,self.base/'D/alias.txt')
        self.assertEqual(self.review()[1],())

    def test_forged_and_overlapping_plans_rejected_before_operations(self):
        self.file('C','one.txt')
        self.file('D','two.txt')
        result,groups,_ = self.review()
        plan = self.plan(groups[0])
        with self.assertRaises(ValueError):
            apply_plans(result,[plan,plan],recycler=self.fake_recycle)
        bad = replace(plan.keep,path=str(self.base/'not-in-inventory.txt'))
        group = replace(groups[0],copies=(bad,*plan.retire))
        with self.assertRaises(ValueError):
            apply_plans(result,[make_plan(group,bad.key)],recycler=self.fake_recycle)

    def test_secret_and_system_paths_excluded_from_review(self):
        self.file('C','windows/file.txt')
        self.file('D','windows/file.txt')
        self.file('C','.ssh/secret.txt')
        self.file('D','.ssh/secret.txt')
        result = scan(self.drives,{'todos'},self.base/'scan',lambda value:None,threading.Event(),personal=False)
        self.assertEqual(find_duplicates(result)[0],())

    def test_cancelled_detection_never_changes_originals(self):
        path = self.file('C','one.txt')
        self.file('D','two.txt')
        result = scan(self.drives,{'todos'},self.base/'scan',lambda value:None,threading.Event())
        cancel = threading.Event();cancel.set()
        with self.assertRaises(Cancelled):
            find_duplicates(result,cancel=cancel)
        self.assertEqual(path.read_bytes(),b'identical content')

    def test_review_ui_marking_and_manual_keeper_survive_preference(self):
        import tkinter as tk
        from mingomedia_desktop import MingoMediaApp
        from mingomedia_duplicates_ui import DuplicateReview
        self.file('C','one.txt')
        self.file('D','two.txt')
        result,groups,_ = self.review()
        root = tk.Tk();root.withdraw()
        app = MingoMediaApp(root,autodetect=False)
        app.result = result;app.drives = self.drives;app.selected = {'C','D','E'}
        dialog = DuplicateReview(app,autostart=False)
        dialog.window.withdraw()
        try:
            dialog.load_groups(groups)
            self.assertEqual(dialog.plans(),())
            dialog.select_all(True)
            self.assertEqual(len(dialog.plans()),1)
            dialog.tree.selection_set('0');dialog.show_copies()
            index = next(index for index,copy in enumerate(groups[0].copies) if copy.drive=='D')
            dialog.copies.selection_set(str(index));dialog.choose_keeper()
            dialog.preferred.set('C: · Disco fijo');dialog.choose_preference()
            self.assertEqual(dialog.plans()[0].keep.drive,'D')
            dialog.select_all(False)
            self.assertEqual(dialog.plans(),())
        finally:
            dialog.destroy();app.closed=True;root.destroy()

    @unittest.skipUnless(os.environ.get('MINGOMEDIA_RECYCLE_TEST')=='1','Synthetic native recycle fixture on Windows CI only')
    def test_native_recycle_only_with_protected_keeper(self):
        keep = self.file('C','keeper-native.txt',b'native recycle fixture')
        candidate = self.file('D','MingoMedia-native-fixture.txt',b'native recycle fixture')
        with protected_read(keep):
            with protected_read(candidate,allow_recycle=True):
                destination = recycle_file(candidate)
            self.assertTrue(keep.exists())
            self.assertFalse(candidate.exists())
            self.assertTrue(destination)
            self.assertTrue(Path(destination).is_file())
            self.assertEqual(Path(destination).read_bytes(),b'native recycle fixture')


if __name__=='__main__':
    unittest.main()
