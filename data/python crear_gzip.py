import os, json, gzip

# Crear la carpeta "data" si no existe
os.makedirs('data', exist_ok=True)

# Estructura de datos a guardar
data = {"generated_at": "manual-placeholder", "items": []}

# Crear el archivo comprimido
with gzip.open('data/inventory.json.gz', 'wb') as f:
    f.write(json.dumps(data).encode('utf-8'))
print("Archivo generado correctamente")
