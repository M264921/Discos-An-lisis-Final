"""Legacy PySimpleGUI inventory interface; retained for its data/gui format.

The current Windows installer uses mingomedia_desktop.py and includes Tk.
This optional interface requires PySimpleGUI separately and is not bundled.
See LEGACY.md before using or packaging older inventory tools.
"""

import os
import json
import gzip
import hashlib
import threading
import time
import tempfile
from pathlib import Path

import PySimpleGUI as sg


# Determina la raíz del repositorio (dos niveles arriba del script)
ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data" / "gui"
INVENTORY_GZ = DATA_DIR / "inventory.json.gz"


def load_inventory() -> dict:
    """Carga el inventario comprimido, si existe, o devuelve un inventario vacío."""
    if INVENTORY_GZ.exists():
        try:
            with gzip.open(INVENTORY_GZ, "rb") as f:
                value = json.loads(f.read().decode("utf-8"))
                if not isinstance(value, dict) or not isinstance(value.get("items"), list):
                    raise ValueError("Formato de inventario GUI incompatible")
                return value
        except Exception as exc:
            raise ValueError("Inventario GUI ilegible; se conserva sin sobrescribir") from exc
    return {"generated_at": "manual-placeholder", "items": []}


def save_inventory(inv: dict) -> None:
    """Guarda el inventario en formato JSON comprimido en gzip."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(inv, ensure_ascii=False, indent=2).encode("utf-8")
    fd, name = tempfile.mkstemp(prefix="inventory-", suffix=".tmp", dir=DATA_DIR)
    os.close(fd)
    try:
        with gzip.open(name, "wb") as f:
            f.write(payload)
        os.replace(name, INVENTORY_GZ)
    finally:
        Path(name).unlink(missing_ok=True)


def list_drives() -> list:
    """Devuelve una lista de letras de unidad disponibles en el sistema Windows."""
    drives = []
    for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        path = Path(f"{letter}:\\")
        if path.exists():
            drives.append(f"{letter}:\\")
    return drives


def hash_file(path: str, algo: str = "sha1") -> str | None:
    """Calcula el hash de un archivo utilizando el algoritmo especificado."""
    try:
        h = hashlib.new(algo)
    except ValueError:
        return None
    try:
        with open(path, "rb") as f:
            while True:
                chunk = f.read(1024 * 1024)
                if not chunk:
                    break
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return None


def scan_and_hash(drive_list: list, algo: str, skip_already_hashed: bool, window: sg.Window) -> None:
    """
    Escanea las unidades seleccionadas, calcula hashes y actualiza el inventario.

    - drive_list: lista de rutas de unidades (por ejemplo ['C:\\', 'D:\\']).
    - algo: nombre del algoritmo de hash ('sha1', 'md5', 'sha256').
    - skip_already_hashed: si True, omite archivos que ya están en el inventario.
    - window: referencia a la ventana GUI para emitir eventos de progreso.
    """
    inv = load_inventory()
    # Diccionario para acceso rápido por ruta
    items_map = {item.get("path"): item for item in inv.get("items", [])}
    new_items = []

    # Contar archivos para calcular el progreso aproximado
    total_files = 0
    for d in drive_list:
        for _, _, files in os.walk(d):
            total_files += len(files)
    if total_files == 0:
        total_files = 1

    processed = 0
    for d in drive_list:
        for root, _, files in os.walk(d):
            for fname in files:
                full_path = os.path.join(root, fname)
                processed += 1
                cached = items_map.get(full_path, {})
                try:
                    stat = os.stat(full_path)
                except OSError:
                    continue
                if (skip_already_hashed and cached.get("algo") == algo
                        and cached.get("size") == stat.st_size
                        and cached.get("mtime_ns") == stat.st_mtime_ns):
                    # Emitir evento de avance, indicar salto
                    window.write_event_value(
                        "-PROG-", (processed, total_files, f"Saltado: {full_path}")
                    )
                    continue
                # Calcular hash
                h = hash_file(full_path, algo)
                window.write_event_value(
                    "-PROG-", (processed, total_files, f"Hasheando: {full_path}")
                )
                if h:
                    try:
                        current = os.stat(full_path)
                    except OSError:
                        continue
                    if (current.st_size, current.st_mtime_ns) != (stat.st_size, stat.st_mtime_ns):
                        continue
                    entry = {
                        "path": full_path,
                        "hash": h,
                        "algo": algo,
                        "timestamp": time.time(),
                        "size": stat.st_size,
                        "mtime_ns": stat.st_mtime_ns,
                    }
                    new_items.append(entry)

    # Actualizar inventario
    for entry in new_items:
        items_map[entry["path"]] = entry
    inv["items"] = list(items_map.values())
    inv["generated_at"] = time.ctime()
    save_inventory(inv)
    # Señalar finalización
    window.write_event_value("-DONE-", f"Escaneo finalizado. {len(new_items)} nuevos elementos añadidos.")


def main() -> None:
    """Función principal que construye la interfaz gráfica y gestiona eventos."""
    sg.theme("DarkBlue3")
    drives = list_drives()
    layout = [
        [sg.Text("Discos detectados (selecciona con el ratón):")],
        [
            sg.Listbox(
                values=drives,
                size=(40, 8),
                select_mode=sg.LISTBOX_SELECT_MODE_EXTENDED,
                key="-DRIVES-",
            )
        ],
        [
            sg.Text("Algoritmo de hash:"),
            sg.Combo(["sha1", "md5", "sha256"], default_value="sha1", key="-ALGO-"),
        ],
        [
            sg.Checkbox(
                "Saltar archivos ya hasheados (si existen en el inventario)",
                default=True,
                key="-SKIP-",
            )
        ],
        [
            sg.Button("Iniciar escaneo", key="-START-"),
            sg.Button("Guardar inventario vacío", key="-NEW-"),
            sg.Button("Salir"),
        ],
        [
            sg.ProgressBar(max_value=100, orientation="h", size=(45, 20), key="-PROG_BAR-"),
            sg.Text("", key="-PROG_TXT-"),
        ],
    ]
    window = sg.Window("MingoMedia Inventory GUI", layout, finalize=True)

    # Bucle de eventos
    while True:
        event, values = window.read()
        if event in (sg.WIN_CLOSED, "Salir"):
            break
        if event == "-NEW-":
            if sg.popup_yes_no("Se reemplazara solo el inventario GUI. Continuar?") != "Yes":
                continue
            inv = {"generated_at": time.ctime(), "items": []}
            save_inventory(inv)
            sg.popup("Inventario vacío guardado en data/gui/inventory.json.gz")
        if event == "-START-":
            selected_drives = values["-DRIVES-"]
            if not selected_drives:
                sg.popup("Selecciona al menos una unidad antes de empezar")
                continue
            algo = values["-ALGO-"]
            skip = values["-SKIP-"]
            # Ejecutar en hilo para no bloquear la GUI
            t = threading.Thread(
                target=scan_and_hash, args=(selected_drives, algo, skip, window), daemon=True
            )
            t.start()
            sg.popup_no_buttons(
                "Escaneo iniciado. Puedes seguir el progreso en la barra de abajo."
            )
        if event == "-PROG-":
            processed, total, msg = values[event]
            percent = int((processed / total) * 100)
            window["-PROG_BAR-"].update(percent)
            window["-PROG_TXT-"].update(f"{processed}/{total}: {msg}")
        if event == "-DONE-":
            window["-PROG_BAR-"].update(100)
            sg.popup(values[event])
    window.close()


if __name__ == "__main__":
    main()
