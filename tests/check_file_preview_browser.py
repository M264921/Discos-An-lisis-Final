"""Optional Chrome integration check; uses temporary synthetic files only."""
from pathlib import Path
import importlib.util
import json
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import threading

REPO = Path(__file__).resolve().parents[1]
BROWSER = os.environ.get('CHROME_PATH') or shutil.which('chrome') or str(Path(os.environ.get('PROGRAMFILES',''))/'Google/Chrome/Application/chrome.exe')
def emit(value):
    print(json.dumps(value), flush=True)

def browser_test():
    candidate = REPO
    docs = BASE / 'browser-docs'
    shutil.copytree(REPO/'docs/assets', docs/'assets', dirs_exist_ok=True)
    for name in ('index.html', 'assets/js/picker.js', 'assets/js/inventory-drive-links.js'):
        dest = docs/name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(candidate/'docs'/name, dest)
    fixture = BASE/'fixture-files'
    fixture.mkdir(exist_ok=True)
    (fixture/'preview.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400"><rect width="600" height="400" fill="#2563eb"/><circle cx="300" cy="170" r="80" fill="#fbbf24"/><text x="300" y="320" text-anchor="middle" fill="white" font-size="36">MingoMedia funciona</text></svg>',encoding='utf-8')
    (fixture/'preview.txt').write_text('<script>window.previewInjected=true</script>\nTexto de prueba: ñ',encoding='utf-8')
    (fixture/'preview.bin').write_bytes(b'example')
    (fixture/'preview.pdf').write_bytes(b'%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Count 0/Kids[]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF')
    import wave
    with wave.open(str(fixture/'preview.wav'),'wb') as audio:
        audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(8000); audio.writeframes(b'\0\0'*16000)
    records = [{'sha':'','tipo':'foto','extension':name.split('.')[-1],'nombre':name,'ruta':'C:\\','unidad':'C:','tamano':100,'fecha':'2026-10-15T00:00:00Z'}
               for name in ('preview.svg','preview.txt','preview.wav','preview.pdf','missing.txt','preview.bin')]
    (docs/'data').mkdir(exist_ok=True)
    (docs/'data/inventory.json').write_text(json.dumps(records),encoding='utf-8')
    spec = importlib.util.spec_from_file_location('remote',candidate/'tools/inventory_remote.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    password = secrets.token_urlsafe(24)
    server = module.ViewerServer(('127.0.0.1',0),docs,password,{'C':fixture})
    threading.Thread(target=server.serve_forever,daemon=True).start()
    env = os.environ.copy()
    env['MINGO_TEST_URL'] = f'http://127.0.0.1:{server.server_port}'
    env['MINGO_TEST_PASSWORD'] = password
    env['MINGO_TEST_OUTPUT'] = str(BASE)
    env['MINGO_TEST_BROWSER'] = str(BROWSER)
    try:
        result = subprocess.run(['node',str(REPO/'tests/file-preview.browser.cjs')],env=env,capture_output=True,text=True,timeout=55,creationflags=subprocess.CREATE_NO_WINDOW)
        emit({'browser_exit':result.returncode,'stdout':result.stdout,'stderr':result.stderr})
        if result.returncode: raise RuntimeError('Browser verification failed')
    finally:
        server.shutdown(); server.server_close()

if __name__ == '__main__':
    if not Path(BROWSER).is_file():
        raise SystemExit('Set CHROME_PATH to an installed Chrome executable.')
    with tempfile.TemporaryDirectory(prefix='mingo-preview-') as directory:
        BASE = Path(directory)
        browser_test()
