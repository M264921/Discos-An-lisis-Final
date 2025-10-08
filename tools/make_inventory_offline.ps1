# make_inventory_offline.ps1 (stub)
param()
try {
  \C:\Users\Antonio\Documents\GitHub\Discos-An-lisis-Final\docs = Join-Path (Split-Path \C:\Users\Antonio\Documents\GitHub\Discos-An-lisis-Final\tools -Parent) 'docs'
  \ = Join-Path \C:\Users\Antonio\Documents\GitHub\Discos-An-lisis-Final\docs 'inventario_interactivo_offline.html'
  \ = Join-Path \C:\Users\Antonio\Documents\GitHub\Discos-An-lisis-Final\docs 'index.html'
  if(Test-Path \){ Copy-Item \ \ -Force }
  Write-Host "HTML regenerado (stub) -> \"
} catch { Write-Warning ("Stub make_inventory_offline falló: {0}" -f \.Exception.Message) }
