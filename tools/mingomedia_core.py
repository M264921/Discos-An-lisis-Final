"""Local scan and private sharing services for the Windows wizard (stdlib only)."""
from dataclasses import dataclass
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
from urllib.parse import quote, urlencode
import uuid

from inventory_remote import ViewerServer

VERSION = '1.1.0'
TUNNEL_VERSION = '2026.10.1'
TUNNEL_SHA256 = '4d2490e74082c5d48dbfedaf92576fa5bd1702379ab88eb7faa0cfbe8dc891b6'
EXTENSIONS = {
    'imagenes': {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic', '.heif', '.tif', '.tiff', '.svg', '.avif', '.raw', '.cr2', '.nef', '.ico'},
    'videos': {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v', '.mpg', '.mpeg', '.mts', '.m2ts', '.wmv', '.ts'},
    'audio': {'.mp3', '.wav', '.flac', '.aac', '.m4a', '.ogg', '.opus', '.wma', '.aiff'},
    'documentos': {'.pdf', '.txt', '.doc', '.docx', '.odt', '.rtf', '.xls', '.xlsx', '.ods', '.csv', '.ppt', '.pptx', '.odp', '.epub', '.md'},
}
SECRET_DIRS = {'.ssh', '.aws', '.azure', '.gnupg', '.codex', 'credentials', 'vault', 'protect'}
SYSTEM_DIRS = {'windows', 'program files', 'program files (x86)', 'programdata', '$recycle.bin',
               'system volume information', 'node_modules', '.git', '.venv', 'venv', '__pycache__',
               'appdata', 'cache', 'caches', 'temp'}
SECRET_EXTENSIONS = {'.pem', '.key', '.p12', '.pfx', '.jks', '.kdbx'}
WEB_ASSETS = (
    'index.html', 'assets/inventory-loader.js', 'assets/inventario.css', 'assets/inventario.js',
    'assets/css/picker.css', 'assets/js/inventory-app.js', 'assets/js/inventory-state.js',
    'assets/js/inventory-drive-links.js', 'assets/js/picker.js',
)
SAFE_CONFIG = ('window.MingoMediaConfig={access:{enabled:false},'
               'view:{storagePrefix:"mingomedia.desktop.view."}};\n')


class Cancelled(Exception):
    """A user cancelled a scan or tunnel startup."""


@dataclass(frozen=True)
class Drive:
    letter: str
    root: Path
    label: str = ''
    kind: str = 'Disco fijo'
    size: int = 0
    free: int = 0


@dataclass(frozen=True)
class ScanResult:
    folder: Path
    catalog: Path
    count: int
    skipped: int
    bytes: int


def detect_drives():
    if os.name != 'nt':
        return []
    # Ask Windows which logical volumes contain mounted media. Never probe A..Z.
    script = r'''
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$buses = @{}
try { Get-Disk -ErrorAction Stop | ForEach-Object {
  $bus = [string]$_.BusType
  $_ | Get-Partition -ErrorAction SilentlyContinue | Where-Object DriveLetter | ForEach-Object {
    $buses[[string]$_.DriveLetter] = $bus
  }
} } catch {}
$items = @(Get-CimInstance Win32_LogicalDisk -ErrorAction Stop | Where-Object {
  $_.DriveType -in 2,3,4,5 -and $_.FileSystem -and $_.Size -gt 0
} | ForEach-Object {
  $letter = $_.DeviceID.Substring(0,1)
  $kind = switch ([int]$_.DriveType) { 2 {'Extraible'} 3 {'Disco fijo'} 4 {'Red'} 5 {'Optica'} }
  if ($buses[$letter] -in 'USB','SD','MMC') { $kind = 'Externo / USB' }
  @{letter=$letter; label=$_.VolumeName; kind=$kind; size=$_.Size; free=$_.FreeSpace}
})
ConvertTo-Json -InputObject $items -Compress
'''
    completed = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script],
                               capture_output=True, encoding='utf-8', timeout=25, check=True,
                               creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    items = json.loads(completed.stdout or '[]')
    return [Drive(item['letter'], Path(item['letter'] + ':\\'), item.get('label') or '',
                  item['kind'], int(item['size']), int(item['free']))
            for item in items if re.fullmatch('[A-Z]', item['letter'])]


def category(path):
    ext = Path(path).suffix.lower()
    return next((name for name, extensions in EXTENSIONS.items() if ext in extensions), 'otros')


def include_file(name, categories):
    lower = name.casefold()
    if Path(name).suffix.lower() in SECRET_EXTENSIONS or lower == '.env' or lower.startswith('.env.'):
        return False
    if lower in {'credentials.json', 'tokens.json', 'id_rsa', 'id_ed25519', 'ntuser.dat', 'pagefile.sys', 'hiberfil.sys', 'swapfile.sys'}:
        return False
    return 'todos' in categories or category(name) in categories


def path_key(path):
    return os.path.normcase(str(Path(path).resolve()))


def data_directory():
    if os.name == 'nt':
        return Path(os.environ.get('LOCALAPPDATA', Path.home()/'AppData/Local'))/'MingoMedia'
    return Path.home()/'.local/share/MingoMedia'


def asset_directory():
    if getattr(sys, 'frozen', False):
        return Path(sys._MEIPASS)/'app_assets'
    return Path(__file__).resolve().parents[1]/'build/mingomedia/assets'


def prepare_web(source_docs, destination):
    """Copy only public viewer code, never existing inventories or access config."""
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    for name in WEB_ASSETS:
        target = destination/name
        target.parent.mkdir(parents=True, exist_ok=True)
        data = (Path(source_docs)/name).read_bytes()
        if name == 'index.html':
            # An old inline payload must never carry the author's inventory to another PC.
            data = re.sub(rb'(<script\b[^>]*\bid="INV_B64"[^>]*>).*?(</script>)', rb'\1\2', data, flags=re.S | re.I)
        target.write_bytes(data)
    (destination/'assets/js/mingomedia-config.js').write_text(SAFE_CONFIG, encoding='utf-8')
    (destination/'data').mkdir(exist_ok=True)
    (destination/'data/inventory.json').write_text('[]', encoding='utf-8')


def scan(drives, categories, folder, progress, cancel, personal=True, hashes=False):
    if not drives or not categories or not set(categories) <= {'todos', 'otros', *EXTENSIONS}:
        raise ValueError('Selecciona unidades y tipos de archivo válidos.')
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    catalog = folder/'catalog.sqlite'
    if catalog.exists():
        raise ValueError('El destino debe ser un análisis nuevo.')
    connection = sqlite3.connect(catalog)
    connection.execute("CREATE TABLE files (path TEXT PRIMARY KEY, original TEXT, drive TEXT, size INTEGER, mtime INTEGER, published INTEGER DEFAULT 0, sha256 TEXT DEFAULT '')")
    skipped = 0
    discovered = 0
    last_update = 0.0

    def emit(phase, processed=0, total=None, force=False):
        nonlocal last_update
        now = time.monotonic()
        if force or now - last_update > 0.15:
            progress({'phase':phase, 'processed':processed, 'total':total, 'skipped':skipped})
            last_update = now

    def check_cancel():
        if cancel.is_set():
            raise Cancelled()

    def walk_error(_error):
        nonlocal skipped
        skipped += 1

    try:
        emit('discover', force=True)
        for drive in drives:
            check_cancel()
            if not drive.root.is_dir():
                raise OSError(f'La unidad {drive.letter}: ya no está disponible.')
            for directory, subdirs, names in os.walk(drive.root, followlinks=False, onerror=walk_error):
                check_cancel()
                kept = []
                for name in subdirs:
                    if name.casefold() in SECRET_DIRS or (personal and name.casefold() in SYSTEM_DIRS):
                        continue
                    try:
                        child = Path(directory)/name
                        stat = child.lstat()
                        if child.resolve().is_relative_to(folder.resolve()) or getattr(stat, 'st_file_attributes', 0) & 0x400 or child.is_symlink():
                            continue
                        kept.append(name)
                    except OSError:
                        skipped += 1
                subdirs[:] = kept
                for name in names:
                    check_cancel()
                    if not include_file(name, categories):
                        continue
                    path = Path(directory)/name
                    try:
                        if path.resolve().is_relative_to(folder.resolve()):
                            continue
                        stat = path.lstat()
                        if path.is_symlink() or getattr(stat, 'st_file_attributes', 0) & (0x400 | 0x1000 | 0x400000):
                            skipped += 1
                            continue
                        added = connection.execute('INSERT OR IGNORE INTO files(path,original,drive,size,mtime) VALUES(?,?,?,?,?)',
                                                   (path_key(path), str(path.absolute()), drive.letter, stat.st_size, stat.st_mtime_ns)).rowcount
                        discovered += added
                    except OSError:
                        skipped += 1
                    emit('discover', discovered)
        connection.commit()
        count = connection.execute('SELECT COUNT(*) FROM files').fetchone()[0]
        emit('scan', 0, count, force=True)
        (folder/'data').mkdir(exist_ok=True)
        temp = folder/'data/inventory.json.gz.tmp'
        published = 0
        total_bytes = 0
        with gzip.open(temp, 'wt', encoding='utf-8') as output:
            output.write('[')
            for processed, (original, path, letter, size, mtime) in enumerate(connection.execute('SELECT original,path,drive,size,mtime FROM files'), 1):
                check_cancel()
                try:
                    file = Path(original)
                    current = file.stat()
                    if (current.st_size, current.st_mtime_ns) != (size, mtime):
                        raise OSError('Changed during scan')
                    digest = ''
                    if hashes:
                        hasher = hashlib.sha256()
                        with file.open('rb') as stream:
                            while True:
                                check_cancel()
                                chunk = stream.read(1024*1024)
                                if not chunk:
                                    break
                                hasher.update(chunk)
                        current = file.stat()
                        if (current.st_size, current.st_mtime_ns) != (size, mtime):
                            raise OSError('Changed while hashing')
                        digest = hasher.hexdigest()
                    kind = category(file)
                    item = {'sha':digest, 'tipo':{'imagenes':'foto','videos':'video','audio':'audio','documentos':'documento'}.get(kind,'otro'),
                            'extension':file.suffix.lstrip('.').lower(), 'nombre':file.name, 'ruta':str(file.parent),
                            'unidad':letter+':', 'tamano':size,
                            'fecha':datetime.fromtimestamp(current.st_mtime,timezone.utc).isoformat()}
                    if published:
                        output.write(',')
                    json.dump(item, output, ensure_ascii=False, separators=(',',':'))
                    connection.execute('UPDATE files SET published=1,sha256=? WHERE path=?', (digest,path))
                    published += 1
                    total_bytes += size
                except (OSError, ValueError):
                    skipped += 1
                emit('scan', processed, count)
            output.write(']')
        check_cancel()
        # A missing JSON triggers the existing gzip fallback. Never retain the
        # initial empty inventory after publishing the actual scan.
        (folder/'data/inventory.json').unlink(missing_ok=True)
        os.replace(temp, folder/'data/inventory.json.gz')
        connection.commit()
        emit('done', count, count, force=True)
        return ScanResult(folder, catalog, published, skipped, total_bytes)
    finally:
        connection.close()
        (folder/'data/inventory.json.gz.tmp').unlink(missing_ok=True)


def inventory_authorizer(catalog):
    def allowed(path):
        connection = sqlite3.connect(catalog)
        try:
            return connection.execute('SELECT 1 FROM files WHERE path=? AND published=1', (path_key(path),)).fetchone() is not None
        finally:
            connection.close()
    return allowed


def email_draft(recipient, link, password=None):
    if recipient and not re.fullmatch(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}', recipient):
        raise ValueError('Introduce una dirección de correo válida.')
    body = 'Mi biblioteca MingoMedia:\n'+link+'\n\nEl ordenador y MingoMedia deben permanecer encendidos y conectados.'
    if password:
        body += '\n\nContraseña: '+password
    return 'mailto:'+recipient+'?'+urlencode({'subject':'Mi enlace privado de MingoMedia', 'body':body},quote_via=quote)


class ShareSession:
    def __init__(self, result, drives, password, assets, cancel, progress):
        self.result = result
        self.drives = drives
        self.password = password
        self.assets = Path(assets)
        self.cancel = cancel
        self.progress = progress
        self.server = None
        self.thread = None
        self.tunnel = None
        self.url = ''
        self.local_url = ''
        self.stopped = threading.Event()

    def start_local(self):
        if self.server:
            return self.local_url
        roots = {drive.letter:drive.root for drive in self.drives}
        self.server = ViewerServer(('127.0.0.1',0), self.result.folder, self.password, roots,
                                   file_authorizer=inventory_authorizer(self.result.catalog))
        self.password = None
        self.local_url = f'http://127.0.0.1:{self.server.server_port}'
        self.thread = threading.Thread(target=self.server.serve_forever,daemon=True)
        self.thread.start()
        threading.Thread(target=self.monitor_drives,daemon=True).start()
        return self.local_url

    def monitor_drives(self):
        while not self.stopped.wait(15):
            try:
                ready = {drive.letter for drive in detect_drives()}
                if not self.stopped.is_set() and self.server:
                    self.server.roots = {drive.letter:drive.root for drive in self.drives if drive.letter in ready}
            except (OSError, ValueError, subprocess.SubprocessError):
                if not self.stopped.is_set() and self.server:
                    self.server.roots = {}

    def start_tunnel(self):
        self.start_local()
        binary = self.assets/'cloudflared.exe'
        if not binary.is_file() or hashlib.sha256(binary.read_bytes()).hexdigest() != TUNNEL_SHA256:
            raise RuntimeError('No se pudo verificar el componente de conexión. Reinstala MingoMedia desde su página oficial.')
        config = self.result.folder/'tunnel-config.yml'
        config.write_text('{}\n',encoding='utf-8')
        self.tunnel = subprocess.Popen([str(binary),'tunnel','--config',str(config),'--url',self.local_url,
                                        '--no-autoupdate','--protocol','http2'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                                       encoding='utf-8',errors='replace',creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        lines = queue.Queue()
        child = self.tunnel
        def reader():
            for line in child.stdout:
                # Retain no tunnel logs, passwords, or filenames on disk.
                if 'trycloudflare.com' in line or 'Registered tunnel connection' in line:
                    lines.put(line)
        threading.Thread(target=reader,daemon=True).start()
        deadline = time.monotonic()+75
        registered = False
        while time.monotonic() < deadline:
            if self.cancel.is_set():
                raise Cancelled()
            if self.tunnel.poll() is not None:
                raise RuntimeError('No se pudo conectar. Comprueba Internet y pulsa Reintentar enlace.')
            try:
                line = lines.get(timeout=0.25)
            except queue.Empty:
                continue
            found = re.search(r'https://[a-z0-9-]+\.trycloudflare\.com',line)
            if found:
                self.url = found[0]
            if 'Registered tunnel connection' in line:
                registered = True
            if self.url and registered:
                self.progress({'phase':'shared','url':self.url})
                return self.url
        raise RuntimeError('La conexión ha tardado demasiado. El análisis está guardado; puedes reintentar el enlace.')

    def stop_tunnel(self):
        if self.tunnel and self.tunnel.poll() is None:
            self.tunnel.terminate()
            try:
                self.tunnel.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.tunnel.kill()
                self.tunnel.wait(timeout=5)
        self.tunnel = None
        self.url = ''

    def close(self):
        self.stopped.set()
        self.stop_tunnel()
        if self.server:
            self.server.shutdown()
            self.server.server_close()
            self.server = None
