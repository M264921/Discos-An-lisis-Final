#!/usr/bin/env python3
"""Remove non-media duplicates listed in dupes_confirmed.csv."""

import argparse
import csv
import os
from datetime import datetime
from pathlib import Path

NON_MEDIA_EXTS = {
    'db',        # Thumbs.db and similares
    'info',      # ZbThumbnail.info, etc.
    'nomedia',
    'database_uuid',
    'mta'
}


def add_long_prefix(path: str) -> str:
    prefix = "\\\\?\\"
    if path.startswith(prefix):
        return path
    if os.name == 'nt' and len(path) > 240 and path[1:3] == ':\\':
        return prefix + path
    return path


def remove_paths(csv_path: Path, log_path: Path, drives=None) -> int:
    drives = {d.upper() for d in drives} if drives else None
    removed = []
    missing = []
    errors = []

    with csv_path.open('r', encoding='utf-8-sig', newline='') as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            path = row['Path']
            if not path:
                continue
            drive = path[0].upper()
            if drives and drive not in drives:
                continue
            ext = path.rsplit('.', 1)[-1].lower() if '.' in path else ''
            if ext not in NON_MEDIA_EXTS:
                continue

            target = path
            long_path = add_long_prefix(target)
            try:
                if os.path.exists(long_path):
                    os.remove(long_path)
                    removed.append({
                        'Hash': row.get('Hash', ''),
                        'Bytes': row.get('Bytes', ''),
                        'LastWrite': row.get('LastWrite', ''),
                        'Path': target
                    })
                else:
                    missing.append(target)
            except Exception as exc:  # pragma: no cover
                errors.append((target, str(exc)))

    if removed:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        with log_path.open('w', encoding='utf-8', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=['Hash', 'Bytes', 'LastWrite', 'Path', 'DeletedAt'])
            writer.writeheader()
            for row in removed:
                row['DeletedAt'] = timestamp
                writer.writerow(row)

    if missing:
        miss_log = log_path.with_name(log_path.stem + '_missing.csv')
        with miss_log.open('w', encoding='utf-8', newline='') as handle:
            writer = csv.writer(handle)
            writer.writerow(['Path'])
            writer.writerows([[p] for p in missing])

    if errors:
        err_log = log_path.with_name(log_path.stem + '_errors.csv')
        with err_log.open('w', encoding='utf-8', newline='') as handle:
            writer = csv.writer(handle)
            writer.writerow(['Path', 'Error'])
            writer.writerows(errors)

    return len(removed)


def main():
    parser = argparse.ArgumentParser(description='Remove non-media duplicates by extension.')
    parser.add_argument('--csv', default='dupes_confirmed.csv', type=Path, help='CSV con duplicados (default: dupes_confirmed.csv)')
    parser.add_argument('--log', default='deleted_nonmedia_duplicates.csv', type=Path, help='CSV de salida con las rutas eliminadas.')
    parser.add_argument('--drives', nargs='*', help='Filtrar por letras de unidad (ej: H J).')
    args = parser.parse_args()

    count = remove_paths(args.csv, args.log, drives=args.drives)
    print(f'Eliminados {count} archivos no multimedia.')


if __name__ == '__main__':
    main()
