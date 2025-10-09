[CmdletBinding()]
param(
  # acepta -Html, -Path o -InputFile indistintamente
  [Parameter(Mandatory)]
  [Alias('Path','InputFile')]
  [string]$Html
)


Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Html = (Resolve-Path $Html).Path
Write-Host "→ Normalizando: $Html" -ForegroundColor Cyan

# Lee HTML
$doc = Get-Content -LiteralPath $Html -Raw

# (Si hay “bridge” viejo, lo quitamos para evitar duplicados – opcional)
$doc = [regex]::Replace($doc, '<script[^>]+id=["'']bridge-inventory-offline["''][\s\S]*?</script>\s*', '', 'IgnoreCase')

# (Ejemplo) Cuenta por unidad en los datos embebidos si existen
$rx = [regex]::new('<script[^>]+id=["'']inventory-data["''][^>]*>(?<json>[\s\S]*?)</script>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$json = $null
if($rx.IsMatch($doc)){
  try{
    $json = ($rx.Match($doc).Groups['json'].Value) | ConvertFrom-Json
  }catch{}
}

# Calcula driveCounts ordenado (si hay datos)
$driveCounts = [ordered]@{}
if($json -and $json.Count -gt 0){
  $json | Group-Object unidad | ForEach-Object {
    $driveCounts[$_.Name] = $_.Count
  }
}

# (Si quieres, aquí podrías reinyectar métricas al HTML; mantengo el HTML tal cual):
# $doc = $doc # noop

# Guarda
Set-Content -LiteralPath $Html -Encoding UTF8 -Value $doc
Write-Host "✔ Normalizado" -ForegroundColor Green
