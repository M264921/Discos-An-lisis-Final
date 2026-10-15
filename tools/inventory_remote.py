"""Private, read-only MingoMedia viewer with sessions and byte-range media.

Run behind an HTTPS tunnel pointed at the printed loopback URL. No file is
uploaded: files are streamed from the PC while this process is running.
"""
import argparse
from collections import defaultdict, deque
import getpass
import hashlib
from http import cookies
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
import os
from pathlib import Path
import re
import secrets
import subprocess
import threading
import time
from urllib.parse import parse_qs, quote, unquote, urlsplit


MIN_PASSWORD_LENGTH = 8


def mounted_drives():
    """Query Windows metadata only; do not probe disconnected drive letters."""
    if os.name != 'nt':
        return {}
    script = ("@(Get-CimInstance Win32_LogicalDisk | Where-Object { "
              "$_.DriveType -in 2,3,4,5 -and $_.FileSystem -and $_.Size -gt 0 } "
              "| ForEach-Object { $_.DeviceID.Substring(0,1) }) "
              "| ConvertTo-Json -Compress")
    result = subprocess.run(
        ['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script],
        capture_output=True, text=True, timeout=15,
        creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0), check=True)
    keys = json.loads(result.stdout or '[]')
    if isinstance(keys, str):
        keys = [keys]
    return {key: Path(key + ':\\') for key in keys if re.fullmatch('[A-Z]', key)}


def byte_range(header, size):
    """Single RFC byte range; reject invalid/unsatisfiable ranges."""
    if not header:
        return None
    match = re.fullmatch(r'bytes=(\d*)-(\d*)', header.strip())
    if not match or not any(match.groups()) or size == 0:
        raise ValueError('Invalid byte range')
    first, last = match.groups()
    if not first:
        suffix = int(last)
        if suffix <= 0:
            raise ValueError('Invalid suffix')
        return max(0, size - suffix), size - 1
    start = int(first)
    end = min(int(last), size - 1) if last else size - 1
    if start >= size or end < start:
        raise ValueError('Unsatisfiable byte range')
    return start, end


def safe_path(root, segments):
    if any(not p or p in ('.', '..') or any(c in p for c in '\\/:\x00')
           or p.endswith((' ', '.'))
           or re.fullmatch(r'(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?', p, re.I)
           for p in segments):
        raise ValueError('Invalid path')
    root = Path(root).resolve()
    target = root.joinpath(*segments).resolve()
    if not target.is_relative_to(root):
        raise ValueError('Path outside root')
    return target


class ViewerServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, docs, password, roots=None, file_authorizer=None):
        if len(password) < MIN_PASSWORD_LENGTH:
            raise ValueError(f'Use a password of at least {MIN_PASSWORD_LENGTH} characters')
        self.docs = Path(docs).resolve()
        self.password_hash = hashlib.sha256(password.encode()).digest()
        self.sessions = {}
        self.failures = defaultdict(deque)
        self.lock = threading.Lock()
        self.roots = dict(roots) if roots is not None else mounted_drives()
        self.dynamic_roots = roots is None
        self.file_authorizer = file_authorizer
        self.stop_refresh = threading.Event()
        super().__init__(address, ViewerHandler)
        if self.dynamic_roots:
            threading.Thread(target=self.refresh_roots, daemon=True).start()

    def refresh_roots(self):
        while not self.stop_refresh.wait(15):
            try:
                self.roots = mounted_drives()
            except (OSError, ValueError, subprocess.SubprocessError):
                self.roots = {}

    def server_close(self):
        self.stop_refresh.set()
        super().server_close()


LOGIN = '''<!doctype html><html lang="es"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Entrar · MingoMedia</title><style>
body{background:#f4f5fb;color:#182235;font:18px system-ui;margin:0;display:grid;
place-items:center;min-height:100svh}main{margin:24px;padding:28px;background:white;
border-radius:20px;max-width:380px;box-shadow:0 4px 32px #1e293b18}
input,button{box-sizing:border-box;width:100%;font:inherit;padding:14px;margin:12px 0;
border:1px solid #cbd5e1;border-radius:10px}button{background:#2563eb;color:white}
</style><main><h1>MingoMedia</h1><p>Acceso privado a tus archivos.</p>
<form method="post" action="/login"><input type="hidden" name="csrf" value="TOKEN">
<label>Contraseña<input type="password" name="password" autocomplete="current-password"
required autofocus></label><button>Entrar</button></form><p>MESSAGE</p></main></html>'''


class ViewerHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def setup(self):
        super().setup()
        self.connection.settimeout(30)

    def handle(self):
        try:
            super().handle()
        except (ConnectionError, TimeoutError):
            pass

    def log_message(self, fmt, *args):
        # Never log file names, passwords, query strings, cookies or tokens.
        pass

    def cookie(self, name):
        jar = cookies.SimpleCookie()
        try:
            jar.load(self.headers.get('Cookie', ''))
            return jar[name].value if name in jar else ''
        except cookies.CookieError:
            return ''

    def set_cookie(self, name, value, max_age):
        secure = '; Secure' if self.headers.get('X-Forwarded-Proto') == 'https' else ''
        self.send_header('Set-Cookie', f'{name}={value}; Path=/; HttpOnly; '
                         f'SameSite=Strict; Max-Age={max_age}{secure}')

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'SAMEORIGIN')
        self.send_header('Referrer-Policy', 'same-origin')
        super().end_headers()

    def send_bytes(self, code, data=b'', mime='text/plain; charset=utf-8'):
        self.send_response(code)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(data)

    def authenticated(self):
        token = self.cookie('mingo_session')
        if not token:
            return False
        key = hashlib.sha256(token.encode()).digest()
        with self.server.lock:
            now = time.time()
            self.server.sessions = {k: v for k, v in self.server.sessions.items() if v > now}
            return self.server.sessions.get(key, 0) > now

    def login_page(self, message=''):
        token = secrets.token_urlsafe(24)
        data = LOGIN.replace('TOKEN', token).replace('MESSAGE', message).encode()
        self.send_response(200)
        self.set_cookie('mingo_csrf', token, 600)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(data)

    def do_POST(self):
        length = self.headers.get('Content-Length', '')
        if not length.isdigit() or int(length) > 4096:
            self.close_connection = True
            return self.send_bytes(413)
        data = self.rfile.read(int(length))
        origin = self.headers.get('Origin')
        if origin and urlsplit(origin).netloc != self.headers.get('Host'):
            return self.send_bytes(403)
        path = urlsplit(self.path).path
        if path == '/logout':
            if not self.authenticated():
                return self.send_bytes(401)
            key = hashlib.sha256(self.cookie('mingo_session').encode()).digest()
            with self.server.lock:
                self.server.sessions.pop(key, None)
            self.send_response(303)
            self.set_cookie('mingo_session', '', 0)
            self.send_header('Location', '/login')
            self.send_header('Content-Length', '0')
            return self.end_headers()
        if path != '/login':
            return self.send_bytes(405)
        values = parse_qs(data.decode('utf-8', errors='replace'))
        csrf = values.get('csrf', [''])[0]
        if not csrf or not secrets.compare_digest(csrf, self.cookie('mingo_csrf')):
            return self.send_bytes(403)
        client = self.headers.get('CF-Connecting-IP', self.client_address[0])
        now = time.time()
        with self.server.lock:
            self.server.failures = defaultdict(deque, {
                key: deque(t for t in times if now - t < 60)
                for key, times in self.server.failures.items() if times and now - times[-1] < 60})
            failures = self.server.failures[client]
            if len(failures) >= 5:
                return self.send_bytes(429, b'Espera un minuto antes de reintentar.')
            supplied = hashlib.sha256(values.get('password', [''])[0].encode()).digest()
            if not secrets.compare_digest(supplied, self.server.password_hash):
                failures.append(now)
                return self.login_page('Contraseña incorrecta.')
            token = secrets.token_urlsafe(32)
            self.server.sessions[hashlib.sha256(token.encode()).digest()] = now + 8 * 3600
            failures.clear()
        self.send_response(303)
        self.set_cookie('mingo_session', token, 8 * 3600)
        self.set_cookie('mingo_csrf', '', 0)
        self.send_header('Location', '/')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        try:
            self.serve()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass

    def serve(self):
        path = urlsplit(self.path).path
        if path == '/login':
            return self.login_page()
        if not self.authenticated():
            if path in ('/', '/index.html'):
                self.send_response(303)
                self.send_header('Location', '/login')
                self.send_header('Content-Length', '0')
                return self.end_headers()
            return self.send_bytes(401, b'Sesion requerida.')
        if path == '/drives':
            payload = {'service': 'MingoMedia.files', 'drives': sorted(self.server.roots)}
            return self.send_bytes(200, json.dumps(payload).encode(), 'application/json')
        is_file = path.startswith('/files/')
        try:
            segments = [unquote(p, errors='strict') for p in path.lstrip('/').split('/')]
            if is_file:
                if len(segments) < 3 or segments[1] not in self.server.roots:
                    return self.send_bytes(404)
                target = safe_path(self.server.roots[segments[1]], segments[2:])
                if self.server.file_authorizer and not self.server.file_authorizer(target):
                    return self.send_bytes(404, b'Archivo fuera del analisis seleccionado.')
            else:
                if path == '/':
                    segments = ['index.html']
                target = safe_path(self.server.docs, segments)
            if not target.is_file():
                return self.send_bytes(404, b'Archivo no encontrado.')
            stream = target.open('rb')
        except (OSError, ValueError, UnicodeError):
            return self.send_bytes(404, b'Archivo no disponible.')
        with stream:
            size = os.fstat(stream.fileno()).st_size
            try:
                span = byte_range(self.headers.get('Range'), size)
            except ValueError:
                self.send_response(416)
                self.send_header('Content-Range', f'bytes */{size}')
                self.send_header('Content-Length', '0')
                return self.end_headers()
            start, end = span if span else (0, size - 1)
            length = max(0, end - start + 1)
            self.send_response(206 if span else 200)
            mime = mimetypes.guess_type(target.name)[0] or 'application/octet-stream'
            self.send_header('Content-Type', mime)
            self.send_header('Content-Length', str(length))
            self.send_header('Accept-Ranges', 'bytes')
            if span:
                self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
            if is_file:
                self.send_header('Content-Security-Policy', "sandbox; default-src 'none'; style-src 'unsafe-inline'")
                self.send_header('Content-Disposition', "inline; filename*=UTF-8''" + quote(target.name))
            self.end_headers()
            if self.command == 'HEAD':
                return
            stream.seek(start)
            while length:
                chunk = stream.read(min(65536, length))
                if not chunk:
                    break
                self.wfile.write(chunk)
                length -= len(chunk)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--docs', type=Path, default=Path(__file__).resolve().parent.parent / 'docs')
    parser.add_argument('--port', type=int, default=8766)
    parser.add_argument('--password-env', help='Environment variable containing a generated password')
    args = parser.parse_args()
    password = os.environ.pop(args.password_env, '') if args.password_env else getpass.getpass(f'Contraseña ({MIN_PASSWORD_LENGTH}+ caracteres): ')
    server = ViewerServer(('127.0.0.1', args.port), args.docs, password)
    del password
    print(json.dumps({'url': f'http://127.0.0.1:{server.server_port}', 'drives': sorted(server.roots)}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
