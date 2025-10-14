import os, json, gzip
os.makedirs("data", exist_ok=True)
data = {}  # pon aquí el dict real si lo tienes
with gzip.open("data/inventory.json.gz", "wb") as f:
    f.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))
print("? Archivo data/inventory.json.gz regenerado correctamente")
