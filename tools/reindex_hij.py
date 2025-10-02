#!/usr/bin/env python3
"""Rebuild the HIJ inventory (index_by_hash and dupes_confirmed) by scanning local drives."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import shutil
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence

BUFFER_SIZE = 1024 * 1024
DEFAULT_DRIVES = ("H", "I", "J")
ROOT = Path(__file__).resolve().parents[1]


@dataclass
class FileRecord:
    sha256: str
    path: str
    drive: str
    extension: str
    length: int
    last_write: datetime

    @property
    def last_iso(self) -> str:
        return self.last_write.strftime("%Y-%m-%d %H:%M:%S")

    @property
    def last_es(self) -> str:
        return self.last_write.strftime("%d/%m/%Y %H:%M:%S")

    @property
    def name(self) -> str:
        return Path(self.path).name


class WarningTracker:
    def __init__(self, limit: int = 3) -> None:
        self.limit = limit
        self.counts: Counter[str] = Counter()

    def warn(self, message: str) -> None:
        self.counts[message] += 1
        current = self.counts[message]
        if current <= self.limit:
            log(f"[WARN] {message}")

    def summary(self) -> None:
        for message, count in self.counts.items():
            if count > self.limit:
                log(f"[WARN] {message} (repetido x{count})")


LOG_FILE: Optional[Path] = None
_LOG_HANDLE = None


def setup_logging(path: Path) -> None:
    global LOG_FILE, _LOG_HANDLE
    LOG_FILE = path
    path.parent.mkdir(parents=True, exist_ok=True)
    _LOG_HANDLE = path.open("w", encoding="utf-8")


def log(message: str) -> None:
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{stamp}] {message}"
    print(line)
    if _LOG_HANDLE:
        _LOG_HANDLE.write(line + "\n")
        _LOG_HANDLE.flush()


def close_logging() -> None:
    if _LOG_HANDLE:
        _LOG_HANDLE.flush()
        _LOG_HANDLE.close()


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--drives",
        nargs="+",
        default=list(DEFAULT_DRIVES),
        help="Drives to scan (default: H I J)",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=ROOT,
        help="Root folder where index_by_hash.csv lives (repo root)",
    )
    parser.add_argument(
        "--snapshot-dir",
        type=Path,
        default=None,
        help="Override snapshot directory (defaults to <root>/_snapshots)",
    )
    parser.add_argument(
        "--log-file",
        type=Path,
        default=None,
        help="Optional log file path (defaults to logs_<timestamp>/reindex.log)",
    )
    parser.add_argument(
        "--skip-copy",
        action="store_true",
        help="Do not copy results to the repo root (keep only in snapshot)",
    )
    return parser.parse_args(argv)


def to_long_path(path: Path) -> str:
    raw = str(path)
    if os.name != "nt":
        return raw
    norm = os.path.normpath(raw)
    if norm.startswith("\\\\?\\"):
        return norm
    if norm.startswith("\\\\"):
        return "\\\\?\\UNC\\" + norm[2:]
    return "\\\\?\\" + norm


def normalise_display_path(path: Path, drive: str) -> str:
    raw = str(path)
    if raw.startswith("\\\\?\\UNC\\"):
        raw = "\\" + raw[8:]
    elif raw.startswith("\\\\?\\"):
        raw = raw[4:]
    raw = raw.replace("/", "\\")
    if len(raw) >= 2 and raw[1] == ":":
        raw = drive.upper() + raw[1:]
    return raw


def skip_directory(path: Path) -> bool:
    name = path.name
    upper = name.upper()
    if upper in {"SYSTEM VOLUME INFORMATION", "$RECYCLE.BIN"}:
        return True
    if upper == "_QUARANTINE_FROM_HIJ":
        return True
    if upper == "_QUARANTINE":
        return True
    if upper.startswith("FOUND.") and upper[6:].isdigit():
        return True
    return False


def compute_sha256(path: Path, warnings: WarningTracker) -> Optional[str]:
    long_path = to_long_path(path)
    digest = hashlib.sha256()
    try:
        with open(long_path, "rb", buffering=0) as handle:
            while True:
                chunk = handle.read(BUFFER_SIZE)
                if not chunk:
                    break
                digest.update(chunk)
        return digest.hexdigest().upper()
    except (OSError, PermissionError) as exc:
        warnings.warn(f"No se pudo leer {path}: {exc}")
        return None


def handle_file(path: Path, drive: str, warnings: WarningTracker) -> Optional[FileRecord]:
    try:
        stat = path.stat()
    except (OSError, PermissionError) as exc:
        warnings.warn(f"No se pudo inspeccionar {path}: {exc}")
        return None

    sha256 = compute_sha256(path, warnings)
    if not sha256:
        return None

    extension = path.suffix.lower() or "(sin)"
    display_path = normalise_display_path(path, drive)
    record = FileRecord(
        sha256=sha256,
        path=display_path,
        drive=drive.upper(),
        extension=extension,
        length=stat.st_size,
        last_write=datetime.fromtimestamp(stat.st_mtime),
    )
    return record


def walk_drive(root: Path, warnings: WarningTracker) -> Iterable[Path]:
    stack: List[Path] = [root]
    while stack:
        current = stack.pop()
        try:
            with os.scandir(current) as iterator:
                for entry in iterator:
                    try:
                        entry_path = Path(entry.path)
                        if entry.is_dir(follow_symlinks=False):
                            if skip_directory(entry_path):
                                continue
                            stack.append(entry_path)
                        elif entry.is_file(follow_symlinks=False):
                            yield entry_path
                    except (OSError, PermissionError) as exc:
                        warnings.warn(f"No se pudo acceder a {entry.path}: {exc}")
        except (OSError, PermissionError) as exc:
            warnings.warn(f"No se pudo enumerar {current}: {exc}")


def scan_drive(drive: str, warnings: WarningTracker) -> List[FileRecord]:
    drive_letter = drive.rstrip(":").upper()
    root = Path(f"{drive_letter}:\\")
    if not root.exists():
        log(f"[WARN] Unidad {drive_letter}:\\ no encontrada, se omite")
        return []

    log(f"[INFO] Escaneando {drive_letter}:\\ ...")
    records: List[FileRecord] = []
    processed = 0
    for path in walk_drive(root, warnings):
        record = handle_file(path, drive_letter, warnings)
        if record:
            records.append(record)
            processed += 1
            if processed % 200 == 0:
                log(f"[{drive_letter}] {processed} archivos procesados")
    log(f"[INFO] {drive_letter}:\\ completado ({len(records)} archivos)")
    return records


def spanish_int(value: int) -> str:
    return f"{value:,}".replace(",", ".")


def spanish_decimal(value: float, decimals: int = 2) -> str:
    formatted = f"{value:,.{decimals}f}"
    formatted = formatted.replace(",", "@").replace(".", ",").replace("@", ".")
    return formatted


def format_mb(length: int) -> str:
    mb_value = length / (1024 * 1024)
    if mb_value < 1:
        return "0"
    formatted = f"{mb_value:.2f}".replace(".", ",")
    if formatted.endswith(",00"):
        formatted = formatted[:-3]
    elif formatted.endswith("0"):
        formatted = formatted[:-1]
    return formatted


def write_index_csv(records: List[FileRecord], target: Path) -> None:
    records_sorted = sorted(records, key=lambda item: (item.sha256, item.path.lower()))
    with target.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["Hash", "Path", "Drive", "Extension", "Length", "MB", "LastWrite"])
        for record in records_sorted:
            writer.writerow([
                record.sha256,
                record.path,
                record.drive,
                record.extension,
                record.length,
                format_mb(record.length),
                record.last_es,
            ])


def write_index_txt(records: List[FileRecord], target: Path) -> None:
    groups: Dict[str, List[FileRecord]] = defaultdict(list)
    for record in records:
        groups[record.sha256].append(record)

    now_label = datetime.now().strftime("%Y-%m-%d %H:%M")
    header = [
        f"==== INDICE POR HASH  {now_label}  {spanish_int(len(records))} archivos ====",
        "(Agrupado por SHA256; grupos ordenados por fecha mas reciente)",
        "",
    ]
    lines: List[str] = header

    group_meta = []
    for sha, entries in groups.items():
        latest = max(item.last_iso for item in entries)
        group_meta.append((latest, sha, entries))

    group_meta.sort(key=lambda item: item[0], reverse=True)

    for latest, sha, entries in group_meta:
        entries_sorted = sorted(entries, key=lambda item: item.last_iso, reverse=True)
        total_bytes = sum(item.length for item in entries_sorted)
        gb_value = total_bytes / (1024 ** 3)
        earliest = min(item.last_iso for item in entries_sorted)
        header_line = (
            f"=== HASH {sha}  {len(entries_sorted)} archivos  {spanish_decimal(gb_value)} GB  "
            f"{earliest} .. {latest} ==="
        )
        lines.append(header_line)
        for entry in entries_sorted:
            size_label = spanish_int(entry.length)
            lines.append(f"{entry.last_iso}   {size_label:>10}  {entry.path}")
        lines.append("")

    target.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def write_dupes_csv(records: List[FileRecord], target: Path) -> Counter[str]:
    groups: Dict[str, List[FileRecord]] = defaultdict(list)
    for record in records:
        groups[record.sha256].append(record)

    duplicates = Counter()
    with target.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["Hash", "SHA256", "Bytes", "LastWrite", "Path"])
        for sha, entries in sorted(groups.items()):
            if len(entries) <= 1:
                continue
            duplicates["groups"] += 1
            duplicates["files"] += len(entries)
            entries_sorted = sorted(entries, key=lambda item: item.path.lower())
            for entry in entries_sorted:
                writer.writerow([
                    sha,
                    sha,
                    entry.length,
                    entry.last_iso,
                    entry.path,
                ])
    return duplicates


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_root = args.output_root.resolve()
    snapshot_dir = (args.snapshot_dir or (output_root / "_snapshots")).resolve()
    log_file = args.log_file or (output_root / f"logs_{timestamp}" / "reindex.log")
    setup_logging(log_file)

    start = datetime.now()
    log("Reindex HIJ - inicio")
    warnings = WarningTracker()

    drives = [drive.rstrip(":") for drive in args.drives]
    all_records: List[FileRecord] = []
    per_drive: Dict[str, Counter[str]] = {}

    for drive in drives:
        records = scan_drive(drive, warnings)
        if records:
            all_records.extend(records)
            counter = Counter()
            counter["files"] = len(records)
            counter["bytes"] = sum(item.length for item in records)
            per_drive[drive.upper()] = counter

    if not all_records:
        log("[ERROR] No se procesaron archivos. Revisa que las unidades esten montadas.")
        warnings.summary()
        close_logging()
        return 2

    snapshot_dir.mkdir(parents=True, exist_ok=True)
    log(f"Guardando resultados en {snapshot_dir}")

    index_csv = snapshot_dir / "index_by_hash.csv"
    index_txt = snapshot_dir / "index_by_hash.txt"
    dupes_csv = snapshot_dir / "dupes_confirmed.csv"

    write_index_csv(all_records, index_csv)
    write_index_txt(all_records, index_txt)
    dupes_counts = write_dupes_csv(all_records, dupes_csv)

    generated = [index_csv, index_txt, dupes_csv]

    if not args.skip_copy:
        log("Copiando artefactos al directorio raiz del repositorio")
        for path in generated:
            target = output_root / path.name
            shutil.copy2(path, target)
            log(f"[OK] {target}")

    total_files = len(all_records)
    total_bytes = sum(item.length for item in all_records)
    hash_counts = Counter(record.sha256 for record in all_records)
    unique_hashes = len(hash_counts)
    duplicate_groups = dupes_counts.get("groups", 0)
    duplicate_files = dupes_counts.get("files", 0)

    log("Resumen de inventario:")
    log(f"  Archivos: {spanish_int(total_files)}")
    log(f"  Hash unicos: {spanish_int(unique_hashes)}")
    log(f"  Tamano total: {spanish_decimal(total_bytes / (1024 ** 4))} TB")
    log(f"  Grupos duplicados: {spanish_int(duplicate_groups)}")
    log(f"  Archivos en duplicados: {spanish_int(duplicate_files)}")

    for drive, stats in sorted(per_drive.items()):
        drive_files = stats.get("files", 0)
        drive_bytes = stats.get("bytes", 0)
        log(
            f"  {drive}: {spanish_int(drive_files)} archivos, "
            f"{spanish_decimal(drive_bytes / (1024 ** 3))} GB"
        )

    duration = datetime.now() - start
    log(f"Reindex HIJ - fin (duracion {duration})")

    warnings.summary()

    report_dir = log_file.parent
    report_path = report_dir / "report-build-status.txt"
    report_lines = [
        "Reindex HIJ",
        f"Fecha: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"Archivos: {total_files}",
        f"Hash unicos: {unique_hashes}",
        f"Duplicados (grupos): {duplicate_groups}",
        f"Duplicados (archivos): {duplicate_files}",
        f"Bytes totales: {total_bytes}",
        f"Artefactos: {', '.join(path.name for path in generated)}",
        "",
        "Revisa reindex.log para mas detalles.",
    ]
    report_path.write_text("\n".join(report_lines), encoding="utf-8")

    close_logging()
    return 0


if __name__ == "__main__":
    sys.exit(main())
