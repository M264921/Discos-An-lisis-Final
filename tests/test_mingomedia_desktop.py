"""Synthetic wizard service and selection-isolation tests; never scan real drives."""
import gzip
import hashlib
import http.client
import importlib
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlencode, urlsplit

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
core = importlib.import_module('mingomedia_core')


class DesktopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mingo-desktop-test-')
        self.base = Path(self.temp.name)
        self.input = self.base/'input'
        self.input.mkdir()
        for name,data in (('Foto Ñ.JPG',b'fake image'),('Video.mp4',b'video'),('Documento.pdf',b'PDF'),
                          ('Sonido.mp3',b'audio'),('script.py',b'code'),('.env',b'secret'),('key.p12',b'secret')):
            (self.input/name).write_bytes(data)
        for name in ('.ssh','Windows','AppData','node_modules'):
            (self.input/name).mkdir()
            (self.input/name/'secret.jpg').write_bytes(b'private or system')
        self.drive = core.Drive('C',self.input)
        self.cancel = threading.Event()
        self.events = []

    def tearDown(self):
        self.temp.cleanup()

    def scan(self,types,**options):
        return core.scan([self.drive],types,self.base/'result',self.events.append,self.cancel,**options)

    def records(self,result):
        with gzip.open(result.folder/'data/inventory.json.gz','rt',encoding='utf-8') as stream:
            return json.load(stream)

    def test_combinable_filters_and_all_types(self):
        self.assertTrue(core.include_file('a.JPG',{'imagenes','documentos'}))
        self.assertTrue(core.include_file('a.pdf',{'imagenes','documentos'}))
        self.assertFalse(core.include_file('a.mp4',{'imagenes','documentos'}))
        self.assertTrue(core.include_file('a.mp4',{'videos','documentos'}))
        self.assertTrue(core.include_file('a.py',{'todos'}))
        self.assertTrue(core.include_file('a.py',{'otros'}))

    def test_all_never_includes_credential_files(self):
        for name in ('.env','.env.production','id_rsa','id_ed25519','credentials.json','tokens.json','cert.pfx','key.pem'):
            self.assertFalse(core.include_file(name,{'todos'}),name)

    def test_scan_preserves_original_names_and_does_not_modify_sources(self):
        before = {str(p.relative_to(self.input)):p.read_bytes() for p in self.input.rglob('*') if p.is_file()}
        result = self.scan({'imagenes','documentos'})
        records = self.records(result)
        self.assertEqual({r['nombre'] for r in records},{'Foto Ñ.JPG','Documento.pdf'})
        self.assertEqual(result.count,2)
        self.assertEqual({str(p.relative_to(self.input)):p.read_bytes() for p in self.input.rglob('*') if p.is_file()},before)
        self.assertFalse((result.folder/'data/inventory.json').exists())
        self.assertEqual(records[0]['unidad'],'C:')
        self.assertTrue(all(r['sha']=='' for r in records))
        self.assertEqual(self.events[0]['phase'],'discover')
        self.assertEqual(self.events[-1],{'phase':'done','processed':2,'total':2,'skipped':0})

    def test_hash_option_and_authorizer(self):
        result = self.scan({'documentos'},hashes=True)
        self.assertEqual(self.records(result)[0]['sha'],hashlib.sha256(b'PDF').hexdigest())
        allowed = core.inventory_authorizer(result.catalog)
        self.assertTrue(allowed(self.input/'Documento.pdf'))
        self.assertFalse(allowed(self.input/'Video.mp4'))
        self.assertFalse(allowed(self.input/'key.p12'))

    def test_system_filter_is_optional_and_credentials_remain_excluded(self):
        result = self.scan({'imagenes'},personal=False)
        records = self.records(result)
        self.assertEqual(result.count,4)
        self.assertFalse(any('.ssh' in r['ruta'] for r in records))

    def test_cancel_never_publishes_partial_inventory(self):
        self.cancel.set()
        with self.assertRaises(core.Cancelled):
            self.scan({'todos'})
        self.assertFalse((self.base/'result/data/inventory.json.gz').exists())
        self.assertFalse((self.base/'result/data/inventory.json.gz.tmp').exists())

    def test_empty_selection_and_missing_drive_fail(self):
        with self.assertRaises(ValueError):
            self.scan(set())
        with self.assertRaises(OSError):
            core.scan([core.Drive('Z',self.base/'absent')],{'todos'},self.base/'result',self.events.append,self.cancel)

    def test_old_inventory_is_never_overwritten(self):
        result = self.scan({'documentos'})
        old = (result.folder/'data/inventory.json.gz').read_bytes()
        with self.assertRaises(ValueError):
            core.scan([self.drive],{'todos'},result.folder,self.events.append,self.cancel)
        self.assertEqual((result.folder/'data/inventory.json.gz').read_bytes(),old)

    def test_scan_output_inside_input_is_excluded(self):
        result = core.scan([self.drive],{'todos'},self.input/'our-output',self.events.append,self.cancel,personal=False)
        self.assertFalse(any('our-output' in r['ruta'] for r in self.records(result)))

    def test_logical_drive_paths_are_preserved_when_the_root_is_an_alias(self):
        alias = self.base/'mapped-volume'
        try:
            alias.symlink_to(self.input,target_is_directory=True)
        except OSError:
            self.skipTest('Creating a synthetic directory alias is unavailable')
        result = core.scan([core.Drive('I',alias)],{'documentos'},self.base/'result',self.events.append,self.cancel)
        record = self.records(result)[0]
        self.assertEqual(record['ruta'],str(alias))
        self.assertEqual(record['unidad'],'I:')
        self.assertTrue(core.inventory_authorizer(result.catalog)(self.input/'Documento.pdf'))

    def test_windows_detection_uses_only_reported_ready_volumes(self):
        payload = [{'letter':'C','kind':'Disco fijo','label':'Sistema','size':100,'free':10},
                   {'letter':'K','kind':'Externo / USB','label':'Fotos','size':200,'free':20}]
        with patch.object(core.os,'name','nt'),patch.object(core.subprocess,'run') as run:
            # Keep the host's concrete Path type when this runs on Linux CI.
            with patch.object(core,'Path',type(self.base)):
                run.return_value.stdout = json.dumps(payload)
                result = core.detect_drives()
        self.assertEqual([d.letter for d in result],['C','K'])
        self.assertEqual(result[1].kind,'Externo / USB')
        self.assertNotIn('ABCDEFGHIJKLMNOPQRSTUVWXYZ',run.call_args.args[0][-1])

    def test_mail_draft_encodes_content_and_blocks_header_injection(self):
        uri = core.email_draft('abuelo@example.com','https://example.trycloudflare.com','Frase larga & privada')
        parts = urlsplit(uri)
        data = parse_qs(parts.query)
        self.assertEqual(parts.path,'abuelo@example.com')
        self.assertIn('Frase larga & privada',data['body'][0])
        self.assertNotIn('Contraseña',parse_qs(urlsplit(core.email_draft('','https://x.test')).query)['body'][0])
        for address in ('a@example.com\nbcc:x@evil.test','not-an-email','a@example.com?bcc=x@evil.test'):
            with self.assertRaises(ValueError):
                core.email_draft(address,'https://x.test')

    def test_bundle_copies_code_not_personal_inventory_or_access_configuration(self):
        source = self.base/'source-web'
        for name in core.WEB_ASSETS:
            path = source/name
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text('<script id="INV_B64">PERSONAL_DATA</script>' if name=='index.html' else 'public code')
        (source/'assets/js/mingomedia-config.js').write_text('PRIVATE_ACCESS_CONFIG')
        (source/'data').mkdir()
        (source/'data/inventory.json').write_text('PERSONAL_INVENTORY')
        dest = self.base/'web'
        core.prepare_web(source,dest)
        self.assertNotIn('PERSONAL_DATA',(dest/'index.html').read_text())
        self.assertNotIn('PRIVATE_ACCESS_CONFIG',(dest/'assets/js/mingomedia-config.js').read_text())
        self.assertEqual((dest/'data/inventory.json').read_text(),'[]')

    def test_gateway_only_serves_files_in_this_scan(self):
        result = self.scan({'documentos'})
        session = core.ShareSession(result,[self.drive],'Frase privada de prueba',self.base,self.cancel,self.events.append)
        base = urlsplit(session.start_local())
        def request(path,method='GET',body=None,cookie=''):
            connection = http.client.HTTPConnection(base.hostname,base.port,timeout=5)
            connection.request(method,path,body,{'Cookie':cookie,'Content-Type':'application/x-www-form-urlencoded'})
            response = connection.getresponse()
            value = response.status,response.getheaders(),response.read()
            connection.close()
            return value
        try:
            self.assertEqual(request('/drives')[0],401)
            _,headers,body = request('/login')
            csrf = re.search(rb'name="csrf" value="([^"]+)"',body)[1].decode()
            code,headers,_ = request('/login','POST',urlencode({'csrf':csrf,'password':'Frase privada de prueba'}),'mingo_csrf='+csrf)
            self.assertEqual(code,303)
            cookie = next(value.split(';')[0] for name,value in headers if name=='Set-Cookie' and value.startswith('mingo_session='))
            self.assertEqual(request('/files/C/Documento.pdf',cookie=cookie)[0],200)
            self.assertEqual(request('/files/C/Video.mp4',cookie=cookie)[0],404)
            self.assertEqual(request('/files/C/key.p12',cookie=cookie)[0],404)
        finally:
            session.close()
        self.assertIsNone(session.server)

    def test_tampered_tunnel_binary_never_runs(self):
        result = self.scan({'documentos'})
        (self.base/'cloudflared.exe').write_bytes(b'untrusted')
        session = core.ShareSession(result,[self.drive],'Frase privada de prueba',self.base,self.cancel,self.events.append)
        try:
            with patch.object(core.subprocess,'Popen') as popen:
                with self.assertRaises(RuntimeError):
                    session.start_tunnel()
                popen.assert_not_called()
        finally:
            session.close()


@unittest.skipUnless(os.name == 'nt','Tk widget checks require the Windows desktop runtime')
class GuiTests(unittest.TestCase):
    def test_wizard_steps_validation_and_small_window_layout(self):
        import tkinter as tk
        import mingomedia_desktop as desktop
        root = tk.Tk()
        root.withdraw()
        app = desktop.MingoMediaApp(root,autodetect=False)
        try:
            app.drives = [core.Drive('C',Path('C:/')),core.Drive('K',Path('K:/'))]
            app.render_drives()
            app.select_drives(True)
            self.assertEqual(app.selected,{'C','K'})
            app.select_drives(False)
            with patch.object(desktop.messagebox,'showinfo') as message:
                app.next()
                self.assertEqual(app.page,0)
                self.assertTrue(message.called)
            app.selected = {'K'}
            app.next()
            self.assertEqual(app.page,1)
            app.all_types.set(False)
            app.types['imagenes'].set(True)
            app.types['documentos'].set(True)
            self.assertEqual(app.categories(),{'imagenes','documentos'})
            app.next()
            self.assertEqual(app.page,2)
            app.password.set('Frase privada de prueba')
            app.confirm.set('diferente')
            with patch.object(desktop.messagebox,'showinfo') as message:
                app.next()
                self.assertEqual(app.page,2)
                self.assertTrue(message.called)
            app.confirm.set(app.password.get())
            with patch.object(app,'start_scan') as start:
                app.next()
                start.assert_called_once()
            for page in range(5):
                app.show_page(page)
                root.update_idletasks()
                self.assertTrue(app.content.winfo_children())
                # Long pages scroll inside the card instead of clipping footer actions.
                self.assertLessEqual(root.winfo_reqheight(),root.winfo_height())
                self.assertTrue(app.canvas.cget('yscrollcommand'))
        finally:
            app.closed = True
            root.destroy()


if __name__ == '__main__':
    unittest.main()
