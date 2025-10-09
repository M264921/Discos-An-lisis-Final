param(
  [string]$ScansDir = ".\docs\inventory",
  [string]$OutJson  = ".\docs\data\inventory.json",
  [string]$Html     = ".\docs\inventario_pro_offline.html"
)

function Get-EmbeddedRows {
  param([string]$HtmlPath)
  if (-not (Test-Path -LiteralPath $HtmlPath)) { return @() }
  $doc = Get-Content -LiteralPath $HtmlPath -Raw
  $m = [regex]::Match($doc, '<script\s+id="inventory-data"[^>]*>(?<json>[\s\S]*?)</script>', 'IgnoreCase')
  if (-not $m.Success) { return @() }
  try {
    $rows = $m.Groups['json'].Value | ConvertFrom-Json
    if ($rows -is [System.Collections.IEnumerable]) { return @($rows) } else { return @() }
  } catch { return @() }
}

function Infer-Tipo {
  param([string]$ext)
  $e = ($ext ?? "").ToLower()
  if ($e -match '^\.+(jpg|jpeg|png|gif|webp|bmp|tiff)$') { return 'foto' }
  if ($e -match '^\.+(mp4|mkv|avi|mov|wmv|webm|m4v)$') { return 'video' }
  if ($e -match '^\.+(mp3|ogg|wav|flac|aac|m4a|opus)$') { return 'audio' }
  return 'otro'
}

# 1) CSVs
$scanFiles = Get-ChildItem -Path $ScansDir -Filter "scan_*.csv" -ErrorAction SilentlyContinue
$fromCsv = @()
foreach ($f in $scanFiles) {
  try {
    $raw = Import-Csv -Path $f.FullName
    foreach ($r in $raw) {
      $sha   = $r.sha   ?? $r.hash   ?? ""
      $path  = $r.ruta  ?? $r.path   ?? ""
      $name  = $r.nombre?? $r.name   ?? $(if($path){ Split-Path $path -Leaf } else { "" })
      $dir   = if ($path) { Split-Path $path -Parent } else { ($r.ruta ?? "") }
      $drive = $r.unidad?? $r.unit   ?? $r.drive ?? $(if($path -match '^([A-Za-z]):'){ $Matches[1] + ":" } else { "" })
      $tam   = $r.tamano?? $r.size   ?? 0
      $date  = $r.fecha ?? $r.mtime  ?? $r.last ?? ""
      $tipo  = $r.tipo  ?? $r.type   ?? (Infer-Tipo ($r.ext ?? [System.IO.Path]::GetExtension($path)))

      $fromCsv += [pscustomobject]@{
        sha=$sha; tipo=$tipo; nombre=$name; ruta=$dir; unidad=$drive
        tamano=[int64]($tam); fecha=$date
      }
    }
  } catch { Write-Warning "No pude leer $($f.Name): $_" }
}

# 2) JSON embebido actual (para no perder C hasta que tengas scan_C.csv)
$fromHtml = Get-EmbeddedRows -HtmlPath $Html | ForEach-Object {
  [pscustomobject]@{
    sha   = $_.sha
    tipo  = $_.tipo
    nombre= $_.nombre
    ruta  = $_.ruta
    unidad= $_.unidad
    tamano= [int64]($_.tamano)
    fecha = $_.fecha
  }
}

# 3) Merge + dedupe (sha+ruta)
$rows = @($fromHtml + $fromCsv) |
  Where-Object { $_.sha } |
  Sort-Object sha, ruta -Unique

# 4) Guardar JSON combinado
$rows | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $OutJson -Encoding UTF8
Write-Host ("✔ Combinado -> {0} ({1} filas)" -f $OutJson, $rows.Count) -ForegroundColor Green

# 5) Re-embebido en HTML
$doc = Get-Content -LiteralPath $Html -Raw
$payload = ($rows | ConvertTo-Json -Depth 6 -Compress)
$pattern = '<script\s+id="inventory-data"[^>]*>(?<json>[\s\S]*?)</script>'
if ($doc -match $pattern) {
  $new = '<script id="inventory-data" type="application/json">' + "`n" + $payload + "`n" + '</script>'
  $doc = [regex]::Replace($doc, $pattern, $new, 'IgnoreCase')
} else {
  $insert = "`n<script id=""inventory-data"" type=""application/json"">`n$payload`n</script>`n"
  $doc = $doc -replace '</body>', ($insert + '</body>')
}
$backup = "$Html.bak_$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item -LiteralPath $Html -Destination $backup -Force
Set-Content -LiteralPath $Html -Value $doc -Encoding UTF8
Write-Host "↪ Backup: $backup" -ForegroundColor DarkGray
Write-Host "✔ JSON embebido en $Html" -ForegroundColor Green