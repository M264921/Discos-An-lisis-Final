param(
  [string]$CsvPath = "docs\hash_data.csv",
  [string]$JsonPath = "docs\data\inventory.json"
)
if(!(Test-Path $CsvPath)){ throw "No existe $CsvPath" }
$rows = Import-Csv $CsvPath
# normaliza nombres esperados por el front
$data = $rows | ForEach-Object {
  [pscustomobject]@{
    sha    = $_.sha
    tipo   = $_.tipo
    nombre = $_.nombre
    ruta   = $_.ruta
    unidad = ($_.Drive ?? $_.unidad ?? $_.unit ?? "").TrimEnd('\').TrimEnd(':') + ':'
    tamano = [int64]($_.tamano ?? $_.size ?? $_.length ?? 0)
    fecha  = $_.fecha ?? $_.lastWriteTime
  }
}
$data | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $JsonPath
Write-Host "Generado $JsonPath con $($data.Count) elementos" -ForegroundColor Green
