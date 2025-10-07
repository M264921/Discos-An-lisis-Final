# tools/minify-and-gzip-inventory.ps1
param(
  [string]$DataDir = "docs\data",
  [string]$Source  = "inventory.json"
)

$ErrorActionPreference = "Stop"

# Rutas
$src = Join-Path $DataDir $Source
$min = Join-Path $DataDir "inventory.min.json"
$gz  = Join-Path $DataDir "inventory.json.gz"

if (-not (Test-Path $src)) {
  throw "No existe el archivo fuente: $src"
}

Write-Host "==> Leyendo $src..." -ForegroundColor Cyan
$json = Get-Content -LiteralPath $src -Raw -Encoding UTF8

# Minificar (reparsea y vuelve a serializar en compacto)
Write-Host "==> Minificando a $min..." -ForegroundColor Cyan
$obj  = $json | ConvertFrom-Json -Depth 100
$mini = $obj  | ConvertTo-Json -Depth 100 -Compress
# Guardar sin BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($min, $mini, $utf8NoBom)

# Gzip del minificado
Write-Host "==> Comprimendo a $gz..." -ForegroundColor Cyan
# Borrar si ya existe
if (Test-Path $gz) { Remove-Item $gz -Force }
$bytes = [System.Text.Encoding]::UTF8.GetBytes($mini)
$fsOut = [System.IO.File]::Create($gz)
try {
  $gzip = New-Object System.IO.Compression.GzipStream($fsOut, [System.IO.Compression.CompressionLevel]::Optimal)
  try { $gzip.Write($bytes, 0, $bytes.Length) }
  finally { $gzip.Dispose() }
}
finally { $fsOut.Dispose() }

# Función helper para SHA y tamaño
function Show-Info($label, $path) {
  $file = Get-Item -LiteralPath $path
  $sha  = Get-FileHash -Algorithm SHA256 -LiteralPath $path | Select-Object -ExpandProperty Hash
  "{0,-24}  {1,12:N0} bytes   SHA256={2}" -f $label, $file.Length, $sha
}

Write-Host "==> Resultados:" -ForegroundColor Green
Show-Info "inventory.json (src)" $src
Show-Info "inventory.min.json"   $min
Show-Info "inventory.json.gz"    $gz

Write-Host "`n✅ Listo. Si sirves con 'python -m http.server', usa inventory.json o inventory.min.json."
Write-Host "   Para usar el .gz sin pako, sirve con un server que envíe 'Content-Encoding: gzip'."
