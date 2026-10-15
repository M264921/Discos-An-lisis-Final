"""Review exact duplicates from a local scan; retain one protected copy per group."""
from dataclasses import dataclass, replace
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import threading
import uuid

from mingomedia_core import Cancelled, SECRET_DIRS, SYSTEM_DIRS, category, include_file, path_key
from mingomedia_recycle import protected_read, recycle_file


@dataclass(frozen=True)
class Copy:
    key: str
    path: str
    drive: str
    size: int
    mtime: int
    sha256: str
    identity: tuple


@dataclass(frozen=True)
class Group:
    copies: tuple

    @property
    def key(self):
        return self.copies[0].sha256 + ':' + str(self.copies[0].size)

    @property
    def reclaimable(self):
        return (len(self.copies)-1)*self.copies[0].size


@dataclass(frozen=True)
class Plan:
    group: Group
    keep: Copy

    @property
    def retire(self):
        return tuple(copy for copy in self.group.copies if copy != self.keep)


@dataclass(frozen=True)
class Outcome:
    result: object
    recycled: int
    skipped: int
    journal: Path
    cancelled: bool


def schema(connection):
    if 'sha256' not in {row[1] for row in connection.execute('PRAGMA table_info(files)')}:
        connection.execute("ALTER TABLE files ADD COLUMN sha256 TEXT DEFAULT ''")
        connection.commit()


def identity(stat):
    return (stat.st_dev, stat.st_ino)


def safe_path(path, key):
    path = Path(path)
    if path_key(path) != key or not include_file(path.name, {'todos'}):
        return False
    if any(part.casefold() in SECRET_DIRS | SYSTEM_DIRS for part in path.parts):
        return False
    # Check every ancestor, including replacement junctions since the scan.
    for part in (path, *path.parents):
        stat = part.lstat()
        if part.is_symlink() or getattr(stat, 'st_file_attributes', 0) & (0x400 | 0x1000 | 0x400000):
            return False
    return path.is_file()


def digest_stream(stream, cancel):
    digest = hashlib.sha256()
    stream.seek(0)
    while True:
        if cancel.is_set():
            raise Cancelled()
        data = stream.read(1024*1024)
        if not data:
            return digest.hexdigest()
        digest.update(data)


def verify(copy, stream, cancel):
    stat = os.fstat(stream.fileno())
    if ((stat.st_size, stat.st_mtime_ns) != (copy.size, copy.mtime)
            or identity(stat) != copy.identity
            or digest_stream(stream, cancel) != copy.sha256):
        raise OSError('El archivo ha cambiado desde la revisión.')
    current = Path(copy.path).stat()
    if identity(current) != copy.identity or not safe_path(copy.path, copy.key):
        raise OSError('La ruta o la unidad ha cambiado desde la revisión.')


def find_duplicates(result, progress=lambda value: None, cancel=None):
    cancel = cancel or threading.Event()
    connection = sqlite3.connect(result.catalog)
    ignored = 0
    buckets = {}
    seen = set()
    try:
        schema(connection)
        rows = connection.execute('''SELECT path,original,drive,size,mtime,sha256 FROM files
            WHERE published=1 AND size>0 AND size IN
            (SELECT size FROM files WHERE published=1 GROUP BY size HAVING count(*)>1)
            ORDER BY size,path''').fetchall()
        for index, (key, path, drive, size, mtime, cached) in enumerate(rows, 1):
            if cancel.is_set():
                raise Cancelled()
            try:
                if not safe_path(path, key):
                    raise OSError('Ruta excluida')
                with protected_read(path) as stream:
                    stat = os.fstat(stream.fileno())
                    if (stat.st_size, stat.st_mtime_ns) != (size, mtime):
                        raise OSError('El archivo ha cambiado')
                    physical = identity(stat)
                    if physical in seen:
                        continue
                    seen.add(physical)
                    # Re-read content for a fresh review, even when the scan cached hashes.
                    digest = digest_stream(stream, cancel)
                    copy = Copy(key, path, drive, size, mtime, digest, physical)
                    verify(copy, stream, cancel)
                buckets.setdefault((size, digest), []).append(copy)
                connection.execute('UPDATE files SET sha256=? WHERE path=?', (digest, key))
            except (OSError, ValueError):
                ignored += 1
            finally:
                progress({'processed':index, 'total':len(rows), 'skipped':ignored})
        connection.commit()
        groups = tuple(Group(tuple(copies)) for copies in buckets.values() if len(copies)>1)
        return tuple(sorted(groups, key=lambda group: (-group.reclaimable, group.key))), ignored
    finally:
        connection.close()


def recommend(group, drives, preferred=''):
    kinds = {drive.letter:drive.kind for drive in drives}

    def rank(copy):
        path = Path(copy.path)
        temporary = any(part.casefold() in {'downloads','descargas','desktop','escritorio','tmp','temporary'} for part in path.parts)
        suffix = bool(re.search(r'(?:[ _-](?:copy|copia)|\(\d+\))', path.stem, re.I))
        return (bool(preferred and copy.drive != preferred),
                kinds.get(copy.drive) != 'Disco fijo', temporary, suffix,
                len(path.parts), copy.path.casefold())

    keeper = min(group.copies, key=rank)
    reasons = []
    if preferred and keeper.drive == preferred:
        reasons.append('unidad preferida')
    if kinds.get(keeper.drive) == 'Disco fijo':
        reasons.append('disco fijo')
    if not any(part.casefold() in {'downloads','descargas','desktop','escritorio','tmp','temporary'} for part in Path(keeper.path).parts):
        reasons.append('fuera de descargas y temporales')
    return keeper, ', '.join(reasons) or 'orden estable de rutas; contenido idéntico'


def make_plan(group, keeper_key):
    matches = [copy for copy in group.copies if copy.key == keeper_key]
    if len(group.copies)<2 or len(matches)!=1 or len({copy.identity for copy in group.copies})!=len(group.copies):
        raise ValueError('Cada grupo debe conservar exactamente una copia independiente.')
    if len({(copy.size, copy.sha256) for copy in group.copies})!=1:
        raise ValueError('Los archivos no tienen el mismo contenido.')
    return Plan(group, matches[0])


def summary(plans):
    lines = ['Se enviarán a la Papelera las copias indicadas. Se conservará una por grupo.',
             'El espacio se liberará cuando vacíes la Papelera por tu cuenta.', '']
    for index, plan in enumerate(plans, 1):
        lines.append(f'Grupo {index} · {plan.keep.size:,} bytes por archivo')
        lines.append(f'CONSERVAR [{plan.keep.drive}:] {plan.keep.path}')
        lines.extend(f'PAPELERA  [{copy.drive}:] {copy.path}' for copy in plan.retire)
        lines.append('')
    lines.append(f'{len(plans)} grupos · {sum(len(plan.retire) for plan in plans)} copias a la Papelera')
    return '\n'.join(lines)


def refresh_inventory(result):
    connection = sqlite3.connect(result.catalog)
    temp = result.folder/'data/inventory.json.gz.duplicates.tmp'
    count = total = 0
    try:
        with gzip.open(temp, 'wt', encoding='utf-8') as output:
            output.write('[')
            for original, drive, size, mtime, sha in connection.execute('SELECT original,drive,size,mtime,sha256 FROM files WHERE published=1 ORDER BY path'):
                path = Path(original)
                kind = category(path)
                item = {'sha':sha or '', 'tipo':{'imagenes':'foto','videos':'video','audio':'audio','documentos':'documento'}.get(kind,'otro'),
                        'extension':path.suffix.lstrip('.').lower(), 'nombre':path.name, 'ruta':str(path.parent),
                        'unidad':drive+':', 'tamano':size, 'fecha':datetime.fromtimestamp(mtime/1e9, timezone.utc).isoformat()}
                if count:
                    output.write(',')
                json.dump(item, output, ensure_ascii=False, separators=(',',':'))
                count += 1
                total += size
            output.write(']')
        os.replace(temp, result.folder/'data/inventory.json.gz')
        return replace(result, count=count, bytes=total)
    finally:
        connection.close()
        temp.unlink(missing_ok=True)


def apply_plans(result, plans, progress=lambda value: None, cancel=None, *, recycler=recycle_file):
    """Apply the confirmed snapshot. A keeper stays locked throughout each group."""
    cancel = cancel or threading.Event()
    plans = tuple(plans)
    keys = [copy.key for plan in plans for copy in plan.group.copies]
    if len(set(keys)) != len(keys):
        raise ValueError('Hay archivos repetidos entre los grupos seleccionados.')
    for plan in plans:
        if make_plan(plan.group, plan.keep.key) != plan:
            raise ValueError('Plan inválido.')
    connection = sqlite3.connect(result.catalog)
    journal = result.folder/('duplicados-'+datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8]+'.jsonl')
    recycled = skipped = processed = 0
    total = sum(len(plan.retire) for plan in plans)
    try:
        schema(connection)
        # Validate the entire plan before touching any file.
        for plan in plans:
            for copy in plan.group.copies:
                row = connection.execute('SELECT original,drive,size,mtime,sha256 FROM files WHERE path=? AND published=1', (copy.key,)).fetchone()
                if row != (copy.path,copy.drive,copy.size,copy.mtime,copy.sha256):
                    raise ValueError('El plan ya no corresponde al análisis actual. Vuelve a revisar los duplicados.')
        with journal.open('x', encoding='utf-8') as log:
            def record(value):
                log.write(json.dumps(value, ensure_ascii=False)+'\n')
                log.flush()
                os.fsync(log.fileno())

            record({'event':'confirmed_plan', 'summary':summary(plans)})
            for plan in plans:
                if cancel.is_set():
                    break
                try:
                    if not safe_path(plan.keep.path, plan.keep.key):
                        raise OSError('La copia a conservar ya no es una ruta válida.')
                    with protected_read(plan.keep.path) as keeper_stream:
                        verify(plan.keep, keeper_stream, cancel)
                        for copy in plan.retire:
                            if cancel.is_set():
                                break
                            try:
                                if not safe_path(copy.path, copy.key):
                                    raise OSError('La ruta de la copia ha cambiado.')
                                with protected_read(copy.path, allow_recycle=True) as stream:
                                    verify(copy, stream, cancel)
                                    # Keeper handle denies deletion/rename/write, including aliases.
                                    if identity(os.fstat(keeper_stream.fileno())) == identity(os.fstat(stream.fileno())):
                                        raise OSError('Ambas rutas apuntan al mismo archivo.')
                                    record({'event':'recycle_pending','keep':plan.keep.path,'path':copy.path})
                                    destination = recycler(Path(copy.path))
                                    if Path(copy.path).exists():
                                        raise OSError('El archivo sigue en su ubicación; Windows no confirmó la retirada.')
                                connection.execute('UPDATE files SET published=0 WHERE path=?', (copy.key,))
                                connection.commit()
                                recycled += 1
                                record({'event':'recycled','path':copy.path,'recycle_location':str(destination or '')})
                            except Cancelled:
                                cancel.set()
                                break
                            except (OSError, ValueError) as error:
                                skipped += 1
                                record({'event':'skipped','path':copy.path,'reason':str(error)})
                            processed += 1
                            progress({'processed':processed,'total':total,'skipped':skipped})
                except Cancelled:
                    cancel.set()
                    break
                except (OSError, ValueError) as error:
                    skipped += len(plan.retire)
                    processed += len(plan.retire)
                    record({'event':'group_blocked','keep':plan.keep.path,'reason':str(error)})
                    progress({'processed':processed,'total':total,'skipped':skipped})
            record({'event':'finished','recycled':recycled,'skipped':skipped,'cancelled':cancel.is_set()})
    finally:
        connection.close()
    updated = refresh_inventory(result)
    return Outcome(updated,recycled,skipped,journal,cancel.is_set())
