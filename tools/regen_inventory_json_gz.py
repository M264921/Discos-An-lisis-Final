# -*- coding: utf-8 -*-
import os, json, gzip

os.makedirs("data", exist_ok=True)
data = {}  # TODO: sustituye por tu inventario real si aplica

with gzip.open("data/inventory.json.gz", "wb") as f:
    f.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))

print("✅ Archivo data/inventory.json.gz regenerado correctamente")
