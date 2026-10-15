#!/usr/bin/env python3
"""Preview non-media duplicates; --apply requires matching current file hashes."""
import argparse
import csv
import hashlib
import os
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

NON_MEDIA_EXTS = {'db', 'info', 'nomedia', 'database_uuid', 'mta'}
ALGORITHMS = {32: 'md5', 40: 'sha1', 64: 'sha256', 128: 'sha512'}


def digest(path, expected):
    algorithm = ALGORITHMS.get(len(expected))
    if not algorithm or any(c not in '0123456789abcdef' for c in expected):
        return None
    if path.is_symlink() or not path.is_file():
        return None
    hasher = hashlib.new(algorithm)
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            hasher.update(block)
    return hasher.hexdigest()


def eligible(path):
    return path.name.lower().rsplit('.', 1)[-1] in NON_MEDIA_EXTS


def remove_paths(csv_path: Path, log_path: Path, drives=None, *, apply=False) -> int:
    """Keep at least one verified file per hash. Return planned/applied removals."""
    groups = defaultdict(dict)
    with csv_path.open('r', encoding='utf-8-sig', newline='') as handle:
        reader = csv.DictReader(handle)
        if not {'Path', 'Hash'}.issubset(reader.fieldnames or []):
            raise ValueError('El CSV debe contener Path y Hash.')
        for row in reader:
            raw = row.get('Path', '').strip()
            if not raw:
                continue
            path = Path(raw)
            if not path.is_absolute():
                continue
            groups[row.get('Hash', '').strip().lower()][os.path.normcase(str(path.absolute()))] = path
    allowed = {d.rstrip(':').upper() for d in drives} if drives else None
    records = []
    count = 0
    for expected, paths in groups.items():
        verified, identities = [], set()
        for path in paths.values():
            try:
                stat = path.stat()
                identity = (stat.st_dev, stat.st_ino)
                if identity not in identities and digest(path, expected) == expected:
                    verified.append(path)
                    identities.add(identity)
            except OSError:
                continue
        if len(verified) < 2:
            continue
        verified.sort(key=lambda p: (eligible(p), str(p).casefold()))
        keeper = verified[0]
        for target in verified[1:]:
            if not eligible(target) or (allowed and target.drive.rstrip(':').upper() not in allowed):
                continue
            status = 'Plan'
            try:
                if digest(keeper, expected) != expected or digest(target, expected) != expected:
                    status = 'Changed'
                elif apply:
                    target.unlink()
                    status = 'Deleted'
            except OSError as exc:
                status = 'Error: ' + str(exc)
            if status in {'Plan', 'Deleted'}:
                count += 1
            records.append({'Hash': expected, 'Path': str(target), 'Keeper': str(keeper), 'Action': status,
                            'CheckedAt': datetime.now(timezone.utc).isoformat()})
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open('w', encoding='utf-8', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=['Hash', 'Path', 'Keeper', 'Action', 'CheckedAt'])
        writer.writeheader()
        writer.writerows(records)
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--csv', default='dupes_confirmed.csv', type=Path)
    parser.add_argument('--log', default='logs/nonmedia-duplicates-preview.csv', type=Path)
    parser.add_argument('--drives', nargs='*', help='Limita candidatos; no reasocia letras historicas.')
    parser.add_argument('--apply', action='store_true', help='Borra solo copias verificadas conservando otra.')
    args = parser.parse_args()
    count = remove_paths(args.csv, args.log, drives=args.drives, apply=args.apply)
    print(f'{"Eliminados" if args.apply else "Planificados"} {count} duplicados no multimedia.')


if __name__ == '__main__':
    main()
