"""Regenerate the picker preview and update entry-point cache versions."""
from pathlib import Path
import re


def sync(root):
    root = Path(root)
    picker = root / 'docs/assets/js/picker.js'
    source = picker.read_text(encoding='utf-8-sig')
    preview = (root / 'tools/templates/inventory-preview.js').read_text(encoding='utf-8')
    start = source.find('  // BEGIN MINGO PREVIEW')
    if start >= 0:
        end = source.index('  async function handleDlnaAction()', start)
    else:
        start = source.index('  function openLocal(')
        end = source.index('  async function handleDlnaAction()', start)
    wrapper = '\n  function openLocal(href, type) {\n    return openPreview(href, type);\n  }\n\n'
    source = source[:start] + preview + wrapper + source[end:]
    picker.write_text(source, encoding='utf-8', newline='\n')
    for name in ('docs/index.html',):
        file = root / name
        data = file.read_bytes()
        data = re.sub(rb'(src="[^"?]*(?:picker|inventory-drive-links)\.js)(?:\?[^"\s]*)?"',
                      rb'\1?v=preview-20261015"', data)
        file.write_bytes(data)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo-root', type=Path, default=Path(__file__).resolve().parent.parent)
    sync(parser.parse_args().repo_root)
