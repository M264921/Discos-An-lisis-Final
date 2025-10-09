param(
  [string]$Drive,                 # ej: "C:"  (si lo omites, te saldrá selector)
  [switch]$WithHash,              # calcula SHA256 (más lento)
  [int]$Max = 0,                  # limita número de archivos (0 = sin límite)
  [switch]$Serve,                 # levanta servidor HTTP en localhost:9753
  [string]$HtmlName = "inventario_pro_offline.html"  # tu HTML pro
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# --- Rutas del proyecto ---
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$docs = Join-Path $root "docs"
$dataDir = Join-Path $docs "data"
$jsonPath = Join-Path $dataDir "inventory.json"
$htmlPath = Join-Path $docs $HtmlName

# --- Helpers ---
function Choose-Drive {
  $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -or $_.DriveType -eq 'Removable' }
  if ($drives.Count -eq 0) { throw "No se encontraron unidades." }
  if ($PSVersionTable.PSEdition -eq 'Desktop' -and (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
    $pick = $drives | Select-Object Name,DriveFormat,DriveType,IsReady,TotalSize,AvailableFreeSpace |
      Out-GridView -Title "Elige unidad para escanear" -PassThru
    if (!$pick) { throw "Cancelado por el usuario." }
    return $pick.Name.TrimEnd('\',':') + ":"
  } else {
    Write-Host "Unidades disponibles:" -ForegroundColor Cyan
    $drives | ForEach-Object { "{0}  ({1})" -f $_.Name,$_.DriveType } | Write-Host
    $d = Read-Host "Escribe la unidad (ej. C:)"
    return ($d.TrimEnd('\',':') + ":")
  }
}

function ExtType([string]$name) {
  $n = ($name ?? "").ToLower()
  switch -regex ($n) {
    '\.(mp4|mkv|avi|mov|wmv|flv|m4v)$' { 'video'; break }
    '\.(jpg|jpeg|png|gif|bmp|tif|tiff|webp|heic|heif)$' { 'foto'; break }
    '\.(mp3|wav|flac|aac|ogg|m4a)$' { 'audio'; break }
    '\.(pdf|docx?|xlsx?|pptx?|rtf|txt)$' { 'documento'; break }
    default { 'otro' }
  }
}

function ToIsoZ($dt) { ($dt.ToUniversalTime()).ToString("s") + "Z" }

# --- 1) Unidad ---
if (-not $Drive) { $Drive = Choose-Drive }
$Drive = $Drive.TrimEnd('\',':') + ":"
if (-not (Test-Path "$Drive\")) { throw "Unidad inválida: $Drive" }

Write-Host "Escaneando $Drive ... (esto puede tardar un poco)" -ForegroundColor Cyan

# --- 2) Enumerar archivos ---
$files = Get-ChildItem -LiteralPath "$Drive\" -Recurse -File -Force -ErrorAction SilentlyContinue
if ($Max -gt 0) { $files = $files | Select-Object -First $Max }

# --- 3) Mapear a esquema estándar ---
$rows = New-Object System.Collections.Generic.List[object]
$idx = 0

foreach ($f in $files) {
  $idx++
  if ($idx % 500 -eq 0) { Write-Progress -Activity "Procesando archivos" -Status "$idx / $($files.Count)" -PercentComplete ([int](100*$idx/$files.Count)) }

  $sha = ""
  if ($WithHash) {
    try { $sha = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -EA SilentlyContinue).Hash } catch {}
  }

  $obj = [pscustomobject]@{
    sha     = $sha
    tipo    = ExtType $f.Name
    nombre  = $f.Name
    ruta    = $f.DirectoryName
    unidad  = ($f.FullName -match '^[A-Za-z]:' ? $Matches[0].TrimEnd(':') + ":" : ($Drive.ToUpper()))
    tamano  = [int64]$f.Length
    fecha   = ToIsoZ $f.LastWriteTime
  }
  $rows.Add($obj)
}

Write-Host "Archivos recolectados: $($rows.Count)" -ForegroundColor Green

# --- 4) Guardar JSON + backup ---
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
if (Test-Path $jsonPath) {
  Copy-Item -LiteralPath $jsonPath -Destination ($jsonPath + ".bak_" + (Get-Date -Format yyyyMMddHHmmss)) -Force
}
$json = $rows | ConvertTo-Json -Depth 6 -Compress
Set-Content -LiteralPath $jsonPath -Value $json -Encoding UTF8
Write-Host "JSON actualizado: $jsonPath" -ForegroundColor Green

# --- 5) Inyectar en el HTML (entre <script id="inventory-data"> ... </script>) ---
if (-not (Test-Path $htmlPath)) { throw "No existe $htmlPath" }
$doc = Get-Content -LiteralPath $htmlPath -Raw

# patrón que localiza ese bloque (id="inventory-data")
$rx = [regex]::new('<script\s+id=["'']inventory-data["''][^>]*>[\s\S]*?</script>', 'Singleline,IgnoreCase')
if ($rx.IsMatch($doc)) {
  $replacement = '<script id="inventory-data" type="application/json">' + "`r`n" + $json + "`r`n" + '</script>'
  $doc = $rx.Replace($doc, $replacement, 1)
} else {
  # si no está, lo insertamos justo antes de </body>
  $replacement = '<script id="inventory-data" type="application/json">' + "`r`n" + $json + "`r`n" + '</script>'
  $doc = $doc -replace '</body>', ($replacement + "`r`n</body>")
}
# backup del HTML
$backup = (Join-Path $docs ($HtmlName + ".bak_" + (Get-Date -Format yyyyMMddHHmmss)))
Copy-Item -LiteralPath $htmlPath -Destination $backup -Force
Set-Content -LiteralPath $htmlPath -Value $doc -Encoding UTF8
Write-Host "HTML actualizado e inyectado. Backup: $backup" -ForegroundColor Green

# --- 6) Abrir (local o server HTTP opcional) ---
if ($Serve) {
  # mini server HTTP con HttpListener (localhost:9753) sirviendo /docs
  $port = 9753
  $prefix = "http://localhost:$port/"
  Write-Host "Levantando server en $prefix (Ctrl+C para parar la ventana del server)" -ForegroundColor Yellow

  $serverScript = @"
param([string]\$www, [int]\$port)
Add-Type -AssemblyName System.Net.HttpListener
\$h = [System.Net.HttpListener]::new()
\$h.Prefixes.Add("http://localhost:\$port/")
\$h.Start()
Write-Host "Server en http://localhost:\$port/ (sirviendo: \$www)"
while (\$h.IsListening) {
  \$ctx = \$h.GetContext()
  \$path = \$ctx.Request.Url.AbsolutePath.TrimStart('/')
  if ([string]::IsNullOrWhiteSpace(\$path)) { \$path = '$($HtmlName)' }
  \$full = Join-Path \$www \$path
  if (-not (Test-Path \$full)) { \$ctx.Response.StatusCode = 404; \$ctx.Response.OutputStream.Close(); continue }
  try {
    \$bytes = [System.IO.File]::ReadAllBytes(\$full)
    \$ext = [System.IO.Path]::GetExtension(\$full).ToLower()
    \$mime = switch (\$ext) {
      '.html' { 'text/html; charset=utf-8' }
      '.json' { 'application/json' }
      '.js'   { 'application/javascript' }
      '.css'  { 'text/css' }
      default { 'application/octet-stream' }
    }
    \$ctx.Response.ContentType = \$mime
    \$ctx.Response.ContentLength64 = \$bytes.Length
    \$ctx.Response.OutputStream.Write(\$bytes,0,\$bytes.Length)
  } catch {}
  \$ctx.Response.OutputStream.Close()
}
"@

  $serverPs1 = Join-Path $env:TEMP "static_server_$([guid]::NewGuid().ToString('N')).ps1"
  Set-Content -LiteralPath $serverPs1 -Value $serverScript -Encoding UTF8
  Start-Process powershell -ArgumentList "-NoExit","-ExecutionPolicy Bypass","-File `"$serverPs1`"","-www `"$docs`"","-port $port" | Out-Null
  Start-Sleep -Milliseconds 600
  Start-Process "http://localhost:$port/$HtmlName"
} else {
  Write-Host "Abriendo local (file://)..." -ForegroundColor Yellow
  Start-Process $htmlPath
}

Write-Host "`n✅ TEST COMPLETO: listo. Disfruta." -ForegroundColor Magenta
