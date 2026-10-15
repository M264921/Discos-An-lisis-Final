"""Read-only checks for tracked source layout, documentation and Git policies."""
import ast
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def git(*arguments, input_text=None):
    result = subprocess.run(['git', *arguments], cwd=ROOT, input=input_text,
                            capture_output=True, text=True, encoding='utf-8', check=True)
    return result.stdout


def main():
    names = git('ls-files', '-z').split('\0')[:-1]
    failures = []
    if not names:
        failures.append('No tracked sources were found.')
    for name in names:
        path = ROOT / name
        if not path.is_file():
            failures.append(f'Missing tracked file: {name}')
            continue
        if (re.search(r'(?:\.bak(?:[_.]|$)|\.backup\.ps1$|(?:^|/)_backup_)', name)
                or name.startswith('releases/') or name == '.safety.patch'):
            failures.append(f'Generated backup/package must stay outside Git: {name}')
        if path.suffix == '.py':
            try:
                ast.parse(path.read_text(encoding='utf-8-sig'), filename=name)
            except (SyntaxError, UnicodeError) as error:
                failures.append(f'{name}: {error}')
        if path.suffix == '.md':
            text = path.read_text(encoding='utf-8-sig')
            for raw in re.findall(r'\[[^\]\n]*\]\(([^)\n]+)\)', text):
                target = raw.strip().strip('<>')
                parsed = urlsplit(target)
                if parsed.scheme or parsed.netloc or not parsed.path:
                    continue
                local = (path.parent / unquote(parsed.path)).resolve()
                if not local.is_relative_to(ROOT) or not local.exists():
                    failures.append(f'{name}: broken local link: {target}')

    core = ast.parse((ROOT/'tools/mingomedia_core.py').read_text(encoding='utf-8-sig'))
    version = next(ast.literal_eval(item.value) for item in core.body
                   if isinstance(item, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'VERSION'
                                                          for target in item.targets))
    installer = (ROOT/'tools/windows/MingoMedia.iss').read_text(encoding='utf-8-sig')
    if f'#define AppVersion "{version}"' not in installer:
        failures.append('Installer default version differs from application VERSION.')
    json.loads((ROOT/'.vscode/launch.json').read_text(encoding='utf-8-sig'))

    ignored = ['dist/local.exe', 'releases/local.zip', 'docs/assets/example.js.bak',
               'tools/_backup_example/old.ps1', '.venv-build/example', '.env',
               'inventory.config.json', 'docs/inventory/scan_Z.csv']
    for name in ignored:
        result = subprocess.run(['git', 'check-ignore', '--no-index', '-q', '--', name], cwd=ROOT)
        if result.returncode != 0:
            failures.append(f'Missing ignore rule for local output: {name}')
    attributes = git('check-attr', 'filter', '--', 'docs/data/inventory.json',
                     'docs/inventario_interactivo_offline.html', 'docs/inventory/scan_J.csv')
    if len(attributes.splitlines()) != 3 or any(not line.endswith(': lfs') for line in attributes.splitlines()):
        failures.append('Historical inventory LFS rules changed or are missing.')
    if failures:
        raise SystemExit('\n'.join(failures))
    print(f'Repository OK: {len(names)} tracked files, Python syntax, local Markdown links, Git policies; app {version}.')


if __name__ == '__main__':
    main()
