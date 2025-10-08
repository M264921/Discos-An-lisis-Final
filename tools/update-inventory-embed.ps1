param(
  [Parameter(Mandatory=$true)] [string] $HtmlPath,
  [Parameter(Mandatory=$true)] [string] $JsonPath
)

$ErrorActionPreference = "Stop"

if(!(Test-Path $HtmlPath)){ throw "No existe HTML: $HtmlPath" }
if(!(Test-Path $JsonPath)){ throw "No existe JSON: $JsonPath" }

$doc = Get-Content -LiteralPath $HtmlPath -Raw
$json = Get-Content -LiteralPath $JsonPath -Raw

# Normaliza salto de línea en JSON
$json = ($json -replace "\r\n","`n")

# Reemplaza el bloque embebido (conserva 'type="application/json"')
$rx = [regex]::new('<script\s+id=["'']inventory-data["'']\s+type=["'']application/json["'']\s*>([\s\S]*?)</script>', 'Singleline,IgnoreCase')
if(!$rx.IsMatch($doc)){ throw "No encuentro <script id=""inventory-data""> en el HTML." }

$new = '<script id="inventory-data" type="application/json">' + "`r`n" + $json + "`r`n" + '</script>'
$doc = $rx.Replace($doc, $new, 1)

# Backup y guardado
$bak = "$HtmlPath.bak_$(Get-Date -Format yyyyMMddHHmmss)"
Copy-Item -LiteralPath $HtmlPath -Destination $bak -Force
Set-Content -LiteralPath $HtmlPath -Value $doc -Encoding UTF8

Write-Host "✔ Embebido actualizado. Backup: $bak"
