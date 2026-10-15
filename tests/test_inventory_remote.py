"""Functional checks for the private read-only gateway (synthetic files only)."""
import http.client
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import threading
import unittest
from urllib.parse import urlencode

SPEC = importlib.util.spec_from_file_location(
    'inventory_remote', Path(__file__).resolve().parents[1] / 'tools/inventory_remote.py')
remote = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(remote)


class RemoteTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        self.docs = root / 'docs'
        self.docs.mkdir()
        (self.docs / 'index.html').write_text('VIEWER')
        self.files = root / 'files'
        self.files.mkdir()
        (self.files / 'prueba ñ.txt').write_bytes(b'<script>alert(1)</script>0123456789')
        (self.files / 'empty.txt').write_bytes(b'')
        self.password = 'Mingo-test-password-123456'
        self.server = remote.ViewerServer(('127.0.0.1', 0), self.docs, self.password, {'C': self.files})
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.session = ''

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, path, method='GET', body=None, headers=None):
        conn = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        request_headers = dict(headers or {})
        if self.session:
            request_headers.setdefault('Cookie', self.session)
        conn.request(method, path, body=body, headers=request_headers)
        response = conn.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        conn.close()
        return result

    def login(self):
        code, headers, body = self.request('/login')
        self.assertEqual(code, 200)
        token = re.search(rb'name="csrf" value="([^"]+)"', body)[1].decode()
        # Preserve separate Set-Cookie headers when obtaining the session.
        conn = http.client.HTTPConnection('127.0.0.1', self.server.server_port)
        conn.request('POST', '/login', urlencode({'csrf': token, 'password': self.password}),
                     {'Cookie': 'mingo_csrf=' + token})
        response = conn.getresponse()
        self.assertEqual(response.status, 303)
        self.session = next(v.split(';')[0] for k, v in response.getheaders()
                            if k.lower() == 'set-cookie' and v.startswith('mingo_session='))
        self.assertIn('HttpOnly', next(v for k, v in response.getheaders() if v.startswith('mingo_session=')))
        response.read()
        conn.close()

    def test_auth_required_for_data_and_static(self):
        for path in ('/drives', '/files/C/prueba%20%C3%B1.txt', '/data/inventory.json', '/assets/js/picker.js'):
            self.assertEqual(self.request(path)[0], 401)
        self.assertEqual(self.request('/')[0], 303)

    def test_login_csrf_and_wrong_password(self):
        self.assertEqual(self.request('/login', 'POST', 'password=x')[0], 403)
        self.assertEqual(self.request('/login', 'POST', 'password=x', {'Origin': 'https://evil.test'})[0], 403)
        _, headers, body = self.request('/login')
        token = re.search(rb'name="csrf" value="([^"]+)"', body)[1].decode()
        for _ in range(5):
            code, _, data = self.request('/login', 'POST', urlencode({'csrf': token, 'password': 'wrong'}),
                                        {'Cookie': 'mingo_csrf=' + token})
            self.assertEqual(code, 200)
            self.assertIn('incorrecta'.encode(), data)
        self.assertEqual(self.request('/login', 'POST', urlencode({'csrf': token, 'password': 'wrong'}),
                                     {'Cookie': 'mingo_csrf=' + token})[0], 429)

    def test_inventory_and_unicode_file(self):
        self.login()
        self.assertEqual(self.request('/')[2], b'VIEWER')
        self.assertEqual(json.loads(self.request('/drives')[2])['drives'], ['C'])
        code, headers, data = self.request('/files/C/prueba%20%C3%B1.txt')
        self.assertEqual(code, 200)
        self.assertTrue(data.startswith(b'<script>'))
        self.assertEqual(headers['X-Content-Type-Options'], 'nosniff')
        self.assertIn('sandbox', headers['Content-Security-Policy'])

    def test_range_head_suffix_and_invalid_ranges(self):
        self.login()
        path = '/files/C/prueba%20%C3%B1.txt'
        code, headers, data = self.request(path, headers={'Range': 'bytes=0-3'})
        self.assertEqual((code, data), (206, b'<scr'))
        self.assertTrue(headers['Content-Range'].startswith('bytes 0-3/'))
        self.assertEqual(self.request(path, headers={'Range': 'bytes=-4'})[2], b'6789')
        code, headers, data = self.request(path, 'HEAD', headers={'Range': 'bytes=4-6'})
        self.assertEqual((code, headers['Content-Length'], data), (206, '3', b''))
        for value in ('bytes=99999-', 'bytes=-0', 'bytes=2-1', 'bytes=0-1,3-4', 'invalid'):
            self.assertEqual(self.request(path, headers={'Range': value})[0], 416)
        self.assertEqual(self.request('/files/C/empty.txt')[0], 200)
        self.assertEqual(self.request('/files/C/empty.txt', headers={'Range': 'bytes=0-'})[0], 416)

    def test_traversal_ads_disconnected_drive_and_directory(self):
        self.login()
        for path in ('/files/Z/missing', '/files/C/%2e%2e/docs/index.html',
                     '/files/C/a%5c..%5csecret', '/files/C/empty.txt%3Asecret',
                     '/files/C/CON', '/files/C/NUL.txt',
                     '/files/C/', '/%2e%2e/files/empty.txt'):
            self.assertEqual(self.request(path)[0], 404, path)
        self.assertEqual(self.request('/files/C/missing.txt')[0], 404)

    def test_logout_invalidates_cookie(self):
        self.login()
        self.assertEqual(self.request('/logout', 'POST', '')[0], 303)
        self.assertEqual(self.request('/drives')[0], 401)


if __name__ == '__main__':
    unittest.main()
