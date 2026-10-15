"""Build the standalone Windows application and optional Inno Setup installer."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from mingomedia_core import TUNNEL_SHA256, TUNNEL_VERSION, VERSION, prepare_web


def download(url, destination, digest=None):
    if not destination.exists() or (digest and hashlib.sha256(destination.read_bytes()).hexdigest() != digest):
        with urllib.request.urlopen(url,timeout=90) as response:
            destination.write_bytes(response.read())
    if digest and hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
        raise RuntimeError('Official download checksum mismatch: '+destination.name)


def prepare_assets(build):
    assets = build/'assets'
    assets.mkdir(parents=True,exist_ok=True)
    prepare_web(ROOT/'docs',assets/'web')
    download(f'https://github.com/cloudflare/cloudflared/releases/download/{TUNNEL_VERSION}/cloudflared-windows-amd64.exe',
             assets/'cloudflared.exe',TUNNEL_SHA256)
    licenses = assets/'licenses'
    licenses.mkdir(exist_ok=True)
    download(f'https://raw.githubusercontent.com/cloudflare/cloudflared/{TUNNEL_VERSION}/LICENSE',licenses/'cloudflared-LICENSE.txt')
    if (ROOT/'LICENSE').exists():
        shutil.copyfile(ROOT/'LICENSE',licenses/'MingoMedia-LICENSE.txt')
    (assets/'version.txt').write_text(VERSION,encoding='utf-8')
    return assets


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only',action='store_true')
    parser.add_argument('--installer',action='store_true')
    parser.add_argument('--iscc',type=Path)
    args = parser.parse_args()
    build = ROOT/'build/mingomedia'
    output = ROOT/'dist/mingomedia'
    build.mkdir(parents=True,exist_ok=True)
    assets = prepare_assets(build)
    if args.prepare_only:
        print(json.dumps({'assets':str(assets)}),flush=True)
        return
    if os.name != 'nt':
        raise RuntimeError('Build Windows executables on Windows.')
    if importlib.util.find_spec('PyInstaller') is None:
        raise RuntimeError('Install tools/windows/requirements-build.txt in the build environment first.')
    output.mkdir(parents=True,exist_ok=True)
    args_build = [sys.executable,'-m','PyInstaller','--noconfirm','--clean','--onedir','--windowed',
                  '--name','MingoMedia','--noupx','--distpath',str(output),
                  '--workpath',str(build/'pyinstaller'),'--specpath',str(build),
                  '--paths',str(ROOT/'tools'),'--add-data',str(assets)+os.pathsep+'app_assets',
                  str(ROOT/'tools/mingomedia_desktop.py')]
    subprocess.run(args_build,check=True)
    package = output/'MingoMedia'
    readme = ROOT/'MINGOMEDIA-WINDOWS.md'
    if readme.exists():
        shutil.copyfile(readme,package/'LEEME.md')
    smoke = build/'frozen-self-test.json'
    smoke.unlink(missing_ok=True)
    subprocess.run([str(package/'MingoMedia.exe'),'--self-test',str(smoke)],check=True,timeout=30)
    verified = json.loads(smoke.read_text(encoding='utf-8'))
    if not verified['web'] or not verified['tunnel'] or verified['version'] != VERSION:
        raise RuntimeError('Frozen executable smoke check failed')
    portable = output/f'MingoMedia-Portable-{VERSION}-win64'
    shutil.make_archive(str(portable),'zip',output,'MingoMedia')
    products = [Path(str(portable)+'.zip')]
    if args.installer:
        compiler = args.iscc or shutil.which('iscc') or Path(os.environ.get('ProgramFiles(x86)',''))/'Inno Setup 6/ISCC.exe'
        if not Path(compiler).is_file():
            raise RuntimeError('Inno Setup 6 compiler is required for --installer.')
        subprocess.run([str(compiler),'/DAppVersion='+VERSION,'/DSourceDir='+str(package),
                        '/DOutputDir='+str(output),str(ROOT/'tools/windows/MingoMedia.iss')],check=True)
        products.append(output/f'MingoMedia-Setup-{VERSION}-win64.exe')
    checksums = ''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in products)
    (output/'SHA256SUMS.txt').write_text(checksums,encoding='ascii')
    print(json.dumps({'version':VERSION,'products':[str(p) for p in products], 'smoke':verified}),flush=True)


if __name__ == '__main__':
    main()
